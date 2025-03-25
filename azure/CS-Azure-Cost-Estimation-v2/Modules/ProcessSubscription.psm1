# Process Subscription Module for CrowdStrike Azure Cost Estimation Tool

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
    
    # Call the progress function if it exists
    if (Get-Command -Name Show-EnhancedProgress -ErrorAction SilentlyContinue) {
        Show-EnhancedProgress -Activity "Processing Subscriptions" -Status "Subscription $ProcessedCount of $TotalCount - $subscriptionName" -PercentComplete $percentComplete -StartTime $StartTime
    }
    
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

# Export functions
Export-ModuleMember -Function Process-Subscription
