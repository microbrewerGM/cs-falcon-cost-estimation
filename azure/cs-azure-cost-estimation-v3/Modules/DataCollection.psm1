# Simplified data collection module for CrowdStrike Azure Cost Estimation Tool v3

# Function to get metadata about subscriptions (region, tags, etc.)
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
            Write-Log "Error getting subscriptions: $($_.Exception.Message)" -Level 'ERROR' -Category 'Subscription'
            return $metadataCollection
        }
    }
    
    Write-Log "Collecting metadata for $($Subscriptions.Count) subscriptions..." -Level 'INFO' -Category 'Subscription'
    
    foreach ($subscription in $Subscriptions) {
        $subscriptionId = $subscription.Id
        $subscriptionName = $subscription.Name
        
        Write-Log "Processing subscription: $subscriptionName ($subscriptionId)" -Level 'INFO' -Category 'Subscription'
        
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
            # Set context to subscription
            $contextSet = $false
            try {
                Set-AzContext -Subscription $subscriptionId -ErrorAction Stop | Out-Null
                $contextSet = $true
            }
            catch {
                Write-Log "Error setting context to subscription $subscriptionId : $($_.Exception.Message)" -Level 'WARNING' -Category 'Subscription'
                # Skip this subscription
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
            
            # If no environment tag, try to determine from subscription name
            if ($metadata.Environment -eq $DefaultEnvironment) {
                $metadata.Environment = Get-EnvironmentType -SubscriptionName $subscriptionName -Tags $metadata.Tags
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
            if ($contextSet) {
                try {
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
                    Write-Log "Error getting resource groups for subscription $subscriptionId : $($_.Exception.Message)" -Level 'WARNING' -Category 'Subscription'
                }
            }
            
            # If still no primary location, use default
            if ($metadata.PrimaryLocation -eq "unknown") {
                $metadata.PrimaryLocation = Get-ConfigSetting -Name 'DefaultRegion' -DefaultValue 'eastus'
            }
        }
        catch {
            Write-Log "Error retrieving metadata for subscription $subscriptionId : $($_.Exception.Message)" -Level 'WARNING' -Category 'Subscription'
        }
        
        # Add to collection
        $metadataCollection[$subscriptionId] = $metadata
    }
    
    Write-Log "Completed metadata collection for $($metadataCollection.Count) subscriptions" -Level 'SUCCESS' -Category 'Subscription'
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
    
    Write-Log "Retrieving activity logs for subscription $SubscriptionId from $startTime to $endTime" -Level 'INFO' -Category 'ActivityLogs'
    
    try {
        # Set context to subscription
        Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
        
        # Using Az PowerShell for activity logs instead of REST API
        $filter = "(eventTimestamp ge '$($startTime.ToString('yyyy-MM-ddTHH:mm:ss'))' and eventTimestamp le '$($endTime.ToString('yyyy-MM-ddTHH:mm:ss'))')"
        $logs = @()
        $pageCount = 0
        $totalLogs = 0
        
        # Get first page
        $firstPage = Get-AzLog -MaxRecord $PageSize -StartTime $startTime -EndTime $endTime -ErrorAction Stop
        if ($firstPage) {
            $logs += $firstPage
            $totalLogs += $firstPage.Count
            $pageCount++
            
            # Retrieve additional pages if needed
            $lastRecord = $firstPage | Select-Object -Last 1
            while ($firstPage.Count -eq $PageSize -and $totalLogs -lt $MaxResults) {
                $firstPage = Get-AzLog -MaxRecord $PageSize -StartTime $startTime -EndTime $lastRecord.EventTimestamp.AddMilliseconds(-1) -ErrorAction Stop
                if ($firstPage -and $firstPage.Count -gt 0) {
                    $logs += $firstPage
                    $totalLogs += $firstPage.Count
                    $lastRecord = $firstPage | Select-Object -Last 1
                    $pageCount++
                }
                else {
                    break
                }
                
                # Limit the number of pages to avoid excessive API calls
                if ($pageCount -ge 10) {
                    Write-Log "Reached maximum page limit (10) for activity logs" -Level 'WARNING' -Category 'ActivityLogs'
                    break
                }
            }
        }
        
        # Process the logs
        $logData.LogCount = $logs.Count
        if ($logs.Count -gt 0) {
            $logData.DailyAverage = [math]::Round($logs.Count / $DaysToAnalyze, 2)
            
            # Group logs by resource provider
            $resourceProviders = $logs | Group-Object -Property ResourceProviderName | 
                                 Where-Object { $_.Name -ne "" } | 
                                 Select-Object Name, Count | 
                                 Sort-Object -Property Count -Descending
            
            foreach ($rp in $resourceProviders) {
                if (-not [string]::IsNullOrEmpty($rp.Name)) {
                    $logData.ResourceProviders[$rp.Name] = $rp.Count
                }
            }
            
            # Group logs by operation name
            $operations = $logs | Group-Object -Property OperationName | 
                          Where-Object { $_.Name -ne "" } | 
                          Select-Object Name, Count | 
                          Sort-Object -Property Count -Descending
            
            foreach ($op in $operations) {
                if (-not [string]::IsNullOrEmpty($op.Name)) {
                    $logData.OperationNames[$op.Name] = $op.Count
                }
            }
            
            # Group logs by day
            $logsByDay = $logs | Group-Object { $_.EventTimestamp.ToString("yyyy-MM-dd") } | 
                        Select-Object Name, Count | 
                        Sort-Object -Property Name
            
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
                    $jsonSize = [System.Text.Encoding]::UTF8.GetByteCount(($log | ConvertTo-Json -Depth 5 -Compress))
                    $sizeKB = $jsonSize / 1024
                    $totalSize += $sizeKB
                }
                
                $logData.AvgLogSizeKB = [math]::Round($totalSize / $samplesToTake, 2)
                $logData.SampledLogCount = $samplesToTake
                
                Write-Log "Sampled $samplesToTake logs. Average log size: $($logData.AvgLogSizeKB) KB" -Level 'INFO' -Category 'ActivityLogs'
            }
        }
        
        Write-Log "Activity log collection complete. Found $($logData.LogCount) logs (Daily average: $($logData.DailyAverage))" -Level 'SUCCESS' -Category 'ActivityLogs'
    }
    catch {
        Write-Log "Failed to retrieve activity logs: $($_.Exception.Message)" -Level 'WARNING' -Category 'ActivityLogs'
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
    
    Write-Log "Analyzing Entra ID metrics..." -Level 'INFO' -Category 'EntraID'
    
    # Calculate estimated log counts
    $dailySignInsPerUser = $SignInsPerUserPerDay[$metrics.Organization]
    $dailyAuditsPerUser = $AuditsPerUserPerDay[$metrics.Organization]
    
    $dailySignIns = $metrics.UserCount * $dailySignInsPerUser
    $dailyAudits = $metrics.UserCount * $dailyAuditsPerUser
    
    $metrics.SignInDailyAverage = [math]::Round($dailySignIns, 2)
    $metrics.AuditDailyAverage = [math]::Round($dailyAudits, 2)
    $metrics.SignInLogCount = [math]::Round($dailySignIns * $DaysToAnalyze)
    $metrics.AuditLogCount = [math]::Round($dailyAudits * $DaysToAnalyze)
    
    Write-Log "Organization size: $($metrics.Organization), Users: $($metrics.UserCount)" -Level 'INFO' -Category 'EntraID'
    Write-Log "Estimated sign-in logs: $($metrics.SignInLogCount), Daily: $($metrics.SignInDailyAverage)" -Level 'INFO' -Category 'EntraID'
    Write-Log "Estimated audit logs: $($metrics.AuditLogCount), Daily: $($metrics.AuditDailyAverage)" -Level 'INFO' -Category 'EntraID'
    
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
    Write-Log "Starting data collection for all subscriptions..." -Level 'INFO' -Category 'DataCollection'
    
    # Get all subscriptions
    $subscriptions = Get-SubscriptionList
    if ($subscriptions.Count -eq 0) {
        Write-Log "No subscriptions found. Cannot collect data." -Level 'ERROR' -Category 'DataCollection'
        return $null
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
        $subId = $subscription.Id
        $subName = $subscription.Name
        
        Write-Log "Collecting activity logs for subscription $current of $total: $subName" -Level 'INFO' -Category 'DataCollection'
        
        $activityLogData = Get-SubscriptionActivityLogs -SubscriptionId $subId -DaysToAnalyze $DaysToAnalyze -SampleSize $SampleLogSize
        $allData.ActivityLogs[$subId] = $activityLogData
        
        # Create progress status
        $status = @{
            "Total" = $total
            "Processed" = $current
            "Percentage" = [math]::Round(($current / $total) * 100)
            "CurrentlyProcessing" = $subName
        }
        
        # Save status to file if output directory is provided
        if ($OutputDirectory -and (Test-Path $OutputDirectory)) {
            $statusPath = Join-Path $OutputDirectory "status.json"
            $status | ConvertTo-Json | Out-File -FilePath $statusPath -Force
        }
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    Write-Log "Data collection complete. Processed $total subscriptions in $($duration.TotalMinutes.ToString("N2")) minutes." -Level 'SUCCESS' -Category 'DataCollection'
    
    return $allData
}

# Export functions
Export-ModuleMember -Function Get-SubscriptionMetadata, Get-SubscriptionActivityLogs, Get-EntraIdLogMetrics, Get-AllCostEstimationData
