# Pricing configuration for CrowdStrike Azure Cost Estimation Tool v3

# These are default static pricing values used if Azure Retail Rates API access fails
# All pricing is in USD
@{
    # Default region to use for pricing information
    'DefaultRegion' = "eastus"
    
    # Default pricing estimates (used as fallback)
    'DefaultPricing' = @{
        # Event Hub pricing
        'EventHubTU' = 0.018          # $0.018 per TU per hour = ~$13.14 per month
        
        # Storage pricing
        'StorageGB' = 0.0208          # $0.0208 per GB per month
        
        # App Service pricing
        'FunctionAppP0V3' = 0.060     # $0.060 per hour = ~$43.80 per month
        
        # Key Vault pricing
        'KeyVault' = 0.03             # $0.03 per 10,000 operations
        
        # Networking pricing
        'PrivateEndpoint' = 0.01      # $0.01 per hour = ~$7.30 per month
        'VnetGateway' = 0.036         # $0.036 per hour = ~$26.28 per month
    }
    
    # Fixed resource costs
    'FixedResourceCosts' = @{
        'PrivateEndpointCount' = 3    # Number of private endpoints needed
        'NetworkingCost' = 25.0       # Estimated fixed networking cost
    }
    
    # Refresh pricing information every 24 hours
    'PricingCacheExpirationHours' = 24
    
    # Flag to enable/disable Azure Retail Rates API
    'UseRetailRatesApi' = $true
}
