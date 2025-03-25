<#
.SYNOPSIS
CrowdStrike Azure Cost Estimation Tool (Modular Version)

.DESCRIPTION
This modular script estimates the costs of deploying CrowdStrike Falcon Cloud Security integration in Azure.
It provides accurate estimates by analyzing actual log sizes, supporting business unit attribution,
retrieving current pricing information, and optimizing performance for large environments.

.PARAMETER DaysToAnalyze
Number of days of logs to analyze. Default is 7.

.PARAMETER DefaultSubscriptionId
The subscription ID where CrowdStrike resources will be deployed. If not specified, the script
will prompt for selection.

.PARAMETER OutputDirectory
Path to the directory where output files will be saved. Default is "cs-azure-cost-estimate-<timestamp>" in the current directory.

.PARAMETER OutputFilePath
Path to the CSV output file. Default is "<OutputDirectory>/cs-azure-cost-estimate.csv".

.PARAMETER LogFilePath
Path to the log file. Default is "<OutputDirectory>/cs-azure-cost-estimate.log".

.PARAMETER SampleLogSize
Number of logs to sample for size calculation. Default is 100.

.PARAMETER UseRealPricing
Use Azure Retail Rates API for current pricing instead of static pricing data. Default is $true.

.PARAMETER ParallelExecution
Enable parallel execution for data collection from multiple subscriptions. Default is $true.

.PARAMETER MaxParallelJobs
Maximum number of parallel jobs when ParallelExecution is enabled. Default is 5.

.PARAMETER BusinessUnitTagName
The tag name used for business unit attribution. Default is "BusinessUnit".

.PARAMETER IncludeManagementGroups
Include management group structure for organizational reporting. Default is $true.

.EXAMPLE
.\cs-azure-cost-estimation-modular.ps1 -DaysToAnalyze 14 -SampleLogSize 200

.NOTES
Requires Azure PowerShell module and appropriate permissions to query:
- Subscriptions and Management Groups
- Activity Logs
- Entra ID logs (requires Global Reader, Security Reader, or higher permissions)
- Resource information
- Azure Retail Rates API (if UseRealPricing is enabled)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 7,

    [Parameter(Mandatory = $false)]
    [string]$DefaultSubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = "",

    [Parameter(Mandatory = $false)]
    [string]$OutputFilePath = "",

    [Parameter(Mandatory = $false)]
    [string]$LogFilePath = "",

    [Parameter(Mandatory = $false)]
    [int]$SampleLogSize = 100,

    [Parameter(Mandatory = $false)]
    [bool]$UseRealPricing = $true,

    [Parameter(Mandatory = $false)]
    [bool]$ParallelExecution = $true,

    [Parameter(Mandatory = $false)]
    [int]$MaxParallelJobs = 5,

    [Parameter(Mandatory = $false)]
    [string]$BusinessUnitTagName = "BusinessUnit",

    [Parameter(Mandatory = $false)]
    [bool]$IncludeManagementGroups = $true
)

# Set up module path - modules are in the CS-Azure-Cost-Estimation-v2/Modules directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesPath = Join-Path $scriptPath "Modules"

# Import required modules
$requiredModules = @(
    "ConfigLoader",
    "Logging",
    "Authentication",
    "Pricing",
    "DataCollection",
    "CostEstimation",
    "Reporting"
)

foreach ($module in $requiredModules) {
    $modulePath = Join-Path $modulesPath "$module.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
        # Write-Host "Imported module: $module" -ForegroundColor Green
    }
    else {
        Write-Error "Required module not found: $modulePath"
        exit 1
    }
}

# Setup and Initialization
# ========================

# Load configuration from the Config directory
$config = Initialize-Configuration
Write-Host "Loading configuration files from Config directory..." -ForegroundColor Cyan

# Override config settings with command-line parameters if provided
if ($PSBoundParameters.ContainsKey('BusinessUnitTagName')) {
    Set-ConfigSetting -Name 'BusinessUnitTagName' -Value $BusinessUnitTagName
}

# Initialize output paths using the ConfigLoader module
$paths = Initialize-OutputPaths -OutputDirectory $OutputDirectory -OutputFilePath $OutputFilePath -LogFilePath $LogFilePath

# Update variables with the initialized paths
$OutputDirectory = $paths.OutputDirectory
$OutputFilePath = $paths.OutputFilePath
$LogFilePath = $paths.LogFilePath
$SummaryJsonPath = $paths.SummaryJsonPath
$StatusFilePath = $paths.StatusFilePath
$BuReportPath = $paths.BuReportPath
$MgReportPath = $paths.MgReportPath
$PricingCachePath = $paths.PricingCachePath
$HtmlReportPath = $paths.HtmlReportPath

# Set up logging
Set-LogFilePath -Path $LogFilePath
Write-Log "CrowdStrike Azure Cost Estimation Tool (Modular Version)" -Level 'INFO' -Category 'Initialization'
Write-Log "Output directory: $OutputDirectory" -Level 'INFO' -Category 'Initialization'
Write-Log "Log file: $LogFilePath" -Level 'INFO' -Category 'Initialization'

# Display script parameters
Write-Log "Script Parameters:" -Level 'INFO' -Category 'Initialization'
Write-Log "  - Days to analyze: $DaysToAnalyze" -Level 'INFO' -Category 'Initialization'
Write-Log "  - Sample log size: $SampleLogSize" -Level 'INFO' -Category 'Initialization'
Write-Log "  - Use real pricing: $UseRealPricing" -Level 'INFO' -Category 'Initialization'
Write-Log "  - Parallel execution: $ParallelExecution" -Level 'INFO' -Category 'Initialization'
Write-Log "  - Max parallel jobs: $MaxParallelJobs" -Level 'INFO' -Category 'Initialization'
Write-Log "  - Business unit tag name: $BusinessUnitTagName" -Level 'INFO' -Category 'Initialization'
Write-Log "  - Include management groups: $IncludeManagementGroups" -Level 'INFO' -Category 'Initialization'

# Authentication
# ==============
Write-Log "Starting Azure authentication process..." -Level 'INFO' -Category 'Authentication'
$authSuccess = Initialize-AzureConnection
if (-not $authSuccess) {
    Write-Log "Authentication failed. Exiting." -Level 'ERROR' -Category 'Authentication'
    exit 1
}

# Select default subscription if not specified
if ([string]::IsNullOrEmpty($DefaultSubscriptionId)) {
    Write-Log "No default subscription ID provided. Prompting for selection..." -Level 'INFO' -Category 'Subscription'
    $defaultSubscription = Select-AzureSubscription
    $DefaultSubscriptionId = $defaultSubscription.Id
    Write-Log "Selected subscription: $($defaultSubscription.Name) ($DefaultSubscriptionId)" -Level 'SUCCESS' -Category 'Subscription'
}
else {
    # Validate the provided subscription ID
    Write-Log "Validating provided subscription ID: $DefaultSubscriptionId" -Level 'INFO' -Category 'Subscription'
    $defaultSubscription = Select-AzureSubscription -DefaultId $DefaultSubscriptionId
    if (-not $defaultSubscription) {
        Write-Log "Could not find or access the specified subscription. Exiting." -Level 'ERROR' -Category 'Subscription'
        exit 1
    }
    Write-Log "Using subscription: $($defaultSubscription.Name) ($DefaultSubscriptionId)" -Level 'SUCCESS' -Category 'Subscription'
}

# Set pricing cache path
Set-PricingCachePath -Path $PricingCachePath

# Get pricing information
Write-Log "Retrieving Azure pricing information..." -Level 'INFO' -Category 'Pricing'
$pricingInfo = if ($UseRealPricing) {
    Get-AzureRetailRates
}
else {
    Get-StaticPricing
}

if (-not $pricingInfo) {
    Write-Log "Failed to retrieve pricing information. Using default static pricing." -Level 'WARNING' -Category 'Pricing'
    $pricingInfo = Get-StaticPricing
}

# Get Entra ID metrics for the entire tenant
Write-Log "Collecting Entra ID metrics..." -Level 'INFO' -Category 'EntraID'
$entraIdMetrics = Get-EntraIdLogMetrics -DaysToAnalyze $DaysToAnalyze

# Get list of all accessible subscriptions
Write-Log "Retrieving available subscriptions..." -Level 'INFO' -Category 'Subscription'
$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
$subscriptionCount = $subscriptions.Count
Write-Log "Found $subscriptionCount accessible subscriptions" -Level 'INFO' -Category 'Subscription'

if ($subscriptionCount -eq 0) {
    Write-Log "No accessible subscriptions found. Exiting." -Level 'ERROR' -Category 'Subscription'
    exit 1
}

# Create an array to store subscription cost estimates
$subscriptionEstimates = @()

# Data Collection and Estimation
# =============================
Write-Log "Starting data collection and cost estimation process..." -Level 'INFO' -Category 'DataCollection'

$totalSubs = $subscriptions.Count
$processedSubs = 0
$startTime = Get-Date

foreach ($subscription in $subscriptions) {
    $subscriptionId = $subscription.Id
    $subscriptionName = $subscription.Name
    
    $processedSubs++
    $percentComplete = [math]::Round(($processedSubs / $totalSubs) * 100)
    
    Show-EnhancedProgress -Activity "Processing Subscriptions" -Status "Subscription $processedSubs of $totalSubs - $subscriptionName" -PercentComplete $percentComplete -StartTime $startTime
    
    Write-Log "Processing subscription $processedSubs of $totalSubs: $subscriptionName ($subscriptionId)" -Level 'INFO' -Category 'Subscription'
    
    # Get subscription metadata
    $subscriptionMetadata = Get-SubscriptionMetadata -SubscriptionId $subscriptionId
    
    # Get subscription activity logs
    $activityLogData = Get-SubscriptionActivityLogs -SubscriptionId $subscriptionId -DaysToAnalyze $DaysToAnalyze -SampleSize $SampleLogSize
    
    # Get subscription resources
    $resourceData = Get-SubscriptionResources -SubscriptionId $subscriptionId
    
    # Get pricing for the subscription's region
    $region = $subscriptionMetadata.PrimaryLocation
    if ($region -eq "unknown") {
        $region = $DefaultRegion
    }
    
    $regionPricing = Get-PricingForRegion -Region $region -PricingData $pricingInfo -UseRetailRates $UseRealPricing
    
    # Determine if this is a production environment
    $isProduction = $subscriptionMetadata.IsProductionLike
    
    # Get business unit
    $businessUnit = $DefaultBusinessUnit
    if ($subscriptionMetadata.BusinessUnit -ne $DefaultBusinessUnit) {
        $businessUnit = $subscriptionMetadata.BusinessUnit
    }
    
    # Calculate cost estimate for this subscription
    $subscriptionEstimate = Get-SubscriptionCostEstimate -SubscriptionId $subscriptionId `
                                                       -SubscriptionMetadata $subscriptionMetadata `
                                                       -ActivityLogData $activityLogData `
                                                       -EntraIdData $entraIdMetrics `
                                                       -Pricing $regionPricing `
                                                       -IsProductionEnvironment $isProduction `
                                                       -BusinessUnit $businessUnit
    
    # Add subscription name to the estimate for easier identification
    $subscriptionEstimate["SubscriptionName"] = $subscriptionName
    
    # Add to the array of estimates
    $subscriptionEstimates += $subscriptionEstimate
    
    Write-Log "Completed cost estimate for $subscriptionName. Monthly cost: $($subscriptionEstimate.MonthlyCost)" -Level 'SUCCESS' -Category 'Estimation'
}

# Business Unit Analysis
# =====================
Write-Log "Performing business unit cost analysis..." -Level 'INFO' -Category 'BusinessUnits'
$businessUnitSummary = Get-BusinessUnitCostSummary -SubscriptionEstimates $subscriptionEstimates

# Reporting
# =========
Write-Log "Generating reports..." -Level 'INFO' -Category 'Reporting'

# Export subscription cost estimates to CSV
$csvExportSuccess = Export-CostEstimatesToCsv -SubscriptionEstimates $subscriptionEstimates -OutputFilePath $OutputFilePath

# Export business unit costs to CSV
$buExportSuccess = Export-BusinessUnitCostsToCsv -BusinessUnitSummary $businessUnitSummary -OutputFilePath $BuReportPath

# Export all data to a summary JSON file
$jsonExportSuccess = Export-SummaryToJson -SubscriptionEstimates $subscriptionEstimates `
                                         -BusinessUnitSummary $businessUnitSummary `
                                         -EntraIdData $entraIdMetrics `
                                         -OutputFilePath $SummaryJsonPath

# Generate HTML report
$htmlReportSuccess = New-HtmlReport -SubscriptionEstimates $subscriptionEstimates `
                                   -BusinessUnitSummary $businessUnitSummary `
                                   -OutputFilePath $HtmlReportPath `
                                   -ReportTitle "CrowdStrike Azure Cost Estimation Report" `
                                   -IncludeCharts $IncludeCharts

# Script Completion
# ================
$totalEstimate = ($subscriptionEstimates | Measure-Object -Property MonthlyCost -Sum).Sum
$totalAnnualEstimate = $totalEstimate * 12

Write-Log "Cost Estimation Summary:" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Total subscriptions analyzed: $($subscriptionEstimates.Count)" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Total monthly cost estimate: $($totalEstimate)" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Total annual cost estimate: $($totalAnnualEstimate)" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Business units identified: $($businessUnitSummary.Keys.Count)" -Level 'SUCCESS' -Category 'Summary'

Write-Log "Reports generated:" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Subscription cost details: $OutputFilePath" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Business unit summary: $BuReportPath" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Full data summary (JSON): $SummaryJsonPath" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - HTML report with visualizations: $HtmlReportPath" -Level 'SUCCESS' -Category 'Summary'

Write-Log "CrowdStrike Azure Cost Estimation Tool completed successfully." -Level 'SUCCESS' -Category 'Completion'

# Open HTML report if available
if ($htmlReportSuccess) {
    $openReport = Read-Host "Would you like to open the HTML report now? (Y/N)"
    if ($openReport -eq "Y" -or $openReport -eq "y") {
        try {
            Invoke-Item $HtmlReportPath
        }
        catch {
            Write-Log "Failed to open the HTML report. You can find it at: $HtmlReportPath" -Level 'WARNING' -Category 'Completion'
        }
    }
}
