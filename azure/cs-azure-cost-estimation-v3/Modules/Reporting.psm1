# Simplified reporting module for CrowdStrike Azure Cost Estimation Tool v3
# Focus on CSV output only (no HTML reports)

# Function to export subscription cost estimates to CSV
function Export-CostEstimatesToCsv {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionEstimates,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFilePath
    )
    
    Write-Log "Exporting cost estimates to CSV: $OutputFilePath" -Level 'INFO' -Category 'Reporting'
    
    # Create output directory if it doesn't exist
    $outputDir = Split-Path -Parent $OutputFilePath
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    
    # Create CSV content
    $csvData = $SubscriptionEstimates | ForEach-Object {
        # Flatten the hierarchical data for CSV format
        [PSCustomObject]@{
            SubscriptionId = $_.SubscriptionId
            SubscriptionName = $_.SubscriptionName
            BusinessUnit = $_.BusinessUnit
            Environment = $_.Environment
            Region = $_.Region
            IsProduction = $_.IsProduction
            MonthlyCost = $_.MonthlyCost
            AnnualCost = $_.MonthlyBreakdown.'Month 12'
            ActivityLogsPerDay = $_.LogVolume.ActivityLogsPerDay
            SignInLogsPerDay = $_.LogVolume.SignInLogsPerDay
            AuditLogsPerDay = $_.LogVolume.AuditLogsPerDay
            TotalEventsPerDay = $_.LogVolume.TotalEventsPerDay
            EventsPerSecond = $_.KeyMetrics.EventsPerSecond
            PeakEventsPerSecond = $_.LogVolume.PeakEventsPerSecond
            AvgLogSizeKB = $_.LogVolume.AvgLogSizeKB
            StoragePerMonthGB = $_.KeyMetrics.StoragePerMonth
            EventHubThroughputUnits = $_.KeyMetrics.ThroughputUnits
            FunctionAppInstances = $_.KeyMetrics.FunctionInstances
            EventHubCost = $_.CostDetails."Event Hub ($($_.KeyMetrics.ThroughputUnits) TUs)"
            StorageCost = $_.CostDetails."Storage ($($_.Requirements.StorageAccountSizeGB) GB)"
            FunctionAppCost = $_.CostDetails."Function App ($($_.KeyMetrics.FunctionInstances) instances)"
            KeyVaultCost = [double]($_.CostDetails.Keys | Where-Object { $_ -like "Key Vault*" } | ForEach-Object { $_.CostDetails[$_] })
            NetworkingCost = [double]($_.CostDetails.Keys | Where-Object { $_ -like "Networking*" } | ForEach-Object { $_.CostDetails[$_] })
        }
    }
    
    try {
        $csvData | Export-Csv -Path $OutputFilePath -NoTypeInformation -Force
        Write-Log "Successfully exported cost estimates to $OutputFilePath" -Level 'SUCCESS' -Category 'Reporting'
        return $true
    }
    catch {
        Write-Log "Error exporting cost estimates to CSV: $($_.Exception.Message)" -Level 'ERROR' -Category 'Reporting'
        return $false
    }
}

# Function to export business unit cost summary to CSV
function Export-BusinessUnitCostsToCsv {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$BusinessUnitSummary,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFilePath
    )
    
    Write-Log "Exporting business unit costs to CSV: $OutputFilePath" -Level 'INFO' -Category 'Reporting'
    
    # Create output directory if it doesn't exist
    $outputDir = Split-Path -Parent $OutputFilePath
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    
    # Create CSV content
    $csvData = $BusinessUnitSummary.Values | ForEach-Object {
        [PSCustomObject]@{
            BusinessUnit = $_.BusinessUnit
            SubscriptionCount = $_.SubscriptionCount
            TotalMonthlyCost = $_.TotalMonthlyCost
            ProductionCost = $_.ProductionCost
            NonProductionCost = $_.NonProductionCost
            EventsPerDay = $_.EventsPerDay
            StoragePerMonthGB = $_.StoragePerMonth
            PercentOfTotalCost = $_.PercentOfTotal
        }
    } | Sort-Object -Property TotalMonthlyCost -Descending
    
    try {
        $csvData | Export-Csv -Path $OutputFilePath -NoTypeInformation -Force
        Write-Log "Successfully exported business unit costs to $OutputFilePath" -Level 'SUCCESS' -Category 'Reporting'
        return $true
    }
    catch {
        Write-Log "Error exporting business unit costs to CSV: $($_.Exception.Message)" -Level 'ERROR' -Category 'Reporting'
        return $false
    }
}

# Function to export all data to a JSON file (for programmatic use)
function Export-SummaryToJson {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionEstimates,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$BusinessUnitSummary,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$EntraIdData,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFilePath
    )
    
    Write-Log "Exporting summary data to JSON: $OutputFilePath" -Level 'INFO' -Category 'Reporting'
    
    # Create output directory if it doesn't exist
    $outputDir = Split-Path -Parent $OutputFilePath
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    
    # Create a summary object
    $summaryData = @{
        GeneratedOn = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        TotalSubscriptions = $SubscriptionEstimates.Count
        TotalBusinessUnits = $BusinessUnitSummary.Count
        TotalMonthlyCost = ($SubscriptionEstimates | Measure-Object -Property MonthlyCost -Sum).Sum
        TotalAnnualCost = ($SubscriptionEstimates | Measure-Object -Property MonthlyCost -Sum).Sum * 12
        EntraIdInfo = $EntraIdData
        BusinessUnits = $BusinessUnitSummary
        SubscriptionEstimates = $SubscriptionEstimates
    }
    
    try {
        $summaryData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFilePath -Force
        Write-Log "Successfully exported summary data to $OutputFilePath" -Level 'SUCCESS' -Category 'Reporting'
        return $true
    }
    catch {
        Write-Log "Error exporting summary data to JSON: $($_.Exception.Message)" -Level 'ERROR' -Category 'Reporting'
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Export-CostEstimatesToCsv, Export-BusinessUnitCostsToCsv, Export-SummaryToJson
