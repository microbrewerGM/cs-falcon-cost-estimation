# Script to process a subscription in a background job
# This script contains all the logic needed to process a subscription
# without relying on the Process-Subscription function from the main script

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionName,
    [Parameter(Mandatory = $true)]
    [int]$ProcessedCount,
    [Parameter(Mandatory = $true)]
    [int]$TotalCount,
    [Parameter(Mandatory = $true)]
    [string]$StartTimeStr,
    [Parameter(Mandatory = $true)]
    [int]$DaysToAnalyze,
    [Parameter(Mandatory = $true)]
    [int]$SampleLogSize,
    [Parameter(Mandatory = $true)]
    [bool]$UseRealPricing,
    [Parameter(Mandatory = $true)]
    [string]$ModulePath,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

# Convert string back to DateTime
$StartTime = [DateTime]::Parse($StartTimeStr)

# Import modules
$env:PSModulePath = $ModulePath + [IO.Path]::PathSeparator + $env:PSModulePath

# Import all required modules
$requiredModules = @(
    "ConfigLoader", 
    "Logging", 
    "Authentication", 
    "Pricing", 
    "DataCollection", 
    "CostEstimation", 
    "Reporting"
)

# Also check for Azure modules
if (-not (Get-Module -Name Az.Accounts -ListAvailable)) {
    Write-Warning "Az.Accounts module not found. Some functionality may be limited."
}

# Try to load AzureAD module if available
if (Get-Module -Name AzureAD -ListAvailable) {
    try {
        Import-Module AzureAD -ErrorAction SilentlyContinue
        Write-Output "AzureAD module loaded."
    }
    catch {
        Write-Warning "AzureAD module found but could not be loaded. Will use Graph API for tenant information."
    }
}
else {
    Write-Warning "AzureAD module not found. Will use Microsoft Graph or Az APIs for tenant information."
}

foreach ($module in $requiredModules) {
    $modulePath = Join-Path $ModulePath "$module.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
    }
    else {
        Write-Error "Required module not found: $modulePath"
        return @{
            Error = $true
            Message = "Required module not found: $modulePath"
        }
    }
}

try {
    # Set up logging for the job
    $LogFilePath = Join-Path $OutputDirectory "job-$SubscriptionId.log"
    Set-LogFilePath -Path $LogFilePath
    
    # Initialize variables
    $subscriptionMetadata = $null
    $activityLogData = $null
    $resourceData = $null
    
    # Set context to the subscription
    Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
    
    # Show progress
    $percentComplete = [math]::Round(($ProcessedCount / $TotalCount) * 100)
    Write-Output "Processing subscription $ProcessedCount of $TotalCount: $SubscriptionName ($SubscriptionId) - $percentComplete% complete"
    
    # Get subscription metadata
    Write-Output "Getting metadata for $SubscriptionName"
    $subscriptionMetadata = Get-SubscriptionMetadata -SubscriptionId $SubscriptionId
    
    # Get subscription activity logs
    Write-Output "Getting activity logs for $SubscriptionName"
    $activityLogData = Get-SubscriptionActivityLogs -SubscriptionId $SubscriptionId -DaysToAnalyze $DaysToAnalyze -SampleSize $SampleLogSize
    
    # Get subscription resources
    Write-Output "Getting resources for $SubscriptionName"
    $resourceData = Get-SubscriptionResources -SubscriptionId $SubscriptionId
    
    # Get pricing for the subscription's region
    $region = $subscriptionMetadata.PrimaryLocation
    if ($region -eq "unknown") {
        $region = "eastus" # Default region
    }
    
    # Load pricing info from file
    $pricingCachePath = Join-Path $OutputDirectory "pricing-data/pricing-cache.json"
    if (Test-Path $pricingCachePath) {
        $pricingInfo = Get-Content $pricingCachePath -Raw | ConvertFrom-Json
    }
    else {
        # Fallback to static pricing
        $pricingInfo = Get-StaticPricing
    }
    
    $regionPricing = Get-PricingForRegion -Region $region -PricingData $pricingInfo -UseRetailRates $UseRealPricing
    
    # Determine if this is a production environment
    $isProduction = $subscriptionMetadata.IsProductionLike
    
    # Get business unit
    $businessUnit = "Unassigned" # Default
    if ($subscriptionMetadata.BusinessUnit -and $subscriptionMetadata.BusinessUnit -ne "Unassigned") {
        $businessUnit = $subscriptionMetadata.BusinessUnit
    }
    
    # Get Entra ID metrics 
    $entraIdMetricsPath = Join-Path $OutputDirectory "entra-id-metrics.json"
    if (Test-Path $entraIdMetricsPath) {
        $entraIdMetrics = Get-Content $entraIdMetricsPath -Raw | ConvertFrom-Json
    }
    else {
        # Create default metrics
        $entraIdMetrics = @{
            SignInLogCount = 1000
            AuditLogCount = 5000
            SignInDailyAverage = 143
            AuditDailyAverage = 714
            UserCount = 100
            SignInSize = 1.5
            AuditSize = 2.0
            Organization = "Small"
        }
    }
    
    # Calculate cost estimate for this subscription
    Write-Output "Calculating cost estimate for $SubscriptionName"
    $subscriptionEstimate = Get-SubscriptionCostEstimate -SubscriptionId $SubscriptionId `
                                                       -SubscriptionMetadata $subscriptionMetadata `
                                                       -ActivityLogData $activityLogData `
                                                       -ResourceData $resourceData `
                                                       -EntraIdData $entraIdMetrics `
                                                       -Pricing $regionPricing `
                                                       -IsProductionEnvironment $isProduction `
                                                       -BusinessUnit $businessUnit
    
    # Add subscription name to the estimate for easier identification
    $subscriptionEstimate["SubscriptionName"] = $SubscriptionName
    
    Write-Output "Completed cost estimate for $SubscriptionName. Monthly cost: $($subscriptionEstimate.MonthlyCost)"
    
    # Return the estimate
    return $subscriptionEstimate
}
catch {
    return @{
        Error = $true
        Message = "Job failed: $($_.Exception.Message)"
        StackTrace = $_.ScriptStackTrace
    }
}
