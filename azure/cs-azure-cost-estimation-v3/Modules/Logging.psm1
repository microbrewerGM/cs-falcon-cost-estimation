# Simplified logging module for CrowdStrike Azure Cost Estimation Tool v3

# Module variables
$script:LogFilePath = $null
$script:LogLevels = @{
    'DEBUG' = 0
    'INFO' = 1
    'WARNING' = 2
    'ERROR' = 3
    'SUCCESS' = 4
}
$script:DefaultLogLevel = 'INFO'
$script:MinLogLevel = 'INFO'  # Only log INFO and above by default

# Function to set the log file path
function Set-LogFilePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    # Create the directory if it doesn't exist
    $logDir = Split-Path -Parent $Path
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    
    $script:LogFilePath = $Path
    Write-Log "Log file set to: $Path" -Level 'DEBUG' -Category 'Logging'
    return $Path
}

# Function to get the current log file path
function Get-LogFilePath {
    return $script:LogFilePath
}

# Function to set the minimum log level
function Set-MinimumLogLevel {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level
    )
    
    $script:MinLogLevel = $Level
    Write-Log "Minimum log level set to: $Level" -Level 'DEBUG' -Category 'Logging'
}

# Main logging function
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = $script:DefaultLogLevel,
        
        [Parameter(Mandatory = $false)]
        [string]$Category = 'General',
        
        [Parameter(Mandatory = $false)]
        [switch]$NoConsole,
        
        [Parameter(Mandatory = $false)]
        [switch]$NoFile
    )
    
    # Skip if the log level is below the minimum
    if ($script:LogLevels[$Level] -lt $script:LogLevels[$script:MinLogLevel]) {
        return
    }
    
    # Format timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Format the log message
    $formattedMessage = "[$timestamp] [$Level] [$Category] $Message"
    
    # Get color for console output
    $consoleColor = switch ($Level) {
        'DEBUG' { 'Gray' }
        'INFO' { 'White' }
        'WARNING' { 'Yellow' }
        'ERROR' { 'Red' }
        'SUCCESS' { 'Green' }
        default { 'White' }
    }
    
    # Write to console if not suppressed
    if (-not $NoConsole) {
        Write-Host $formattedMessage -ForegroundColor $consoleColor
    }
    
    # Write to log file if path is set and not suppressed
    if ($script:LogFilePath -and -not $NoFile) {
        try {
            Add-Content -Path $script:LogFilePath -Value $formattedMessage -ErrorAction Stop
        }
        catch {
            # If we can't write to the log file, just output to console
            Write-Host "Failed to write to log file: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    return $formattedMessage
}

# Export functions
Export-ModuleMember -Function Set-LogFilePath, Get-LogFilePath, Set-MinimumLogLevel, Write-Log
