#!/usr/bin/env pwsh
#
# CrowdStrike Azure Cost Estimation Tool v3
# 
# This script estimates the cost of implementing CrowdStrike's security solutions
# in Azure environments by analyzing subscription activity logs and other metrics.
#
# Browser-based Authentication & Simplified Version

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = "",
    
    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,
    
    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 7,
    
    [Parameter(Mandatory = $false)]
    [int]$LogRetentionDays = 30,
    
    [Parameter(Mandatory = $false)]
    [switch]$ForceRefreshPricing = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$Quiet = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$DebugMode = $false
)

# Script Settings
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Suppress progress bars

# Script Variables
$script:ScriptStartTime = Get-Date
$script:ScriptPath = $PSScriptRoot
$script:ModulesPath = Join-Path $PSScriptRoot "Modules"

# Import all modules
$modules = @(
    "Logging",
    "Config",
    "Authentication",
    "Pricing",
    "DataCollection",
    "CostEstimation",
    "Reporting"
)

# Silence module import messages (unless debugging)
$VerbosePreference = if ($DebugMode) { 'Continue' } else { 'SilentlyContinue' }

Write-Host "Loading modules..." -ForegroundColor Cyan
foreach ($module in $modules) {
    $modulePath = Join-Path $script:ModulesPath "$module.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -Verbose:$DebugMode
    }
    else {
        Write-Host "Error: Module $module not found at $modulePath" -ForegroundColor Red
        exit 1
    }
}
Write-Host "All modules loaded successfully" -ForegroundColor Green

function Start-CostEstimation {
    # Set minimum log level based on parameters
    if ($DebugMode) {
        Set-MinimumLogLevel -Level 'DEBUG'
    }
    elseif ($Quiet) {
        Set-MinimumLogLevel -Level 'WARNING'
    }
    else {
        Set-MinimumLogLevel -Level 'INFO'
    }
    
    # Initialize output paths
    $paths = Initialize-OutputPaths -OutputDirectory $OutputDirectory
    
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "CrowdStrike Azure Cost Estimation" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "Output directory: $($paths.OutputDirectory)" -ForegroundColor Cyan
    
    # Setup logging
    Set-LogFilePath -Path $paths.LogFilePath
    Write-Log "Starting CrowdStrike Azure Cost Estimation v3" -Level 'INFO' -Category 'Main'
    
    # Initialize configuration
    Initialize-Configuration
    Write-Log "Configuration initialized" -Level 'DEBUG' -Category 'Main'
    
    # Set pricing cache path
    Set-PricingCachePath -Path $paths.PricingCachePath
    
    # Initialize Azure connection
    Write-Log "Connecting to Azure..." -Level 'INFO' -Category 'Main'
    $connectionSuccess = Initialize-AzureConnection -TenantId $TenantId
    
    if (-not $connectionSuccess) {
        Write-Log "Failed to connect to Azure. Exiting." -Level 'ERROR' -Category 'Main'
        return
    }
    
    # Get pricing information
    Write-Log "Retrieving pricing information..." -Level 'INFO' -Category 'Main'
    $rawPricingInfo = if ($ForceRefreshPricing) {
        Get-AzureRetailRates -ForceRefresh
    }
    else {
        Get-AzureRetailRates
    }
    
    # Ensure pricing info is a hashtable
    Write-Log "Pricing info type: $($rawPricingInfo.GetType().FullName)" -Level 'DEBUG' -Category 'Main'
    [hashtable]$pricingInfo = @{}
    foreach ($key in $rawPricingInfo.Keys) {
        $pricingInfo[$key] = $rawPricingInfo[$key]
    }
    Write-Log "Processed pricing type: $($pricingInfo.GetType().FullName)" -Level 'DEBUG' -Category 'Main'
    
    # Collect data from all subscriptions
    Write-Log "Collecting data from all subscriptions..." -Level 'INFO' -Category 'Main'
    $collectedData = Get-AllCostEstimationData -DaysToAnalyze $DaysToAnalyze -OutputDirectory $paths.OutputDirectory
    
    if (-not $collectedData) {
        Write-Log "No data collected. Exiting." -Level 'ERROR' -Category 'Main'
        return
    }
    
    # Calculate cost estimates
    Write-Log "Calculating cost estimates..." -Level 'INFO' -Category 'Main'
    
    # Add debugging for data type
    Write-Log "CollectedData type: $($collectedData.GetType().FullName)" -Level 'DEBUG' -Category 'Main'
    Write-Log "CollectedData keys: $($collectedData.Keys -join ', ')" -Level 'DEBUG' -Category 'Main'
    
    # Ensure the data is properly cast as a hashtable
    [hashtable]$collectedDataHash = @{}
    foreach ($key in $collectedData.Keys) {
        $collectedDataHash[$key] = $collectedData[$key]
    }
    
    Write-Log "Processed data type: $($collectedDataHash.GetType().FullName)" -Level 'DEBUG' -Category 'Main'
    
    # Call with explicitly cast hashtable
    $estimates = Get-AllSubscriptionsCostEstimate -CollectedData $collectedDataHash -Pricing $pricingInfo
    
    if ($estimates.Count -eq 0) {
        Write-Log "No cost estimates generated. Exiting." -Level 'ERROR' -Category 'Main'
        return
    }
    
    # Get business unit summary
    Write-Log "Creating business unit cost summary..." -Level 'INFO' -Category 'Main'
    $rawBuSummary = Get-BusinessUnitCostSummary -SubscriptionEstimates $estimates
    
    # Ensure business unit summary is a hashtable
    [hashtable]$buSummary = @{}
    if ($rawBuSummary -and $rawBuSummary.Keys) {
        foreach ($key in $rawBuSummary.Keys) {
            $buSummary[$key] = $rawBuSummary[$key]
        }
    }
    Write-Log "Business unit summary type: $($buSummary.GetType().FullName)" -Level 'DEBUG' -Category 'Main'
    
    # Export reports
    Write-Log "Generating reports..." -Level 'INFO' -Category 'Main'
    
    $reportsGenerated = 0
    
    # Export main cost estimates to CSV
    $csvSuccess = Export-CostEstimatesToCsv -SubscriptionEstimates $estimates -OutputFilePath $paths.OutputFilePath
    if ($csvSuccess) { $reportsGenerated++ }
    
    # Handle empty business unit summary 
    if ($buSummary.Count -gt 0) {
        # Export business unit summary to CSV
        $buCsvSuccess = Export-BusinessUnitCostsToCsv -BusinessUnitSummary $buSummary -OutputFilePath $paths.BusinessUnitReportPath
        if ($buCsvSuccess) { $reportsGenerated++ }
    } else {
        Write-Log "Skipping business unit report: No business units found" -Level 'INFO' -Category 'Main'
    }
    
    # Export all data to JSON
    # Explicitly cast EntraIdMetrics to a hashtable in case it's an array
    [hashtable]$entraIdMetricsHash = @{}
    if ($collectedData.EntraIdMetrics -and $collectedData.EntraIdMetrics.Keys) {
        foreach ($key in $collectedData.EntraIdMetrics.Keys) {
            $entraIdMetricsHash[$key] = $collectedData.EntraIdMetrics[$key]
        }
    }
    
    $jsonSuccess = Export-SummaryToJson -SubscriptionEstimates $estimates -BusinessUnitSummary $buSummary -EntraIdData $entraIdMetricsHash -OutputFilePath $paths.SummaryJsonPath
    if ($jsonSuccess) { $reportsGenerated++ }
    
    # Calculate script execution time
    $executionTime = (Get-Date) - $script:ScriptStartTime
    $executionTimeFormatted = "{0:hh\:mm\:ss}" -f $executionTime
    
    # Output summary - handle null values defensively
    $totalCost = 0
    if ($estimates -and $estimates.Count -gt 0) {
        $measureResult = $estimates | Measure-Object -Property MonthlyCost -Sum
        if ($measureResult) {
            $totalCost = $measureResult.Sum
        }
    }
    
    $totalSubscriptions = if ($estimates) { $estimates.Count } else { 0 }
    
    Write-Host "`n=================================" -ForegroundColor Green
    Write-Host "Cost Estimation Complete" -ForegroundColor Green
    Write-Host "=================================" -ForegroundColor Green
    Write-Host "Analyzed $totalSubscriptions subscriptions" -ForegroundColor Cyan
    Write-Host "Total Estimated Monthly Cost: `$$($totalCost.ToString('N2'))" -ForegroundColor Yellow
    Write-Host "Total Estimated Annual Cost:  `$$([math]::Round($totalCost * 12, 2).ToString('N2'))" -ForegroundColor Yellow
    Write-Host "Execution Time: $executionTimeFormatted" -ForegroundColor Cyan
    Write-Host "Generated $reportsGenerated reports" -ForegroundColor Cyan
    Write-Host "`nReports saved to:" -ForegroundColor Green
    Write-Host "  - Main CSV: $($paths.OutputFilePath)" -ForegroundColor White
    Write-Host "  - Business Unit CSV: $($paths.BusinessUnitReportPath)" -ForegroundColor White
    Write-Host "  - Summary JSON: $($paths.SummaryJsonPath)" -ForegroundColor White
    Write-Host "  - Log File: $($paths.LogFilePath)" -ForegroundColor White
    
    Write-Log "Cost estimation complete. Analyzed $totalSubscriptions subscriptions. Total Monthly Cost: `$$($totalCost.ToString('N2'))" -Level 'SUCCESS' -Category 'Main'
    
    # Return the paths to the reports
    return $paths
}

# Start the cost estimation process
Start-CostEstimation
