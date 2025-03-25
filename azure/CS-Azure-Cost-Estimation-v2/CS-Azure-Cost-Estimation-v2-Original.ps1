<#
.SYNOPSIS
CrowdStrike Azure Cost Estimation Tool (v2)

.DESCRIPTION
This enhanced script estimates the costs of deploying CrowdStrike Falcon Cloud Security integration in Azure.
It provides more accurate estimates by analyzing actual log sizes, supporting business unit attribution,
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
.\cs-azure-cost-estimation-v2.ps1 -DaysToAnalyze 14 -SampleLogSize 200

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

#region Configuration Settings
# This section contains all the customizable variables organizations may want to modify

# Default Azure region if the script can't determine it from existing resources
$DefaultRegion = "eastus"

# Currency code for pricing information
$CurrencyCode = "USD"

# Pricing cache settings
$PricingCacheExpirationHours = 24 # How long cached pricing data remains valid

# Log size estimation defaults when sampling isn't possible
$DefaultActivityLogSizeKB = 1.0 # Default size estimation for Activity Log entries
$DefaultEntraIdLogSizeKB = 2.0  # Default size estimation for Entra ID log entries

# Throughput estimation defaults
$EventsPerInstancePerSecond = 50 # Events a single Function App instance can process
$MinimumThroughputUnits = 2     # Minimum Event Hub throughput units
$MaximumThroughputUnits = 10    # Maximum Event Hub throughput units

# Storage calculation defaults
$LogRetentionDays = 30         # Number of days logs are retained in storage
$MinimumFunctionInstances = 1   # Minimum Function App instances
$MaximumFunctionInstances = 4   # Maximum Function App instances

# Key Vault operation assumptions
$KeyVaultMonthlyOperations = 100000 # Default monthly operations for Key Vault

# Default pricing fallbacks by region
$StaticPricing = @{
    "eastus" = @{
        EventHubTU = 20.73       # $/TU/month
        StorageGB = 0.0184       # $/GB/month
        FunctionAppP0V3 = 56.58  # $/instance/month
        KeyVault = 0.03          # $/10,000 operations
        PrivateEndpoint = 0.01   # $/hour
        VnetGateway = 0.30       # $/hour
    }
    "westus" = @{
        EventHubTU = 20.73       # $/TU/month
        StorageGB = 0.0184       # $/GB/month
        FunctionAppP0V3 = 56.58  # $/instance/month
        KeyVault = 0.03          # $/10,000 operations
        PrivateEndpoint = 0.01   # $/hour
        VnetGateway = 0.30       # $/hour
    }
    "centralus" = @{
        EventHubTU = 19.72       # $/TU/month
        StorageGB = 0.0177       # $/GB/month
        FunctionAppP0V3 = 53.75  # $/instance/month
        KeyVault = 0.03          # $/10,000 operations
        PrivateEndpoint = 0.01   # $/hour
        VnetGateway = 0.29       # $/hour
    }
    "default" = @{
        EventHubTU = 22.00       # $/TU/month (higher estimate for unknown regions)
        StorageGB = 0.02         # $/GB/month
        FunctionAppP0V3 = 60.00  # $/instance/month
        KeyVault = 0.03          # $/10,000 operations
        PrivateEndpoint = 0.01   # $/hour
        VnetGateway = 0.32       # $/hour
    }
}

# For extrapolating Entra ID log volumes based on user count
$SignInsPerUserPerDay = @{
    Small = 2.2  # <1000 users - higher per-user rate due to fewer service accounts
    Medium = 1.8 # 1000-10000 users - average sign-ins per user per day
    Large = 1.5  # >10000 users - lower per-user rate due to more service accounts
}

$AuditsPerUserPerDay = @{
    Small = 0.9  # <1000 users
    Medium = 0.7 # 1000-10000 users
    Large = 0.5  # >10000 users
}

# Fixed costs that don't scale with usage
$FixedResourceCosts = @{
    NetworkingCost = 30.00   # Estimate for NSG, IP addresses, and other networking components
    PrivateEndpointCount = 4 # Number of private endpoints deployed
}

# Activity log query limits
$MaxActivityLogsToRetrieve = 5000  # Cap on total logs to retrieve per subscription (for performance)
$ActivityLogPageSize = 1000        # Default page size for activity log queries

# Parallel Execution Configuration
$MaxDegreeOfParallelism = 10       # Maximum number of parallel threads for runspace pool (overrides MaxParallelJobs if higher)
$ParallelTimeout = 300             # Timeout in seconds for parallel jobs
$ThrottleLimitFactorForSubs = 0.3  # Percentage of subscriptions to process in parallel (prevents throttling)

# Environment Classification Settings
$EnvironmentCategories = @{
    Production = @{
        NamePatterns = @("prod", "production", "prd")
        TagKeys = @("Environment", "Env")
        TagValues = @("prod", "production", "prd")
        Color = "#DC3912"  # Red
        Priority = 1       # Higher priority means this category takes precedence when multiple matches
    }
    PreProduction = @{
        NamePatterns = @("preprod", "staging", "stg", "uat")
        TagKeys = @("Environment", "Env")
        TagValues = @("preprod", "staging", "stg", "uat")
        Color = "#FF9900"  # Orange
        Priority = 2
    }
    QA = @{
        NamePatterns = @("qa", "test", "testing")
        TagKeys = @("Environment", "Env")
        TagValues = @("qa", "test", "testing")
        Color = "#109618"  # Green
        Priority = 3
    }
    Development = @{
        NamePatterns = @("dev", "development")
        TagKeys = @("Environment", "Env")
        TagValues = @("dev", "development")
        Color = "#3366CC"  # Blue
        Priority = 4
    }
    Sandbox = @{
        NamePatterns = @("sandbox", "lab", "poc", "demo", "experiment")
        TagKeys = @("Environment", "Env")
        TagValues = @("sandbox", "lab", "poc", "demo", "experiment")
        Color = "#990099"  # Purple
        Priority = 5
    }
    DataModeling = @{
        NamePatterns = @("data", "analytics", "ml", "ai")
        TagKeys = @("Environment", "Env", "Purpose")
        TagValues = @("data", "analytics", "ml", "ai", "datamodeling")
        Color = "#0099C6"  # Cyan
        Priority = 6
    }
    Infrastructure = @{
        NamePatterns = @("infra", "mgmt", "management", "shared", "hub")
        TagKeys = @("Environment", "Env", "Purpose")
        TagValues = @("infra", "infrastructure", "mgmt", "management", "shared", "hub")
        Color = "#DD4477"  # Pink
        Priority = 7
    }
    Personal = @{
        NamePatterns = @("personal", "individual", "user")
        TagKeys = @("Environment", "Env", "Purpose", "Owner")
        TagValues = @("personal", "individual", "research")
        Color = "#66AA00"  # Light green
        Priority = 8
    }
}

$DefaultEnvironment = "Unclassified"  # Default environment when none can be determined
$EnvironmentTagName = "Environment"   # Default tag name for environment detection

# Report visualization settings
$GenerateHtmlReport = $true           # Generate HTML report with visualizations
$IncludeCharts = $true                # Include charts in the HTML report
$ChartPalette = @(                    # Color palette for charts (hex color codes)
    "#3366CC", "#DC3912", "#FF9900", "#109618", "#990099", 
    "#3B3EAC", "#0099C6", "#DD4477", "#66AA00", "#B82E2E"
)
$DefaultBusinessUnit = "Unassigned"   # Default business unit name when none can be determined

#endregion

#region Setup and Utilities

# Create timestamped output directory if not specified
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
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

# Function to write to log file with enhanced prefixing for clarity in extensive logs
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG', 'METRIC')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [string]$Category = 'General',

        [Parameter(Mandatory = $false)]
        [switch]$NoConsole
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [$Category] $Message"
    
    # Write to log file
    Add-Content -Path $LogFilePath -Value $logMessage -ErrorAction SilentlyContinue
    
    # Also write to console with color, unless NoConsole is specified
    if (-not $NoConsole) {
        switch ($Level) {
            'INFO' { Write-Host $logMessage -ForegroundColor Cyan }
            'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
            'ERROR' { Write-Host $logMessage -ForegroundColor Red }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            'DEBUG' { 
                if ($VerbosePreference -eq 'Continue') {
                    Write-Host $logMessage -ForegroundColor Gray 
                }
            }
            'METRIC' { Write-Host $logMessage -ForegroundColor Magenta }
            default { Write-Host $logMessage }
        }
    }
}

# Function to check if a command executed successfully with enhanced error handling
function Test-CommandSuccess {
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [switch]$ContinueOnError,
        
        [Parameter(Mandatory = $false)]
        [string]$Category = 'General'
    )
    
    try {
        $result = & $Command
        return @{
            Success = $true
            Result = $result
        }
    }
    catch {
        if ($ContinueOnError) {
            Write-Log "$ErrorMessage - $($_.Exception.Message)" -Level 'WARNING' -Category $Category
            return @{
                Success = $false
                Error = $_
                ErrorMessage = "$ErrorMessage - $($_.Exception.Message)"
            }
        }
        else {
            Write-Log "$ErrorMessage - $($_.Exception.Message)" -Level 'ERROR' -Category $Category
            throw
        }
    }
}

# Enhanced progress tracking with ETA estimation
function Show-EnhancedProgress {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Activity,
        
        [Parameter(Mandatory = $true)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory = $false)]
        [string]$Status = "",
        
        [Parameter(Mandatory = $false)]
        [DateTime]$StartTime,
        
        [Parameter(Mandatory = $false)]
        [string]$Category = 'Progress'
    )
    
    # Calculate ETA if StartTime is provided and we're not at 0%
    $etaString = ""
    if ($StartTime -and $PercentComplete -gt 0 -and $PercentComplete -lt 100) {
        $elapsed = (Get-Date) - $StartTime
        $estimatedTotal = $elapsed.TotalSeconds / ($PercentComplete / 100)
        $estimatedRemaining = $estimatedTotal - $elapsed.TotalSeconds
        
        if ($estimatedRemaining -gt 0) {
            $etaTimeSpan = [TimeSpan]::FromSeconds($estimatedRemaining)
            if ($etaTimeSpan.TotalHours -ge 1) {
                $etaString = " (ETA: {0:h\h\ m\m\ s\s})" -f $etaTimeSpan
            }
            else {
                $etaString = " (ETA: {0:m\m\ s\s})" -f $etaTimeSpan
            }
        }
    }
    
    $statusWithEta = "$Status$etaString"
    Write-Progress -Activity $Activity -Status $statusWithEta -PercentComplete $PercentComplete
    Write-Log "$Activity - $statusWithEta ($PercentComplete%)" -Level 'INFO' -Category $Category
}

#endregion

#region Authentication and Setup

# Function to initialize Azure connection with enhanced error handling
function Initialize-AzureConnection {
    Write-Log "Checking for required Azure modules..." -Level 'INFO' -Category 'Setup'
    
    # Check for Az PowerShell module with specific version requirements
    $requiredModules = @(
        @{Name = "Az.Accounts"; MinVersion = "2.5.0"},
        @{Name = "Az.Resources"; MinVersion = "5.0.0"},
        @{Name = "Az.Monitor"; MinVersion = "3.0.0"}
    )
    
    $modulesNeedingUpdate = @()
    
    foreach ($module in $requiredModules) {
        $installedModule = Get-Module -ListAvailable -Name $module.Name | Sort-Object Version -Descending | Select-Object -First 1
        
        if (-not $installedModule) {
            Write-Log "$($module.Name) module not found. Please install it using: Install-Module -Name $($module.Name) -AllowClobber -Scope CurrentUser" -Level 'ERROR' -Category 'Setup'
            return $false
        }
        
        if ([version]$installedModule.Version -lt [version]$module.MinVersion) {
            $modulesNeedingUpdate += "$($module.Name) (current: $($installedModule.Version), required: $($module.MinVersion))"
        }
    }
    
    if ($modulesNeedingUpdate.Count -gt 0) {
        Write-Log "Some modules need to be updated: $($modulesNeedingUpdate -join ', ')" -Level 'WARNING' -Category 'Setup'
        Write-Log "You can update modules using: Update-Module -Name [ModuleName]" -Level 'WARNING' -Category 'Setup'
    }
    
    # Check for Azure CLI
    try {
        $azVersion = & az version
        Write-Log "Azure CLI found. Version information: $azVersion" -Level 'INFO' -Category 'Setup'
    }
    catch {
        Write-Log "Azure CLI not found or not in PATH. Please install Azure CLI from https://docs.microsoft.com/cli/azure/install-azure-cli" -Level 'ERROR' -Category 'Setup'
        return $false
    }
    
    # Prompt for Azure login
    Write-Log "Initiating Azure login process..." -Level 'INFO' -Category 'Authentication'
    Write-Host "`nPlease log in to your Azure account. A browser window will open for authentication.`n" -ForegroundColor Yellow
    
    $azLoginResult = Test-CommandSuccess -Command { 
        & az login 
    } -ErrorMessage "Failed to login to Azure" -ContinueOnError -Category 'Authentication'
    
    $azLoginSuccess = $azLoginResult.Success
    
    # Connect with Az PowerShell module
    $azPowerShellResult = Test-CommandSuccess -Command { 
        Connect-AzAccount 
    } -ErrorMessage "Failed to connect using Az PowerShell module" -ContinueOnError -Category 'Authentication'
    
    $azPowerShellSuccess = $azPowerShellResult.Success
    
    if (-not $azLoginSuccess -and -not $azPowerShellSuccess) {
        Write-Log "Failed to authenticate with Azure. Cannot proceed." -Level 'ERROR' -Category 'Authentication'
        return $false
    }
    
    if (-not $azLoginSuccess) {
        Write-Log "Unable to authenticate with Azure CLI. Some functionality may be limited." -Level 'WARNING' -Category 'Authentication'
    }
    else {
        Write-Log "Successfully authenticated with Azure CLI" -Level 'SUCCESS' -Category 'Authentication'
    }
    
    if (-not $azPowerShellSuccess) {
        Write-Log "Unable to authenticate with Az PowerShell module. Some functionality may be limited." -Level 'WARNING' -Category 'Authentication'
    }
    else {
        Write-Log "Successfully authenticated with Az PowerShell module" -Level 'SUCCESS' -Category 'Authentication'
    }
    
    # If requested, try to connect to Azure AD for Entra ID logs
    try {
        # Import the module first if not already available
        if (-not (Get-Module -ListAvailable -Name AzureAD)) {
            Write-Log "AzureAD module not found. Some Entra ID log analysis will be limited." -Level 'WARNING' -Category 'Authentication'
        }
        else {
            Import-Module AzureAD -ErrorAction SilentlyContinue
            Connect-AzureAD -ErrorAction Stop | Out-Null
            Write-Log "Successfully connected to Azure AD" -Level 'SUCCESS' -Category 'Authentication'
        }
    }
    catch {
        Write-Log "Unable to connect to Azure AD. Entra ID log analysis will be limited: $($_.Exception.Message)" -Level 'WARNING' -Category 'Authentication'
    }
    
    return $true
}

#endregion

#region Pricing Functions

# Function to get current pricing from Azure Retail Rates API
function Get-AzureRetailRates {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Region = "eastus",
        
        [Parameter(Mandatory = $false)]
        [string]$CurrencyCode = $script:CurrencyCode,
        
        [Parameter(Mandatory = $false)]
        [string]$CachePath = $PricingCachePath,
        
        [Parameter(Mandatory = $false)]
        [int]$CacheExpirationHours = $PricingCacheExpirationHours
    )
    
    $serviceNames = @(
        "Event Hubs",
        "Storage",
        "Azure Functions",
        "Key Vault",
        "Private Link",
        "Virtual Network"
    )
    
    # Check if we have a recent cache file
    if (Test-Path $CachePath) {
        $cacheFile = Get-Item $CachePath
        $cacheAge = (Get-Date) - $cacheFile.LastWriteTime
        
        if ($cacheAge.TotalHours -lt $CacheExpirationHours) {
            Write-Log "Using cached pricing data (last updated $($cacheFile.LastWriteTime))" -Level 'INFO' -Category 'Pricing'
            $cachedData = Get-Content $CachePath -Raw | ConvertFrom-Json
            
            # Validate it has what we need
            $hasPricing = $true
            foreach ($service in $serviceNames) {
                if (-not ($cachedData.PSObject.Properties.Name -contains $service)) {
                    $hasPricing = $false
                    break
                }
            }
            
            if ($hasPricing) {
                return $cachedData
            }
            
            Write-Log "Cached pricing data is incomplete, retrieving latest pricing" -Level 'INFO' -Category 'Pricing'
        }
        else {
            Write-Log "Cached pricing data is outdated, retrieving latest pricing" -Level 'INFO' -Category 'Pricing'
        }
    }
    
    Write-Log "Retrieving current Azure pricing information from Retail Rates API..." -Level 'INFO' -Category 'Pricing'
    
    $pricing = @{}
    $allRates = @()
    
    try {
        # The Azure Retail Rates API has a lot of data, so we'll filter by services we need
        foreach ($service in $serviceNames) {
            Write-Log "Retrieving pricing for $service..." -Level 'DEBUG' -Category 'Pricing'
            $filter = "serviceName eq '$service' and priceType eq 'Consumption' and armRegionName eq '$Region'"
            
            $apiUrl = "https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview&currencyCode=$CurrencyCode&`$filter=$filter"
            
            $retryCount = 0
            $maxRetries = 3
            $delay = 2
            
            while ($retryCount -lt $maxRetries) {
                try {
                    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -ErrorAction Stop
                    break
                }
                catch {
                    $retryCount++
                    if ($retryCount -eq $maxRetries) {
                        throw
                    }
                    Write-Log "Retry $retryCount of $maxRetries for $service pricing. Waiting ${delay}s..." -Level 'WARNING' -Category 'Pricing'
                    Start-Sleep -Seconds $delay
                    $delay *= 2 # Exponential backoff
                }
            }
            
            if ($response.Items) {
                $rates = $response.Items
                $allRates += $rates
                $pricing[$service] = $rates
                Write-Log "Retrieved $($rates.Count) pricing items for $service" -Level 'DEBUG' -Category 'Pricing'
            }
            else {
                Write-Log "No pricing data found for $service in region $Region" -Level 'WARNING' -Category 'Pricing'
            }
            
            # Avoid rate limiting
            Start-Sleep -Milliseconds 500
        }
        
        # Save to cache
        $pricing | ConvertTo-Json -Depth 10 | Set-Content $CachePath
        Write-Log "Saved pricing data to cache file" -Level 'INFO' -Category 'Pricing'
        
        return $pricing
    }
    catch {
        Write-Log "Failed to retrieve pricing from Azure Retail Rates API: $($_.Exception.Message)" -Level 'ERROR' -Category 'Pricing'
        
        # Fall back to static pricing
        return Get-StaticPricing -Region $Region
    }
}

# Fallback function for static pricing when Retail Rates API is unavailable
function Get-StaticPricing {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Region = $DefaultRegion
    )
    
    Write-Log "Using static pricing data for region $Region" -Level 'WARNING' -Category 'Pricing'
    
    # Use the global static pricing table from Configuration Settings
    $pricingData = $script:StaticPricing
    
    $regionKey = $Region.ToLower()
    if ($pricingData.ContainsKey($regionKey)) {
        return $pricingData[$regionKey]
    }
    else {
        Write-Log "No specific pricing found for region $Region. Using default pricing." -Level 'WARNING' -Category 'Pricing'
        return $pricingData["default"]
    }
}

# Function to extract useful pricing from the retail rates API response
function Get-PricingForRegion {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Region,
        
        [Parameter(Mandatory = $true)]
        [object]$PricingData,
        
        [Parameter(Mandatory = $false)]
        [bool]$UseRetailRates = $UseRealPricing
    )
    
    if (-not $UseRetailRates -or $PricingData -is [hashtable]) {
        # This is already a formatted pricing object (static pricing)
        $regionKey = $Region.ToLower()
        if ($PricingData.ContainsKey($regionKey)) {
            return $PricingData[$regionKey]
        }
        else {
            Write-Log "No specific pricing found for region $Region. Using default pricing." -Level 'WARNING' -Category 'Pricing'
            return $PricingData["default"]
        }
    }
    
    # If we're here, PricingData is from the Retail Rates API
    # Extract and format the pricing we need
    $formattedPricing = @{
        EventHubTU = 0
        StorageGB = 0
        FunctionAppP0V3 = 0
        KeyVault = 0
        PrivateEndpoint = 0
        VnetGateway = 0
    }
    
    # Event Hub Pricing (Standard tier, Throughput Unit)
    $eventHubItem = $PricingData['Event Hubs'] | Where-Object { 
        $_.skuName -eq 'Standard' -and $_.productName -eq 'Event Hubs' -and 
        $_.meterName -like "*Throughput*" -and $_.unitOfMeasure -like "*Units*"
    } | Select-Object -First 1
    
    if ($eventHubItem) {
        $formattedPricing.EventHubTU = $eventHubItem.retailPrice * 744 # Convert hourly to monthly (average hours/month)
        Write-Log "Event Hub TU monthly price: $($formattedPricing.EventHubTU)" -Level 'DEBUG' -Category 'Pricing'
    }
    else {
        $formattedPricing.EventH
