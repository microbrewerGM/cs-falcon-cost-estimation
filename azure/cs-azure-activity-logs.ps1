#Requires -Modules Az.Accounts, Az.Monitor

<#
.SYNOPSIS
    Azure Activity Log collection module with time-window chunking.

.DESCRIPTION
    This PowerShell module extends the data collection capabilities
    for CrowdStrike cost estimation by bypassing the 1000-record 
    limitation on Azure Activity Logs using time-window chunking.
#>

function Get-AllActivityLogsWithChunking {
    <#
    .SYNOPSIS
        Retrieves all Activity Logs for a subscription by breaking requests into time chunks.
    
    .DESCRIPTION
        Bypasses the 1000-record limitation of the Get-AzActivityLog cmdlet by
        splitting the requested time period into smaller chunks and aggregating the results.
        The chunk size will automatically adjust if any chunk returns the maximum 1000 records.
        
    .PARAMETER SubscriptionId
        The ID of the subscription to retrieve Activity Logs for.
        
    .PARAMETER StartTime
        The start of the time range to retrieve logs for.
        
    .PARAMETER EndTime
        The end of the time range to retrieve logs for.
        
    .PARAMETER InitialChunkSizeHours
        The initial size of each time chunk in hours. Will auto-adjust if needed.
        
    .PARAMETER OutputDir
        Directory to write logs to.
        
    .PARAMETER CurrentSubscriptionNumber
        Current subscription number for progress tracking.
        
    .PARAMETER TotalSubscriptions
        Total number of subscriptions for progress tracking.
        
    .OUTPUTS
        [PSObject[]] Array of Activity Log objects.
    #>
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
        [string]$OutputDir = $null,
        
        [Parameter(Mandatory = $false)]
        [int]$CurrentSubscriptionNumber = 0,
        
        [Parameter(Mandatory = $false)]
        [int]$TotalSubscriptions = 0
    )
    
    # Set up subscription context
    $currentContext = Set-AzContext -Subscription $SubscriptionId -ErrorAction Stop
    
    # Build a prefix for status messages if we have subscription count info
    $subCountPrefix = ""
    if ($CurrentSubscriptionNumber -gt 0 -and $TotalSubscriptions -gt 0) {
        $subCountPrefix = "[$CurrentSubscriptionNumber/$TotalSubscriptions] "
    }
    
        # Calculate total number of chunks based on initial chunk size
        $totalHours = [Math]::Ceiling(($EndTime - $StartTime).TotalHours)
        $initialChunkCount = [Math]::Ceiling($totalHours / $InitialChunkSizeHours)
    
    Write-Host "${subCountPrefix}Breaking request into $initialChunkCount time chunks (initial estimate)..." -ForegroundColor Cyan
    if ($OutputDir) {
        Write-LogEntry -Message "${subCountPrefix}Breaking request into approximately $initialChunkCount time chunks to bypass 1000-record limit" -OutputDir $OutputDir
    }
    
    # Set up progress tracking
    $progressParams = @{
        Activity = "Retrieving Activity Logs with Time Chunking"
        Status = "Preparing to process chunks"
        PercentComplete = 0
    }
    if ($CurrentSubscriptionNumber -gt 0 -and $TotalSubscriptions -gt 0) {
        $progressParams.Activity = "Retrieving Activity Logs (Subscription $CurrentSubscriptionNumber of $TotalSubscriptions) with Time Chunking"
    }
    Write-Progress @progressParams
    
    # Begin chunked retrieval
    $allLogs = @()
    $currentStart = $StartTime
    $chunkSizeHours = $InitialChunkSizeHours
    $chunkNumber = 0
    $totalChunksProcessed = 0
    $hitLimitCount = 0
    $noLogsCount = 0
    
    # Detect the minimum viable chunk size that works
    $minWorkingChunkSize = $chunkSizeHours
    
    # Process time windows until we've covered the entire range
    while ($currentStart -lt $EndTime) {
        $chunkNumber++
        
        # Calculate end time for this chunk
        $currentEnd = $currentStart.AddHours($chunkSizeHours)
        if ($currentEnd -gt $EndTime) {
            $currentEnd = $EndTime
        }
        
        # Update progress bar - ensure variables use ${} for clarity in string interpolation
        # Use commas to separate Math method arguments properly to avoid parsing errors
        $progressPercent = [Math]::Min(100, [Math]::Ceiling((($currentStart - $StartTime).TotalHours / $totalHours) * 100))
        Write-Progress @progressParams -Status "${subCountPrefix}Processing chunk ${chunkNumber}: ${currentStart} to ${currentEnd}" -PercentComplete $progressPercent
        
        # Make the chunked request - use ${} for variable names in strings for clarity
        Write-Host "${subCountPrefix}Processing time chunk ${chunkNumber}: $($currentStart.ToString('yyyy-MM-dd HH:mm')) to $($currentEnd.ToString('yyyy-MM-dd HH:mm')) (${chunkSizeHours} hour(s))" -ForegroundColor Cyan
        if ($OutputDir) {
            Write-LogEntry -Message "${subCountPrefix}Processing time chunk ${chunkNumber}: $($currentStart.ToString('yyyy-MM-dd HH:mm')) to $($currentEnd.ToString('yyyy-MM-dd HH:mm')) (${chunkSizeHours} hour(s))" -OutputDir $OutputDir
        }
        
        try {
            # IMPORTANT: DO NOT ADD DetailedOutput PARAMETER HERE!
            # The DetailedOutput parameter has been deprecated and causes warnings.
            $logs = Get-AzActivityLog -StartTime $currentStart -EndTime $currentEnd -MaxRecord 1000
            $totalChunksProcessed++
            
            if ($logs -and $logs.Count -gt 0) {
                $allLogs += $logs
                Write-Host "${subCountPrefix}Retrieved $($logs.Count) logs from this chunk. Total logs so far: $($allLogs.Count)" -ForegroundColor Green
                if ($OutputDir) {
                    Write-LogEntry -Message "${subCountPrefix}Retrieved $($logs.Count) logs from chunk ${chunkNumber}. Total so far: $($allLogs.Count)" -OutputDir $OutputDir
                }
                
                # Adjust chunk size if we hit the 1000 record limit
                if ($logs.Count -eq 1000) {
                    $hitLimitCount++
                    Write-Host "${subCountPrefix}⚠️ Reached 1000-record limit in this chunk. Reducing chunk size." -ForegroundColor Yellow
                    if ($OutputDir) {
                        Write-LogEntry -Message "${subCountPrefix}WARNING: Hit 1000-record limit in chunk ${chunkNumber}. Reducing time window size." -Level 'WARNING' -OutputDir $OutputDir
                    }
                    
                    # Reduce chunk size for next iteration, but never below 1 hour
                    $newChunkSize = [Math]::Max(1, [Math]::Floor($chunkSizeHours / 2))
                    
                    # If we're already at 1 hour and still hitting limits, log a warning
                    if ($chunkSizeHours == 1 && $newChunkSize == 1) {
                        Write-Host "${subCountPrefix}⚠️ Already at minimum chunk size (1 hour). Some logs may still be truncated." -ForegroundColor Yellow
                        if ($OutputDir) {
                            Write-LogEntry -Message "${subCountPrefix}WARNING: Already at minimum chunk size (1 hour). Log data may be incomplete due to high volume." -Level 'WARNING' -OutputDir $OutputDir
                        }
                    }
                    
                    $chunkSizeHours = $newChunkSize
                } else {
                    # Track the most efficient chunk size that doesn't hit limits
                    if ($chunkSizeHours > $minWorkingChunkSize) {
                        $minWorkingChunkSize = $chunkSizeHours
                    }
                    
                    # Potentially increase chunk size if we're well below limit, but only if we haven't hit limits recently
                    if ($logs.Count < 500 && $hitLimitCount == 0 && $chunkSizeHours < $InitialChunkSizeHours) {
                        $newChunkSize = [Math]::Min($InitialChunkSizeHours, $chunkSizeHours * 2)
                        if ($newChunkSize > $chunkSizeHours) {
                            Write-Host "${subCountPrefix}Chunk well below limit ($($logs.Count) logs). Increasing chunk size from $chunkSizeHours to $newChunkSize hours." -ForegroundColor Cyan
                            $chunkSizeHours = $newChunkSize
                        }
                    }
                }
            } else {
                $noLogsCount++
                Write-Host "${subCountPrefix}No logs found in this time chunk." -ForegroundColor DarkGray
                
                # If we've had several empty chunks, consider increasing chunk size
                if ($noLogsCount >= 3 && $chunkSizeHours < $InitialChunkSizeHours) {
                    $newChunkSize = [Math]::Min($InitialChunkSizeHours, $chunkSizeHours * 2)
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
        }
        
        # Move to next time window
        $currentStart = $currentEnd
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

# Export the function for dot-sourcing
Export-ModuleMember -Function Get-AllActivityLogsWithChunking
