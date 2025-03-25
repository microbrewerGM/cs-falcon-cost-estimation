# Simplified configuration module for CrowdStrike Azure Cost Estimation Tool v3

# Module variables
$script:ConfigSettings = @{}
$script:DefaultConfigValues = @{
    'OutputDirectory' = ""
    'BusinessUnitTagName' = "BusinessUnit"
    'DefaultBusinessUnit' = "Unassigned"
    'EnvironmentTagName' = "Environment"
    'DefaultEnvironment' = "Unknown"
    'DefaultRegion' = "eastus"
    'SampleLogSize' = 100
    'DaysToAnalyze' = 7
    'LogRetentionDays' = 30
    'EventsPerInstancePerSecond' = 5000
    'MinimumThroughputUnits' = 1
    'MaximumThroughputUnits' = 20
    'MinimumFunctionInstances' = 1
    'MaximumFunctionInstances' = 10
    'KeyVaultMonthlyOperations' = 100000
    'DefaultActivityLogSizeKB' = 2.5
    'DefaultEntraIdLogSizeKB' = 2.0
    'MaxActivityLogsToRetrieve' = 10000
    'ActivityLogPageSize' = 1000
}

# Environment categorization patterns
$script:EnvironmentCategories = @{
    "Production" = @{
        "NamePatterns" = @("prod", "production")
        "TagValues" = @("Production", "PROD", "Prod")
    }
    "PreProduction" = @{
        "NamePatterns" = @("preprod", "pre-prod", "staging")
        "TagValues" = @("PreProduction", "Pre-Production", "Staging", "PREPROD")
    }
    "QA" = @{
        "NamePatterns" = @("qa", "test")
        "TagValues" = @("QA", "Test", "Testing")
    }
    "Development" = @{
        "NamePatterns" = @("dev", "development")
        "TagValues" = @("Development", "DEV", "Dev")
    }
    "Sandbox" = @{
        "NamePatterns" = @("sandbox", "demo", "poc", "lab")
        "TagValues" = @("Sandbox", "Demo", "POC", "Lab")
    }
}

# Fixed resource costs
$script:FixedResourceCosts = @{
    "PrivateEndpointCount" = 3
    "NetworkingCost" = 25.0  # Estimated fixed networking cost
}

# Log volume estimates by user count
$script:SignInsPerUserPerDay = @{
    "Small" = 0.7     # < 1000 users
    "Medium" = 0.5    # 1000-10000 users
    "Large" = 0.3     # > 10000 users
}

$script:AuditsPerUserPerDay = @{
    "Small" = 3.5     # < 1000 users
    "Medium" = 2.5    # 1000-10000 users
    "Large" = 1.5     # > 10000 users
}

# Function to initialize configuration
function Initialize-Configuration {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$ConfigDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) "Config")
    )
    
    # Reset config
    $script:ConfigSettings = @{}
    
    # Load default configuration
    foreach ($key in $script:DefaultConfigValues.Keys) {
        $script:ConfigSettings[$key] = $script:DefaultConfigValues[$key]
    }
    
    # Load configuration from files if they exist
    if (Test-Path $ConfigDirectory) {
        # Get all PS1 files in the configuration directory
        $configFiles = Get-ChildItem -Path $ConfigDirectory -Filter "*.ps1" -File
        
        foreach ($file in $configFiles) {
            try {
                # Execute the configuration file to load variables into the current scope
                $configContent = Get-Content -Path $file.FullName -Raw
                
                # Create a new scope and execute the configuration
                $scriptBlock = [ScriptBlock]::Create($configContent)
                $configVariables = & $scriptBlock
                
                # If the script returned variables directly, use those
                if ($configVariables -is [hashtable]) {
                    foreach ($key in $configVariables.Keys) {
                        $script:ConfigSettings[$key] = $configVariables[$key]
                    }
                }
                
                Write-Log "Loaded configuration from: $($file.Name)" -Level 'INFO' -Category 'Configuration'
            }
            catch {
                Write-Log "Error loading configuration from $($file.Name): $($_.Exception.Message)" -Level 'ERROR' -Category 'Configuration'
            }
        }
    }
    else {
        Write-Log "Configuration directory not found: $ConfigDirectory" -Level 'WARNING' -Category 'Configuration'
    }
    
    return $script:ConfigSettings
}

# Function to set a configuration value
function Set-ConfigSetting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $true)]
        [object]$Value
    )
    
    $script:ConfigSettings[$Name] = $Value
    Write-Log "Configuration setting '$Name' set to '$Value'" -Level 'DEBUG' -Category 'Configuration'
}

# Function to get a configuration value
function Get-ConfigSetting {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [Parameter(Mandatory = $false)]
        [object]$DefaultValue = $null
    )
    
    if ($script:ConfigSettings.ContainsKey($Name)) {
        return $script:ConfigSettings[$Name]
    }
    
    return $DefaultValue
}

# Function to initialize output paths
function Initialize-OutputPaths {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory = "",
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFilePath = "",
        
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = ""
    )
    
    # Create timestamp for default directory name
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    
    # If no output directory specified, create one in the current directory
    if ([string]::IsNullOrEmpty($OutputDirectory)) {
        $OutputDirectory = Join-Path (Get-Location) "cs-azure-cost-estimate-$timestamp"
    }
    
    # Create the output directory if it doesn't exist
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }
    
    # Set default paths if not specified
    if ([string]::IsNullOrEmpty($OutputFilePath)) {
        $OutputFilePath = Join-Path $OutputDirectory "cs-azure-cost-estimate.csv"
    }
    
    if ([string]::IsNullOrEmpty($LogFilePath)) {
        $LogFilePath = Join-Path $OutputDirectory "cs-azure-cost-estimate.log"
    }
    
    # Create directories for data storage
    $pricingDataDir = Join-Path $OutputDirectory "pricing-data"
    $subscriptionDataDir = Join-Path $OutputDirectory "subscription-data"
    
    # Create directories if they don't exist
    foreach ($dir in @($pricingDataDir, $subscriptionDataDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
    
    # Return a hashtable with all the paths
    $paths = @{
        OutputDirectory = $OutputDirectory
        OutputFilePath = $OutputFilePath
        LogFilePath = $LogFilePath
        PricingCachePath = Join-Path $pricingDataDir "pricing-cache.json"
        SummaryJsonPath = Join-Path $OutputDirectory "cs-azure-cost-estimate-summary.json"
        StatusFilePath = Join-Path $OutputDirectory "status.json"
        BusinessUnitReportPath = Join-Path $OutputDirectory "business-unit-costs.csv"
    }
    
    # Store in config
    $script:ConfigSettings["OutputDirectory"] = $OutputDirectory
    $script:ConfigSettings["OutputFilePath"] = $OutputFilePath
    $script:ConfigSettings["LogFilePath"] = $LogFilePath
    
    return $paths
}

# Function to determine environment type from subscription name or tags
function Get-EnvironmentType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionName,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Tags = @{}
    )
    
    # Check for environment tag first
    $envTagName = Get-ConfigSetting -Name 'EnvironmentTagName' -DefaultValue 'Environment'
    if ($Tags.ContainsKey($envTagName)) {
        $tagValue = $Tags[$envTagName]
        
        # Check each environment category for matching tag values
        foreach ($envCategory in $script:EnvironmentCategories.Keys) {
            if ($script:EnvironmentCategories[$envCategory].TagValues -contains $tagValue) {
                return $envCategory
            }
        }
    }
    
    # If no tag match, check name patterns
    $subscriptionNameLower = $SubscriptionName.ToLower()
    
    foreach ($envCategory in $script:EnvironmentCategories.Keys) {
        foreach ($pattern in $script:EnvironmentCategories[$envCategory].NamePatterns) {
            if ($subscriptionNameLower -match $pattern) {
                return $envCategory
            }
        }
    }
    
    # Default environment if no match found
    return Get-ConfigSetting -Name 'DefaultEnvironment' -DefaultValue 'Unknown'
}

# Export the module functions and variables
Export-ModuleMember -Function Initialize-Configuration, Set-ConfigSetting, Get-ConfigSetting, Initialize-OutputPaths, Get-EnvironmentType
Export-ModuleMember -Variable EnvironmentCategories, SignInsPerUserPerDay, AuditsPerUserPerDay, FixedResourceCosts
