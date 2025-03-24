# CrowdStrike Azure Cost Estimation Plan

## Language: PowerShell

## Approach:

1. **Data Collection Component**
   - Query Activity Log volumes across subscriptions
   - Measure Entra ID SignIn and Audit log volumes
   - Analyze current resource counts by type

2. **Analysis Component**
   - Calculate projected Event Hub throughput needs
   - Estimate storage requirements
   - Model function app scaling patterns

3. **Reporting Component**
   - Output detailed subscription-by-subscription estimates in CSV format only
   - Include placeholder column for Business Unit mapping
   - Include region information for each subscription

## Resources to Query and Logic

### 1. Subscription Data Collection
```powershell
# Get all subscriptions
$subscriptions = Get-AzSubscription | Where-Object {$_.State -eq "Enabled"}

foreach ($subscription in $subscriptions) {
    # Set context to current subscription
    Set-AzContext -Subscription $subscription.Id
    
    # Get subscription region
    $locations = Get-AzResourceGroup | Select-Object -ExpandProperty Location | Sort-Object -Unique
    
    # Store in output array
    $results += [PSCustomObject]@{
        SubscriptionId = $subscription.Id
        SubscriptionName = $subscription.Name
        Region = $locations -join ','
        BusinessUnit = "" # Placeholder for manual mapping
        # Other fields will be populated later
    }
}
```

### 2. Activity Log Volume Analysis
```powershell
# For each subscription
foreach ($subscription in $subscriptions) {
    # Set context
    Set-AzContext -Subscription $subscription.Id
    
    # Get Activity Log count for time period
    $startTime = (Get-Date).AddDays(-$DaysToAnalyze)
    $endTime = Get-Date
    
    $activityLogCount = Get-AzLog -StartTime $startTime -EndTime $endTime | Measure-Object | Select-Object -ExpandProperty Count
    
    # Calculate daily average
    $dailyAverage = $activityLogCount / $DaysToAnalyze
    
    # Update results array
    $subscriptionResult = $results | Where-Object {$_.SubscriptionId -eq $subscription.Id}
    $subscriptionResult.ActivityLogCount = $activityLogCount
    $subscriptionResult.DailyAverage = $dailyAverage
}
```

### 3. Entra ID Log Analysis
```powershell
# Only need to do this once as Entra ID logs are tenant-wide
# Requires Global Admin or Security Admin rights
$startTime = (Get-Date).AddDays(-$DaysToAnalyze)
$endTime = Get-Date

# Get sign-in log metrics
$signInLogCount = Get-AzLog -StartTime $startTime -EndTime $endTime -ResourceProvider "Microsoft.Aadiam" -ResourceType "SignInLogs" | Measure-Object | Select-Object -ExpandProperty Count

# Get audit log metrics
$auditLogCount = Get-AzLog -StartTime $startTime -EndTime $endTime -ResourceProvider "Microsoft.Aadiam" -ResourceType "AuditLogs" | Measure-Object | Select-Object -ExpandProperty Count

# Calculate daily averages
$signInDailyAverage = $signInLogCount / $DaysToAnalyze
$auditDailyAverage = $auditLogCount / $DaysToAnalyze

# Store tenant-wide metrics for later calculations
$tenantMetrics = @{
    SignInLogCount = $signInLogCount
    AuditLogCount = $auditLogCount
    SignInDailyAverage = $signInDailyAverage
    AuditDailyAverage = $auditDailyAverage
}
```

### 4. Resource Count Analysis
```powershell
# For each subscription
foreach ($subscription in $subscriptions) {
    # Set context
    Set-AzContext -Subscription $subscription.Id
    
    # Get resource counts by type
    $resources = Get-AzResource
    $resourceCounts = $resources | Group-Object -Property ResourceType | Select-Object Name, Count
    
    # Update results with resource counts
    $subscriptionResult = $results | Where-Object {$_.SubscriptionId -eq $subscription.Id}
    $subscriptionResult.ResourceCount = $resources.Count
    
    # Store detailed resource counts for later analysis
    $subscriptionResult.ResourceTypes = $resourceCounts
}
```

### 5. Event Hub Throughput Estimation
```powershell
# Event Hub throughput calculation logic
# Each subscription contributes activity logs
# Tenant contributes Entra ID logs

# For each subscription
foreach ($subscription in $subscriptions) {
    $subscriptionResult = $results | Where-Object {$_.SubscriptionId -eq $subscription.Id}
    
    # Activity logs - assume avg size of 1KB per log
    $activityLogSizeKB = $subscriptionResult.DailyAverage * 1  # 1KB per log estimate
    
    # Calculate ingress events per day (each log is an event)
    $ingressEventsPerDay = $subscriptionResult.DailyAverage
    
    # Add to results
    $subscriptionResult.EstimatedDailyEventHubIngress = $activityLogSizeKB
    $subscriptionResult.EstimatedDailyEventCount = $ingressEventsPerDay
}

# Default subscription will handle all Entra ID logs too
$defaultSubResult = $results | Where-Object {$_.SubscriptionId -eq $DefaultSubscriptionId}
$defaultSubResult.EstimatedDailyEventHubIngress += ($tenantMetrics.SignInDailyAverage + $tenantMetrics.AuditDailyAverage) * 2  # 2KB per Entra ID log estimate
$defaultSubResult.EstimatedDailyEventCount += ($tenantMetrics.SignInDailyAverage + $tenantMetrics.AuditDailyAverage)

# Calculate throughput units needed
# 1 TU = 1MB/s ingress
foreach ($subscriptionResult in $results) {
    # Convert KB to MB per second
    $mbPerDay = $subscriptionResult.EstimatedDailyEventHubIngress / 1024
    $mbPerSecond = $mbPerDay / 86400  # seconds in a day
    
    # Event Hub TUs (min 2, max 10)
    $estimatedTUs = [Math]::Max(2, [Math]::Min(10, [Math]::Ceiling($mbPerSecond)))
    $subscriptionResult.EstimatedEventHubTUs = $estimatedTUs
}
```

### 6. Storage Requirements Calculation
```powershell
# For each subscription
foreach ($subscription in $subscriptions) {
    $subscriptionResult = $results | Where-Object {$_.SubscriptionId -eq $subscription.Id}
    
    # Calculate storage needed for log retention (30 days)
    # Activity logs - daily size * retention period
    $activityLogStorageGB = ($subscriptionResult.EstimatedDailyEventHubIngress * 30) / (1024 * 1024)  # Convert KB to GB
    
    # Add to results
    $subscriptionResult.EstimatedStorageGB = $activityLogStorageGB
}

# Default subscription also needs storage for Entra ID logs
$defaultSubResult = $results | Where-Object {$_.SubscriptionId -eq $DefaultSubscriptionId}
$entraIdLogStorageGB = (($tenantMetrics.SignInDailyAverage + $tenantMetrics.AuditDailyAverage) * 2 * 30) / (1024 * 1024)  # Convert KB to GB
$defaultSubResult.EstimatedStorageGB += $entraIdLogStorageGB
```

### 7. Function App Scaling Estimation
```powershell
# Function App scaling depends on event processing rate
# For default subscription where function apps are deployed
$defaultSubResult = $results | Where-Object {$_.SubscriptionId -eq $DefaultSubscriptionId}

# Calculate events per second
$eventsPerSecond = $defaultSubResult.EstimatedDailyEventCount / 86400

# Function App instance calculation
# P0V3 can handle ~X events/second per instance
$eventsPerInstancePerSecond = 50  # Estimate - adjust based on actual performance data
$estimatedInstances = [Math]::Max(1, [Math]::Min(4, [Math]::Ceiling($eventsPerSecond / $eventsPerInstancePerSecond)))

$defaultSubResult.EstimatedFunctionAppInstances = $estimatedInstances
```

### 8. Cost Calculation
```powershell
# Get regional pricing information
$regionPricing = @{
    # Sample pricing data - would be replaced with API call or lookup table
    "eastus" = @{
        EventHubTU = 20.73  # $/TU/month
        StorageGB = 0.0184  # $/GB/month
        FunctionAppP0V3 = 56.58  # $/instance/month
    }
    # Other regions...
}

# Calculate costs for each subscription
foreach ($subscriptionResult in $results) {
    # Get appropriate pricing for subscription's region
    # If multiple regions, use primary or most expensive
    $region = $subscriptionResult.Region.Split(',')[0].ToLower()
    $pricing = $regionPricing[$region]
    
    # Only default subscription has direct costs
    if ($subscriptionResult.SubscriptionId -eq $DefaultSubscriptionId) {
        # Calculate component costs
        $eventHubCost = $subscriptionResult.EstimatedEventHubTUs * $pricing.EventHubTU
        $storageCost = $subscriptionResult.EstimatedStorageGB * $pricing.StorageGB
        $functionAppCost = $subscriptionResult.EstimatedFunctionAppInstances * $pricing.FunctionAppP0V3 * 2  # 2 function apps
        
        # Add additional costs (KeyVault, Private Link, etc.)
        $additionalCosts = 50  # Estimate for other resources
        
        $totalCost = $eventHubCost + $storageCost + $functionAppCost + $additionalCosts
    } else {
        # Non-default subscriptions only have diagnostic setting - no direct cost
        $totalCost = 0
    }
    
    $subscriptionResult.EstimatedMonthlyCost = $totalCost
}
```

### 9. CSV Export
```powershell
# Export results to CSV
$results | Select-Object SubscriptionId, SubscriptionName, Region, BusinessUnit, ActivityLogCount, 
    DailyAverage, EstimatedEventHubTUs, EstimatedStorageGB, EstimatedFunctionAppInstances, 
    EstimatedMonthlyCost | Export-Csv -Path $OutputFilePath -NoTypeInformation
```

## Implementation Plan:

1. Create PowerShell script with parameterized values for:
   - Analysis timeframe (default to 7 days, with options for 14 and 30 days)
   - Region filtering (include all, but report region in output)

2. Analysis progression:
   - Initial run with 7-day window for quick analysis
   - Secondary run with 14-day window for trend validation
   - Final run with 30-day window for comprehensive assessment

3. Region handling:
   - Skip disabled regions automatically
   - Include region information in output for pivot analysis
   - Report on region-specific pricing variations

4. Authentication:
   - Use interactive `az login` authentication
   - Validate successful authentication before proceeding

5. CSV Output Structure:
   - Subscription ID
   - Subscription Name
   - Region
   - Business Unit (placeholder column)
   - Activity Log Count
   - Estimated Event Hub Throughput
   - Estimated Storage Requirements
   - Projected Monthly Cost
