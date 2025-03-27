#Requires -Modules Az.Accounts, Az.Monitor

<#
.SYNOPSIS
    Azure Activity Log collection module with time-window chunking.

.DESCRIPTION
    This PowerShell module extends the data collection capabilities
    for CrowdStrike cost estimation by bypassing the 1000-record 
    limitation on Azure Activity Logs using time-window chunking.

.PARAMETER SubscriptionId
    The ID of the subscription to retrieve Activity Logs for.
    
.PARAMETER StartTime
    The start of the time range to retrieve logs for.
    
.PARAMETER EndTime
    The end of the time range to retrieve logs for.
    
.PARAMETER InitialChunkSizeHours
    The initial size of each time chunk in hours. Default is 24 hours.
    Will auto-adjust if needed based on log density.
    
.PARAMETER MinChunkSizeHours
    The minimum size of the time window in hours when hitting record limits.
    Default is 1 hour.
    
.PARAMETER MaxChunkSizeHours
    The maximum size of the time window in hours, used for adaptive increases.
    Default is 48 hours.
    
.PARAMETER OutputDir
    Directory to write logs to. Optional.
    
.PARAMETER CurrentSubscriptionNumber
    Current subscription number for progress tracking. Optional.
    
.PARAMETER TotalSubscriptions
    Total number of subscriptions for progress tracking. Optional.
    
.PARAMETER Filter
    Optional. A string filter compatible with Get-AzActivityLog's -Filter parameter
    (e.g., "ResourceGroupName eq 'MyRG'").
    
.EXAMPLE
    $activityLogs = Get-AllActivityLogsWithChunking -SubscriptionId "00000000-0000-0000-0000-000000000000" -StartTime (Get-Date).AddDays(-7) -EndTime (Get-Date) 

.EXAMPLE
    $activityLogs = Get-AllActivityLogsWithChunking -SubscriptionId "00000000-0000-0000-0000-000000000000" -StartTime "2025-03-20T00:00:00Z" -EndTime "2025-03-27T00:00:00Z" -InitialChunkSizeHours 12 -MinChunkSizeHours 1 -Filter "ResourceProvider eq 'Microsoft.Compute'"
#>

# =============================================================================
# IMPORTANT: PowerShell String Interpolation Warning
# =============================================================================
# When using string interpolation with variables in PowerShell, you MUST:
#
# 1. Use ${varName} syntax when the variable appears next to non-variable
#    characters, especially colons (":") and in template strings
#
# 2. NEVER use $varName: syntax (without braces) which causes errors like:
#    "was not followed by a valid variable name character"
#
# 3. ALWAYS include commas between method arguments:
#    [Math]::Min(100, 200) ✓
#    [Math]::Min(100 200) ✗ - WRONG!
#
# This error has appeared multiple times in our code history.
# =============================================================================

function Get-AllActivityLogsWithChunking {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $true)]
        [DateTime]$StartTime,
        
        [Parameter(Mandatory = $true)]
        [DateTime]$EndTime,
        
        [Parameter(Mandatory = $false)]
        [int]$InitialChunkSizeHours = 24,
        
        [Parameter(Mandatory = $false)]
        [int]$MinChunkSizeHours = 1,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxChunkSizeHours = 48,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputDir = $null,
        
        [Parameter(Mandatory = $false)]
        [int]$CurrentSubscriptionNumber = 0,
        
        [Parameter(Mandatory = $false)]
        [int]$TotalSubscriptions = 0,
        
        [Parameter(Mandatory = $false)]
        [string]$Filter = $null
    )
    
    # Input validation
    if ($StartTime -ge $EndTime) {
        Write-Error "StartTime must be earlier than EndTime."
        return @()
    }
    if ($InitialChunkSizeHours -le 0) {
        Write-Warning "InitialChunkSizeHours must be positive. Using default value 24."
        $InitialChunkSizeHours = 24
    }
    if ($MinChunkSizeHours -le 0) {
        Write-Warning "MinChunkSizeHours must be positive. Using default value 1."
        $MinChunkSizeHours = 1
    }
    if ($MaxChunkSizeHours -le $MinChunkSizeHours) {
        Write-Warning "MaxChunkSizeHours must be greater than MinChunkSizeHours. Adjusting MaxChunkSizeHours."
        $MaxChunkSizeHours = [Math]::Max($MinChunkSizeHours + 1, 24)
    }
    if ($InitialChunkSizeHours -lt $MinChunkSizeHours) {
        Write-Warning "InitialChunkSizeHours cannot be less than MinChunkSizeHours. Setting InitialChunkSizeHours to MinChunkSizeHours."
        $InitialChunkSizeHours = $MinChunkSizeHours
    }
    if ($InitialChunkSizeHours -gt $MaxChunkSizeHours) {
        Write-Warning "InitialChunkSizeHours cannot be greater than MaxChunkSizeHours. Setting InitialChunkSizeHours to MaxChunkSizeHours."
        $InitialChunkSizeHours = $MaxChunkSizeHours
    }
    
    # Set up subscription context
    try {
        $currentContext = Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to set Azure context for Subscription ID: $SubscriptionId. Error: $($_.Exception.Message)"
        return @()
    }
    
    # Build a prefix for status messages if we have subscription count info
    $subCountPrefix = ""
    if ($CurrentSubscriptionNumber -gt 0 -and $TotalSubscriptions -gt 0) {
        $subCountPrefix = "[$CurrentSubscriptionNumber/$TotalSubscriptions] "
    }
    
    # Calculate total time span and number of chunks based on initial chunk size
    $totalHours = [Math]::Ceiling(($EndTime - $StartTime).TotalHours)
    $initialChunkCount = [Math]::Ceiling($totalHours / $InitialChunkSizeHours)
    
    Write-Host "${subCountPrefix}Breaking request into $initialChunkCount time chunks (initial estimate)..." -ForegroundColor Cyan
    if ($OutputDir) {
        Write-LogEntry -Message "${subCountPrefix}Breaking request into approximately $initialChunkCount time chunks to bypass 1000-record limit" -OutputDir $OutputDir
    }
    
    # Set up progress tracking
    $progressActivity = "Retrieving Activity Logs with Time Chunking"
    $progressParams = @{
        Activity = $progressActivity
        Status = "Preparing to process chunks"
        PercentComplete = 0
    }
    if ($CurrentSubscriptionNumber -gt 0 -and $TotalSubscriptions -gt 0) {
        $progressParams.Activity = "Retrieving Activity Logs (Subscription $CurrentSubscriptionNumber of $TotalSubscriptions) with Time Chunking"
    }
    Write-Progress @progressParams
    
    # Begin chunked retrieval
    $allLogs = [System.Collections.ArrayList]::new()
    $currentStart = $StartTime
    $chunkSizeHours = $InitialChunkSizeHours
    $chunkNumber = 0
    $totalChunksProcessed = 0
    $hitLimitCount = 0
    $noLogsCount = 0
    
    # Process time windows until we've covered the entire range
    while ($currentStart -lt $EndTime) {
        $chunkNumber++
        
        # Calculate end time for this chunk
        $currentEnd = $currentStart.AddHours($chunkSizeHours)
        if ($currentEnd -gt $EndTime) {
            $currentEnd = $EndTime
        }
        
        # Update progress bar
        $completedHours = ($currentStart - $StartTime).TotalHours
        $progressPercent = [Math]::Min(100, [Math]::Ceiling(($completedHours / $totalHours) * 100))
        
        $statusMessage = "${subCountPrefix}Processing chunk ${chunkNumber}: $($currentStart.ToString('yyyy-MM-dd HH:mm')) to $($currentEnd.ToString('yyyy-MM-dd HH:mm')) (${chunkSizeHours} hour(s))"
        Write-Progress @progressParams -Status $statusMessage -PercentComplete $progressPercent -CurrentOperation "Total logs so far: $($allLogs.Count)"
        
        # Make the chunked request
        Write-Host "${subCountPrefix}Processing time chunk ${chunkNumber}: $($currentStart.ToString('yyyy-MM-dd HH:mm')) to $($currentEnd.ToString('yyyy-MM-dd HH:mm')) (${chunkSizeHours} hour(s))" -ForegroundColor Cyan
        if ($OutputDir) {
            Write-LogEntry -Message "${subCountPrefix}Processing time chunk ${chunkNumber}: $($currentStart.ToString('yyyy-MM-dd HH:mm')) to $($currentEnd.ToString('yyyy-MM-dd HH:mm')) (${chunkSizeHours} hour(s))" -OutputDir $OutputDir
        }
        
        try {
            # Construct parameters for Get-AzActivityLog
            $azLogParams = @{
                StartTime = $currentStart
                EndTime = $currentEnd
                ErrorAction = 'Stop'
            }
            
            # Add filter if provided
            if (-not [string]::IsNullOrEmpty($Filter)) {
                $azLogParams.Filter = $Filter
            }
            
            # IMPORTANT: DO NOT ADD DetailedOutput PARAMETER HERE!
            # The DetailedOutput parameter has been deprecated and causes warnings.
            $logs = Get-AzActivityLog @azLogParams
            $totalChunksProcessed++
            
            # Determine log count - handle case when single log is returned (not an array)
            $logCount = 0
            if ($null -ne $logs) {
                if ($logs -is [array]) {
                    $logCount = $logs.Count
                }
                else {
                    $logCount = 1
                }
            }
            
            if ($logCount -gt 0) {
                [void]$allLogs.AddRange(@($logs)) # Force array conversion with @()
                Write-Host "${subCountPrefix}Retrieved $logCount logs from this chunk. Total logs so far: $($allLogs.Count)" -ForegroundColor Green
                if ($OutputDir) {
                    Write-LogEntry -Message "${subCountPrefix}Retrieved $logCount logs from chunk ${chunkNumber}. Total so far: $($allLogs.Count)" -OutputDir $OutputDir
                }
                
                # Adjust chunk size if we hit the 1000 record limit
                if ($logCount -eq 1000) {
                    $hitLimitCount++
                    Write-Host "${subCountPrefix}⚠️ Reached 1000-record limit in this chunk. Reducing chunk size." -ForegroundColor Yellow
                    if ($OutputDir) {
                        Write-LogEntry -Message "${subCountPrefix}WARNING: Hit 1000-record limit in chunk ${chunkNumber}. Reducing time window size." -Level 'WARNING' -OutputDir $OutputDir
                    }
                    
                    # Reduce chunk size for next iteration, but never below minimum
                    $newChunkSize = [Math]::Max($MinChunkSizeHours, [Math]::Floor($chunkSizeHours / 2))
                    
                    # If we're already at minimum chunk size and still hitting limits, log a warning
                    if ($chunkSizeHours -eq $MinChunkSizeHours -and $newChunkSize -eq $MinChunkSizeHours) {
                        Write-Host "${subCountPrefix}⚠️ Already at minimum chunk size ($MinChunkSizeHours hour(s)). Some logs may still be truncated." -ForegroundColor Yellow
                        if ($OutputDir) {
                            Write-LogEntry -Message "${subCountPrefix}WARNING: Already at minimum chunk size ($MinChunkSizeHours hour(s)). Log data may be incomplete due to high volume." -Level 'WARNING' -OutputDir $OutputDir
                        }
                        
                        # Must advance time to prevent infinite loop
                        $currentStart = $currentStart.AddHours($MinChunkSizeHours)
                    }
                    else {
                        # Set the new chunk size but don't advance time - retry same interval with smaller chunk
                        $chunkSizeHours = $newChunkSize
                    }
                }
                else {
                    # Not hitting limit - advance to next time window
                    $currentStart = $currentEnd
                    
                    # Potentially increase chunk size if well below limit and we have reduced before
                    if ($logCount -lt 500 -and $hitLimitCount -gt 0 -and $chunkSizeHours -lt $InitialChunkSizeHours) {
                        $newChunkSize = [Math]::Min($InitialChunkSizeHours, $chunkSizeHours * 1.5) # Increase by 50%
                        $newChunkSize = [Math]::Ceiling($newChunkSize) # Round up to ensure progress
                        
                        if ($newChunkSize -gt $chunkSizeHours) {
                            Write-Host "${subCountPrefix}Chunk well below limit ($logCount logs). Increasing chunk size from $chunkSizeHours to $newChunkSize hours." -ForegroundColor Cyan
                            $chunkSizeHours = [int]$newChunkSize
                        }
                    }
                }
            }
            else {
                $noLogsCount++
                Write-Host "${subCountPrefix}No logs found in this time chunk." -ForegroundColor DarkGray
                
                # Advance time window since no logs found
                $currentStart = $currentEnd
                
                # If we've had several empty chunks, consider increasing chunk size
                if ($noLogsCount -ge 3 -and $chunkSizeHours -lt $MaxChunkSizeHours) {
                    $newChunkSize = [Math]::Min($MaxChunkSizeHours, $chunkSizeHours * 2)
                    Write-Host "${subCountPrefix}Multiple empty chunks. Increasing chunk size from $chunkSizeHours to $newChunkSize hours." -ForegroundColor Cyan
                    $chunkSizeHours = $newChunkSize
                    $noLogsCount = 0
                }
            }
        }
        catch {
            Write-Warning "${subCountPrefix}Error retrieving activity logs for chunk ${chunkNumber}: $($_.Exception.Message)"
            if ($OutputDir) {
                Write-LogEntry -Message "${subCountPrefix}ERROR: Failed to retrieve logs for chunk ${chunkNumber}: $($_.Exception.Message)" -Level 'ERROR' -OutputDir $OutputDir
            }
            
            # Decide whether to skip this interval or retry
            if ($_.Exception.Message -match "throttl|rate limit|limit exceeded") {
                # For throttling, reduce chunk size and retry
                Write-Host "${subCountPrefix}Throttling detected. Reducing chunk size and retrying after delay." -ForegroundColor Yellow
                $chunkSizeHours = [Math]::Max($MinChunkSizeHours, [Math]::Floor($chunkSizeHours / 2))
                Start-Sleep -Seconds 5 # Add delay when throttled
            }
            else {
                # For other errors, skip this interval and continue
                Write-Host "${subCountPrefix}Skipping this interval due to error." -ForegroundColor Yellow
                $currentStart = $currentEnd
            }
        }
    }
    
    # Complete the progress bar
    Write-Progress @progressParams -Completed
    
    # Provide summary
    Write-Host "${subCountPrefix}Completed Activity Log retrieval with time chunking:" -ForegroundColor Green
    Write-Host "${subCountPrefix}- Total chunks processed: $totalChunksProcessed" -ForegroundColor Green
    Write-Host "${subCountPrefix}- Total logs retrieved: $($allLogs.Count)" -ForegroundColor Green
    Write-Host "${subCountPrefix}- Final chunk size used: $chunkSizeHours hour(s)" -ForegroundColor Green
    
    if ($hitLimitCount -gt 0) {
        Write-Host "${subCountPrefix}- Chunks that hit 1000-record limit: $hitLimitCount" -ForegroundColor Yellow
    }
    
    if ($OutputDir) {
        Write-LogEntry -Message "${subCountPrefix}Completed Activity Log retrieval with time chunking: $totalChunksProcessed chunks processed, $($allLogs.Count) total logs retrieved." -OutputDir $OutputDir
    }
    
    return $allLogs
}

# Function is exposed through dot-sourcing the script
# No Export-ModuleMember needed since this isn't a formal PowerShell module (.psm1)
