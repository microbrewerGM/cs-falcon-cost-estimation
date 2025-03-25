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

# Path to key directories
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mainDir = Join-Path $scriptDir "CS-Azure-Cost-Estimation-v2"
$modulesDir = Join-Path $mainDir "Modules"
$mainScriptPath = Join-Path $mainDir "CS-Azure-Cost-Estimation-v2-Main.ps1"

Write-Host "Launching CrowdStrike Azure Cost Estimation Tool (v2)" -ForegroundColor Cyan
Write-Host "Main script: $mainScriptPath" -ForegroundColor Cyan
Write-Host ""

# Check for required PowerShell modules before proceeding
Write-Host "Checking prerequisites..." -ForegroundColor Cyan

# First, check if script is running in PowerShell Core (pwsh) rather than Windows PowerShell
if ($PSVersionTable.PSEdition -ne "Core") {
    Write-Host "This script requires PowerShell Core (pwsh) to run properly." -ForegroundColor Red
    Write-Host "Please install PowerShell Core and run this script using 'pwsh' instead of 'powershell'." -ForegroundColor Red
    exit 1
}

# Check if Azure PowerShell modules are installed
$azureModules = @(
    "Az.Accounts",
    "Az.Resources",
    "Az.Monitor",
    "Microsoft.Graph.Identity.DirectoryManagement",
    "Microsoft.Graph.Users"
)

$missingAzModules = @()
foreach ($module in $azureModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        $missingAzModules += $module
    }
}

if ($missingAzModules.Count -gt 0) {
    Write-Host "Error: Required Azure PowerShell modules are missing:" -ForegroundColor Red
    foreach ($module in $missingAzModules) {
        Write-Host "  - $module" -ForegroundColor Red
    }
    
    Write-Host "`nThese modules are required for script operation. Would you like to:" -ForegroundColor Yellow
    Write-Host "  1. Install the missing modules now (requires admin permissions)"
    Write-Host "  2. Exit"
    
    $choice = Read-Host "Enter your choice (1-2)"
    
    switch ($choice) {
        "1" {
            Write-Host "Installing missing Azure PowerShell modules..." -ForegroundColor Cyan
            foreach ($module in $missingAzModules) {
                try {
                    Write-Host "Installing $module..." -ForegroundColor Cyan
                    Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
                    Write-Host "$module installed successfully" -ForegroundColor Green
                }
                catch {
                    Write-Host "Failed to install $module. Error: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "You can try installing it manually using: Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber" -ForegroundColor Yellow
                    exit 1
                }
            }
            
            # All required modules have been installed
            Write-Host "All required modules have been installed successfully." -ForegroundColor Green
        }
        "2" {
            Write-Host "Exiting script" -ForegroundColor Red
            exit 0
        }
        default {
            Write-Host "Invalid choice. Exiting script" -ForegroundColor Red
            exit 1
        }
    }
}
else {
    Write-Host "Required Azure PowerShell modules are installed" -ForegroundColor Green
}

# Check all required module files exist 
$requiredModules = @(
    "ConfigLoader",
    "Logging",
    "Authentication",
    "Pricing",
    "DataCollection",
    "CostEstimation",
    "Reporting"
)

$missingModules = @()
foreach ($module in $requiredModules) {
    $modulePath = Join-Path $modulesDir "$module.psm1"
    if (-not (Test-Path $modulePath)) {
        $missingModules += $module
    }
}

if ($missingModules.Count -gt 0) {
    Write-Host "Error: The following required modules are missing:" -ForegroundColor Red
    foreach ($module in $missingModules) {
        Write-Host "  - $module" -ForegroundColor Red
    }
    Write-Host "Please make sure all required module files are present in: $modulesDir" -ForegroundColor Red
    exit 1
}

# Check if main script exists
if (-not (Test-Path $mainScriptPath)) {
    Write-Host "Error: Main script not found at: $mainScriptPath" -ForegroundColor Red
    exit 1
}

# Build the parameter splat from the received parameters
$paramSplat = @{}
foreach ($param in $PSBoundParameters.Keys) {
    $paramSplat[$param] = $PSBoundParameters[$param]
}

Write-Host "All prerequisites met. Launching main script..." -ForegroundColor Green

# Set module export path explicitly to ensure modules can be found
$env:PSModulePath = $modulesDir + [IO.Path]::PathSeparator + $env:PSModulePath

# Call the main script with all parameters
& $mainScriptPath @paramSplat
