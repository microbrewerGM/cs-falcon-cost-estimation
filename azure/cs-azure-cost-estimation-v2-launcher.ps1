<#
.SYNOPSIS
Launcher for CrowdStrike Azure Cost Estimation Tool (v2)

.DESCRIPTION
This script is a launcher for the modular CrowdStrike Azure Cost Estimation Tool (v2). 
It simply forwards all parameters to the main script in the CS-Azure-Cost-Estimation-v2 directory.

.PARAMETER DaysToAnalyze
Number of days of logs to analyze. Default is 7.

.PARAMETER DefaultSubscriptionId
The subscription ID where CrowdStrike resources will be deployed.

.PARAMETER OutputDirectory
Path to the directory where output files will be saved.

.PARAMETER OutputFilePath
Path to the CSV output file.

.PARAMETER LogFilePath
Path to the log file.

.PARAMETER SampleLogSize
Number of logs to sample for size calculation.

.PARAMETER UseRealPricing
Use Azure Retail Rates API for current pricing instead of static pricing data.

.PARAMETER ParallelExecution
Enable parallel execution for data collection from multiple subscriptions.

.PARAMETER MaxParallelJobs
Maximum number of parallel jobs when ParallelExecution is enabled.

.PARAMETER BusinessUnitTagName
The tag name used for business unit attribution.

.PARAMETER IncludeManagementGroups
Include management group structure for organizational reporting.

.EXAMPLE
.\cs-azure-cost-estimation-v2-launcher.ps1 -DaysToAnalyze 14 -SampleLogSize 200

.NOTES
This is a launcher script that calls the main script in the CS-Azure-Cost-Estimation-v2 directory.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze,

    [Parameter(Mandatory = $false)]
    [string]$DefaultSubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [string]$OutputFilePath,

    [Parameter(Mandatory = $false)]
    [string]$LogFilePath,

    [Parameter(Mandatory = $false)]
    [int]$SampleLogSize,

    [Parameter(Mandatory = $false)]
    [bool]$UseRealPricing,

    [Parameter(Mandatory = $false)]
    [bool]$ParallelExecution,

    [Parameter(Mandatory = $false)]
    [int]$MaxParallelJobs,

    [Parameter(Mandatory = $false)]
    [string]$BusinessUnitTagName,

    [Parameter(Mandatory = $false)]
    [bool]$IncludeManagementGroups
)

# Build the parameter splat from the received parameters
$paramSplat = @{}
foreach ($param in $PSBoundParameters.Keys) {
    $paramSplat[$param] = $PSBoundParameters[$param]
}

# Path to the main script in the CS-Azure-Cost-Estimation-v2 directory
$scriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "CS-Azure-Cost-Estimation-v2/CS-Azure-Cost-Estimation-v2-Main.ps1"

Write-Host "Launching CrowdStrike Azure Cost Estimation Tool (v2)" -ForegroundColor Cyan
Write-Host "Main script: $scriptPath" -ForegroundColor Cyan
Write-Host ""

# Call the main script with all parameters
& $scriptPath @paramSplat
