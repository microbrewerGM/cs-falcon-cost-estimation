# Reporting Module for CrowdStrike Azure Cost Estimation Tool

# Import required modules
Import-Module "$PSScriptRoot\Logging.psm1" -Force
Import-Module "$PSScriptRoot\Config.psm1" -Force

# Function to export subscription cost estimates to CSV
function Export-CostEstimatesToCsv {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionEstimates,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFilePath
    )
    
    $csvData = @()
    
    foreach ($estimate in $SubscriptionEstimates) {
        $csvRow = [PSCustomObject]@{
            SubscriptionId = $estimate.SubscriptionId
            BusinessUnit = $estimate.BusinessUnit
            Environment = $estimate.Environment
            Region = $estimate.Region
            IsProduction = $estimate.IsProduction
            ActivityLogsPerDay = $estimate.LogVolume.ActivityLogsPerDay
            SignInLogsPerDay = $estimate.LogVolume.SignInLogsPerDay
            AuditLogsPerDay = $estimate.LogVolume.AuditLogsPerDay
            TotalEventsPerDay = $estimate.LogVolume.TotalEventsPerDay
            EventsPerSecond = $estimate.KeyMetrics.EventsPerSecond
            PeakEventsPerSecond = $estimate.LogVolume.PeakEventsPerSecond
            AvgLogSizeKB = $estimate.LogVolume.AvgLogSizeKB
            StoragePerMonthGB = $estimate.KeyMetrics.StoragePerMonth
            EventHubThroughputUnits = $estimate.KeyMetrics.ThroughputUnits
            FunctionAppInstances = $estimate.KeyMetrics.FunctionInstances
            MonthlyCost = $estimate.MonthlyCost
            EventHubCost = $estimate.CostDetails."Event Hub ($($estimate.KeyMetrics.ThroughputUnits) TUs)"
            StorageCost = $estimate.CostDetails."Storage ($($estimate.Requirements.StorageAccountSizeGB) GB)"
            FunctionAppCost = ($estimate.CostDetails | Where-Object { $_ -like "*Function App*" } | Select-Object -First 1).Value
            KeyVaultCost = ($estimate.CostDetails | Where-Object { $_ -like "*Key Vault*" } | Select-Object -First 1).Value
            NetworkingCost = ($estimate.CostDetails | Where-Object { $_ -like "*Networking*" } | Select-Object -First 1).Value
        }
        
        $csvData += $csvRow
    }
    
    try {
        $csvData | Export-Csv -Path $OutputFilePath -NoTypeInformation
        Write-Log "Cost estimates exported to $OutputFilePath" -Level 'SUCCESS' -Category 'Reporting'
        return $true
    }
    catch {
        Write-Log "Failed to export cost estimates to CSV: $($_.Exception.Message)" -Level 'ERROR' -Category 'Reporting'
        return $false
    }
}

# Function to export business unit cost summary to CSV
function Export-BusinessUnitCostsToCsv {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$BusinessUnitSummary,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFilePath
    )
    
    $csvData = @()
    
    foreach ($bu in $BusinessUnitSummary.Keys) {
        $summary = $BusinessUnitSummary[$bu]
        
        $csvRow = [PSCustomObject]@{
            BusinessUnit = $summary.BusinessUnit
            SubscriptionCount = $summary.SubscriptionCount
            TotalMonthlyCost = $summary.TotalMonthlyCost
            ProductionCost = $summary.ProductionCost
            NonProductionCost = $summary.NonProductionCost
            PercentOfTotalCost = $summary.PercentOfTotal
            EventsPerDay = $summary.EventsPerDay
            StoragePerMonthGB = $summary.StoragePerMonth
        }
        
        $csvData += $csvRow
    }
    
    try {
        $csvData | Export-Csv -Path $OutputFilePath -NoTypeInformation
        Write-Log "Business unit cost summary exported to $OutputFilePath" -Level 'SUCCESS' -Category 'Reporting'
        return $true
    }
    catch {
        Write-Log "Failed to export business unit costs to CSV: $($_.Exception.Message)" -Level 'ERROR' -Category 'Reporting'
        return $false
    }
}

# Function to export all data to a summary JSON file
function Export-SummaryToJson {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionEstimates,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$BusinessUnitSummary,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFilePath,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$EntraIdData,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$GlobalStats = @{}
    )
    
    $summary = @{
        GeneratedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        GlobalStats = $GlobalStats
        EntraIdStats = $EntraIdData
        BusinessUnits = $BusinessUnitSummary
        Subscriptions = $SubscriptionEstimates
    }
    
    try {
        $summary | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputFilePath
        Write-Log "Full summary exported to $OutputFilePath" -Level 'SUCCESS' -Category 'Reporting'
        return $true
    }
    catch {
        Write-Log "Failed to export summary to JSON: $($_.Exception.Message)" -Level 'ERROR' -Category 'Reporting'
        return $false
    }
}

# Function to generate an HTML report with visualizations
function New-HtmlReport {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionEstimates,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$BusinessUnitSummary,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFilePath,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$GlobalStats = @{},
        
        [Parameter(Mandatory = $false)]
        [string]$ReportTitle = "CrowdStrike Azure Cost Estimation Report",
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeCharts = $IncludeCharts
    )
    
    # Calculate global totals
    $totalMonthlyEstimate = ($SubscriptionEstimates | Measure-Object -Property MonthlyCost -Sum).Sum
    $totalAnnualEstimate = $totalMonthlyEstimate * 12
    $totalSubscriptions = $SubscriptionEstimates.Count
    $totalBusinessUnits = $BusinessUnitSummary.Keys.Count
    
    # Create chart data JSON for potential JavaScript charts
    $buChartData = @()
    foreach ($bu in $BusinessUnitSummary.Keys) {
        $buChartData += @{
            name = $bu
            value = $BusinessUnitSummary[$bu].TotalMonthlyCost
            color = $ChartPalette[$buChartData.Count % $ChartPalette.Count]
        }
    }
    
    $componentChartData = @(
        @{ name = "Event Hub"; value = ($SubscriptionEstimates | Measure-Object { $_.CostDetails."Event Hub ($($_.KeyMetrics.ThroughputUnits) TUs)" } -Sum).Sum; color = $ChartPalette[0] },
        @{ name = "Storage"; value = ($SubscriptionEstimates | Measure-Object { $_.CostDetails."Storage ($($_.Requirements.StorageAccountSizeGB) GB)" } -Sum).Sum; color = $ChartPalette[1] },
        @{ name = "Function App"; value = ($SubscriptionEstimates | Measure-Object { ($_.CostDetails | Where-Object {$_ -like "*Function App*"}).Value } -Sum).Sum; color = $ChartPalette[2] },
        @{ name = "Key Vault"; value = ($SubscriptionEstimates | Measure-Object { ($_.CostDetails | Where-Object {$_ -like "*Key Vault*"}).Value } -Sum).Sum; color = $ChartPalette[3] },
        @{ name = "Networking"; value = ($SubscriptionEstimates | Measure-Object { ($_.CostDetails | Where-Object {$_ -like "*Networking*"}).Value } -Sum).Sum; color = $ChartPalette[4] }
    )
    
    $envChartData = @()
    $environments = $SubscriptionEstimates | Group-Object -Property Environment | Select-Object Name, Count, @{
        Name = 'Cost'; 
        Expression = { ($_.Group | Measure-Object -Property MonthlyCost -Sum).Sum }
    }
    
    foreach ($env in $environments) {
        $envChartData += @{
            name = $env.Name
            value = $env.Cost
            count = $env.Count
            color = $EnvironmentCategories[$env.Name].Color
        }
    }
    
    # Generate the HTML
    $chartScripts = ""
    if ($IncludeCharts) {
        # Include Chart.js scripts
        $chartScripts = @"
<script src="https://cdn.jsdelivr.net/npm/chart.js@3.7.1/dist/chart.min.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function() {
    // Business Unit Chart
    const buChartData = $($buChartData | ConvertTo-Json);
    const componentChartData = $($componentChartData | ConvertTo-Json);
    const envChartData = $($envChartData | ConvertTo-Json);
    
    // Business Unit Pie Chart
    const buCtx = document.getElementById('businessUnitChart').getContext('2d');
    new Chart(buCtx, {
        type: 'pie',
        data: {
            labels: buChartData.map(item => item.name),
            datasets: [{
                data: buChartData.map(item => item.value),
                backgroundColor: buChartData.map(item => item.color),
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'right',
                },
                title: {
                    display: true,
                    text: 'Cost by Business Unit'
                }
            }
        }
    });
    
    // Component Pie Chart
    const componentCtx = document.getElementById('componentChart').getContext('2d');
    new Chart(componentCtx, {
        type: 'pie',
        data: {
            labels: componentChartData.map(item => item.name),
            datasets: [{
                data: componentChartData.map(item => item.value),
                backgroundColor: componentChartData.map(item => item.color),
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'right',
                },
                title: {
                    display: true,
                    text: 'Cost by Component'
                }
            }
        }
    });
    
    // Environment Pie Chart
    const envCtx = document.getElementById('environmentChart').getContext('2d');
    new Chart(envCtx, {
        type: 'pie',
        data: {
            labels: envChartData.map(item => item.name),
            datasets: [{
                data: envChartData.map(item => item.value),
                backgroundColor: envChartData.map(item => item.color),
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'right',
                },
                title: {
                    display: true,
                    text: 'Cost by Environment'
                }
            }
        }
    });
});
</script>
"@
    }
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$ReportTitle</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
            border-bottom: 1px solid #ddd;
            padding-bottom: 10px;
        }
        .summary-box {
            display: inline-block;
            width: 22%;
            margin: 0 1%;
            padding: 15px;
            background-color: #f8f9fa;
            border-radius: 5px;
            text-align: center;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .summary-box h3 {
            margin-top: 0;
            color: #666;
            font-size: 14px;
            text-transform: uppercase;
        }
        .summary-box p {
            margin-bottom: 0;
            font-size: 24px;
            font-weight: bold;
            color: #0066cc;
        }
        .section {
            margin-bottom: 40px;
        }
        .chart-container {
            width: 32%;
            height: 300px;
            display: inline-block;
            margin-right: 1%;
            vertical-align: top;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
        }
        th, td {
            padding: 10px;
            border: 1px solid #ddd;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
            font-weight: bold;
        }
        tr:nth-child(even) {
            background-color: #f8f9fa;
        }
        .footnote {
            font-size: 12px;
            color: #666;
            margin-top: 40px;
            border-top: 1px solid #ddd;
            padding-top: 10px;
        }
    </style>
    $chartScripts
</head>
<body>
    <div class="header">
        <h1>$ReportTitle</h1>
        <p>Generated on $(Get-Date -Format "MMMM d, yyyy 'at' h:mm tt")</p>
    </div>
    
    <div class="section">
        <div class="summary-box">
            <h3>Monthly Cost Estimate</h3>
            <p>$$([math]::Round($totalMonthlyEstimate, 2))</p>
        </div>
        <div class="summary-box">
            <h3>Annual Cost Estimate</h3>
            <p>$$([math]::Round($totalAnnualEstimate, 2))</p>
        </div>
        <div class="summary-box">
            <h3>Subscriptions</h3>
            <p>$totalSubscriptions</p>
        </div>
        <div class="summary-box">
            <h3>Business Units</h3>
            <p>$totalBusinessUnits</p>
        </div>
    </div>
    
    $(if ($IncludeCharts) {
        @"
    <div class="section">
        <h2>Cost Distribution</h2>
        <div class="chart-container">
            <canvas id="businessUnitChart"></canvas>
        </div>
        <div class="chart-container">
            <canvas id="componentChart"></canvas>
        </div>
        <div class="chart-container">
            <canvas id="environmentChart"></canvas>
        </div>
    </div>
"@
    })
    
    <div class="section">
        <h2>Business Unit Summary</h2>
        <table>
            <tr>
                <th>Business Unit</th>
                <th>Subscriptions</th>
                <th>Monthly Cost</th>
                <th>% of Total</th>
                <th>Prod Cost</th>
                <th>Non-Prod Cost</th>
                <th>Events/Day</th>
                <th>Storage/Month (GB)</th>
            </tr>
            $(foreach ($bu in ($BusinessUnitSummary.Keys | Sort-Object)) {
                $summary = $BusinessUnitSummary[$bu]
                @"
            <tr>
                <td>$($summary.BusinessUnit)</td>
                <td>$($summary.SubscriptionCount)</td>
                <td>$$$([math]::Round($summary.TotalMonthlyCost, 2))</td>
                <td>$($summary.PercentOfTotal)%</td>
                <td>$$$([math]::Round($summary.ProductionCost, 2))</td>
                <td>$$$([math]::Round($summary.NonProductionCost, 2))</td>
                <td>$([math]::Round($summary.EventsPerDay, 0))</td>
                <td>$([math]::Round($summary.StoragePerMonth, 2))</td>
            </tr>
"@
            })
        </table>
    </div>
    
    <div class="section">
        <h2>Subscription Cost Estimates</h2>
        <table>
            <tr>
                <th>Subscription ID</th>
                <th>Business Unit</th>
                <th>Environment</th>
                <th>Region</th>
                <th>Events/Day</th>
                <th>Events/Sec (Peak)</th>
                <th>Storage/Month (GB)</th>
                <th>Monthly Cost</th>
            </tr>
            $(foreach ($sub in ($SubscriptionEstimates | Sort-Object -Property MonthlyCost -Descending)) {
                @"
            <tr>
                <td>$($sub.SubscriptionId)</td>
                <td>$($sub.BusinessUnit)</td>
                <td>$($sub.Environment)</td>
                <td>$($sub.Region)</td>
                <td>$([math]::Round($sub.LogVolume.TotalEventsPerDay, 0))</td>
                <td>$($sub.LogVolume.PeakEventsPerSecond)</td>
                <td>$([math]::Round($sub.KeyMetrics.StoragePerMonth, 2))</td>
                <td>$$$([math]::Round($sub.MonthlyCost, 2))</td>
            </tr>
"@
            })
        </table>
    </div>
    
    <div class="footnote">
        <p>This is an estimate of the cost to deploy and operate the CrowdStrike Falcon Cloud Security integration in Azure. Actual costs may vary based on usage patterns and Azure pricing changes.</p>
        <p>The estimates are based on the current Azure Retail Rates API pricing information or static pricing data where API information is not available.</p>
    </div>
</body>
</html>
"@
    
    try {
        $html | Set-Content -Path $OutputFilePath
        Write-Log "HTML report generated at $OutputFilePath" -Level 'SUCCESS' -Category 'Reporting'
        return $true
    }
    catch {
        Write-Log "Failed to generate HTML report: $($_.Exception.Message)" -Level 'ERROR' -Category 'Reporting'
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Export-CostEstimatesToCsv, Export-BusinessUnitCostsToCsv, Export-SummaryToJson, New-HtmlReport
