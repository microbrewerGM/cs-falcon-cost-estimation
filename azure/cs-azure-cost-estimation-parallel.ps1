#region Parallel Execution Implementation

# Function to initialize runspace pool for parallel execution
function Initialize-RunspacePool {
    param (
        [Parameter(Mandatory = $false)]
        [int]$MaxThreads = $script:MaxDegreeOfParallelism
    )
    
    Write-Log "Initializing runspace pool with max threads: $MaxThreads" -Level 'INFO' -Category 'Parallel'
    
    # Create session state and import required modules
    $sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    
    # Add required modules to session state
    $requiredModules = @("Az.Accounts", "Az.Resources", "Az.Monitor")
    foreach ($module in $requiredModules) {
        $sessionState.ImportPSModule($module)
    }
    
    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads, $sessionState, $Host)
    $runspacePool.Open()
    
    return $runspacePool
}

# Function to process subscriptions in parallel
function Get-SubscriptionDataInParallel {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Subscriptions,
        
        [Parameter(Mandatory = $true)]
        [string]$DefaultSubscriptionId,
        
        [Parameter(Mandatory = $true)]
        [object]$GlobalPricing,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxJobs = $script:MaxParallelJobs,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = $script:ParallelTimeout
    )
    
    # If not using parallel execution, process sequentially
    if (-not $ParallelExecution) {
        Write-Log "Parallel execution disabled, processing subscriptions sequentially" -Level 'INFO' -Category 'Parallel'
        
        $results = @()
        $totalSubs = $Subscriptions.Count
        $currentSub = 0
        
        foreach ($subscription in $Subscriptions) {
            $currentSub++
            $percentComplete = [math]::Floor(($currentSub / $totalSubs) * 100)
            
            Show-EnhancedProgress -Activity "Processing subscriptions sequentially" -Status "$currentSub of $totalSubs - $($subscription.Name)" -PercentComplete $percentComplete -Category 'Subscriptions'
            
            $isDefaultSubscription = ($subscription.Id -eq $DefaultSubscriptionId)
            $subData = Get-SubscriptionData -Subscription $subscription -IsDefaultSubscription $isDefaultSubscription -Pricing $GlobalPricing
            
            $results += $subData
        }
        
        return $results
    }
    
    # Calculate optimal number of jobs based on subscription count
    $optimalJobs = [Math]::Max(1, [Math]::Min($MaxJobs, [Math]::Ceiling($Subscriptions.Count * $script:ThrottleLimitFactorForSubs)))
    Write-Log "Processing $($Subscriptions.Count) subscriptions with $optimalJobs parallel jobs" -Level 'INFO' -Category 'Parallel'
    
    # Initialize runspace pool
    $runspacePool = Initialize-RunspacePool -MaxThreads $optimalJobs
    
    # Create script block for parallel execution
    $scriptBlock = {
        param($Subscription, $IsDefaultSubscription, $GlobalPricing, $LogFilePath, $DaysToAnalyze, $SampleLogSize, $OutputDirectory)
        
        try {
            # Import helper functions
            # Note: In a real implementation, you would either:
            # 1. Define all helper functions inside this scriptblock, or
            # 2. Import them from a module
            # For this demo, we'll assume required functions are available
            
            # Set context to the subscription
            Set-AzContext -Subscription $Subscription.Id -ErrorAction Stop | Out-Null
            
            # Timestamp for log
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            
            # Write to subscription-specific log file
            $subLogMessage = "[$timestamp] [INFO] [ParallelJob] Started processing subscription $($Subscription.Name) ($($Subscription.Id))"
            Add-Content -Path $LogFilePath -Value $subLogMessage -ErrorAction SilentlyContinue
            
            # Initialize subscription data
            $subscriptionData = [PSCustomObject]@{
                SubscriptionId = $Subscription.Id
                SubscriptionName = $Subscription.Name
                Region = $null
                BusinessUnit = $null
                ActivityLogCount = 0
                ResourceCount = 0
                DailyAverage = 0
                EstimatedEventHubTUs = 0
                EstimatedStorageGB = 0
                EstimatedDailyEventHubIngress = 0
                EstimatedDailyEventCount = 0
                EstimatedFunctionAppInstances = 0
                CostDetails = @{}
                EstimatedMonthlyCost = 0
                IsDefaultSubscription = $IsDefaultSubscription
                LogSizeDetails = @{
                    SampledLogCount = 0
                    AverageLogSizeKB = 0
                    MaxLogSizeKB = 0
                    MinLogSizeKB = 0
                    LogSizeDistribution = @{}
                }
                ProcessingDetails = @{
                    StartTime = Get-Date
                    EndTime = $null
                    Duration = $null
                    Success = $false
                    ErrorMessage = $null
                }
            }
            
            # Get subscription region
            try {
                $resourceGroups = Get-AzResourceGroup -ErrorAction Stop
                $locations = $resourceGroups | Select-Object -ExpandProperty Location | Sort-Object -Unique
                $subscriptionData.Region = $locations -join ','
                
                if ([string]::IsNullOrWhiteSpace($subscriptionData.Region)) {
                    $subscriptionData.Region = "eastus" # Default
                }
            }
            catch {
                $subscriptionData.Region = "eastus" # Default if can't determine
                $subscriptionData.ProcessingDetails.ErrorMessage = "Failed to get regions: $($_.Exception.Message)"
            }
            
            # Get Business Unit from tags
            try {
                $sub = Get-AzSubscription -SubscriptionId $Subscription.Id
                $tags = Get-AzTag -ResourceId "/subscriptions/$($Subscription.Id)" -ErrorAction SilentlyContinue
                
                if ($tags -and $tags.Properties.TagsProperty.ContainsKey("BusinessUnit")) {
                    $subscriptionData.BusinessUnit = $tags.Properties.TagsProperty["BusinessUnit"]
                }
                else {
                    # Try to derive from management group if available
                    $mgPath = Get-AzManagementGroupPath -SubscriptionId $Subscription.Id -ErrorAction SilentlyContinue
                    if ($mgPath) {
                        # Look for a segment that might represent a business unit
                        $buSegment = $mgPath | Where-Object { $_ -match "BU-|Dept-|Division-" }
                        if ($buSegment) {
                            $subscriptionData.BusinessUnit = ($buSegment -split "-")[1]
                        }
                    }
                    
                    # If still not set, use default
                    if ([string]::IsNullOrWhiteSpace($subscriptionData.BusinessUnit)) {
                        $subscriptionData.BusinessUnit = "Unassigned"
                    }
                }
            }
            catch {
                $subscriptionData.BusinessUnit = "Unassigned"
                $subscriptionData.ProcessingDetails.ErrorMessage += "; Failed to get business unit: $($_.Exception.Message)"
            }
            
            # [Placeholder - actual implementation would get activity logs, calculate metrics, etc.]
            # This is just a demonstration of the parallel structure
            
            # Simulate getting resource counts
            try {
                $resources = Get-AzResource
                $subscriptionData.ResourceCount = $resources.Count
            }
            catch {
                $subscriptionData.ResourceCount = 0
                $subscriptionData.ProcessingDetails.ErrorMessage += "; Failed to get resources: $($_.Exception.Message)"
            }
            
            # Simulate getting log counts and metrics
            $subscriptionData.ActivityLogCount = 1000 # Default placeholder
            $subscriptionData.DailyAverage = [math]::Round(1000 / $DaysToAnalyze, 2)
            
            # Save subscription data to individual JSON file
            $subscriptionDataPath = Join-Path $OutputDirectory "subscription-data/$($Subscription.Id).json"
            $subscriptionData | ConvertTo-Json -Depth 10 | Set-Content $subscriptionDataPath
            
            # Complete processing
            $subscriptionData.ProcessingDetails.EndTime = Get-Date
            $subscriptionData.ProcessingDetails.Duration = $subscriptionData.ProcessingDetails.EndTime - $subscriptionData.ProcessingDetails.StartTime
            $subscriptionData.ProcessingDetails.Success = $true
            
            return $subscriptionData
        }
        catch {
            # Log error and return partial data
            $errorSubscriptionData = [PSCustomObject]@{
                SubscriptionId = $Subscription.Id
                SubscriptionName = $Subscription.Name
                ProcessingDetails = @{
                    StartTime = Get-Date
                    EndTime = Get-Date
                    Duration = [TimeSpan]::Zero
                    Success = $false
                    ErrorMessage = $_.Exception.Message
                }
            }
            
            # Write error to main log
            $errorMsg = "[$timestamp] [ERROR] [ParallelJob] Failed processing subscription $($Subscription.Name): $($_.Exception.Message)"
            Add-Content -Path $LogFilePath -Value $errorMsg -ErrorAction SilentlyContinue
            
            return $errorSubscriptionData
        }
    }
    
    # Create and start jobs
    $jobs = @()
    foreach ($subscription in $Subscriptions) {
        $isDefaultSubscription = ($subscription.Id -eq $DefaultSubscriptionId)
        
        $powershell = [powershell]::Create().AddScript($scriptBlock)
        $powershell.RunspacePool = $runspacePool
        
        # Add parameters
        [void]$powershell.AddParameter("Subscription", $subscription)
        [void]$powershell.AddParameter("IsDefaultSubscription", $isDefaultSubscription)
        [void]$powershell.AddParameter("GlobalPricing", $GlobalPricing)
        [void]$powershell.AddParameter("LogFilePath", $LogFilePath)
        [void]$powershell.AddParameter("DaysToAnalyze", $DaysToAnalyze)
        [void]$powershell.AddParameter("SampleLogSize", $SampleLogSize)
        [void]$powershell.AddParameter("OutputDirectory", $OutputDirectory)
        
        # Start the job
        $handle = $powershell.BeginInvoke()
        
        $jobInfo = [PSCustomObject]@{
            Runspace = $powershell
            Handle = $handle
            Subscription = $subscription
            StartTime = Get-Date
        }
        
        $jobs += $jobInfo
    }
    
    # Monitor job progress
    $results = @()
    $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
    $completedJobs = 0
    $totalJobs = $jobs.Count
    
    Write-Log "Started $totalJobs parallel jobs, monitoring progress..." -Level 'INFO' -Category 'Parallel'
    
    do {
        # Check for completed jobs
        for ($i = 0; $i -lt $jobs.Count; $i++) {
            $job = $jobs[$i]
            if ($job -eq $null) { continue }
            
            if ($job.Handle.IsCompleted) {
                # Get the result
                try {
                    $jobResult = $job.Runspace.EndInvoke($job.Handle)
                    $results += $jobResult
                    
                    $completedJobs++
                    $percentComplete = [math]::Floor(($completedJobs / $totalJobs) * 100)
                    
                    $elapsedTime = $elapsed.Elapsed
                    $estimatedTotalTime = [TimeSpan]::FromTicks([math]::Round($elapsedTime.Ticks / ($completedJobs / $totalJobs)))
                    $remainingTime = $estimatedTotalTime - $elapsedTime
                    
                    Show-EnhancedProgress -Activity "Processing subscriptions in parallel" -Status "$completedJobs of $totalJobs completed" -PercentComplete $percentComplete -Category 'Parallel'
                    
                    Write-Log "Completed processing subscription $($job.Subscription.Name) ($completedJobs of $totalJobs)" -Level 'INFO' -Category 'Parallel'
                }
                catch {
                    Write-Log "Error getting results for subscription $($job.Subscription.Name): $($_.Exception.Message)" -Level 'ERROR' -Category 'Parallel'
                }
                finally {
                    # Clean up regardless of success/failure
                    $job.Runspace.Dispose()
                    $jobs[$i] = $null
                }
            }
            elseif ($elapsed.Elapsed.TotalSeconds -gt $TimeoutSeconds) {
                # Job timeout
                try {
                    Write-Log "Timeout for subscription $($job.Subscription.Name) after $($elapsed.Elapsed.TotalSeconds) seconds" -Level 'WARNING' -Category 'Parallel'
                    $job.Runspace.Stop()
                    $job.Runspace.Dispose()
                }
                catch {
                    Write-Log "Error stopping job for subscription $($job.Subscription.Name): $($_.Exception.Message)" -Level 'ERROR' -Category 'Parallel'
                }
                finally {
                    $jobs[$i] = $null
                    $completedJobs++
                }
            }
        }
        
        # Remove completed jobs from collection
        $jobs = $jobs | Where-Object { $_ -ne $null }
        
        # Pause to reduce CPU usage
        if ($jobs.Count -gt 0) {
            Start-Sleep -Milliseconds 500
        }
    } while ($jobs.Count -gt 0)
    
    $elapsed.Stop()
    
    # Close runspace pool
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    Write-Log "Completed all parallel subscription processing in $($elapsed.Elapsed.ToString())" -Level 'SUCCESS' -Category 'Parallel'
    
    # Filter out any failed results or process retries if needed
    $successfulResults = $results | Where-Object { $_.ProcessingDetails.Success -eq $true }
    $failedResults = $results | Where-Object { $_.ProcessingDetails.Success -eq $false }
    
    Write-Log "Successfully processed $($successfulResults.Count) subscriptions, $($failedResults.Count) failed" -Level 'INFO' -Category 'Parallel'
    
    if ($failedResults.Count -gt 0) {
        Write-Log "Failed subscriptions: $($failedResults.SubscriptionName -join ', ')" -Level 'WARNING' -Category 'Parallel'
    }
    
    return $results
}

#endregion

#region Business Unit Rollup Reporting

# Function to generate business unit rollup report
function Get-BusinessUnitRollup {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionData
    )
    
    Write-Log "Generating business unit cost rollup report..." -Level 'INFO' -Category 'BusinessUnits'
    
    # Group by business unit
    $buGroups = $SubscriptionData | Group-Object -Property BusinessUnit
    
    $buRollup = @()
    
    foreach ($buGroup in $buGroups) {
        $buName = $buGroup.Name
        if ([string]::IsNullOrWhiteSpace($buName)) {
            $buName = $script:DefaultBusinessUnit
        }
        
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

#endregion

#region HTML Report Generation

# Function to generate an HTML report with visualizations
function New-HtmlCostReport {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SubscriptionData,
        
        [Parameter(Mandatory = $true)]
        [array]$BusinessUnitData,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputPath = $HtmlReportPath,
        
        [Parameter(Mandatory = $false)]
        [bool]$IncludeCharts = $script:IncludeCharts
    )
    
    Write-Log "Generating HTML report with visualizations..." -Level 'INFO' -Category 'Reporting'
    
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

    # Charts section (if enabled)
    $chartsSection = ""
    if ($IncludeCharts) {
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
    }

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
        $defaultTag = $sub.IsDefaultSubscription ? "(Default)" : ""
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
    $chartJs = ""
    if ($IncludeCharts) {
        # Prepare data for business unit chart
        $buLabels = $BusinessUnitData.BusinessUnit | ConvertTo-Json
        $buValues = $BusinessUnitData.TotalMonthlyCost | ConvertTo-Json
        
        # Prepare data for cost breakdown chart
        $breakdownLabels = @("Default Subscription", "Other Subscriptions") | ConvertTo-Json
        $breakdownValues = @($defaultSubCost, $otherSubsCost) | ConvertTo-Json
        
        # Colors for charts
        $chartColors = $script:ChartPalette | ConvertTo-Json
        
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
    }

    # Footer section
    $footer = @"
    <div class="footer">
        <p>CrowdStrike Azure Cost Estimation Tool v2.0 | &copy; $(Get-Date -Format 'yyyy') CrowdStrike, Inc.</p>
    </div>
"@

    # Complete HTML document
    $htmlDocument = $htmlHeader + $summarySection + $chartsSection + $buSection + $subscriptionSection + $footer + $chartJs + "</body></html>"
    
    # Save to file
    $htmlDocument | Set-Content -Path $OutputPath
    
    Write-Log "HTML report generated and saved to $OutputPath" -Level 'SUCCESS' -Category 'Reporting'
    
    return $OutputPath
}

#endregion
