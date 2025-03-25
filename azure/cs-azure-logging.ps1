<#
.SYNOPSIS
    Azure operations logging module.

.DESCRIPTION
    This PowerShell module handles logging and output operations
    including creating timestamped directories and writing CSV files.
#>

function New-OutputDirectory {
    <#
    .SYNOPSIS
        Creates a new timestamped output directory.
    
    .DESCRIPTION
        Creates a new directory with a timestamp for storing output files.
        
    .OUTPUTS
        [string] Path to the created directory.
    #>
    
    # Create timestamp format for directory name
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $baseOutputDir = Join-Path -Path $PSScriptRoot -ChildPath "output"
    $outputDir = Join-Path -Path $baseOutputDir -ChildPath $timestamp
    
    # Create directory if it doesn't exist
    if (-not (Test-Path -Path $outputDir)) {
        try {
            $null = New-Item -Path $outputDir -ItemType Directory -Force -ErrorAction Stop
            Write-Host "Created output directory: $outputDir" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to create output directory: $_"
            # Fall back to script directory if output dir creation fails
            $outputDir = $PSScriptRoot
        }
    }
    
    return $outputDir
}

function Export-ToCsv {
    <#
    .SYNOPSIS
        Exports data to a CSV file.
    
    .DESCRIPTION
        Exports the provided data to a CSV file in the specified directory.
        
    .PARAMETER Data
        The data to export.
        
    .PARAMETER OutputDir
        Directory where the CSV file will be saved.
        
    .PARAMETER FileName
        Name of the CSV file without extension.
        
    .OUTPUTS
        [string] Path to the created CSV file or $null if failed.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Data,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        
        [Parameter(Mandatory = $true)]
        [string]$FileName
    )
    
    try {
        $filePath = Join-Path -Path $OutputDir -ChildPath "$FileName.csv"
        $Data | Export-Csv -Path $filePath -NoTypeInformation -ErrorAction Stop
        Write-Host "Data exported to: $filePath" -ForegroundColor Green
        return $filePath
    }
    catch {
        Write-Error "Failed to export data to CSV: $_"
        return $null
    }
}

function Write-LogEntry {
    <#
    .SYNOPSIS
        Writes a log entry to a log file.
    
    .DESCRIPTION
        Writes a timestamped log entry to a log file in the specified directory.
        
    .PARAMETER Message
        The message to log.
        
    .PARAMETER Level
        The log level (INFO, WARNING, ERROR).
        
    .PARAMETER OutputDir
        Directory where the log file will be saved.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO',
        
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )
    
    try {
        $logFile = Join-Path -Path $OutputDir -ChildPath "execution.log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        # Append to log file
        Add-Content -Path $logFile -Value $logEntry -ErrorAction Stop
        
        # Also write to console with appropriate color
        switch ($Level) {
            'INFO' { Write-Host $logEntry -ForegroundColor White }
            'WARNING' { Write-Host $logEntry -ForegroundColor Yellow }
            'ERROR' { Write-Host $logEntry -ForegroundColor Red }
        }
    }
    catch {
        # Just write to console if file logging fails
        Write-Host "Failed to write to log file: $_" -ForegroundColor Red
        Write-Host "[$timestamp] [$Level] $Message"
    }
}

# Functions are exposed via dot-sourcing
