# ConfigLoader Module for CrowdStrike Azure Cost Estimation Tool
# This module loads all configuration files and exports the settings as variables

# Store the path to the config directory
$script:ConfigDir = Join-Path (Split-Path -Parent $PSScriptRoot) "Config"

# Create an object to store all configuration settings
$script:Config = @{}

# Function to load all configuration files
function Initialize-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CustomConfigPath = "",

        [Parameter(Mandatory = $false)]
        [switch]$Verbose = $false
    )

    # Get all PS1 files in the config directory
    $configFiles = @(
        "General.ps1",
        "Pricing.ps1",
        "Capacity.ps1",
        "Environments.ps1",
        "Reporting.ps1"
    )

    # Load standard configuration files
    foreach ($file in $configFiles) {
        $filePath = Join-Path $script:ConfigDir $file
        if (Test-Path $filePath) {
            if ($Verbose) {
                Write-Host "Loading configuration from $filePath" -ForegroundColor Cyan
            }
            
            # Create a new scope and load variables from the config file
            $configData = & {
                # Source the config file and capture all variables
                . $filePath
                # Get all variables that are not automatic variables
                Get-Variable | Where-Object { 
                    $_.Name -notlike "*?*" -and 
                    $_.Name -ne "filePath" -and 
                    $_.Name -ne "file" -and 
                    $_.Name -ne "configFiles" -and
                    $_.Name -ne "configData" -and
                    $_.Name -notin @("PSCmdlet", "PSBoundParameters", "file", "Verbose")
                }
            }

            # Add the variables to our config object
            foreach ($varObj in $configData) {
                $script:Config[$varObj.Name] = $varObj.Value
            }
        }
        else {
            Write-Warning "Configuration file not found: $filePath"
        }
    }

    # Load custom configuration file if specified
    if (-not [string]::IsNullOrWhiteSpace($CustomConfigPath) -and (Test-Path $CustomConfigPath)) {
        if ($Verbose) {
            Write-Host "Loading custom configuration from $CustomConfigPath" -ForegroundColor Yellow
        }
        
        # Source the custom config file to override settings
        & {
            . $CustomConfigPath
            # Get all variables that are not automatic variables
            $customVars = Get-Variable | Where-Object { 
                $_.Name -notlike "*?*" -and 
                $_.Name -ne "CustomConfigPath" -and 
                $_.Name -ne "Verbose" -and
                $_.Name -notin @("PSCmdlet", "PSBoundParameters")
            }
            
            # Override the settings with custom values
            foreach ($varObj in $customVars) {
                $script:Config[$varObj.Name] = $varObj.Value
                if ($Verbose) {
                    Write-Host "  Overriding setting: $($varObj.Name)" -ForegroundColor Yellow
                }
            }
        }
    }

    # Return the configuration object
    return $script:Config
}

# Function to get a configuration setting
function Get-ConfigSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        $DefaultValue = $null
    )
    
    if ($script:Config.ContainsKey($Name)) {
        return $script:Config[$Name]
    }
    
    return $DefaultValue
}

# Function to set a configuration setting
function Set-ConfigSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        $Value
    )
    
    $script:Config[$Name] = $Value
}

# Function to initialize output paths with support for custom config
function Initialize-OutputPaths {
    param (
        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory = "",
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFilePath = "",
        
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = ""
    )

    # Create a timestamp for directory naming
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    
    # Create the output directory if not specified
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = "cs-azure-cost-estimate-$timestamp"
    }
    
    # Create the output directory if it doesn't exist
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
        Write-Host "Created output directory: $OutputDirectory" -ForegroundColor Green
    }
    
    # Create subdirectories
    $SubscriptionDataDir = Join-Path $OutputDirectory "subscription-data"
    $ManagementGroupDataDir = Join-Path $OutputDirectory "management-group-data"
    $PricingDataDir = Join-Path $OutputDirectory "pricing-data"
    
    foreach ($dir in @($SubscriptionDataDir, $ManagementGroupDataDir, $PricingDataDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: $dir" -ForegroundColor Green
        }
    }
    
    # Set default file paths if not specified
    if ([string]::IsNullOrWhiteSpace($OutputFilePath)) {
        $OutputFilePath = Join-Path $OutputDirectory "cs-azure-cost-estimate.csv"
    }
    
    if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
        $LogFilePath = Join-Path $OutputDirectory "cs-azure-cost-estimate.log"
    }
    
    # Additional output files
    $SummaryJsonPath = Join-Path $OutputDirectory "summary.json"
    $StatusFilePath = Join-Path $OutputDirectory "script-status.json"
    $BuReportPath = Join-Path $OutputDirectory "business-unit-costs.csv"
    $MgReportPath = Join-Path $OutputDirectory "management-group-costs.csv"
    $PricingCachePath = Join-Path $PricingDataDir "azure-pricing-cache.json"
    $HtmlReportPath = Join-Path $OutputDirectory "cs-azure-cost-estimate-report.html"
    
    # Return all paths as a hashtable
    return @{
        OutputDirectory = $OutputDirectory
        SubscriptionDataDir = $SubscriptionDataDir
        ManagementGroupDataDir = $ManagementGroupDataDir
        PricingDataDir = $PricingDataDir
        OutputFilePath = $OutputFilePath
        LogFilePath = $LogFilePath
        SummaryJsonPath = $SummaryJsonPath
        StatusFilePath = $StatusFilePath
        BuReportPath = $BuReportPath
        MgReportPath = $MgReportPath
        PricingCachePath = $PricingCachePath
        HtmlReportPath = $HtmlReportPath
    }
}

# Export functions
Export-ModuleMember -Function Initialize-Configuration, Get-ConfigSetting, Set-ConfigSetting, Initialize-OutputPaths
