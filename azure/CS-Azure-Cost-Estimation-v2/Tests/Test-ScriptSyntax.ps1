<#
.SYNOPSIS
Validates the syntax of PowerShell scripts without executing them.

.DESCRIPTION
This script performs static analysis on PowerShell scripts to check for syntax errors,
parser errors, and other common issues without actually executing the scripts.

.PARAMETER ScriptPath
Path to the PowerShell script to validate. Can be a single file or a directory.

.EXAMPLE
.\Test-ScriptSyntax.ps1 -ScriptPath "..\CS-Azure-Cost-Estimation-v2-Main.ps1"

.NOTES
This script helps catch syntax errors before they are committed to the repository.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath
)

function Test-PowerShellSyntax {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    Write-Host "Validating syntax for: ${FilePath}" -ForegroundColor Cyan
    
    try {
        # Use the PowerShell parser to check for syntax errors
        $errors = $null
        $tokens = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $FilePath, 
            [ref]$tokens, 
            [ref]$errors
        )
        
        if ($errors.Count -gt 0) {
            Write-Host "❌ Syntax errors found in ${FilePath}:" -ForegroundColor Red
            foreach ($error in $errors) {
                Write-Host "   - Line $($error.Extent.StartLineNumber), Col $($error.Extent.StartColumnNumber): $($error.Message)" -ForegroundColor Red
            }
            return $false
        }
        else {
            Write-Host "✅ No syntax errors found in ${FilePath}" -ForegroundColor Green
            
            # Additional checks could be added here
            # For example, checking for specific coding patterns or best practices
            
            return $true
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Host "❌ Error validating ${FilePath}: $errorMessage" -ForegroundColor Red
        return $false
    }
}

$allPassed = $true

# Handle directory or single file
if (Test-Path -Path $ScriptPath -PathType Container) {
    # Process all PS1 files in the directory
    $scripts = Get-ChildItem -Path $ScriptPath -Filter "*.ps1" -Recurse
    foreach ($script in $scripts) {
        $scriptPassed = Test-PowerShellSyntax -FilePath $script.FullName
        $allPassed = $allPassed -and $scriptPassed
    }
} else {
    # Process single file
    $scriptPassed = Test-PowerShellSyntax -FilePath $ScriptPath
    $allPassed = $allPassed -and $scriptPassed
}

# Return an overall result
if ($allPassed) {
    Write-Host "✅ All scripts passed syntax validation!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ Some scripts failed validation. Please fix the issues before committing." -ForegroundColor Red
    exit 1
}
