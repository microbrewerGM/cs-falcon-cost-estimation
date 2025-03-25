# Environment detection functions for the CrowdStrike Azure Cost Estimation tool

# Function to determine the environment category of a subscription
function Get-SubscriptionEnvironment {
    param (
        [Parameter(Mandatory = $true)]
        [object]$Subscription,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$EnvironmentCategories = $script:EnvironmentCategories,
        
        [Parameter(Mandatory = $false)]
        [string]$DefaultEnvironment = $script:DefaultEnvironment,
        
        [Parameter(Mandatory = $false)]
        [string]$EnvironmentTagName = $script:EnvironmentTagName
    )
    
    # Initialize matched environments with priorities
    $matchedEnvironments = @()
    
    # Get subscription tags
    try {
        $tags = Get-AzTag -ResourceId "/subscriptions/$($Subscription.Id)" -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log "Could not get tags for subscription $($Subscription.Name): $($_.Exception.Message)" -Level 'WARNING' -Category 'Environment'
        $tags = $null
    }
    
    # Check each environment category
    foreach ($envName in $EnvironmentCategories.Keys) {
        $envConfig = $EnvironmentCategories[$envName]
        $isMatch = $false
        $matchSource = ""
        
        # Check subscription name for patterns
        foreach ($pattern in $envConfig.NamePatterns) {
            if ($Subscription.Name -match $pattern) {
                $isMatch = $true
                $matchSource = "Name pattern: $pattern"
                break
            }
        }
        
        # If not matched by name, check tags
        if (-not $isMatch -and $tags) {
            # Check tag keys defined in environment category
            foreach ($tagKey in $envConfig.TagKeys) {
                if ($tags.Properties.TagsProperty.ContainsKey($tagKey)) {
                    $tagValue = $tags.Properties.TagsProperty[$tagKey]
                    
                    # Check if tag value matches any of the expected values
                    foreach ($valuePattern in $envConfig.TagValues) {
                        if ($tagValue -match $valuePattern) {
                            $isMatch = $true
                            $matchSource = "Tag: $tagKey=$tagValue"
                            break
                        }
                    }
                    
                    if ($isMatch) { break }
                }
            }
        }
        
        # If matched, add to results with priority
        if ($isMatch) {
            $matchedEnvironments += [PSCustomObject]@{
                Environment = $envName
                Priority = $envConfig.Priority
                MatchSource = $matchSource
                Color = $envConfig.Color
            }
        }
    }
    
    # If no matches, try to find environment tag directly
    if ($matchedEnvironments.Count -eq 0 -and $tags) {
        # Check specific environment tag
        if ($tags.Properties.TagsProperty.ContainsKey($EnvironmentTagName)) {
            $envTagValue = $tags.Properties.TagsProperty[$EnvironmentTagName]
            
            # Try to map to known environments
            foreach ($envName in $EnvironmentCategories.Keys) {
                $envConfig = $EnvironmentCategories[$envName]
                
                foreach ($valuePattern in $envConfig.TagValues) {
                    if ($envTagValue -match $valuePattern) {
                        $matchedEnvironments += [PSCustomObject]@{
                            Environment = $envName
                            Priority = $envConfig.Priority
                            MatchSource = "Environment tag: $envTagValue"
                            Color = $envConfig.Color
                        }
                        break
                    }
                }
            }
            
            # If still no match, but we have an Environment tag, use its value directly
            if ($matchedEnvironments.Count -eq 0) {
                $customEnvironment = $envTagValue.Replace(" ", "")
                
                # If it's a valid name, use it
                if ($customEnvironment -match "^[a-zA-Z0-9]+$") {
                    $matchedEnvironments += [PSCustomObject]@{
                        Environment = $customEnvironment
                        Priority = 999  # Lowest priority
                        MatchSource = "Custom environment tag: $envTagValue"
                        Color = "#808080"  # Gray for custom environments
                    }
                }
            }
        }
    }
    
    # Return the highest priority match or default if none
    if ($matchedEnvironments.Count -gt 0) {
        $bestMatch = $matchedEnvironments | Sort-Object -Property Priority | Select-Object -First 1
        
        Write-Log "Subscription $($Subscription.Name) categorized as: $($bestMatch.Environment) via $($bestMatch.MatchSource)" -Level 'DEBUG' -Category 'Environment'
        
        return [PSCustomObject]@{
            Name = $bestMatch.Environment
            Color = $bestMatch.Color
            Source = $bestMatch.MatchSource
        }
    }
    else {
        Write-Log "Subscription $($Subscription.Name) could not be categorized, using default: $DefaultEnvironment" -Level 'DEBUG' -Category 'Environment'
        
        return [PSCustomObject]@{
            Name = $DefaultEnvironment
            Color = "#808080"  # Gray
            Source = "Default (no matching criteria)"
        }
    }
}

# Function to generate environment rollup report from subscription data
function Get-EnvironmentRollup {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionData
    )
    
    Write-Log "Generating environment cost rollup report..." -Level 'INFO' -Category 'Environments'
    
    # Group by environment
    $envGroups = $SubscriptionData | Group-Object -Property Environment
    
    $envRollup = @()
    
    foreach ($envGroup in $envGroups) {
        $envName = $envGroup.Name
        if ([string]::IsNullOrWhiteSpace($envName)) {
            $envName = $script:DefaultEnvironment
        }
        
        $subscriptions = $envGroup.Group
        $totalCost = ($subscriptions | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum
        $defaultSubCost = 0
        
        $defaultSub = $subscriptions | Where-Object { $_.IsDefaultSubscription }
        if ($defaultSub) {
            $defaultSubCost = $defaultSub.EstimatedMonthlyCost
        }
        
        $resourceCount = ($subscriptions | Measure-Object -Property ResourceCount -Sum).Sum
        $activityLogCount = ($subscriptions | Measure-Object -Property ActivityLogCount -Sum).Sum
        
        $envReport = [PSCustomObject]@{
            Environment = $envName
            SubscriptionCount = $subscriptions.Count
            ResourceCount = $resourceCount
            ActivityLogCount = $activityLogCount
            DefaultSubscriptionCost = $defaultSubCost
            OtherSubscriptionsCost = $totalCost - $defaultSubCost
            TotalMonthlyCost = $totalCost
            IncludesDefaultSubscription = ($defaultSub -ne $null)
            Subscriptions = $subscriptions.SubscriptionName -join ', '
            Color = ($subscriptions | Select-Object -First 1).EnvironmentColor
        }
        
        $envRollup += $envReport
    }
    
    # Sort by total cost descending
    $envRollup = $envRollup | Sort-Object -Property TotalMonthlyCost -Descending
    
    return $envRollup
}

# Function to generate cross-tabulation of business units and environments
function Get-BusinessUnitEnvironmentMatrix {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionData
    )
    
    Write-Log "Generating business unit by environment matrix..." -Level 'INFO' -Category 'CrossTab'
    
    # Get unique business units and environments
    $businessUnits = $SubscriptionData | Select-Object -ExpandProperty BusinessUnit -Unique | Sort-Object
    $environments = $SubscriptionData | Select-Object -ExpandProperty Environment -Unique | Sort-Object
    
    # Create matrix
    $matrix = @{}
    
    # Initialize with zeros
    foreach ($bu in $businessUnits) {
        $matrix[$bu] = @{}
        foreach ($env in $environments) {
            $matrix[$bu][$env] = 0
        }
    }
    
    # Fill in costs
    foreach ($sub in $SubscriptionData) {
        $bu = $sub.BusinessUnit
        $env = $sub.Environment
        $matrix[$bu][$env] += $sub.EstimatedMonthlyCost
    }
    
    # Create row totals
    foreach ($bu in $businessUnits) {
        $total = 0
        foreach ($env in $environments) {
            $total += $matrix[$bu][$env]
        }
        $matrix[$bu]['Total'] = $total
    }
    
    # Create column totals
    $matrix['Total'] = @{}
    foreach ($env in $environments) {
        $total = 0
        foreach ($bu in $businessUnits) {
            $total += $matrix[$bu][$env]
        }
        $matrix['Total'][$env] = $total
    }
    
    # Calculate grand total
    $grandTotal = 0
    foreach ($bu in $businessUnits) {
        $grandTotal += $matrix[$bu]['Total']
    }
    $matrix['Total']['Total'] = $grandTotal
    
    # Return the matrix with metadata
    return [PSCustomObject]@{
        Matrix = $matrix
        BusinessUnits = $businessUnits
        Environments = $environments
        GrandTotal = $grandTotal
    }
}
