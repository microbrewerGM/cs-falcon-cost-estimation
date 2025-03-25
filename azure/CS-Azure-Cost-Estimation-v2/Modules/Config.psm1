# Configuration Module for CrowdStrike Azure Cost Estimation Tool

# Default Azure region if the script can't determine it from existing resources
$script:DefaultRegion = "eastus"

# Currency code for pricing information
$script:CurrencyCode = "USD"

# Pricing cache settings
$script:PricingCacheExpirationHours = 24 # How long cached pricing data remains valid

# Log size estimation defaults when sampling isn't possible
$script:DefaultActivityLogSizeKB = 1.0 # Default size estimation for Activity Log entries
$script:DefaultEntraIdLogSizeKB = 2.0  # Default size estimation for Entra ID log entries

# Throughput estimation defaults
$script:EventsPerInstancePerSecond = 50 # Events a single Function App instance can process
$script:MinimumThroughputUnits = 2     # Minimum Event Hub throughput units
$script:MaximumThroughputUnits = 10    # Maximum Event Hub throughput units

# Storage calculation defaults
$script:LogRetentionDays = 30         # Number of days logs are retained in storage
$script:MinimumFunctionInstances = 1   # Minimum Function App instances
$script:MaximumFunctionInstances = 4   # Maximum Function App instances

# Key Vault operation assumptions
$script:KeyVaultMonthlyOperations = 100000 # Default monthly operations for Key Vault

# Default pricing fallbacks by region
$script:StaticPricing = @{
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
$script:SignInsPerUserPerDay = @{
    Small = 2.2  # <1000 users - higher per-user rate due to fewer service accounts
    Medium = 1.8 # 1000-10000 users - average sign-ins per user per day
    Large = 1.5  # >10000 users - lower per-user rate due to more service accounts
}

$script:AuditsPerUserPerDay = @{
    Small = 0.9  # <1000 users
    Medium = 0.7 # 1000-10000 users
    Large = 0.5  # >10000 users
}

# Fixed costs that don't scale with usage
$script:FixedResourceCosts = @{
    NetworkingCost = 30.00   # Estimate for NSG, IP addresses, and other networking components
    PrivateEndpointCount = 4 # Number of private endpoints deployed
}

# Activity log query limits
$script:MaxActivityLogsToRetrieve = 5000  # Cap on total logs to retrieve per subscription (for performance)
$script:ActivityLogPageSize = 1000        # Default page size for activity log queries

# Parallel Execution Configuration
$script:MaxDegreeOfParallelism = 10       # Maximum number of parallel threads for runspace pool (overrides MaxParallelJobs if higher)
$script:ParallelTimeout = 300             # Timeout in seconds for parallel jobs
$script:ThrottleLimitFactorForSubs = 0.3  # Percentage of subscriptions to process in parallel (prevents throttling)

# Environment Classification Settings
$script:EnvironmentCategories = @{
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

$script:DefaultEnvironment = "Unclassified"  # Default environment when none can be determined
$script:EnvironmentTagName = "Environment"   # Default tag name for environment detection

# Report visualization settings
$script:GenerateHtmlReport = $true           # Generate HTML report with visualizations
$script:IncludeCharts = $true                # Include charts in the HTML report
$script:ChartPalette = @(                    # Color palette for charts (hex color codes)
    "#3366CC", "#DC3912", "#FF9900", "#109618", "#990099", 
    "#3B3EAC", "#0099C6", "#DD4477", "#66AA00", "#B82E2E"
)
$script:DefaultBusinessUnit = "Unassigned"   # Default business unit name when none can be determined

# Function to initialize output paths
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

# Export functions and variables
Export-ModuleMember -Function Initialize-OutputPaths
Export-ModuleMember -Variable DefaultRegion, CurrencyCode, PricingCacheExpirationHours, DefaultActivityLogSizeKB, DefaultEntraIdLogSizeKB, 
    EventsPerInstancePerSecond, MinimumThroughputUnits, MaximumThroughputUnits, LogRetentionDays, MinimumFunctionInstances,
    MaximumFunctionInstances, KeyVaultMonthlyOperations, StaticPricing, SignInsPerUserPerDay, AuditsPerUserPerDay,
    FixedResourceCosts, MaxActivityLogsToRetrieve, ActivityLogPageSize, MaxDegreeOfParallelism, ParallelTimeout,
    ThrottleLimitFactorForSubs, EnvironmentCategories, DefaultEnvironment, EnvironmentTagName, GenerateHtmlReport,
    IncludeCharts, ChartPalette, DefaultBusinessUnit
