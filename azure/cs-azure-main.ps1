#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    CrowdStrike Azure Cost Estimation Main Script.

.DESCRIPTION
    This PowerShell script serves as the main entry point for the CrowdStrike
    Azure Cost Estimation tool. It authenticates to Azure, retrieves subscription
    information, and prepares for further operations.
#>

#region Configuration Settings
# Centralized configuration parameters for the Azure Cost Estimation Tool
# Modify these settings to customize the behavior of the tool for your environment

$Script:Config = @{
    # Default Azure region to use if subscription region is not specified
    # The script will account for all available Azure regions for pricing calculations
    DefaultRegion = "eastus"
    
    # Currency code for cost reporting
    CurrencyCode = "USD"
    
    # Analysis period configuration
    DefaultSampleDays = 7              # Number of days to sample for log volume analysis
    
    # Output configuration
    OutputFormat = "CSV"               # All outputs are in CSV format
    IncludeDetailedBreakdown = $true   # Whether to include detailed cost breakdown in reports
    IncludeRegionalPricing = $true     # Whether to include regional pricing information
}
#endregion Configuration Settings

# Source required files
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$filesToSource = @(
    "$scriptPath\cs-azure-auth.ps1",
    "$scriptPath\cs-azure-subscriptions.ps1",
    "$scriptPath\cs-azure-logging.ps1",
    "$scriptPath\cs-azure-data-collection.ps1"
)

foreach ($file in $filesToSource) {
    try {
        . $file
        Write-Host "Sourced file: $file" -ForegroundColor DarkGray
    }
    catch {
        Write-Error "Failed to source file $file : $_"
        exit 1
    }
}

# Display simple header
function Show-Header {
    Write-Host "CrowdStrike Azure Cost Estimation Tool v1.0" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------" -ForegroundColor Cyan
}

# Main function
function Start-AzureCostEstimation {
    # Display header
    Show-Header
    
    # Create output directory
    $outputDir = New-OutputDirectory
    Write-LogEntry -Message "Starting Azure Cost Estimation Tool" -OutputDir $outputDir
    
    # Check required modules
    if (-not (Confirm-AzModules)) {
        Write-LogEntry -Message "Required Azure modules are missing. Please install them and try again." -Level ERROR -OutputDir $outputDir
        return
    }
    
    # Authenticate to Azure
    Write-LogEntry -Message "Attempting to authenticate to Azure..." -OutputDir $outputDir
    
    # Standard authentication
    $loginSuccessful = Connect-ToAzure
    
    if (-not $loginSuccessful) {
        Write-LogEntry -Message "Azure authentication failed. Please try again." -Level ERROR -OutputDir $outputDir
        return
    }
    
    Write-LogEntry -Message "Successfully authenticated to Azure." -OutputDir $outputDir
    
    # Retrieve subscription information
    Write-LogEntry -Message "Retrieving Azure subscriptions..." -OutputDir $outputDir
    $subscriptions = Get-AllSubscriptions
    
    if (-not $subscriptions -or $subscriptions.Count -eq 0) {
        Write-LogEntry -Message "No Azure subscriptions found or unable to retrieve subscriptions." -Level WARNING -OutputDir $outputDir
        return
    }
    
    # Format subscription data
    $formattedSubscriptions = Format-SubscriptionData -Subscriptions $subscriptions
    Write-LogEntry -Message "Retrieved $($subscriptions.Count) subscription(s)." -OutputDir $outputDir
    
    # Export subscription data to CSV
    $csvPath = Export-ToCsv -Data $formattedSubscriptions -OutputDir $outputDir -FileName "subscriptions"
    
    if (-not $csvPath) {
        Write-LogEntry -Message "Failed to export subscription data to CSV." -Level ERROR -OutputDir $outputDir
        return
    }
    
    # Display subscription summary on console
    Write-Host "`nSubscription Summary:" -ForegroundColor Green
    $formattedSubscriptions | Format-Table -Property SubscriptionName, SubscriptionId, State -AutoSize
    
    # Collect Activity Log metrics
    Write-LogEntry -Message "Collecting Activity Log metrics for all subscriptions..." -OutputDir $outputDir
    $activityLogMetrics = Get-ActivityLogMetricsForAllSubscriptions -Subscriptions $subscriptions -SampleDays $Script:Config.DefaultSampleDays
    
    # Count successful and failed metrics
    $failedMetrics = @($activityLogMetrics | Where-Object { $_.PSObject.Properties.Name -contains "Error" })
    $successfulMetrics = @($activityLogMetrics | Where-Object { -not ($_.PSObject.Properties.Name -contains "Error") })
    
    if ($failedMetrics.Count -gt 0) {
        Write-LogEntry -Message "Failed to collect metrics for $($failedMetrics.Count) subscription(s). Continuing with available data." -Level WARNING -OutputDir $outputDir
        
        # Log each failure
        foreach ($metric in $failedMetrics) {
            Write-LogEntry -Message "Failed to collect metrics for subscription: $($metric.SubscriptionName) - $($metric.Error)" -Level WARNING -OutputDir $outputDir
        }
    }
    
    # If we have at least some successful metrics, proceed
    if ($successfulMetrics.Count -gt 0) {
        # Export Activity Log metrics to CSV (only the successful ones)
        $activityLogCsvPath = Export-ToCsv -Data $successfulMetrics -OutputDir $outputDir -FileName "activity_log_metrics"
        
        if ($activityLogCsvPath) {
            Write-LogEntry -Message "Activity Log metrics exported to CSV: $activityLogCsvPath" -OutputDir $outputDir
            
            # Display summary of collected metrics
            $totalLogEntries = ($successfulMetrics | Measure-Object -Property TotalLogEntries -Sum).Sum
            $totalDailySize = ($successfulMetrics | Measure-Object -Property EstimatedDailySizeKB -Sum).Sum
            
            Write-Host "`nActivity Log Metrics Summary:" -ForegroundColor Green
            if ($failedMetrics.Count -gt 0) {
                Write-Host "NOTE: Data from $($successfulMetrics.Count) of $($subscriptions.Count) subscriptions (some failed)" -ForegroundColor Yellow
            }
            Write-Host "Total Log Entries: $totalLogEntries" -ForegroundColor White
            Write-Host "Estimated Daily Size (KB): $totalDailySize" -ForegroundColor White
            Write-Host "Sample Period (days): $($Script:Config.DefaultSampleDays)" -ForegroundColor White
            
            # Show per-subscription breakdown if multiple successful subscriptions
            if ($successfulMetrics.Count -gt 1) {
                Write-Host "`nPer-Subscription Activity Log Metrics:" -ForegroundColor Green
                $successfulMetrics | Format-Table -Property SubscriptionName, TotalLogEntries, AverageEntriesPerDay, EstimatedDailySizeKB -AutoSize
            }
            
            Write-LogEntry -Message "Azure Cost Estimation Tool completed successfully." -OutputDir $outputDir
        }
        else {
            Write-LogEntry -Message "Failed to export Activity Log metrics to CSV." -Level ERROR -OutputDir $outputDir
        }
    }
    else {
        Write-LogEntry -Message "Failed to collect any subscription metrics. Check logs for details." -Level ERROR -OutputDir $outputDir
    }
}

# Execute the main function
Start-AzureCostEstimation
