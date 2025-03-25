# Logging Module for CrowdStrike Azure Cost Estimation Tool

# Default log file path
$script:LogFilePath = ""

# Function to set the log file path
function Set-LogFilePath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $script:LogFilePath = $Path
}

# Function to write to log file with enhanced prefixing for clarity in extensive logs
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS', 'DEBUG', 'METRIC')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [string]$Category = 'General',

        [Parameter(Mandatory = $false)]
        [switch]$NoConsole
    )

    # Check if LogFilePath is set
    if ([string]::IsNullOrWhiteSpace($script:LogFilePath)) {
        Write-Warning "Log file path not set. Use Set-LogFilePath to set it."
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] [$Category] $Message"
    
    # Write to log file
    Add-Content -Path $script:LogFilePath -Value $logMessage -ErrorAction SilentlyContinue
    
    # Also write to console with color, unless NoConsole is specified
    if (-not $NoConsole) {
        switch ($Level) {
            'INFO' { Write-Host $logMessage -ForegroundColor Cyan }
            'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
            'ERROR' { Write-Host $logMessage -ForegroundColor Red }
            'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
            'DEBUG' { 
                if ($VerbosePreference -eq 'Continue') {
                    Write-Host $logMessage -ForegroundColor Gray 
                }
            }
            'METRIC' { Write-Host $logMessage -ForegroundColor Magenta }
            default { Write-Host $logMessage }
        }
    }
}

# Function to execute a command with error handling and logging
function Test-CommandSuccess {
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [switch]$ContinueOnError,
        
        [Parameter(Mandatory = $false)]
        [string]$Category = 'General'
    )
    
    try {
        $result = & $Command
        return @{
            Success = $true
            Result = $result
        }
    }
    catch {
        if ($ContinueOnError) {
            Write-Log "$ErrorMessage - $($_.Exception.Message)" -Level 'WARNING' -Category $Category
            return @{
                Success = $false
                Error = $_
                ErrorMessage = "$ErrorMessage - $($_.Exception.Message)"
            }
        }
        else {
            Write-Log "$ErrorMessage - $($_.Exception.Message)" -Level 'ERROR' -Category $Category
            throw
        }
    }
}

# Enhanced progress tracking with ETA estimation
function Show-EnhancedProgress {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Activity,
        
        [Parameter(Mandatory = $true)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory = $false)]
        [string]$Status = "",
        
        [Parameter(Mandatory = $false)]
        [DateTime]$StartTime,
        
        [Parameter(Mandatory = $false)]
        [string]$Category = 'Progress'
    )
    
    # Calculate ETA if StartTime is provided and we're not at 0%
    $etaString = ""
    if ($StartTime -and $PercentComplete -gt 0 -and $PercentComplete -lt 100) {
        $elapsed = (Get-Date) - $StartTime
        $estimatedTotal = $elapsed.TotalSeconds / ($PercentComplete / 100)
        $estimatedRemaining = $estimatedTotal - $elapsed.TotalSeconds
        
        if ($estimatedRemaining -gt 0) {
            $etaTimeSpan = [TimeSpan]::FromSeconds($estimatedRemaining)
            if ($etaTimeSpan.TotalHours -ge 1) {
                $etaString = " (ETA: {0:h\h\ m\m\ s\s})" -f $etaTimeSpan
            }
            else {
                $etaString = " (ETA: {0:m\m\ s\s})" -f $etaTimeSpan
            }
        }
    }
    
    $statusWithEta = "$Status$etaString"
    Write-Progress -Activity $Activity -Status $statusWithEta -PercentComplete $PercentComplete
    Write-Log "$Activity - $statusWithEta ($PercentComplete%)" -Level 'INFO' -Category $Category
}

# Export functions and variables
Export-ModuleMember -Function Set-LogFilePath, Write-Log, Test-CommandSuccess, Show-EnhancedProgress
