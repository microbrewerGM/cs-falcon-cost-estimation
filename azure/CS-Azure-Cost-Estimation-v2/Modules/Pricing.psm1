# Pricing Module for CrowdStrike Azure Cost Estimation Tool

# Import required modules
Import-Module "$PSScriptRoot\Logging.psm1" -Force
Import-Module "$PSScriptRoot\Config.psm1" -Force

# Path to pricing cache file
$script:PricingCachePath = ""

# Function to set the pricing cache path
function Set-PricingCachePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $script:PricingCachePath = $Path
}

# Function to get current pricing from Azure Retail Rates API
function Get-AzureRetailRates {
    param (
        [Parameter(Mandatory = $false)]
        [string]$Region = $DefaultRegion,

        [Parameter(Mandatory = $false)]
        [string]$CurrencyCode = $CurrencyCode,

        [Parameter(Mandatory = $false)]
        [int]$CacheExpirationHours = $PricingCacheExpirationHours
    )

    # Check if cache path is set
    if ([string]::IsNullOrWhiteSpace($script:PricingCachePath)) {
        Write-Log "Pricing cache path not set. Using default directory." -Level 'WARNING' -Category 'Pricing'
        $script:PricingCachePath = Join-Path $env:TEMP "azure-pricing-cache.json"
    }

    $serviceNames = @(
        "Event Hubs",
        "Storage",
        "Azure Functions",
        "Key Vault",
        "Private Link",
        "Virtual Network"
    )

    # Check if we have a recent cache file
    if (Test-Path $script:PricingCachePath) {
        $cacheFile = Get-Item $script:PricingCachePath
        $cacheAge = (Get-Date) - $cacheFile.LastWriteTime

        if ($cacheAge.TotalHours -lt $CacheExpirationHours) {
            Write-Log "Using cached pricing data (last updated $($cacheFile.LastWriteTime))" -Level 'INFO' -Category 'Pricing'
            $cachedData = Get-Content $script:PricingCachePath -Raw | ConvertFrom-Json

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

            Write-Log "Cached pricing data is incomplete retrieving latest pricing" -Level 'INFO' -Category 'Pricing'
        }
        else {
            Write-Log "Cached pricing data is outdated retrieving latest pricing" -Level 'INFO' -Category 'Pricing'
        }
    }

    Write-Log "Retrieving current Azure pricing information from Retail Rates API..." -Level 'INFO' -Category 'Pricing'

    $pricing = @{}
    $allRates = @()

    try {
        # The Azure Retail Rates API has a lot of data so we'll filter by services we need
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
        $pricing | ConvertTo-Json -Depth 10 | Set-Content $script:PricingCachePath
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
    $pricingData = $StaticPricing

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
        [bool]$UseRetailRates = $true
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

    # If we're here PricingData is from the Retail Rates API
    # Extract and format the pricing we need
    $formattedPricing = @{
        EventHubTU = 0
        StorageGB = 0
        FunctionAppP0V3 = 0
        KeyVault = 0
        PrivateEndpoint = 0
        VnetGateway = 0
    }

    # Event Hub Pricing (Standard tier Throughput Unit)
    $eventHubItem = $PricingData['Event Hubs'] | Where-Object {
        $_.skuName -eq 'Standard' -and $_.productName -eq 'Event Hubs' -and
        $_.meterName -like "*Throughput*" -and $_.unitOfMeasure -like "*Units*"
    } | Select-Object -First 1

    if ($eventHubItem) {
        $formattedPricing.EventHubTU = $eventHubItem.retailPrice * 744 # Convert hourly to monthly (average hours/month)
        Write-Log "Event Hub TU monthly price: $($formattedPricing.EventHubTU)" -Level 'DEBUG' -Category 'Pricing'
    }
    else {
        $formattedPricing.EventHubTU = $StaticPricing.default.EventHubTU # Fallback
        Write-Log "Could not find Event Hub pricing using fallback: $($formattedPricing.EventHubTU)" -Level 'WARNING' -Category 'Pricing'
    }

    # Storage Pricing (Standard LRS)
    $storageItem = $PricingData['Storage'] | Where-Object {
        $_.skuName -eq 'Standard' -and $_.productName -like "*Blob Storage*" -and
        $_.meterName -like "*LRS*" -and $_.unitOfMeasure -eq '1 GB/Month'
    } | Select-Object -First 1

    if ($storageItem) {
        $formattedPricing.StorageGB = $storageItem.retailPrice
        Write-Log "Storage GB monthly price: $($formattedPricing.StorageGB)" -Level 'DEBUG' -Category 'Pricing'
    }
    else {
        $formattedPricing.StorageGB = $StaticPricing.default.StorageGB # Fallback
        Write-Log "Could not find Storage pricing using fallback: $($formattedPricing.StorageGB)" -Level 'WARNING' -Category 'Pricing'
    }

    # Function App Pricing (Premium V3)
    $functionItem = $PricingData['Azure Functions'] | Where-Object {
        $_.skuName -eq 'Premium' -and $_.productName -like "*Functions Premium*" -and
        $_.meterName -like "*P0V3*"
    } | Select-Object -First 1

    if ($functionItem) {
        $formattedPricing.FunctionAppP0V3 = $functionItem.retailPrice * 744 # Convert hourly to monthly
        Write-Log "Function App P0V3 monthly price: $($formattedPricing.FunctionAppP0V3)" -Level 'DEBUG' -Category 'Pricing'
    }
    else {
        $formattedPricing.FunctionAppP0V3 = $StaticPricing.default.FunctionAppP0V3 # Fallback
        Write-Log "Could not find Function App pricing using fallback: $($formattedPricing.FunctionAppP0V3)" -Level 'WARNING' -Category 'Pricing'
    }

    # Key Vault Operations
    $keyVaultItem = $PricingData['Key Vault'] | Where-Object {
        $_.productName -like "*Key Vault*" -and $_.meterName -like "*operations*"
    } | Select-Object -First 1

    if ($keyVaultItem) {
        # Convert to cost per 10000 operations
        $operationsMultiplier = 10000
        if ($keyVaultItem.unitOfMeasure -like "*10000*") {
            $operationsMultiplier = 1
        }
        elseif ($keyVaultItem.unitOfMeasure -like "*100000*") {
            $operationsMultiplier = 0.1
        }

        $formattedPricing.KeyVault = $keyVaultItem.retailPrice * $operationsMultiplier
        Write-Log "Key Vault price per 10000 operations: $($formattedPricing.KeyVault)" -Level 'DEBUG' -Category 'Pricing'
    }
    else {
        $formattedPricing.KeyVault = $StaticPricing.default.KeyVault # Fallback
        Write-Log "Could not find Key Vault pricing using fallback: $($formattedPricing.KeyVault)" -Level 'WARNING' -Category 'Pricing'
    }

    # Private Endpoint Pricing
    $privateEndpointItem = $PricingData['Private Link'] | Where-Object {
        $_.productName -like "*Private Endpoint*" -and $_.unitOfMeasure -eq '1 Hour'
    } | Select-Object -First 1

    if ($privateEndpointItem) {
        $formattedPricing.PrivateEndpoint = $privateEndpointItem.retailPrice
        Write-Log "Private Endpoint hourly price: $($formattedPricing.PrivateEndpoint)" -Level 'DEBUG' -Category 'Pricing'
    }
    else {
        $formattedPricing.PrivateEndpoint = $StaticPricing.default.PrivateEndpoint # Fallback
        Write-Log "Could not find Private Endpoint pricing using fallback: $($formattedPricing.PrivateEndpoint)" -Level 'WARNING' -Category 'Pricing'
    }

    # VNet Gateway Pricing
    $vnetGatewayItem = $PricingData['Virtual Network'] | Where-Object {
        $_.productName -like "*VPN Gateway*" -and $_.skuName -eq 'Basic' -and $_.unitOfMeasure -eq '1 Hour'
    } | Select-Object -First 1

    if ($vnetGatewayItem) {
        $formattedPricing.VnetGateway = $vnetGatewayItem.retailPrice
        Write-Log "VNet Gateway hourly price: $($formattedPricing.VnetGateway)" -Level 'DEBUG' -Category 'Pricing'
    }
    else {
        $formattedPricing.VnetGateway = $StaticPricing.default.VnetGateway # Fallback
        Write-Log "Could not find VNet Gateway pricing using fallback: $($formattedPricing.VnetGateway)" -Level 'WARNING' -Category 'Pricing'
    }

    return $formattedPricing
}

# Export functions
Export-ModuleMember -Function Set-PricingCachePath, Get-AzureRetailRates, Get-StaticPricing, Get-PricingForRegion
