# Pricing Configuration Settings

# Pricing cache settings
$PricingCacheExpirationHours = 24 # How long cached pricing data remains valid

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

# Fixed costs that don't scale with usage
$FixedResourceCosts = @{
    NetworkingCost = 30.00   # Estimate for NSG, IP addresses, and other networking components
    PrivateEndpointCount = 4 # Number of private endpoints deployed
}

# Key Vault operation assumptions
$KeyVaultMonthlyOperations = 100000 # Default monthly operations for Key Vault
