# Data Collection Module for CrowdStrike Azure Cost Estimation Tool

# Note: Do not import modules here - they should be imported by the main script
# This avoids issues with duplicate module loading and function scope

# Function to get metadata about a subscription (region, tags, etc.)
function Get-SubscriptionMetadata {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )
    
    $metadata = @{
        Region = "unknown"
        BusinessUnit = $DefaultBusinessUnit
        Environment = $DefaultEnvironment
        IsProductionLike = $false
        IsDevelopmentLike = $false
        HasTagsApplied = $false
        PrimaryLocation = "unknown"
    }
    
    try {
        # Set context to subscription
        Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
        
        # Get subscription details
        $subscription = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
        
        # Check for business unit tag
        if ($subscription.Tags -and $subscription.Tags.ContainsKey($BusinessUnitTagName)) {
            $metadata.BusinessUnit = $subscription.Tags[$BusinessUnitTagName]
            $metadata.HasTagsApplied = $true
        }
        
        # Check for environment tag
        if ($subscription.Tags -and $subscription.Tags.ContainsKey($EnvironmentTagName)) {
            $metadata.Environment = $subscription.Tags[$EnvironmentTagName]
            $metadata.HasTagsApplied = $true
        }
        else {
            # Try to determine environment from subscription name
            foreach ($envCategory in $EnvironmentCategories.Keys) {
                $patterns = $EnvironmentCategories[$envCategory].NamePatterns
                foreach ($pattern in $patterns) {
                    if ($subscription.Name -match $pattern) {
                        $metadata.Environment = $envCategory
                        break
                    }
                }
                
                if ($metadata.Environment -ne $DefaultEnvironment) {
                    break
                }
            }
        }
        
        # Determine if production-like or development-like
        $prodLikeEnvs = @("Production", "PreProduction")
        $devLikeEnvs = @("Development", "QA", "Sandbox")
        
        if ($prodLikeEnvs -contains $metadata.Environment) {
            $metadata.IsProductionLike = $true
        }
        elseif ($devLikeEnvs -contains $metadata.Environment) {
            $metadata.IsDevelopmentLike = $true
        }
        
        # Try to get primary region from resource groups
        $resourceGroups = Get-AzResourceGroup -ErrorAction Stop
        if ($resourceGroups.Count -gt 0) {
            $locations = $resourceGroups | ForEach-Object { $_.Location } | Group-Object | Sort-Object -Property Count -Descending
            if ($locations.Count -gt 0) {
                $metadata.PrimaryLocation = $locations[0].Name
                $metadata.Region = $locations | ForEach-Object { $_.Name } | Sort-Object -Unique | Join-String -Separator ","
            }
        }
    }
    catch {
        Write-Log "Error retrieving metadata for subscription $SubscriptionId : $($_.Exception.Message)" -Level 'WARNING' -Category 'Subscription'
    }
    
    return $metadata
}

# Function to retrieve activity logs for a subscription
function Get-SubscriptionActivityLogs {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $true)]
        [int]$DaysToAnalyze,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxResults = $MaxActivityLogsToRetrieve,
        
        [Parameter(Mandatory = $false)]
        [int]$PageSize = $ActivityLogPageSize,
        
        [Parameter(Mandatory = $false)]
        [int]$SampleSize = $SampleLogSize
    )
    
    $logData = @{
        LogCount = 0
        DailyAverage = 0
        AvgLogSizeKB = $DefaultActivityLogSizeKB
        SampledLogCount = 0
        ResourceProviders = @{}
        OperationNames = @{}
        LogsByDay = @{}
        LogDistribution = @{}
    }
    
    $startTime = (Get-Date).AddDays(-$DaysToAnalyze)
    $endTime = Get-Date
    
    Write-Log "Retrieving activity logs for subscription $SubscriptionId from $startTime to $endTime" -Level 'INFO' -Category 'ActivityLogs'
    
    try {
        Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
        
        # Using Az REST API for more flexibility
        $filter = "eventTimestamp ge '${startTime}' and eventTimestamp le '${endTime}'"
        $requestURI = "/subscriptions/$SubscriptionId/providers/Microsoft.Insights/eventtypes/management/values?api-version=2017-03-01-preview&`$filter=$filter&`$top=$PageSize"
        
        $logs = @()
        $pageCount = 0
        $skipToken = $null
        
        # Retrieve logs with paging
        do {
            $pageCount++
            $uri = $requestURI
            
            if ($skipToken) {
                $uri += "&`$skipToken=$skipToken"
            }
            
            Write-Log "Retrieving activity logs page $pageCount..." -Level 'INFO' -Category 'ActivityLogs'
            
            $response = Invoke-AzRestMethod -Method GET -Path $uri -ErrorAction Stop
            
            if ($response.StatusCode -eq 200) {
                $content = $response.Content | ConvertFrom-Json
                $pageItems = @($content.value)
                
                if ($pageItems.Count -gt 0) {
                    $logs += $pageItems
                    Write-Log "Retrieved $($pageItems.Count) logs (Total: $($logs.Count))" -Level 'INFO' -Category 'ActivityLogs'
                    
                    # Get skipToken for next page if available
                    $skipToken = $null
                    if ($content.nextLink -and $content.nextLink -match "\`$skipToken=([^&]+)") {
                        $skipToken = $matches[1]
                    }
                }
                
                # Exit loop if we've reached the limit
                if ($logs.Count -ge $MaxResults) {
                    Write-Log "Reached maximum result limit of $MaxResults" -Level 'WARNING' -Category 'ActivityLogs'
                    break
                }
            }
            else {
                Write-Log "Failed to retrieve logs: $($response.StatusCode)" -Level 'WARNING' -Category 'ActivityLogs'
                break
            }
        } while ($skipToken -and $pageItems.Count -gt 0)
        
        # Process the logs
        $logData.LogCount = $logs.Count
        $logData.DailyAverage = [math]::Round($logs.Count / $DaysToAnalyze, 2)
        
        # Group logs by resource provider
        $resourceProviders = $logs | Group-Object { $_.resourceProvider.value } | Select-Object Name, Count
        foreach ($rp in $resourceProviders) {
            if (-not [string]::IsNullOrEmpty($rp.Name)) {
                $logData.ResourceProviders[$rp.Name] = $rp.Count
            }
        }
        
        # Group logs by operation name
        $operations = $logs | Group-Object { $_.operationName.value } | Select-Object Name, Count | Sort-Object -Property Count -Descending
        foreach ($op in $operations) {
            if (-not [string]::IsNullOrEmpty($op.Name)) {
                $logData.OperationNames[$op.Name] = $op.Count
            }
        }
        
        # Group logs by day
        $logsByDay = $logs | Group-Object { ([DateTime]$_.eventTimestamp).Date.ToString("yyyy-MM-dd") } | Select-Object Name, Count
        foreach ($day in $logsByDay) {
            $logData.LogsByDay[$day.Name] = $day.Count
        }
        
        # Sample logs to determine average size
        if ($logs.Count -gt 0) {
            $samplesToTake = [math]::Min($SampleSize, $logs.Count)
            $sampledLogs = $logs | Get-Random -Count $samplesToTake
            $totalSize = 0
            
            foreach ($log in $sampledLogs) {
                # Convert to JSON and count bytes
                $jsonSize = ([System.Text.Encoding]::UTF8.GetByteCount(($log | ConvertTo-Json -Depth 10 -Compress)))
                $sizeKB = $jsonSize / 1024
                $totalSize += $sizeKB
            }
            
            $logData.AvgLogSizeKB = [math]::Round($totalSize / $samplesToTake, 2)
            $logData.SampledLogCount = $samplesToTake
            
            Write-Log "Sampled $samplesToTake logs. Average log size: $($logData.AvgLogSizeKB) KB" -Level 'INFO' -Category 'ActivityLogs'
        }
        
        Write-Log "Activity log collection complete. Found $($logData.LogCount) logs (Daily average: $($logData.DailyAverage))" -Level 'SUCCESS' -Category 'ActivityLogs'
    }
    catch {
        Write-Log "Failed to retrieve activity logs: $($_.Exception.Message)" -Level 'WARNING' -Category 'ActivityLogs'
    }
    
    return $logData
}

# Function to get resource data for a subscription
function Get-SubscriptionResources {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId
    )
    
    $resourceData = @{
        TotalResources = 0
        ResourceTypes = @{}
        LocationCounts = @{}
        TaggedResourceCount = 0
        PercentTagged = 0
        SecuredResourceCount = 0
        HasDiagnosticSettings = $false
    }
    
    try {
        Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
        
        $resources = Get-AzResource -ErrorAction Stop
        $resourceData.TotalResources = $resources.Count
        
        if ($resources.Count -gt 0) {
            # Process resource types
            $resourceTypes = $resources | Group-Object -Property ResourceType | Select-Object Name, Count | Sort-Object -Property Count -Descending
            foreach ($type in $resourceTypes) {
                $resourceData.ResourceTypes[$type.Name] = $type.Count
            }
            
            # Process locations
            $locations = $resources | Group-Object -Property Location | Select-Object Name, Count | Sort-Object -Property Count -Descending
            foreach ($location in $locations) {
                if (-not [string]::IsNullOrEmpty($location.Name)) {
                    $resourceData.LocationCounts[$location.Name] = $location.Count
                }
            }
            
            # Count tagged resources
            $taggedResources = $resources | Where-Object { $_.Tags -and $_.Tags.Count -gt 0 }
            $resourceData.TaggedResourceCount = $taggedResources.Count
            
            if ($resources.Count -gt 0) {
                $resourceData.PercentTagged = [math]::Round(($taggedResources.Count / $resources.Count) * 100, 1)
            }
            
            # Check for diagnostic settings
            try {
                $diagnosticSettings = Get-AzDiagnosticSetting -ErrorAction Stop
                $resourceData.HasDiagnosticSettings = ($diagnosticSettings.Count -gt 0)
            }
            catch {
                Write-Log "Unable to check diagnostic settings: $($_.Exception.Message)" -Level 'DEBUG' -Category 'Resources'
            }
            
            # Check for secured resources (just an approximation)
            $securityResources = $resources | Where-Object { 
                $_.ResourceType -like "*lock*" -or 
                $_.ResourceType -like "*keyvault*" -or 
                $_.ResourceType -like "*security*" -or
                $_.ResourceType -like "*privatelink*"
            }
            $resourceData.SecuredResourceCount = $securityResources.Count
        }
        
        Write-Log "Resource collection complete. Found $($resourceData.TotalResources) resources across $($resourceData.ResourceTypes.Count) resource types." -Level 'SUCCESS' -Category 'Resources'
    }
    catch {
        Write-Log "Failed to retrieve resources: $($_.Exception.Message)" -Level 'WARNING' -Category 'Resources'
    }
    
    return $resourceData
}

# Function to get Entra ID log metrics
function Get-EntraIdLogMetrics {
    param (
        [Parameter(Mandatory = $false)]
        [int]$DaysToAnalyze = $DaysToAnalyze
    )
    
    $metrics = @{
        SignInLogCount = 0
        AuditLogCount = 0
        SignInDailyAverage = 0
        AuditDailyAverage = 0
        UserCount = 0
        SignInSize = $DefaultEntraIdLogSizeKB
        AuditSize = $DefaultEntraIdLogSizeKB
        Organization = "Small"  # Default, will update based on user count
    }
    
    Write-Log "Analyzing Entra ID metrics..." -Level 'INFO' -Category 'EntraID'
    
    try {
        # Try to connect to Azure AD if not already connected
        $connected = $false
        
        try {
            # First try using Azure AD module if available
            if (Get-Module -Name AzureAD -ListAvailable) {
                try {
                    # Check if module is loaded
                    if (-not (Get-Module -Name AzureAD)) {
                        Import-Module AzureAD -ErrorAction Stop
                    }
                    
                    # Connect to Azure AD
                    Connect-AzureAD -ErrorAction Stop | Out-Null
                    $connected = $true
                    Write-Log "Connected to Azure AD using AzureAD module" -Level 'INFO' -Category 'EntraID'
                }
                catch {
                    Write-Log "Failed to connect using AzureAD module: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
                    # Continue to try other methods
                }
            }
            
            # If AzureAD not available or failed, try Microsoft Graph
            if (-not $connected -and (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.DirectoryManagement)) {
                try {
                    # Load required Microsoft Graph modules
                    Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction SilentlyContinue
                    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
                        Connect-MgGraph -Scopes "Directory.Read.All" -ErrorAction Stop | Out-Null
                    }
                    $orgInfo = Get-MgOrganization -ErrorAction Stop
                    $connected = $true
                    Write-Log "Connected to Entra ID using Microsoft Graph module" -Level 'INFO' -Category 'EntraID'
                }
                catch {
                    Write-Log "Failed to connect using Microsoft Graph: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
                }
            }
            
            # If still not connected, try using Az modules as last resort
            if (-not $connected) {
                try {
                    $tenantDetails = Get-AzTenant -ErrorAction Stop
                    $connected = $true
                    Write-Log "Using Az module for tenant information" -Level 'INFO' -Category 'EntraID'
                }
                catch {
                    Write-Log "Failed to get tenant info using Az module: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
                }
            }
        }
        catch {
            Write-Log "Unable to connect to Entra ID: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
        }
        
        if ($connected) {
            # Get user count which will help with estimating sign-in volume
            try {
                # Try using Graph API first
                if (Get-Module -ListAvailable -Name Microsoft.Graph.Users) {
                    try {
                        Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
                        if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
                            Connect-MgGraph -Scopes "Directory.Read.All" -ErrorAction SilentlyContinue | Out-Null
                        }
                        $users = Get-MgUser -Count userCount -ConsistencyLevel eventual -ErrorAction Stop
                        $metrics.UserCount = $users.Count
                        Write-Log "Retrieved user count using Microsoft Graph module" -Level 'INFO' -Category 'EntraID'
                    }
                    catch {
                        Write-Log "Failed to get user count using Graph: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
                        # Fall through to the Az estimate
                    }
                }
                
                # If we still don't have a user count, use Az module for estimation
                if ($metrics.UserCount -eq 0) {
                    # This is less accurate but provides a fallback
                    $tenantId = (Get-AzContext).Tenant.Id
                    Write-Log "Using estimated user count for tenant $tenantId" -Level 'INFO' -Category 'EntraID'
                    # Set a default value, we'll estimate based on subscription count
                    $subCount = (Get-AzSubscription).Count
                    $metrics.UserCount = [Math]::Max(500, $subCount * 50) # Rough estimate
                }
            }
            catch {
                Write-Log "Unable to get user count, using default: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
                $metrics.UserCount = 500 # Default fallback
            }
            
            # Determine organization size based on user count
            if ($metrics.UserCount -lt 1000) {
                $metrics.Organization = "Small"
                $dailySignInsPerUser = $SignInsPerUserPerDay.Small
                $dailyAuditsPerUser = $AuditsPerUserPerDay.Small
            }
            elseif ($metrics.UserCount -lt 10000) {
                $metrics.Organization = "Medium"
                $dailySignInsPerUser = $SignInsPerUserPerDay.Medium
                $dailyAuditsPerUser = $AuditsPerUserPerDay.Medium
            }
            else {
                $metrics.Organization = "Large"
                $dailySignInsPerUser = $SignInsPerUserPerDay.Large
                $dailyAuditsPerUser = $AuditsPerUserPerDay.Large
            }
            
            # Calculate estimated log counts
            $dailySignIns = $metrics.UserCount * $dailySignInsPerUser
            $dailyAudits = $metrics.UserCount * $dailyAuditsPerUser
            
            $metrics.SignInDailyAverage = [math]::Round($dailySignIns, 2)
            $metrics.AuditDailyAverage = [math]::Round($dailyAudits, 2)
            $metrics.SignInLogCount = [math]::Round($dailySignIns * $DaysToAnalyze)
            $metrics.AuditLogCount = [math]::Round($dailyAudits * $DaysToAnalyze)
            
            Write-Log "Organization size: $($metrics.Organization), Users: $($metrics.UserCount)" -Level 'INFO' -Category 'EntraID'
            Write-Log "Estimated sign-in logs: $($metrics.SignInLogCount), Daily: $($metrics.SignInDailyAverage)" -Level 'INFO' -Category 'EntraID'
            Write-Log "Estimated audit logs: $($metrics.AuditLogCount), Daily: $($metrics.AuditDailyAverage)" -Level 'INFO' -Category 'EntraID'
        }
        else {
            # Estimate based on tenant size
            # This is just a placeholder - a very rough estimate
            $metrics.UserCount = 500  # Conservative default
            $metrics.SignInDailyAverage = [math]::Round($metrics.UserCount * $SignInsPerUserPerDay.Small, 2)
            $metrics.AuditDailyAverage = [math]::Round($metrics.UserCount * $AuditsPerUserPerDay.Small, 2)
            $metrics.SignInLogCount = [math]::Round($metrics.SignInDailyAverage * $DaysToAnalyze)
            $metrics.AuditLogCount = [math]::Round($metrics.AuditDailyAverage * $DaysToAnalyze)
            
            Write-Log "Using estimated Entra ID metrics based on small organization size" -Level 'WARNING' -Category 'EntraID'
        }
    }
    catch {
        Write-Log "Error analyzing Entra ID metrics: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
    }
    
    return $metrics
}

# Export functions
Export-ModuleMember -Function Get-SubscriptionMetadata, Get-SubscriptionActivityLogs, Get-SubscriptionResources, Get-EntraIdLogMetrics
