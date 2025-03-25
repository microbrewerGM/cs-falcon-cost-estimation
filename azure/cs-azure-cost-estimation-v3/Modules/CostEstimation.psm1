# Simplified cost estimation module for CrowdStrike Azure Cost Estimation Tool v3

# Function to calculate size-based requirements
function Get-SizeBasedRequirements {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$LogData,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$EntraIdData,
        
        [Parameter(Mandatory = $false)]
        [int]$RetentionDays = (Get-ConfigSetting -Name 'LogRetentionDays' -DefaultValue 30),
        
        [Parameter(Mandatory = $false)]
        [int]$EventsPerSecondPerInstance = (Get-ConfigSetting -Name 'EventsPerInstancePerSecond' -DefaultValue 5000),
        
        [Parameter(Mandatory = $false)]
        [int]$MinimumThroughputUnits = (Get-ConfigSetting -Name 'MinimumThroughputUnits' -DefaultValue 1),
        
        [Parameter(Mandatory = $false)]
        [int]$MaximumThroughputUnits = (Get-ConfigSetting -Name 'MaximumThroughputUnits' -DefaultValue 20),
        
        [Parameter(Mandatory = $false)]
        [int]$MinimumFunctionInstances = (Get-ConfigSetting -Name 'MinimumFunctionInstances' -DefaultValue 1),
        
        [Parameter(Mandatory = $false)]
        [int]$MaximumFunctionInstances = (Get-ConfigSetting -Name 'MaximumFunctionInstances' -DefaultValue 10)
    )
    
    $requirements = @{
        ActivityLogEventsPerDay = $LogData.DailyAverage
        EntraSignInEventsPerDay = $EntraIdData.SignInDailyAverage
        EntraAuditEventsPerDay = $EntraIdData.AuditDailyAverage
        TotalEventsPerDay = 0
        EventsPerSecond = 0
        PeakEventsPerSecond = 0
        AvgLogSizeKB = 0
        DailyStorageUsageGB = 0
        MonthlyStorageUsageGB = 0
        EventHubThroughputUnits = 0
        StorageAccountSizeGB = 0
        FunctionAppInstances = 0
    }
    
    # Calculate total events per day
    $requirements.TotalEventsPerDay = $requirements.ActivityLogEventsPerDay + 
                                     $requirements.EntraSignInEventsPerDay + 
                                     $requirements.EntraAuditEventsPerDay
    
    # Calculate average events per second
    $requirements.EventsPerSecond = [math]::Ceiling($requirements.TotalEventsPerDay / 86400)
    
    # Add a peak multiplier (assuming peak is 3x average)
    $requirements.PeakEventsPerSecond = [math]::Ceiling($requirements.EventsPerSecond * 3)
    
    # Calculate average log size (weighted average)
    $totalEvents = $LogData.LogCount + $EntraIdData.SignInLogCount + $EntraIdData.AuditLogCount
    if ($totalEvents -gt 0) {
        $weightedSize = (($LogData.LogCount * $LogData.AvgLogSizeKB) + 
                       ($EntraIdData.SignInLogCount * $EntraIdData.SignInSize) + 
                       ($EntraIdData.AuditLogCount * $EntraIdData.AuditSize)) / $totalEvents
        $requirements.AvgLogSizeKB = [math]::Round($weightedSize, 2)
    }
    else {
        # Fallback if no log data available
        $requirements.AvgLogSizeKB = ($LogData.AvgLogSizeKB + $EntraIdData.SignInSize + $EntraIdData.AuditSize) / 3
    }
    
    # Calculate daily storage usage (GB)
    $dailyDataKB = $requirements.TotalEventsPerDay * $requirements.AvgLogSizeKB
    $requirements.DailyStorageUsageGB = [math]::Round($dailyDataKB / 1024 / 1024, 2)
    
    # Calculate monthly storage (GB)
    $requirements.MonthlyStorageUsageGB = [math]::Round($requirements.DailyStorageUsageGB * 30, 2)
    
    # Calculate storage account size based on retention period
    $requirements.StorageAccountSizeGB = [math]::Ceiling($requirements.DailyStorageUsageGB * $RetentionDays)
    
    # Calculate required Event Hub throughput units
    # 1 TU = 1 MB/s or 1000 events/s (whichever is reached first)
    $dataRateMBps = ($requirements.PeakEventsPerSecond * $requirements.AvgLogSizeKB) / 1024
    $tuByData = [math]::Ceiling($dataRateMBps)
    $tuByEvents = [math]::Ceiling($requirements.PeakEventsPerSecond / 1000)
    $requirements.EventHubThroughputUnits = [math]::Max($MinimumThroughputUnits, [math]::Min($MaximumThroughputUnits, [math]::Max($tuByData, $tuByEvents)))
    
    # Calculate required Function App instances
    $instances = [math]::Ceiling($requirements.PeakEventsPerSecond / $EventsPerSecondPerInstance)
    $requirements.FunctionAppInstances = [math]::Max($MinimumFunctionInstances, [math]::Min($MaximumFunctionInstances, $instances))
    
    return $requirements
}

# Function to calculate cost estimates based on requirements
function Get-CostEstimates {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Requirements,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Pricing,
        
        [Parameter(Mandatory = $false)]
        [int]$MonthlyKeyVaultOperations = (Get-ConfigSetting -Name 'KeyVaultMonthlyOperations' -DefaultValue 100000),
        
        [Parameter(Mandatory = $false)]
        [hashtable]$FixedResourceCosts = $(Get-Variable -Name 'FixedResourceCosts' -ValueOnly -ErrorAction SilentlyContinue),
        
        [Parameter(Mandatory = $false)]
        [bool]$UseVpnGateway = $false
    )
    
    $estimates = @{
        EventHubCost = 0
        StorageCost = 0
        FunctionAppCost = 0
        KeyVaultCost = 0
        NetworkingCost = 0
        TotalCost = 0
        CostBreakdown = @{}
        MonthlyBreakdown = @{}
    }
    
    # Calculate Event Hub cost
    $estimates.EventHubCost = [math]::Round($Requirements.EventHubThroughputUnits * $Pricing.EventHubTU * 730, 2)
    
    # Calculate Storage cost
    $estimates.StorageCost = [math]::Round($Requirements.StorageAccountSizeGB * $Pricing.StorageGB, 2)
    
    # Calculate Function App cost
    $estimates.FunctionAppCost = [math]::Round($Requirements.FunctionAppInstances * $Pricing.FunctionAppP0V3 * 730, 2)
    
    # Calculate Key Vault cost
    $keyVaultOperationsTenK = [math]::Ceiling($MonthlyKeyVaultOperations / 10000)
    $estimates.KeyVaultCost = [math]::Round($keyVaultOperationsTenK * $Pricing.KeyVault, 2)
    
    # Calculate Networking costs
    $privateEndpointCount = $FixedResourceCosts.PrivateEndpointCount
    $privateEndpointHours = $privateEndpointCount * 730 # Hours in a month
    $privateEndpointCost = $privateEndpointHours * $Pricing.PrivateEndpoint
    
    $vpnGatewayCost = 0
    if ($UseVpnGateway) {
        $vpnGatewayHours = 730 # Hours in a month
        $vpnGatewayCost = $vpnGatewayHours * $Pricing.VnetGateway
    }
    
    $estimates.NetworkingCost = [math]::Round($privateEndpointCost + $vpnGatewayCost + $FixedResourceCosts.NetworkingCost, 2)
    
    # Calculate total cost
    $estimates.TotalCost = $estimates.EventHubCost + $estimates.StorageCost + $estimates.FunctionAppCost + $estimates.KeyVaultCost + $estimates.NetworkingCost
    $estimates.TotalCost = [math]::Round($estimates.TotalCost, 2)
    
    # Create detailed cost breakdown
    $estimates.CostBreakdown = @{
        "Event Hub ($($Requirements.EventHubThroughputUnits) TUs)" = $estimates.EventHubCost
        "Storage ($($Requirements.StorageAccountSizeGB) GB)" = $estimates.StorageCost
        "Function App ($($Requirements.FunctionAppInstances) instances)" = $estimates.FunctionAppCost
        "Key Vault ($($keyVaultOperationsTenK * 10000) operations)" = $estimates.KeyVaultCost
        "Networking (Private Endpoints, VNet)" = $estimates.NetworkingCost
    }
    
    # Create monthly breakdown for forecasting
    $estimates.MonthlyBreakdown = @{
        "Month 1" = $estimates.TotalCost
        "Month 3" = [math]::Round($estimates.TotalCost * 3, 2)
        "Month 6" = [math]::Round($estimates.TotalCost * 6, 2)
        "Month 12" = [math]::Round($estimates.TotalCost * 12, 2)
    }
    
    return $estimates
}

# Function to estimate costs for a subscription
function Get-SubscriptionCostEstimate {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$SubscriptionMetadata,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$ActivityLogData,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$EntraIdData,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Pricing,
        
        [Parameter(Mandatory = $false)]
        [bool]$IsProductionEnvironment = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$BusinessUnit = $(Get-ConfigSetting -Name 'DefaultBusinessUnit' -DefaultValue 'Unassigned')
    )
    
    # Get size-based requirements
    $requirements = Get-SizeBasedRequirements -LogData $ActivityLogData -EntraIdData $EntraIdData
    
    # Determine if VPN Gateway is needed (typically for production environments)
    $useVpnGateway = $IsProductionEnvironment
    
    # Get cost estimates
    $costEstimates = Get-CostEstimates -Requirements $requirements -Pricing $Pricing -UseVpnGateway $useVpnGateway
    
    # Create subscription cost estimate object
    $subscriptionEstimate = @{
        SubscriptionId = $SubscriptionId
        SubscriptionName = $SubscriptionMetadata.SubscriptionName
        BusinessUnit = $BusinessUnit
        Environment = $SubscriptionMetadata.Environment
        Region = $SubscriptionMetadata.PrimaryLocation
        IsProduction = $IsProductionEnvironment
        LogVolume = @{
            ActivityLogsPerDay = $ActivityLogData.DailyAverage
            SignInLogsPerDay = $EntraIdData.SignInDailyAverage
            AuditLogsPerDay = $EntraIdData.AuditDailyAverage
            TotalEventsPerDay = $requirements.TotalEventsPerDay
            PeakEventsPerSecond = $requirements.PeakEventsPerSecond
            AvgLogSizeKB = $requirements.AvgLogSizeKB
        }
        Requirements = $requirements
        MonthlyCost = $costEstimates.TotalCost
        CostDetails = $costEstimates.CostBreakdown
        KeyMetrics = @{
            EventsPerSecond = $requirements.EventsPerSecond
            StoragePerMonth = $requirements.MonthlyStorageUsageGB
            ThroughputUnits = $requirements.EventHubThroughputUnits
            FunctionInstances = $requirements.FunctionAppInstances
        }
        MonthlyBreakdown = $costEstimates.MonthlyBreakdown
    }
    
    return $subscriptionEstimate
}

# Function to calculate costs for all subscriptions
function Get-AllSubscriptionsCostEstimate {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$CollectedData,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Pricing
    )
    
    $estimates = @()
    $subscriptions = $CollectedData.Subscriptions
    $entraIdMetrics = $CollectedData.EntraIdMetrics
    $subscriptionMetadata = $CollectedData.SubscriptionMetadata
    $activityLogs = $CollectedData.ActivityLogs
    
    Write-Log "Calculating cost estimates for $($subscriptions.Count) subscriptions..." -Level 'INFO' -Category 'CostEstimation'
    
    foreach ($subscription in $subscriptions) {
        $subscriptionId = $subscription.Id
        
        # Skip if we don't have metadata or activity logs for this subscription
        if (-not $subscriptionMetadata.ContainsKey($subscriptionId) -or -not $activityLogs.ContainsKey($subscriptionId)) {
            Write-Log "Skipping subscription $subscriptionId - missing data" -Level 'WARNING' -Category 'CostEstimation'
            continue
        }
        
        $metadata = $subscriptionMetadata[$subscriptionId]
        $logData = $activityLogs[$subscriptionId]
        
        # Determine if production environment
        $isProduction = $metadata.IsProductionLike
        
        # Get business unit
        $businessUnit = $metadata.BusinessUnit
        
        # Calculate cost estimate
        $estimate = Get-SubscriptionCostEstimate -SubscriptionId $subscriptionId `
                                                 -SubscriptionMetadata $metadata `
                                                 -ActivityLogData $logData `
                                                 -EntraIdData $entraIdMetrics `
                                                 -Pricing $Pricing `
                                                 -IsProductionEnvironment $isProduction `
                                                 -BusinessUnit $businessUnit
        
        $estimates += $estimate
        Write-Log "Calculated cost estimate for $($metadata.SubscriptionName): $($estimate.MonthlyCost)" -Level 'INFO' -Category 'CostEstimation'
    }
    
    Write-Log "Completed cost estimates for $($estimates.Count) subscriptions" -Level 'SUCCESS' -Category 'CostEstimation'
    return $estimates
}

# Function to aggregate cost estimates for business units
function Get-BusinessUnitCostSummary {
    param (
        [Parameter(Mandatory = $false)]
        [array]$SubscriptionEstimates = @()
    )
    
    # Return empty hashtable if no subscription estimates provided
    if ($null -eq $SubscriptionEstimates -or $SubscriptionEstimates.Count -eq 0) {
        Write-Log "No subscription estimates provided to summarize" -Level 'WARNING' -Category 'CostEstimation'
        return @{}
    }
    
    $buSummary = @{}
    
    foreach ($estimate in $SubscriptionEstimates) {
        # Skip null estimates
        if ($null -eq $estimate) {
            continue
        }
        
        # Use default business unit if not present
        $bu = if ($null -eq $estimate.BusinessUnit) {
            Get-ConfigSetting -Name 'DefaultBusinessUnit' -DefaultValue 'Unassigned'
        } else {
            $estimate.BusinessUnit
        }
        
        # Initialize business unit if not already tracked
        if (-not $buSummary.ContainsKey($bu)) {
            $buSummary[$bu] = @{
                BusinessUnit = $bu
                SubscriptionCount = 0
                TotalMonthlyCost = 0
                ProductionCost = 0
                NonProductionCost = 0
                EventsPerDay = 0
                StoragePerMonth = 0
                Subscriptions = @{}
            }
        }
        
        # Increment counters safely, checking for null values
        $buSummary[$bu].SubscriptionCount++
        
        # Add cost data with null checks
        $monthlyCost = if ($null -eq $estimate.MonthlyCost) { 0 } else { $estimate.MonthlyCost }
        $buSummary[$bu].TotalMonthlyCost += $monthlyCost
        
        # Get events per day safely
        $eventsPerDay = if ($null -eq $estimate.LogVolume -or $null -eq $estimate.LogVolume.TotalEventsPerDay) { 
            0 
        } else { 
            $estimate.LogVolume.TotalEventsPerDay 
        }
        $buSummary[$bu].EventsPerDay += $eventsPerDay
        
        # Get storage safely
        $storagePerMonth = if ($null -eq $estimate.Requirements -or $null -eq $estimate.Requirements.MonthlyStorageUsageGB) { 
            0 
        } else { 
            $estimate.Requirements.MonthlyStorageUsageGB 
        }
        $buSummary[$bu].StoragePerMonth += $storagePerMonth
        
        # Split costs by environment type
        $isProduction = if ($null -eq $estimate.IsProduction) { $false } else { $estimate.IsProduction }
        if ($isProduction) {
            $buSummary[$bu].ProductionCost += $monthlyCost
        } else {
            $buSummary[$bu].NonProductionCost += $monthlyCost
        }
        
        # Skip subscription details if ID is missing
        if ($null -ne $estimate.SubscriptionId) {
            $buSummary[$bu].Subscriptions[$estimate.SubscriptionId] = @{
                Name = if ($null -eq $estimate.SubscriptionName) { "Unknown" } else { $estimate.SubscriptionName }
                MonthlyCost = $monthlyCost
                IsProduction = $isProduction
                EventsPerDay = $eventsPerDay
            }
        }
    }
    
    # If we have business units to process
    if ($buSummary.Count -gt 0) {
        # Round values and calculate percentages
        $totalCostData = $buSummary.Values | Measure-Object -Property TotalMonthlyCost -Sum
        $totalCost = if ($null -eq $totalCostData -or $null -eq $totalCostData.Sum) { 0 } else { $totalCostData.Sum }
        
        foreach ($bu in $buSummary.Keys) {
            # Safely round values with null checks
            $buSummary[$bu].TotalMonthlyCost = [math]::Round($buSummary[$bu].TotalMonthlyCost, 2)
            $buSummary[$bu].ProductionCost = [math]::Round($buSummary[$bu].ProductionCost, 2)
            $buSummary[$bu].NonProductionCost = [math]::Round($buSummary[$bu].NonProductionCost, 2)
            $buSummary[$bu].EventsPerDay = [math]::Round($buSummary[$bu].EventsPerDay, 0)
            $buSummary[$bu].StoragePerMonth = [math]::Round($buSummary[$bu].StoragePerMonth, 2)
            
            if ($totalCost -gt 0) {
                $buSummary[$bu].PercentOfTotal = [math]::Round(($buSummary[$bu].TotalMonthlyCost / $totalCost) * 100, 1)
            } else {
                $buSummary[$bu].PercentOfTotal = 0
            }
        }
    }
    
    Write-Log "Created cost summary for $($buSummary.Count) business units" -Level 'SUCCESS' -Category 'CostEstimation'
    return $buSummary
}

# Export functions
Export-ModuleMember -Function Get-SizeBasedRequirements, Get-CostEstimates, Get-SubscriptionCostEstimate, 
                    Get-AllSubscriptionsCostEstimate, Get-BusinessUnitCostSummary
