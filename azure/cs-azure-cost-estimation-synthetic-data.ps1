# This script generates synthetic data for demonstrating the CrowdStrike Azure Cost Estimation tool

# Create synthetic subscription data
function New-SyntheticSubscriptionData {
    [CmdletBinding()]
    param()
    
    # Define business units
    $businessUnits = @(
        "IT Operations",
        "Finance",
        "Sales",
        "Marketing",
        "HR",
        "R&D",
        "Legal",
        "Executive"
    )
    
    # Define regions
    $regions = @(
        "eastus",
        "westus2",
        "centralus",
        "northeurope",
        "westeurope"
    )
    
    # Create synthetic subscriptions
    $subscriptions = @()
    
    # IT Operations - typically has larger footprint
        $subscriptions += [PSCustomObject]@{
            SubscriptionId = "00000000-0000-0000-0000-000000000001"
            SubscriptionName = "IT-Operations-Primary"
            Region = $regions[0]
            BusinessUnit = $businessUnits[0]
            Environment = "Production"
            EnvironmentColor = "#DC3912" # Red for production
            ActivityLogCount = 8500
            ResourceCount = 320
            DailyAverage = 1214
            EstimatedEventHubTUs = 6
            EstimatedStorageGB = 42.5
            EstimatedDailyEventHubIngress = 1456.2
            EstimatedDailyEventCount = 1214
            EstimatedFunctionAppInstances = 2
            IsDefaultSubscription = $true
            EstimatedMonthlyCost = 742.35
        }
    
    $subscriptions += [PSCustomObject]@{
        SubscriptionId = "00000000-0000-0000-0000-000000000002"
        SubscriptionName = "IT-Operations-Secondary"
        Region = $regions[0]
        BusinessUnit = $businessUnits[0]
        Environment = "Development"
        EnvironmentColor = "#3366CC"  # Blue for dev
        ActivityLogCount = 3200
        ResourceCount = 110
        DailyAverage = 457
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 548.4
        EstimatedDailyEventCount = 457
        EstimatedFunctionAppInstances = 0
        IsDefaultSubscription = $false
        EstimatedMonthlyCost = 0
    }
    
    # Finance
    $subscriptions += [PSCustomObject]@{
        SubscriptionId = "00000000-0000-0000-0000-000000000003"
        SubscriptionName = "Finance-Production"
        Region = $regions[1]
        BusinessUnit = $businessUnits[1]
        Environment = "Production"
        EnvironmentColor = "#DC3912"  # Red for production
        ActivityLogCount = 2100
        ResourceCount = 87
        DailyAverage = 300
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 360
        EstimatedDailyEventCount = 300
        EstimatedFunctionAppInstances = 0
        IsDefaultSubscription = $false
        EstimatedMonthlyCost = 0
    }
    
    # Sales
    $subscriptions += [PSCustomObject]@{
        SubscriptionId = "00000000-0000-0000-0000-000000000004"
        SubscriptionName = "Sales-CRM"
        Region = $regions[2]
        BusinessUnit = $businessUnits[2]
        ActivityLogCount = 4300
        ResourceCount = 145
        DailyAverage = 614
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 736.8
        EstimatedDailyEventCount = 614
        EstimatedFunctionAppInstances = 0
        IsDefaultSubscription = $false
        EstimatedMonthlyCost = 0
    }
    
    # Marketing
    $subscriptions += [PSCustomObject]@{
        SubscriptionId = "00000000-0000-0000-0000-000000000005"
        SubscriptionName = "Marketing-Digital"
        Region = $regions[2]
        BusinessUnit = $businessUnits[3]
        ActivityLogCount = 3800
        ResourceCount = 115
        DailyAverage = 542
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 650.4
        EstimatedDailyEventCount = 542
        EstimatedFunctionAppInstances = 0
        IsDefaultSubscription = $false
        EstimatedMonthlyCost = 0
    }
    
    # HR
    $subscriptions += [PSCustomObject]@{
        SubscriptionId = "00000000-0000-0000-0000-000000000006"
        SubscriptionName = "HR-Production"
        Region = $regions[3]
        BusinessUnit = $businessUnits[4]
        ActivityLogCount = 1800
        ResourceCount = 65
        DailyAverage = 257
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 308.4
        EstimatedDailyEventCount = 257
        EstimatedFunctionAppInstances = 0
        IsDefaultSubscription = $false
        EstimatedMonthlyCost = 0
    }
    
    # R&D - Medium size
    $subscriptions += [PSCustomObject]@{
        SubscriptionId = "00000000-0000-0000-0000-000000000007"
        SubscriptionName = "RnD-Development"
        Region = $regions[0]
        BusinessUnit = $businessUnits[5]
        ActivityLogCount = 5200
        ResourceCount = 230
        DailyAverage = 742
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 890.4
        EstimatedDailyEventCount = 742
        EstimatedFunctionAppInstances = 0
        IsDefaultSubscription = $false
        EstimatedMonthlyCost = 0
    }
    
    # Legal - Small footprint
    $subscriptions += [PSCustomObject]@{
        SubscriptionId = "00000000-0000-0000-0000-000000000008"
        SubscriptionName = "Legal-Production"
        Region = $regions[4]
        BusinessUnit = $businessUnits[6]
        ActivityLogCount = 950
        ResourceCount = 30
        DailyAverage = 135
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 162
        EstimatedDailyEventCount = 135
        EstimatedFunctionAppInstances = 0
        IsDefaultSubscription = $false
        EstimatedMonthlyCost = 0
    }
    
    # Executive - Smallest footprint
    $subscriptions += [PSCustomObject]@{
        SubscriptionId = "00000000-0000-0000-0000-000000000009"
        SubscriptionName = "Executive-Services"
        Region = $regions[4]
        BusinessUnit = $businessUnits[7]
        ActivityLogCount = 700
        ResourceCount = 25
        DailyAverage = 100
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 120
        EstimatedDailyEventCount = 100
        EstimatedFunctionAppInstances = 0
        IsDefaultSubscription = $false
        EstimatedMonthlyCost = 0
    }
    
    # Add details for some business units with multiple subscriptions
    $subscriptions += [PSCustomObject]@{
        SubscriptionId = "00000000-0000-0000-0000-000000000010"
        SubscriptionName = "Sales-Analytics"
        Region = $regions[1]
        BusinessUnit = $businessUnits[2]
        ActivityLogCount = 2200
        ResourceCount = 95
        DailyAverage = 314
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 376.8
        EstimatedDailyEventCount = 314
        EstimatedFunctionAppInstances = 0
        IsDefaultSubscription = $false
        EstimatedMonthlyCost = 0
    }
    
    # Return the synthetic subscription data
    return $subscriptions
}

# Generate business unit rollup report from subscription data
function Get-SyntheticBusinessUnitRollup {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionData
    )
    
    # Group by business unit
    $buGroups = $SubscriptionData | Group-Object -Property BusinessUnit
    
    $buRollup = @()
    
    foreach ($buGroup in $buGroups) {
        $buName = $buGroup.Name
        
        $subscriptions = $buGroup.Group
        $totalCost = ($subscriptions | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum
        $defaultSubCost = 0
        
        $defaultSub = $subscriptions | Where-Object { $_.IsDefaultSubscription }
        if ($defaultSub) {
            $defaultSubCost = $defaultSub.EstimatedMonthlyCost
        }
        
        $resourceCount = ($subscriptions | Measure-Object -Property ResourceCount -Sum).Sum
        $activityLogCount = ($subscriptions | Measure-Object -Property ActivityLogCount -Sum).Sum
        
        $buReport = [PSCustomObject]@{
            BusinessUnit = $buName
            SubscriptionCount = $subscriptions.Count
            ResourceCount = $resourceCount
            ActivityLogCount = $activityLogCount
            DefaultSubscriptionCost = $defaultSubCost
            OtherSubscriptionsCost = $totalCost - $defaultSubCost
            TotalMonthlyCost = $totalCost
            IncludesDefaultSubscription = ($defaultSub -ne $null)
            Subscriptions = $subscriptions.SubscriptionName -join ', '
        }
        
        $buRollup += $buReport
    }
    
    # Sort by total cost descending
    $buRollup = $buRollup | Sort-Object -Property TotalMonthlyCost -Descending
    
    return $buRollup
}

# Generate HTML report from synthetic data
function New-SyntheticHtmlReport {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionData,
        
        [Parameter(Mandatory = $true)]
        [array]$BusinessUnitData,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = "cs-azure-cost-estimate-demo.html"
    )
    
    # Basic styles and JavaScript libraries
    $chartJsUrl = "https://cdn.jsdelivr.net/npm/chart.js"
    
    $htmlHeader = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CrowdStrike Azure Cost Estimation Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        h1, h2, h3 {
            color: #0078d4;
        }
        .report-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
            border-bottom: 2px solid #0078d4;
            padding-bottom: 15px;
        }
        .timestamp {
            font-size: 14px;
            color: #666;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 30px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #f2f2f2;
            font-weight: bold;
        }
        tr:hover {
            background-color: #f5f5f5;
        }
        .summary-box {
            background-color: #f9f9f9;
            border-left: 4px solid #0078d4;
            padding: 15px;
            margin-bottom: 20px;
        }
        .summary-metric {
            display: inline-block;
            margin-right: 30px;
            margin-bottom: 10px;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            color: #0078d4;
        }
        .metric-label {
            font-size: 14px;
            color: #666;
        }
        .chart-container {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            margin-bottom: 30px;
        }
        .chart {
            width: 48%;
            height: 300px;
            margin-bottom: 20px;
            background-color: #f9f9f9;
            padding: 15px;
            border-radius: 4px;
        }
        @media (max-width: 768px) {
            .chart {
                width: 100%;
            }
        }
        .money {
            font-family: monospace;
            text-align: right;
        }
        .footer {
            margin-top: 40px;
            border-top: 1px solid #ddd;
            padding-top: 10px;
            font-size: 14px;
            color: #666;
            text-align: center;
        }
    </style>
    <script src="$chartJsUrl"></script>
</head>
<body>
    <div class="report-header">
        <h1>CrowdStrike Azure Cost Estimation Report</h1>
        <div class="timestamp">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
    </div>
"@

    # Generate summary metrics
    $totalSubscriptions = $SubscriptionData.Count
    $totalBusinessUnits = $BusinessUnitData.Count
    $totalCost = ($SubscriptionData | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum
    $totalResources = ($SubscriptionData | Measure-Object -Property ResourceCount -Sum).Sum
    
    $defaultSub = $SubscriptionData | Where-Object { $_.IsDefaultSubscription }
    $defaultSubCost = 0
    if ($defaultSub) {
        $defaultSubCost = $defaultSub.EstimatedMonthlyCost
    }
    $otherSubsCost = $totalCost - $defaultSubCost
    
    $summarySection = @"
    <div class="summary-box">
        <h2>Executive Summary</h2>
        <div>
            <div class="summary-metric">
                <div class="metric-value">$totalSubscriptions</div>
                <div class="metric-label">Subscriptions</div>
            </div>
            <div class="summary-metric">
                <div class="metric-value">$totalBusinessUnits</div>
                <div class="metric-label">Business Units</div>
            </div>
            <div class="summary-metric">
                <div class="metric-value">$${totalCost.ToString("N2")}</div>
                <div class="metric-label">Total Monthly Cost</div>
            </div>
            <div class="summary-metric">
                <div class="metric-value">$totalResources</div>
                <div class="metric-label">Azure Resources</div>
            </div>
        </div>
        <p>This report estimates the costs of deploying CrowdStrike Falcon Cloud Security integration in Azure based on analyzing $totalSubscriptions subscriptions across $totalBusinessUnits business units.</p>
    </div>
"@

    # Charts section
    $chartsSection = @"
    <h2>Cost Visualizations</h2>
    <div class="chart-container">
        <div class="chart">
            <canvas id="businessUnitCostChart"></canvas>
        </div>
        <div class="chart">
            <canvas id="costBreakdownChart"></canvas>
        </div>
    </div>
"@

    # Business Unit table
    $buTableRows = ""
    foreach ($bu in $BusinessUnitData) {
        $buTableRows += @"
        <tr>
            <td>$($bu.BusinessUnit)</td>
            <td>$($bu.SubscriptionCount)</td>
            <td>$($bu.ResourceCount)</td>
            <td class="money">$($bu.DefaultSubscriptionCost.ToString("N2"))</td>
            <td class="money">$($bu.OtherSubscriptionsCost.ToString("N2"))</td>
            <td class="money">$($bu.TotalMonthlyCost.ToString("N2"))</td>
        </tr>
"@
    }

    $buSection = @"
    <h2>Business Unit Cost Analysis</h2>
    <table>
        <thead>
            <tr>
                <th>Business Unit</th>
                <th>Subscriptions</th>
                <th>Resources</th>
                <th>Default Sub Cost ($)</th>
                <th>Other Subs Cost ($)</th>
                <th>Total Monthly Cost ($)</th>
            </tr>
        </thead>
        <tbody>
            $buTableRows
        </tbody>
    </table>
"@

    # Subscription table
    $subscriptionTableRows = ""
    foreach ($sub in $SubscriptionData | Sort-Object -Property EstimatedMonthlyCost -Descending) {
        $defaultTag = if ($sub.IsDefaultSubscription) { "(Default)" } else { "" }
        $subscriptionTableRows += @"
        <tr>
            <td>$($sub.SubscriptionName) $defaultTag</td>
            <td>$($sub.BusinessUnit)</td>
            <td>$($sub.ResourceCount)</td>
            <td>$($sub.ActivityLogCount)</td>
            <td>$($sub.EstimatedEventHubTUs)</td>
            <td class="money">$($sub.EstimatedMonthlyCost.ToString("N2"))</td>
        </tr>
"@
    }

    $subscriptionSection = @"
    <h2>Subscription Details</h2>
    <table>
        <thead>
            <tr>
                <th>Subscription</th>
                <th>Business Unit</th>
                <th>Resources</th>
                <th>Activity Logs</th>
                <th>Est. TUs</th>
                <th>Monthly Cost ($)</th>
            </tr>
        </thead>
        <tbody>
            $subscriptionTableRows
        </tbody>
    </table>
"@

    # JavaScript for charts
    $buLabels = $BusinessUnitData.BusinessUnit | ConvertTo-Json
    $buValues = $BusinessUnitData.TotalMonthlyCost | ConvertTo-Json
    
    $breakdownLabels = @("Default Subscription", "Other Subscriptions") | ConvertTo-Json
    $breakdownValues = @($defaultSubCost, $otherSubsCost) | ConvertTo-Json
    
    $chartColors = @("#3366CC", "#DC3912", "#FF9900", "#109618", "#990099", "#3B3EAC", "#0099C6", "#DD4477", "#66AA00", "#B82E2E") | ConvertTo-Json
    
    $chartJs = @"
    <script>
        // Business unit cost chart
        new Chart(document.getElementById('businessUnitCostChart'), {
            type: 'bar',
            data: {
                labels: $buLabels,
                datasets: [{
                    label: 'Monthly Cost ($)',
                    data: $buValues,
                    backgroundColor: $chartColors,
                    borderColor: $chartColors,
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        display: false
                    },
                    title: {
                        display: true,
                        text: 'Monthly Cost by Business Unit'
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Monthly Cost ($)'
                        }
                    }
                }
            }
        });
        
        // Cost breakdown chart
        new Chart(document.getElementById('costBreakdownChart'), {
            type: 'pie',
            data: {
                labels: $breakdownLabels,
                datasets: [{
                    data: $breakdownValues,
                    backgroundColor: $chartColors.slice(0, 2),
                    hoverOffset: 4
                }]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: {
                        position: 'bottom'
                    },
                    title: {
                        display: true,
                        text: 'Cost Distribution'
                    }
                }
            }
        });
    </script>
"@

    # Footer
    $footer = @"
    <div class="footer">
        <p>CrowdStrike Azure Cost Estimation Tool v2.0 | &copy; $(Get-Date -Format 'yyyy') CrowdStrike, Inc.</p>
    </div>
"@

    # Complete HTML document
    $htmlDocument = $htmlHeader + $summarySection + $chartsSection + $buSection + $subscriptionSection + $footer + $chartJs + "</body></html>"
    
    # Save to file
    $htmlDocument | Set-Content -Path $OutputPath
    
    return $OutputPath
}

# Main execution
$subscriptions = New-SyntheticSubscriptionData
$businessUnitRollup = Get-SyntheticBusinessUnitRollup -SubscriptionData $subscriptions
$htmlReportPath = New-SyntheticHtmlReport -SubscriptionData $subscriptions -BusinessUnitData $businessUnitRollup -OutputPath "azure/cs-azure-cost-estimate-demo.html"

Write-Host "Synthetic data generated and report created at: $htmlReportPath"
