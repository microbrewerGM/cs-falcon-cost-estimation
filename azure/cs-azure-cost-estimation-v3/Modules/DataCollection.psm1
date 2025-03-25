# Data collection module for CrowdStrike Azure Cost Estimation Tool v3

# Function to get metadata about subscriptions
function Get-SubscriptionMetadata {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [object[]]$Subscriptions = $null
    )
    
    $metadataCollection = @{}
    
    # If no subscriptions provided, get all accessible subscriptions
    if (-not $Subscriptions) {
        try {
            $Subscriptions = Get-SubscriptionList
        }
        catch {
            Write-Log "Error getting subscriptions - $($_.Exception.Message)" -Level 'ERROR' -Category 'Subscription'
            return $metadataCollection
        }
    }
    
    Write-Log "Collecting metadata for $($Subscriptions.Count) subscriptions" -Level 'INFO' -Category 'Subscription'
    
    foreach ($subscription in $Subscriptions) {
        $subscriptionId = $subscription.Id
        $subscriptionName = $subscription.Name
        
        # Initialize metadata object
        $metadata = @{
            SubscriptionId = $subscriptionId
            SubscriptionName = $subscriptionName
            Region = "unknown"
            PrimaryLocation = "unknown"
            BusinessUnit = Get-ConfigSetting -Name 'DefaultBusinessUnit' -DefaultValue 'Unassigned'
            Environment = Get-ConfigSetting -Name 'DefaultEnvironment' -DefaultValue 'Unknown'
            IsProductionLike = $false
            IsDevelopmentLike = $false
            Tags = @{}
        }
        
        try {
            # Check if we have a valid Azure connection
            $currentContext = Get-AzContext -ErrorAction SilentlyContinue
            if (-not $currentContext) {
                Write-Log "No active Azure session found when processing subscription $subscriptionId" -Level 'WARNING' -Category 'Subscription'
                continue
            }
            
            # Set context to subscription with retry
            $contextSet = $false
            $retryCount = 0
            $maxRetries = 2
            
            while (-not $contextSet -and $retryCount -le $maxRetries) {
                try {
                    # First check if subscription exists in this tenant
                    $sub = Get-AzSubscription -SubscriptionId $subscriptionId -TenantId $currentContext.Tenant.Id -ErrorAction Stop
                    if (-not $sub) {
                        Write-Log "Subscription $subscriptionId not found in current tenant $($currentContext.Tenant.Id)" -Level 'WARNING' -Category 'Subscription'
                        break
                    }
                    
                    # Try to set context
                    $contextResult = Set-AzContext -Subscription $subscriptionId -ErrorAction Stop
                    if ($contextResult -and $contextResult.Subscription.Id -eq $subscriptionId) {
                        $contextSet = $true
                        Write-Log "Successfully set context to subscription $subscriptionId" -Level 'DEBUG' -Category 'Subscription'
                    }
                    else {
                        throw "Context switch succeeded but returned unexpected subscription"
                    }
                }
                catch {
                    $retryCount++
                    $errorMsg = if ($_.Exception) { $_.Exception.Message } else { "Unknown error" }
                    
                    if ($retryCount -le $maxRetries) {
                        Write-Log "Retry $retryCount/$maxRetries: Context switch error for subscription $subscriptionId : $errorMsg" -Level 'DEBUG' -Category 'Subscription'
                        Start-Sleep -Seconds 2  # Brief pause before retry
                    }
                    else {
                        Write-Log "Context switch error for subscription $subscriptionId after $maxRetries retries: $errorMsg" -Level 'WARNING' -Category 'Subscription'
                        break
                    }
                }
            }
            
            if (-not $contextSet) {
                continue
            }
            
            # Get subscription details and tags
            $subDetail = Get-AzSubscription -SubscriptionId $subscriptionId -ErrorAction Stop
            
            # Copy tags
            if ($subDetail.Tags -and $subDetail.Tags.Count -gt 0) {
                $metadata.Tags = $subDetail.Tags.Clone()
                
                # Look for business unit tag
                $buTagName = Get-ConfigSetting -Name 'BusinessUnitTagName' -DefaultValue 'BusinessUnit'
                if ($subDetail.Tags.ContainsKey($buTagName)) {
                    $metadata.BusinessUnit = $subDetail.Tags[$buTagName]
                }
                
                # Look for environment tag
                $envTagName = Get-ConfigSetting -Name 'EnvironmentTagName' -DefaultValue 'Environment'
                if ($subDetail.Tags.ContainsKey($envTagName)) {
                    $metadata.Environment = $subDetail.Tags[$envTagName]
                }
            }
        }
        catch {
            $errorMsg = if ($_.Exception) { $_.Exception.Message } else { "Unknown error" }
            Write-Log "Error with subscription $subscriptionId : $errorMsg" -Level 'WARNING' -Category 'Subscription'
        }
        
        # Add to collection
        $metadataCollection[$subscriptionId] = $metadata
    }
    
    return $metadataCollection
}

# Function to retrieve activity logs for a subscription
function Get-SubscriptionActivityLogs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $false)]
        [int]$DaysToAnalyze = 7,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxResults = 1000,
        
        [Parameter(Mandatory = $false)]
        [int]$PageSize = 100,
        
        [Parameter(Mandatory = $false)]
        [int]$SampleSize = 50
    )
    
    $logData = @{
        LogCount = 0
        DailyAverage = 0
        AvgLogSizeKB = Get-ConfigSetting -Name 'DefaultActivityLogSizeKB' -DefaultValue 2.5
        SampledLogCount = 0
        ResourceProviders = @{}
        OperationNames = @{}
        LogsByDay = @{}
    }
    
    $startTime = (Get-Date).AddDays(-$DaysToAnalyze)
    $endTime = Get-Date
    
    try {
        # Check if we have a valid Azure connection
        $currentContext = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $currentContext) {
            throw "No active Azure session found"
        }
        
        # Set context to subscription with retry
        $contextSet = $false
        $retryCount = 0
        $maxRetries = 2
        
        while (-not $contextSet -and $retryCount -le $maxRetries) {
            try {
                $contextResult = Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop
                if ($contextResult -and $contextResult.Subscription.Id -eq $SubscriptionId) {
                    $contextSet = $true
                    Write-Log "Context set to subscription $SubscriptionId for activity log retrieval" -Level 'DEBUG' -Category 'ActivityLogs'
                }
                else {
                    throw "Context switch succeeded but returned unexpected subscription"
                }
            }
            catch {
                $retryCount++
                $errorMsg = if ($_.Exception) { $_.Exception.Message } else { "Unknown error" }
                
                if ($retryCount -le $maxRetries) {
                    Write-Log "Retry $retryCount/$maxRetries: Context switch error for log retrieval: $errorMsg" -Level 'DEBUG' -Category 'ActivityLogs'
                    Start-Sleep -Seconds 2  # Brief pause before retry
                }
                else {
                    throw "Failed to set context after $maxRetries retries: $errorMsg"
                }
            }
        }
        
        # Using Az PowerShell for activity logs instead of REST API
        $logs = @()
        $pageCount = 0
        $totalLogs = 0
        
        # Get logs with retry logic
        $logRetryCount = 0
        $logMaxRetries = 2
        $logSuccess = $false
        
        while (-not $logSuccess -and $logRetryCount -le $logMaxRetries) {
            try {
                $firstPage = Get-AzLog -MaxRecord $PageSize -StartTime $startTime -EndTime $endTime -ErrorAction Stop
                if ($firstPage) {
                    $logs += $firstPage
                    $totalLogs += $firstPage.Count
                    $pageCount++
                }
                $logSuccess = $true
            }
            catch {
                $logRetryCount++
                $errorMsg = if ($_.Exception) { $_.Exception.Message } else { "Unknown error" }
                
                if ($logRetryCount -le $logMaxRetries) {
                    Write-Log "Retry $logRetryCount/$logMaxRetries: Error retrieving logs: $errorMsg" -Level 'DEBUG' -Category 'ActivityLogs'
                    Start-Sleep -Seconds 3  # Slightly longer pause for API rate limits
                }
                else {
                    throw "Failed to retrieve logs after $logMaxRetries retries: $errorMsg"
                }
            }
        }
        
        # Process the logs
        $logData.LogCount = $logs.Count
        if ($logs.Count -gt 0) {
            $logData.DailyAverage = [math]::Round(($logs.Count / $DaysToAnalyze), 2)
        }
    }
    catch {
        $errorMsg = if ($_.Exception) { $_.Exception.Message } else { "Unknown error" }
        Write-Log "Log retrieval error for subscription $SubscriptionId : $errorMsg" -Level 'WARNING' -Category 'ActivityLogs'
    }
    
    return $logData
}

# Function to get Entra ID log metrics
function Get-EntraIdLogMetrics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$DaysToAnalyze = 7
    )
    
    # Try to get Entra ID info
    $entraIdInfo = Get-EntraIdInfo
    
    $metrics = @{
        SignInLogCount = 0
        AuditLogCount = 0
        SignInDailyAverage = 0
        AuditDailyAverage = 0
        UserCount = $entraIdInfo.UserCount
        SignInSize = Get-ConfigSetting -Name 'DefaultEntraIdLogSizeKB' -DefaultValue 2.0
        AuditSize = Get-ConfigSetting -Name 'DefaultEntraIdLogSizeKB' -DefaultValue 2.0
        Organization = $entraIdInfo.OrganizationSize
    }
    
    # Default values
    $dailySignInsMap = @{
        "Small" = 5
        "Medium" = 10
        "Large" = 20
    }
    
    $dailyAuditsMap = @{
        "Small" = 1
        "Medium" = 2
        "Large" = 4
    }
    
    $dailySignInsPerUser = $dailySignInsMap[$metrics.Organization]
    $dailyAuditsPerUser = $dailyAuditsMap[$metrics.Organization]
    
    $dailySignIns = $metrics.UserCount * $dailySignInsPerUser
    $dailyAudits = $metrics.UserCount * $dailyAuditsPerUser
    
    $metrics.SignInDailyAverage = [math]::Round($dailySignIns, 2)
    $metrics.AuditDailyAverage = [math]::Round($dailyAudits, 2)
    $metrics.SignInLogCount = [math]::Round(($dailySignIns * $DaysToAnalyze))
    $metrics.AuditLogCount = [math]::Round(($dailyAudits * $DaysToAnalyze))
    
    return $metrics
}

# Function to collect all data needed for cost estimation
function Get-AllCostEstimationData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$DaysToAnalyze = 7,
        
        [Parameter(Mandatory = $false)]
        [int]$SampleLogSize = 50,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory = $(Get-ConfigSetting -Name 'OutputDirectory' -DefaultValue "")
    )
    
    $startTime = Get-Date
    Write-Log "Starting data collection" -Level 'INFO' -Category 'DataCollection'
    
    # Get all subscriptions from Azure
    $subscriptions = Get-SubscriptionList
    
    if ($null -eq $subscriptions -or $subscriptions.Count -eq 0) {
        Write-Log "No subscriptions found" -Level 'ERROR' -Category 'DataCollection'
        
        # Return a minimal structure
        return @{
            CollectionStartTime = $startTime
            EntraIdMetrics = Get-EntraIdLogMetrics -DaysToAnalyze $DaysToAnalyze
            SubscriptionMetadata = @{}
            ActivityLogs = @{}
            Subscriptions = @()
        }
    }
    
    Write-Log "Found $($subscriptions.Count) subscriptions" -Level 'INFO' -Category 'DataCollection'
    
    # Create data structure
    $allData = @{
        CollectionStartTime = $startTime
        EntraIdMetrics = $null
        SubscriptionMetadata = @{}
        ActivityLogs = @{}
        Subscriptions = $subscriptions
    }
    
    # Get Entra ID metrics (tenant-wide)
    $allData.EntraIdMetrics = Get-EntraIdLogMetrics -DaysToAnalyze $DaysToAnalyze
    
    # Get subscription metadata for all subscriptions
    $allData.SubscriptionMetadata = Get-SubscriptionMetadata -Subscriptions $subscriptions
    
    # Get activity logs for each subscription
    $total = $subscriptions.Count
    $current = 0
    
    foreach ($subscription in $subscriptions) {
        $current++
        
        # Skip subscriptions with empty IDs
        if ([string]::IsNullOrEmpty($subscription.Id)) {
            Write-Log "Skipping subscription with empty ID" -Level 'WARNING' -Category 'DataCollection'
            continue
        }
        
        $subId = $subscription.Id
        $subName = "Unknown"
        if (-not [string]::IsNullOrEmpty($subscription.Name)) {
            $subName = $subscription.Name
        }
        
        Write-Log "Processing subscription $subId ($subName)" -Level 'INFO' -Category 'DataCollection'
        
        try {
            $activityLogData = Get-SubscriptionActivityLogs -SubscriptionId $subId -DaysToAnalyze $DaysToAnalyze -SampleSize $SampleLogSize
            $allData.ActivityLogs[$subId] = $activityLogData
        }
        catch {
            $errorMsg = if ($_.Exception) { $_.Exception.Message } else { "Unknown error" }
            Write-Log "Error collecting activity logs for subscription $subId : $errorMsg" -Level 'WARNING' -Category 'DataCollection'
            # Create empty activity log data with default values
            $allData.ActivityLogs[$subId] = @{
                LogCount = 0
                DailyAverage = 0
                AvgLogSizeKB = Get-ConfigSetting -Name 'DefaultActivityLogSizeKB' -DefaultValue 2.5
                SampledLogCount = 0
                ResourceProviders = @{}
                OperationNames = @{}
                LogsByDay = @{}
            }
        }
    }
    
    # Return the data as a properly typed hashtable
    return [hashtable]$allData
}

# Export functions
Export-ModuleMember -Function Get-SubscriptionMetadata, Get-SubscriptionActivityLogs, Get-EntraIdLogMetrics, Get-AllCostEstimationData
