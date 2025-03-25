#Requires -Modules Az.Accounts, Az.Monitor

# Add System.Web for URL encoding
Add-Type -AssemblyName System.Web

# ====================================================================
# !!!          IMPORTANT MAINTAINER NOTES AND WARNINGS            !!!
# ====================================================================
# 1. DO NOT USE THE DETAILEDOUTPUT PARAMETER with Get-AzActivityLog
#    This parameter is deprecated and causes warnings.
#
# 2. ACTIVITY LOG COLLECTION APPROACHES
#    Two methods are available for Activity Log collection:
#    a) Simple method: Get-AzActivityLog with 1000 record limit
#    b) Time-chunking method: Get-AllActivityLogsWithChunking breaks
#       time periods into smaller chunks to bypass the 1000-record limit
#
# 3. REST API PAGINATION CAUTION
#    Do not implement custom REST API pagination without thorough testing.
#    Previous attempts have resulted in 404 errors due to various issues
#    with the REST API endpoints.
# ====================================================================

<#
.SYNOPSIS
    Azure data collection module for cost estimation.

.DESCRIPTION
    This PowerShell module handles collection of metrics and data required
    for accurate cost estimation of CrowdStrike resources in Azure.
#>

# Source extended activity log function with time-chunking
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$activityLogsFilePath = Join-Path -Path $scriptPath -ChildPath "cs-azure-activity-logs.ps1"
. $activityLogsFilePath

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
        [string]$OutputDir = $null,
        
        [Parameter(Mandatory = $false)]
        [int]$CurrentSubscriptionNumber = 0,
        
        [Parameter(Mandatory = $false)]
        [int]$TotalSubscriptions = 0
    )
    
    $currentContext = $null
    $startTime = $null
    $endTime = $null
    
    try {
        # Select the subscription
        # Using -Subscription parameter which accepts subscription IDs (SubscriptionId is an alias)
        $currentContext = Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop
        
        # Calculate time range for log collection
        $endTime = Get-Date
        $startTime = $endTime.AddDays(-$SampleDays)
        
        # Build a prefix for status messages if we have subscription count info
        $subCountPrefix = ""
        if ($CurrentSubscriptionNumber -gt 0 -and $TotalSubscriptions -gt 0) {
            $subCountPrefix = "[$CurrentSubscriptionNumber/$TotalSubscriptions] "
        }
        
        Write-Host "${subCountPrefix}Collecting Activity Log metrics for subscription: $($currentContext.Subscription.Name)" -ForegroundColor Cyan
        Write-Host "Time range: $startTime to $endTime" -ForegroundColor DarkGray
        
        # Retrieve Activity Logs for the time period with detailed status updates
        Write-Host "${subCountPrefix}Starting Activity Log query for subscription: $($currentContext.Subscription.Name) (this may take some time)..." -ForegroundColor Cyan
        
        # Write to log file if OutputDir is provided
        if ($OutputDir) {
            Write-LogEntry -Message "${subCountPrefix}Starting Activity Log query for subscription: $($currentContext.Subscription.Name)" -OutputDir $OutputDir
        }
        
        # Set up activity name to include subscription count if available
        $activityName = "Retrieving Activity Logs"
        if ($CurrentSubscriptionNumber -gt 0 -and $TotalSubscriptions -gt 0) {
            $activityName = "Retrieving Activity Logs (Subscription $CurrentSubscriptionNumber of $TotalSubscriptions)"
        }
        
        # Show progress indicator while querying
        $progressParams = @{
            Activity = $activityName
            Status = "Querying logs for subscription: $($currentContext.Subscription.Name)"
            PercentComplete = 10
        }
        Write-Progress @progressParams
        
        # Retrieve Activity Logs with proper pagination to handle more than 1000 results
        Write-Progress @progressParams -Status "${subCountPrefix}Retrieving initial logs for subscription: $($currentContext.Subscription.Name)" -PercentComplete 20
        
        if ($OutputDir) {
            Write-LogEntry -Message "${subCountPrefix}Starting paginated Activity Log retrieval for subscription: $($currentContext.Subscription.Name)" -OutputDir $OutputDir
        }
        
        # Use REST API with pagination since Get-AzActivityLog doesn't support continuation tokens
        # Use the Enhanced Get-AllActivityLogsWithChunking function to retrieve ALL activity logs
        # bypassing the 1000-record limitation by breaking the time period into smaller chunks
        Write-Host "${subCountPrefix}Using time-chunking method to retrieve all Activity Logs (bypassing 1000-record limit)" -ForegroundColor Cyan
        
        $activityLogs = Get-AllActivityLogsWithChunking `
            -SubscriptionId $SubscriptionId `
            -StartTime $startTime `
            -EndTime $endTime `
            -InitialChunkSizeHours 24 `
            -OutputDir $OutputDir `
            -CurrentSubscriptionNumber $CurrentSubscriptionNumber `
            -TotalSubscriptions $TotalSubscriptions
        
        Write-Progress @progressParams -PercentComplete 100 -Completed
        Write-Host "${subCountPrefix}Completed Activity Log query for subscription: $($currentContext.Subscription.Name). Found $($activityLogs.Count) total log entries." -ForegroundColor Green
        
        # Write to log file if OutputDir is provided
        if ($OutputDir) {
            Write-LogEntry -Message "${subCountPrefix}Completed Activity Log query for subscription: $($currentContext.Subscription.Name). Found $($activityLogs.Count) log entries." -OutputDir $OutputDir
        }
        
        # If no logs found, return empty metrics
        if ($null -eq $activityLogs -or $activityLogs.Count -eq 0) {
            Write-Host "${subCountPrefix}No Activity Logs found for the specified time period." -ForegroundColor Yellow
            
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
        
        $metrics = Get-ActivityLogMetrics -SubscriptionId $subscription.Id -SampleDays $SampleDays -OutputDir $OutputDir -CurrentSubscriptionNumber $currentSubscription -TotalSubscriptions $totalSubscriptions
        
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
