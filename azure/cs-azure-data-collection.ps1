#Requires -Modules Az.Accounts, Az.Monitor

<#
.SYNOPSIS
    Azure data collection module for cost estimation.

.DESCRIPTION
    This PowerShell module handles collection of metrics and data required
    for accurate cost estimation of CrowdStrike resources in Azure.
#>

function Get-ActivityLogMetrics {
    <#
    .SYNOPSIS
        Collects Activity Log metrics for a subscription.
    
    .DESCRIPTION
        Retrieves Activity Log count and volume metrics for a specified
        subscription over a configurable time period.
        
    .PARAMETER SubscriptionId
        The ID of the subscription to collect Activity Log metrics for.
        
    .PARAMETER SampleDays
        Number of days to sample for metrics collection.
        
    .PARAMETER OutputDir
        Directory to write logs to.
        
    .OUTPUTS
        [PSCustomObject] Object containing Activity Log metrics.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $false)]
        [int]$SampleDays = 7,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputDir = $null
    )
    
    $currentContext = $null
    $startTime = $null
    $endTime = $null
    
    try {
        # Select the subscription
        $currentContext = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
        
        # Calculate time range for log collection
        $endTime = Get-Date
        $startTime = $endTime.AddDays(-$SampleDays)
        
        Write-Host "Collecting Activity Log metrics for subscription: $($currentContext.Subscription.Name)" -ForegroundColor Cyan
        Write-Host "Time range: $startTime to $endTime" -ForegroundColor DarkGray
        
        # Retrieve Activity Logs for the time period with detailed status updates
        Write-Host "Starting Activity Log query for subscription: $($currentContext.Subscription.Name) (this may take some time)..." -ForegroundColor Cyan
        
        # Write to log file if OutputDir is provided
        if ($OutputDir) {
            Write-LogEntry -Message "Starting Activity Log query for subscription: $($currentContext.Subscription.Name)" -OutputDir $OutputDir
        }
        
        # Show progress indicator while querying
        $progressParams = @{
            Activity = "Retrieving Activity Logs" 
            Status = "Querying logs for subscription: $($currentContext.Subscription.Name)"
            PercentComplete = 10
        }
        Write-Progress @progressParams
        
        # Using Get-AzActivityLog with paging to handle large result sets
        $allActivityLogs = @()
        $pageNumber = 1
        $maxRecordsPerPage = 1000  # Maximum allowed by the API
        $hasMoreRecords = $true
        
        while ($hasMoreRecords) {
            Write-Progress @progressParams -Status "Retrieving page $pageNumber for subscription: $($currentContext.Subscription.Name)" -PercentComplete ((($pageNumber - 1) % 10) * 10)
            
            if ($OutputDir) {
                Write-LogEntry -Message "Retrieving Activity Log page $pageNumber for subscription: $($currentContext.Subscription.Name)" -OutputDir $OutputDir
            }
            
            if ($pageNumber -eq 1) {
                # First page
                $response = Get-AzActivityLog -StartTime $startTime -EndTime $endTime -MaxRecord $maxRecordsPerPage
            }
            else {
                # Subsequent pages with continuation token
                $response = Get-AzActivityLog -StartTime $startTime -EndTime $endTime -MaxRecord $maxRecordsPerPage -ContinuationToken $continuationToken
            }
            
            # Add results to our collection
            $allActivityLogs += $response
            
            # Check for continuation token to see if there are more pages
            if ($response.PSAzureOperationResponse -and 
                $response.PSAzureOperationResponse.ContinuationToken) {
                $continuationToken = $response.PSAzureOperationResponse.ContinuationToken
                $hasMoreRecords = $true
                $pageNumber++
                
                # Log progress for large result sets
                if ($OutputDir) {
                    Write-LogEntry -Message "Retrieved $($response.Count) records from page $($pageNumber-1). More records exist." -OutputDir $OutputDir
                }
                
                Write-Host "Retrieved $($response.Count) log entries from page $($pageNumber-1). Continuing to next page..." -ForegroundColor Cyan
            }
            else {
                $hasMoreRecords = $false
                
                if ($pageNumber -gt 1) {
                    Write-Host "Retrieved $($response.Count) log entries from final page $($pageNumber). No more records exist." -ForegroundColor Cyan
                }
            }
        }
        
        # Assign the collected logs
        $activityLogs = $allActivityLogs
        
        Write-Progress @progressParams -PercentComplete 100 -Completed
        Write-Host "Completed Activity Log query for subscription: $($currentContext.Subscription.Name). Found $($activityLogs.Count) log entries across $pageNumber page(s)." -ForegroundColor Green
        
        # Write to log file if OutputDir is provided
        if ($OutputDir) {
            Write-LogEntry -Message "Completed Activity Log query for subscription: $($currentContext.Subscription.Name). Found $($activityLogs.Count) log entries." -OutputDir $OutputDir
        }
        
        # If no logs found, return empty metrics
        if ($null -eq $activityLogs -or $activityLogs.Count -eq 0) {
            Write-Host "No Activity Logs found for the specified time period." -ForegroundColor Yellow
            
            return [PSCustomObject]@{
                SubscriptionId = $SubscriptionId
                SubscriptionName = $currentContext.Subscription.Name
                TotalLogEntries = 0
                AverageEntriesPerDay = 0
                EstimatedSizeKB = 0
                EstimatedDailySizeKB = 0
                SampleDays = $SampleDays
                TimeRange = "$startTime to $endTime"
            }
        }
        
        # Calculate metrics
        $totalLogEntries = $activityLogs.Count
        $averageEntriesPerDay = [math]::Ceiling($totalLogEntries / $SampleDays)
        
        # Estimate size (using 1KB as average size per log entry as mentioned in the plan)
        $averageLogSizeKB = 1.0
        $estimatedSizeKB = $totalLogEntries * $averageLogSizeKB
        $estimatedDailySizeKB = $averageEntriesPerDay * $averageLogSizeKB
        
        # Return metrics object
        return [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = $currentContext.Subscription.Name
            TotalLogEntries = $totalLogEntries
            AverageEntriesPerDay = $averageEntriesPerDay
            EstimatedSizeKB = $estimatedSizeKB
            EstimatedDailySizeKB = $estimatedDailySizeKB
            SampleDays = $SampleDays
            TimeRange = "$startTime to $endTime"
        }
    }
    catch {
        Write-Error "Error collecting Activity Log metrics for subscription $SubscriptionId : $_"
        
        # Determine subscription name for error reporting
        $subName = "Unknown"
        if ($null -ne $currentContext -and $null -ne $currentContext.Subscription) {
            $subName = $currentContext.Subscription.Name
        }
        
        # Create time range string for error reporting
        $timeRangeString = "Unknown time range"
        if ($null -ne $startTime -and $null -ne $endTime) {
            $timeRangeString = "$startTime to $endTime"
        }
        
        # Create and return error object
        $errorObj = [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            SubscriptionName = $subName
            Error = $_.Exception.Message
            SampleDays = $SampleDays
            TimeRange = $timeRangeString
        }
        
        return $errorObj
    }
}

function Get-ActivityLogMetricsForAllSubscriptions {
    <#
    .SYNOPSIS
        Collects Activity Log metrics for all accessible subscriptions.
    
    .DESCRIPTION
        Iterates through all accessible subscriptions and collects Activity Log metrics
        for each, aggregating the results into a collection.
        
    .PARAMETER Subscriptions
        Array of subscription objects to process.
        
    .PARAMETER SampleDays
        Number of days to sample for metrics collection.
        
    .PARAMETER OutputDir
        Directory to write logs to.
        
    .OUTPUTS
        [PSCustomObject[]] Array of Activity Log metrics objects.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Subscriptions,
        
        [Parameter(Mandatory = $false)]
        [int]$SampleDays = 7,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputDir = $null
    )
    
    $allMetrics = @()
    $totalSubscriptions = $Subscriptions.Count
    $currentSubscription = 0
    $failedSubscriptions = @()
    
    foreach ($subscription in $Subscriptions) {
        $currentSubscription++
        
        # Skip if subscription ID is missing
        if (-not $subscription.Id) {
            Write-Warning "Skipping subscription with missing ID: $($subscription.Name)"
            continue
        }
        
        # Progress indicator
        Write-Progress -Activity "Collecting Activity Log Metrics" -Status "Processing subscription $currentSubscription of $totalSubscriptions" -PercentComplete (($currentSubscription / $totalSubscriptions) * 100)
        
        # Get metrics for this subscription
        Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Cyan
        
        # Write to log file if OutputDir is provided
        if ($OutputDir) {
            Write-LogEntry -Message "Processing subscription: $($subscription.Name) ($($subscription.Id))" -OutputDir $OutputDir
        }
        
        $metrics = Get-ActivityLogMetrics -SubscriptionId $subscription.Id -SampleDays $SampleDays -OutputDir $OutputDir
        
        # Check if there was an error in the metrics retrieval
        if ($metrics.PSObject.Properties.Name -contains "Error") {
            Write-Warning "Failed to collect metrics for subscription: $($subscription.Name) - $($metrics.Error)"
            $failedSubscriptions += $subscription.Name
        }
        
        $allMetrics += $metrics
        
        # Throttle requests to avoid Azure API limits
        Start-Sleep -Milliseconds 500
    }
    
    Write-Progress -Activity "Collecting Activity Log Metrics" -Completed
    
    # Report on any failed subscriptions
    if ($failedSubscriptions.Count -gt 0) {
        Write-Host "Failed to collect metrics for $($failedSubscriptions.Count) subscription(s):" -ForegroundColor Yellow
        foreach ($sub in $failedSubscriptions) {
            Write-Host " - $sub" -ForegroundColor Yellow
        }
        Write-Host "The tool will continue with available data. See logs for details." -ForegroundColor Yellow
    }
    
    return $allMetrics
}

# Functions are exposed via dot-sourcing
