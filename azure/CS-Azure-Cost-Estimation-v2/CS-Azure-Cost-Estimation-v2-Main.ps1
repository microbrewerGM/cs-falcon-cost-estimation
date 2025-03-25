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

.PARAMETER IncludeCharts
Include visual charts in the HTML report. Default is $true.

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
[bool]$ParallelExecution = $false, # Disabled by default due to parameter passing issues

    [Parameter(Mandatory = $false)]
    [int]$MaxParallelJobs = 5,

    [Parameter(Mandatory = $false)]
    [string]$BusinessUnitTagName = "BusinessUnit",

    [Parameter(Mandatory = $false)]
    [bool]$IncludeManagementGroups = $true,

    [Parameter(Mandatory = $false)]
    [bool]$IncludeCharts = $true
)

# Set up module path - modules are in the CS-Azure-Cost-Estimation-v2/Modules directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesPath = Join-Path $scriptPath "Modules"

Write-Host "Loading modules..." -ForegroundColor Cyan

# Define module paths
$configLoaderPath = Join-Path $modulesPath "ConfigLoader.psm1"
$loggingPath = Join-Path $modulesPath "Logging.psm1"
$authenticationPath = Join-Path $modulesPath "Authentication.psm1"
$pricingPath = Join-Path $modulesPath "Pricing.psm1"
$dataCollectionPath = Join-Path $modulesPath "DataCollection.psm1"
$costEstimationPath = Join-Path $modulesPath "CostEstimation.psm1"
$reportingPath = Join-Path $modulesPath "Reporting.psm1"

# Check that all module files exist
$modulePaths = @(
    $configLoaderPath,
    $loggingPath,
    $authenticationPath,
    $pricingPath,
    $dataCollectionPath,
    $costEstimationPath,
    $reportingPath
)

foreach ($path in $modulePaths) {
    if (-not (Test-Path $path)) {
        Write-Error "Required module file not found: $path"
        exit 1
    }
}

# ABSOLUTE SIMPLEST APPROACH - Import the modules using traditional Import-Module
Write-Host "Loading modules using traditional Import-Module..." -ForegroundColor Cyan

try {
    # Remove any existing modules first to prevent conflicts
    foreach ($module in @("ConfigLoader", "Logging", "Authentication", "Pricing", "DataCollection", "CostEstimation", "Reporting")) {
        if (Get-Module -Name $module -ErrorAction SilentlyContinue) {
            Remove-Module -Name $module -Force
        }
    }
    
    # Add modules path to PSModulePath temporarily
    $originalPSModulePath = $env:PSModulePath
    $env:PSModulePath = $modulesPath + [IO.Path]::PathSeparator + $env:PSModulePath
    
# Import modules directly using Import-Module with paths
Write-Host "Importing ConfigLoader module..." -ForegroundColor Cyan
Import-Module $configLoaderPath -Force -Global
Write-Host "Imported ConfigLoader module" -ForegroundColor Green

Write-Host "Importing Logging module..." -ForegroundColor Cyan
Import-Module $loggingPath -Force -Global
Write-Host "Imported Logging module" -ForegroundColor Green

Write-Host "Importing Authentication module..." -ForegroundColor Cyan
Import-Module $authenticationPath -Force -Global
Write-Host "Imported Authentication module" -ForegroundColor Green

Write-Host "Importing Pricing module..." -ForegroundColor Cyan
Import-Module $pricingPath -Force -Global
Write-Host "Imported Pricing module" -ForegroundColor Green

Write-Host "Importing DataCollection module..." -ForegroundColor Cyan
Import-Module $dataCollectionPath -Force -Global
Write-Host "Imported DataCollection module" -ForegroundColor Green

Write-Host "Importing CostEstimation module..." -ForegroundColor Cyan
Import-Module $costEstimationPath -Force -Global
Write-Host "Imported CostEstimation module" -ForegroundColor Green

Write-Host "Importing Reporting module..." -ForegroundColor Cyan
Import-Module $reportingPath -Force -Global
Write-Host "Imported Reporting module" -ForegroundColor Green

# Also import ProcessSubscription module for parallel jobs
$processSubscriptionPath = Join-Path $modulesPath "ProcessSubscription.psm1"
if (Test-Path $processSubscriptionPath) {
    Write-Host "Importing ProcessSubscription module..." -ForegroundColor Cyan
    Import-Module $processSubscriptionPath -Force -Global
    Write-Host "Imported ProcessSubscription module" -ForegroundColor Green
}
else {
    Write-Host "ProcessSubscription module not found at $processSubscriptionPath. Only sequential processing will be available." -ForegroundColor Yellow
    $ParallelExecution = $false
}

# Check for required Azure modules
if (-not (Get-Module -Name Az.Accounts -ListAvailable)) {
    Write-Warning "Az.Accounts module not found. Please install it using 'Install-Module Az.Accounts -Force'"
}

if (-not (Get-Module -Name Microsoft.Graph.Identity.DirectoryManagement -ListAvailable) -and 
    -not (Get-Module -Name Az.Resources -ListAvailable)) {
    Write-Warning "Neither Microsoft.Graph.Identity.DirectoryManagement nor Az.Resources module found. Limited functionality will be available."
    Write-Warning "Install Microsoft.Graph modules using 'Install-Module Microsoft.Graph -Force'"
}

# Try to load AzureAD module if available (not required, will fall back to Graph API)
if (Get-Module -Name AzureAD -ListAvailable) {
    try {
        Import-Module AzureAD -ErrorAction SilentlyContinue
        Write-Host "AzureAD module loaded." -ForegroundColor Green
    }
    catch {
        Write-Warning "AzureAD module found but could not be loaded. Will use Graph API for tenant information."
    }
}
else {
    Write-Warning "AzureAD module not found. Will use Microsoft Graph or Az APIs for tenant information."
}
    
    # Restore original PSModulePath
    $env:PSModulePath = $originalPSModulePath
}
catch {
    Write-Error "Error loading modules: $($_.Exception.Message)"
    exit 1
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
Write-Log "  - Include charts in HTML report: $IncludeCharts" -Level 'INFO' -Category 'Initialization'

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

# Save Entra ID metrics to a file for job access
$entraIdMetricsPath = Join-Path $OutputDirectory "entra-id-metrics.json"
$entraIdMetrics | ConvertTo-Json -Depth 10 | Out-File -FilePath $entraIdMetricsPath -Force
Write-Log "Saved Entra ID metrics to $entraIdMetricsPath" -Level 'INFO' -Category 'EntraID'

# Also save pricing info if we're using parallel jobs
if ($UseRealPricing -and $ParallelExecution) {
    $pricingDirPath = Join-Path $OutputDirectory "pricing-data"
    if (-not (Test-Path $pricingDirPath)) {
        New-Item -Path $pricingDirPath -ItemType Directory -Force | Out-Null
    }
    $pricingCachePath = Join-Path $pricingDirPath "pricing-cache.json"
    $pricingInfo | ConvertTo-Json -Depth 10 | Out-File -FilePath $pricingCachePath -Force
    Write-Log "Saved pricing data to $pricingCachePath" -Level 'INFO' -Category 'Pricing'
}

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

# Function to process a single subscription
function Process-Subscription {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Subscription,
        [Parameter(Mandatory = $true)]
        [int]$ProcessedCount,
        [Parameter(Mandatory = $true)]
        [int]$TotalCount,
        [Parameter(Mandatory = $true)]
        [datetime]$StartTime
    )
    
    $subscriptionId = $Subscription.Id
    $subscriptionName = $Subscription.Name
    
    $percentComplete = [math]::Round(($ProcessedCount / $TotalCount) * 100)
    
    Show-EnhancedProgress -Activity "Processing Subscriptions" -Status "Subscription $ProcessedCount of $TotalCount - $subscriptionName" -PercentComplete $percentComplete -StartTime $StartTime
    
    Write-Log "Processing subscription $ProcessedCount of ${TotalCount}: $subscriptionName ($subscriptionId)" -Level 'INFO' -Category 'Subscription'
    
    # Get subscription metadata
    $subscriptionMetadata = Get-SubscriptionMetadata -SubscriptionId $subscriptionId
    
    # Get subscription activity logs
    $activityLogData = Get-SubscriptionActivityLogs -SubscriptionId $subscriptionId -DaysToAnalyze $script:DaysToAnalyze -SampleSize $script:SampleLogSize
    
    # Get subscription resources
    $resourceData = Get-SubscriptionResources -SubscriptionId $subscriptionId
    
    # Get pricing for the subscription's region
    $region = $subscriptionMetadata.PrimaryLocation
    if ($region -eq "unknown") {
        $region = Get-ConfigSetting -Name 'DefaultRegion' -DefaultValue 'eastus'
    }
    
    $regionPricing = Get-PricingForRegion -Region $region -PricingData $script:pricingInfo -UseRetailRates $script:UseRealPricing
    
    # Determine if this is a production environment
    $isProduction = $subscriptionMetadata.IsProductionLike
    
    # Get business unit
    $businessUnit = Get-ConfigSetting -Name 'DefaultBusinessUnit' -DefaultValue 'Unassigned'
    if ($subscriptionMetadata.BusinessUnit -ne $businessUnit) {
        $businessUnit = $subscriptionMetadata.BusinessUnit
    }
    
    # Calculate cost estimate for this subscription
    $subscriptionEstimate = Get-SubscriptionCostEstimate -SubscriptionId $subscriptionId `
                                                         -SubscriptionMetadata $subscriptionMetadata `
                                                         -ActivityLogData $activityLogData `
                                                         -ResourceData $resourceData `
                                                         -EntraIdData $script:entraIdMetrics `
                                                         -Pricing $regionPricing `
                                                         -IsProductionEnvironment $isProduction `
                                                         -BusinessUnit $businessUnit
    
    # Add subscription name to the estimate for easier identification
    $subscriptionEstimate["SubscriptionName"] = $subscriptionName
    
    Write-Log "Completed cost estimate for $subscriptionName. Monthly cost: $($subscriptionEstimate.MonthlyCost)" -Level 'SUCCESS' -Category 'Estimation'
    
    # Return the estimate
    return $subscriptionEstimate
}

# Process subscriptions either sequentially or in parallel
if ($ParallelExecution -and $subscriptionCount -gt 1) {
    Write-Log "Using parallel execution with maximum of $MaxParallelJobs concurrent jobs" -Level 'INFO' -Category 'Execution'
    
    # Use the external job script file instead of inline script block
    $jobScriptPath = Join-Path $scriptPath "Process-Subscription-Job.ps1"
    
    if (-not (Test-Path $jobScriptPath)) {
        Write-Log "Job script not found at $jobScriptPath. Falling back to sequential processing." -Level 'WARNING' -Category 'Execution'
        $ParallelExecution = $false
    }
    else {
        # Create jobs array
        $jobs = @()
        
        # Submit jobs in batches according to MaxParallelJobs
        for ($i = 0; $i -lt $subscriptionCount; $i++) {
            $subscription = $subscriptions[$i]
            $processedCount = $i + 1
            
            # Get parameters for job
            $jobParams = @{
                SubscriptionId = $subscription.Id
                SubscriptionName = $subscription.Name
                ProcessedCount = $processedCount
                TotalCount = $totalSubs
                StartTimeStr = $startTime.ToString("o") # ISO 8601 format for reliable parsing
                DaysToAnalyze = $DaysToAnalyze
                SampleLogSize = $SampleLogSize
                UseRealPricing = $UseRealPricing
                ModulePath = $modulesPath
                OutputDirectory = $OutputDirectory
            }
            
            # Start the job
            $job = Start-Job -FilePath $jobScriptPath -ArgumentList @(
                $jobParams.SubscriptionId, 
                $jobParams.SubscriptionName, 
                $jobParams.ProcessedCount, 
                $jobParams.TotalCount, 
                $jobParams.StartTimeStr,
                $jobParams.DaysToAnalyze,
                $jobParams.SampleLogSize,
                $jobParams.UseRealPricing,
                $jobParams.ModulePath,
                $jobParams.OutputDirectory
            )
            $jobs += $job
            
            # Update status file
            $status = @{
                "Total" = $totalSubs
                "Processed" = $processedCount
                "Percentage" = [math]::Round(($processedCount / $totalSubs) * 100)
                "CurrentlyProcessing" = "$($subscription.Name)"
            }
            $status | ConvertTo-Json | Out-File -FilePath $StatusFilePath -Force
            
            # If we've reached the maximum number of parallel jobs, wait for one to complete
            if ($jobs.Count -ge $MaxParallelJobs) {
                $completedJob = $jobs | Wait-Job -Any
                $estimate = Receive-Job $completedJob
                $subscriptionEstimates += $estimate
                Remove-Job $completedJob
                $jobs = $jobs | Where-Object { $_.Id -ne $completedJob.Id }
            }
        }
    }
    
    # Wait for any remaining jobs to complete
    while ($jobs.Count -gt 0) {
        $completedJob = $jobs | Wait-Job -Any
        $estimate = Receive-Job $completedJob
        $subscriptionEstimates += $estimate
        Remove-Job $completedJob
        $jobs = $jobs | Where-Object { $_.Id -ne $completedJob.Id }
    }
    
    Write-Log "All parallel subscription processing jobs completed" -Level 'SUCCESS' -Category 'Execution'
} else {
    # Process subscriptions sequentially
    Write-Log "Using sequential processing for subscriptions" -Level 'INFO' -Category 'Execution'
    
    for ($i = 0; $i -lt $subscriptionCount; $i++) {
        $subscription = $subscriptions[$i]
        $processedCount = $i + 1
        
        # Update status file
        $status = @{
            "Total" = $totalSubs
            "Processed" = $processedCount
            "Percentage" = [math]::Round(($processedCount / $totalSubs) * 100)
            "CurrentlyProcessing" = "$($subscription.Name)"
        }
        $status | ConvertTo-Json | Out-File -FilePath $StatusFilePath -Force
        
        # Process the subscription
        $estimate = Process-Subscription -Subscription $subscription -ProcessedCount $processedCount -TotalCount $totalSubs -StartTime $startTime
        $subscriptionEstimates += $estimate
    }
}

# Business Unit Analysis
# =====================
Write-Log "Performing business unit cost analysis..." -Level 'INFO' -Category 'BusinessUnits'
$businessUnitSummary = Get-BusinessUnitCostSummary -SubscriptionEstimates $subscriptionEstimates

# Management Group Analysis (if enabled)
# =====================================
$managementGroupSummary = @{}
if ($IncludeManagementGroups) {
    Write-Log "Collecting management group structure..." -Level 'INFO' -Category 'ManagementGroups'
    
    # Get management group hierarchy
    try {
        $managementGroups = Get-AzManagementGroup -Expand -Recurse
        Write-Log "Found $(($managementGroups | Measure-Object).Count) management groups" -Level 'INFO' -Category 'ManagementGroups'
        
        # Create a lookup table of subscription to management group
        $subscriptionToMgLookup = @{}
        foreach ($mg in $managementGroups) {
            if ($mg.Children) {
                foreach ($child in $mg.Children) {
                    if ($child.Type -eq 'Microsoft.Management/managementGroups') {
                        # This is a nested management group, skip
                        continue
                    }
                    elseif ($child.Type -eq 'Microsoft.Management/subscriptions') {
                        # This is a subscription
                        $subscriptionId = $child.Name
                        $subscriptionToMgLookup[$subscriptionId] = $mg.Name
                    }
                }
            }
        }
        
        # Aggregate costs by management group
        foreach ($estimate in $subscriptionEstimates) {
            $subId = $estimate.SubscriptionId
            $mgName = $subscriptionToMgLookup[$subId]
            
            # If we don't have a management group for this subscription, use "Unassigned"
            if (-not $mgName) {
                $mgName = "Unassigned"
            }
            
            # Add to management group summary
            if (-not $managementGroupSummary.ContainsKey($mgName)) {
                $managementGroupSummary[$mgName] = @{
                    "MonthlyCost" = 0
                    "SubscriptionCount" = 0
                    "Subscriptions" = @()
                }
            }
            
            $managementGroupSummary[$mgName].MonthlyCost += $estimate.MonthlyCost
            $managementGroupSummary[$mgName].SubscriptionCount++
            $managementGroupSummary[$mgName].Subscriptions += $estimate.SubscriptionName
        }
        
        # Export management group costs to CSV
        $mgExportSuccess = Export-ManagementGroupCostsToCsv -ManagementGroupSummary $managementGroupSummary -OutputFilePath $MgReportPath
        Write-Log "Management group cost analysis complete. Found $($managementGroupSummary.Keys.Count) groups" -Level 'SUCCESS' -Category 'ManagementGroups'
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error collecting management group information: $errorMessage" -Level 'WARNING' -Category 'ManagementGroups'
        Write-Log "Management group reporting disabled. Continuing with other analyses." -Level 'WARNING' -Category 'ManagementGroups'
    }
}

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
                                          -ManagementGroupSummary $managementGroupSummary `
                                          -EntraIdData $entraIdMetrics `
                                          -OutputFilePath $SummaryJsonPath

# Generate HTML report
$htmlReportSuccess = New-HtmlReport -SubscriptionEstimates $subscriptionEstimates `
                                    -BusinessUnitSummary $businessUnitSummary `
                                    -ManagementGroupSummary $managementGroupSummary `
                                    -OutputFilePath $HtmlReportPath `
                                    -ReportTitle "CrowdStrike Azure Cost Estimation Report" `
                                    -IncludeCharts $IncludeCharts

# Script Completion
# ================
$totalEstimate = ($subscriptionEstimates | Measure-Object -Property MonthlyCost -Sum).Sum
$totalAnnualEstimate = $totalEstimate * 12

Write-Log "Cost Estimation Summary:" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Total subscriptions analyzed: $($subscriptionEstimates.Count)" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Total monthly cost estimate: $totalEstimate" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Total annual cost estimate: $totalAnnualEstimate" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Business units identified: $($businessUnitSummary.Keys.Count)" -Level 'SUCCESS' -Category 'Summary'
if ($IncludeManagementGroups -and $managementGroupSummary.Count -gt 0) {
    Write-Log "  - Management groups analyzed: $($managementGroupSummary.Keys.Count)" -Level 'SUCCESS' -Category 'Summary'
}

Write-Log "Reports generated:" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Subscription cost details: $OutputFilePath" -Level 'SUCCESS' -Category 'Summary'
Write-Log "  - Business unit summary: $BuReportPath" -Level 'SUCCESS' -Category 'Summary'
if ($IncludeManagementGroups -and $mgExportSuccess) {
    Write-Log "  - Management group summary: $MgReportPath" -Level 'SUCCESS' -Category 'Summary'
}
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
