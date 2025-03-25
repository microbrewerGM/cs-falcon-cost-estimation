# Simplified pricing module for CrowdStrike Azure Cost Estimation Tool v3

# Module variables
$script:PricingCachePath = $null
$script:DefaultPricing = @{
    # Event Hub pricing
    EventHubTU = 0.018          # $0.018 per TU per hour = ~$13.14 per month
    
    # Storage pricing
    StorageGB = 0.0208          # $0.0208 per GB per month
    
    # App Service pricing
    FunctionAppP0V3 = 0.060     # $0.060 per hour = ~$43.80 per month
    
    # Key Vault pricing
    KeyVault = 0.03             # $0.03 per 10,000 operations
    
    # Networking pricing
    PrivateEndpoint = 0.01      # $0.01 per hour = ~$7.30 per month
    VnetGateway = 0.036         # $0.036 per hour = ~$26.28 per month
}

# Default region
$script:DefaultRegion = "eastus"

# Function to set the pricing cache file path
function Set-PricingCachePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $script:PricingCachePath = $Path
    Write-Log "Pricing cache path set to: $Path" -Level 'DEBUG' -Category 'Pricing'
    return $Path
}

# Function to get static pricing information
function Get-StaticPricing {
    [CmdletBinding()]
    param()
    
    Write-Log "Using static pricing data" -Level 'INFO' -Category 'Pricing'
    return $script:DefaultPricing
}

# Function to retrieve pricing from Azure Retail Rates API
function Get-AzureRetailRates {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [switch]$ForceRefresh = $false,
        
        [Parameter(Mandatory = $false)]
        [int]$CacheExpirationHours = 24
    )
    
    # Check if we have a cache path set
    if (-not $script:PricingCachePath) {
        Write-Log "Pricing cache path not set. Using static pricing." -Level 'WARNING' -Category 'Pricing'
        return Get-StaticPricing
    }
    
    # Check if cache exists and is not expired
    $useCachedData = $false
    if (-not $ForceRefresh -and (Test-Path $script:PricingCachePath)) {
        try {
            $cacheFile = Get-Item $script:PricingCachePath
            $cacheAge = (Get-Date) - $cacheFile.LastWriteTime
            if ($cacheAge.TotalHours -lt $CacheExpirationHours) {
                $useCachedData = $true
            }
        }
        catch {
            Write-Log "Error checking cache file: $($_.Exception.Message)" -Level 'WARNING' -Category 'Pricing'
        }
    }
    
    # Use cached data if available and not expired
    if ($useCachedData) {
        try {
            $cachedPricing = Get-Content -Path $script:PricingCachePath -Raw -ErrorAction Stop | 
                             ConvertFrom-Json -ErrorAction Stop
            Write-Log "Using cached pricing data from $($cacheFile.LastWriteTime)" -Level 'INFO' -Category 'Pricing'
            return $cachedPricing
        }
        catch {
            Write-Log "Error reading cached pricing data: $($_.Exception.Message)" -Level 'WARNING' -Category 'Pricing'
            # Continue to retrieve fresh data
        }
    }
    
    # Attempt to get pricing from Azure Retail Rates API
    Write-Log "Retrieving pricing data from Azure Retail Rates API..." -Level 'INFO' -Category 'Pricing'
    
    # Create a pricing object that we'll populate
    $pricing = $script:DefaultPricing.Clone()
    
    try {
        # Azure Retail Rates API doesn't have an official PowerShell module,
        # so we need to use the REST API directly
        
        # Define the services we're interested in
        $services = @(
            @{
                name = "Event Hubs"
                meterName = "Standard Throughput Unit" 
                property = "EventHubTU"
                unit = "Hours"
                divideBy = 730  # Hours per month to get hourly rate
            },
            @{
                name = "Storage"
                meterName = "Standard Data Lake Storage" 
                property = "StorageGB"
                unit = "GB/Month"
                divideBy = 1    # Already per month
            },
            @{
                name = "App Service"
                meterName = "Premium v3 P0" 
                property = "FunctionAppP0V3"
                unit = "Hours"
                divideBy = 730  # Hours per month to get hourly rate
            },
            @{
                name = "Key Vault"
                meterName = "Operations" 
                property = "KeyVault"
                unit = "10K transactions"
                divideBy = 1    # Already per 10K operations
            },
            @{
                name = "Virtual Network"
                meterName = "Private Link" 
                property = "PrivateEndpoint"
                unit = "Hours"
                divideBy = 730  # Hours per month to get hourly rate
            }
        )
        
        # Filter to reduce number of API calls
        $serviceFilters = $services | ForEach-Object { $_.name } | Join-String -Separator " or "
        $filter = "serviceName eq '$serviceFilters'"
        
        # API endpoint
        $apiVersion = "2023-01-01-preview"
        $endpoint = "https://prices.azure.com/api/retail/prices?api-version=$apiVersion&`$filter=armRegionName eq '$script:DefaultRegion' and ($filter)"
        
        # Call the API
        $response = Invoke-RestMethod -Uri $endpoint -Method Get -ErrorAction Stop
        
        if ($response.Items) {
            Write-Log "Retrieved $($response.Count) pricing items from Azure Retail Rates API" -Level 'INFO' -Category 'Pricing'
            
            # Process each service
            foreach ($service in $services) {
                $matchingItems = $response.Items | Where-Object { 
                    $_.serviceName -eq $service.name -and 
                    $_.meterName -like "*$($service.meterName)*" -and 
                    $_.unitOfMeasure -eq $service.unit
                }
                
                if ($matchingItems) {
                    # Use the lowest price if multiple items match
                    $bestPrice = ($matchingItems | Sort-Object -Property retailPrice)[0]
                    
                    # Normalize to our pricing model
                    $pricing[$service.property] = $bestPrice.retailPrice / $service.divideBy
                    
                    Write-Log "Updated $($service.name) pricing: $($pricing[$service.property])" -Level 'DEBUG' -Category 'Pricing'
                }
                else {
                    Write-Log "No pricing found for $($service.name). Using default." -Level 'WARNING' -Category 'Pricing'
                }
            }
            
            # Cache the pricing data
            try {
                # Make sure directory exists
                $cacheDir = Split-Path -Parent $script:PricingCachePath
                if (-not (Test-Path $cacheDir)) {
                    New-Item -Path $cacheDir -ItemType Directory -Force | Out-Null
                }
                
                $pricing | ConvertTo-Json -Depth 5 | Out-File -Path $script:PricingCachePath -Force
                Write-Log "Cached pricing data to $script:PricingCachePath" -Level 'INFO' -Category 'Pricing'
            }
            catch {
                Write-Log "Error caching pricing data: $($_.Exception.Message)" -Level 'WARNING' -Category 'Pricing'
            }
        }
        else {
            Write-Log "No pricing data returned from Azure Retail Rates API. Using default pricing." -Level 'WARNING' -Category 'Pricing'
        }
    }
    catch {
        Write-Log "Error retrieving pricing data: $($_.Exception.Message)" -Level 'ERROR' -Category 'Pricing'
        Write-Log "Using static pricing data instead" -Level 'INFO' -Category 'Pricing'
    }
    
    return $pricing
}

# Function to get pricing for a specific region
function Get-PricingForRegion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$Region = $script:DefaultRegion,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$PricingData = $null,
        
        [Parameter(Mandatory = $false)]
        [bool]$UseRetailRates = $true
    )
    
    if (-not $PricingData) {
        $PricingData = if ($UseRetailRates) { Get-AzureRetailRates } else { Get-StaticPricing }
    }
    
    # For future: we could implement region-specific pricing adjustments here
    # For now, we'll just use the same pricing for all regions
    
    Write-Log "Using pricing data for region: $Region" -Level 'INFO' -Category 'Pricing'
    return $PricingData
}

# Export functions
Export-ModuleMember -Function Set-PricingCachePath, Get-StaticPricing, Get-AzureRetailRates, Get-PricingForRegion
Export-ModuleMember -Variable DefaultPricing, DefaultRegion
