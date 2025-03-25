<#
.SYNOPSIS
    Tests PowerShell scripts for backtick alignment issues

.DESCRIPTION
    This script analyzes PowerShell files for common backtick alignment issues
    that can cause the "Variable reference is not valid. ':' was not followed
    by a valid variable name character" error at runtime.

.PARAMETER Path
    The path to a specific script file or directory to analyze

.EXAMPLE
    .\Test-BacktickAlignment.ps1 -Path ..\Modules
    Checks all .ps1 and .psm1 files in the Modules directory

.EXAMPLE
    .\Test-BacktickAlignment.ps1 -Path ..\CS-Azure-Cost-Estimation-v2-Main.ps1
    Checks a specific PowerShell script file
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# Regex pattern to detect misaligned backticks
# This looks for lines that end with a backtick where the following line has less spaces
# than the minimum required for proper continuation alignment
function Test-BacktickAlignmentInFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    # Variables to track results
    $issues = @()
    $lineNumber = 0
    $inContinuation = $false
    $indentationLevel = 0
    
    # Read the file line by line
    $content = Get-Content -Path $FilePath
    
    foreach ($line in $content) {
        $lineNumber++
        
        # Check if the previous line ended with a backtick
        if ($inContinuation) {
            # Calculate indentation of current line
            $currentIndent = 0
            if ($line -match "^(\s+)") {
                $currentIndent = $matches[1].Length
            }
            
            # Check if indentation is inconsistent with previous line
            if ($currentIndent -lt $indentationLevel) {
                $issues += @{
                    LineNumber = $lineNumber
                    Line = $line.TrimEnd()
                    Issue = "Misaligned continuation line (expected at least $indentationLevel spaces, found $currentIndent)"
                }
            }
            
            # Check if this line also ends with a backtick
            $inContinuation = $line.TrimEnd() -match '`$'
        }
        else {
            # Check if this line ends with a backtick
            if ($line.TrimEnd() -match '`$') {
                $inContinuation = $true
                
                # Calculate expected indentation for next line
                # Extract non-whitespace content
                if ($line -match "^(\s+)") {
                    # For lines that have a command and then a backtick, we need to align to the parameters
                    # Example: Get-SomeThing -Parameter1 Value1 `
                    #                        -Parameter2 Value2
                    if ($line -match "^(\s*)(\S+)(\s+)") {
                        $leadingSpaces = $matches[1].Length
                        $firstWord = $matches[2].Length
                        $spacesAfterWord = $matches[3].Length
                        $indentationLevel = $leadingSpaces + $firstWord + $spacesAfterWord
                    }
                    else {
                        $indentationLevel = $matches[1].Length
                    }
                }
                else {
                    # If line starts with non-whitespace, calculate indent for parameter alignment
                    if ($line -match "^(\S+)(\s+)") {
                        $firstWord = $matches[1].Length
                        $spacesAfterWord = $matches[2].Length
                        $indentationLevel = $firstWord + $spacesAfterWord
                    }
                    else {
                        $indentationLevel = 4  # Default indentation if we can't determine
                    }
                }
            }
            else {
                $inContinuation = $false
            }
        }
    }
    
    return $issues
}

# Main function to analyze files
function Test-BacktickAlignment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    # Check if the path is a file or directory
    if (Test-Path -Path $Path -PathType Leaf) {
        # Single file mode
        $fileExt = [System.IO.Path]::GetExtension($Path).ToLower()
        if ($fileExt -eq ".ps1" -or $fileExt -eq ".psm1") {
            $issues = Test-BacktickAlignmentInFile -FilePath $Path
            if ($issues.Count -gt 0) {
                Write-Host "Issues found in ${Path}:"
                foreach ($issue in $issues) {
                    Write-Host "Line $($issue.LineNumber): $($issue.Issue)"
                    Write-Host "  $($issue.Line)" -ForegroundColor Yellow
                }
                return $false
            }
            else {
                Write-Host "No backtick alignment issues found in ${Path}" -ForegroundColor Green
                return $true
            }
        }
        else {
            Write-Host "File ${Path} is not a PowerShell script (.ps1) or module (.psm1)" -ForegroundColor Yellow
            return $true
        }
    }
    elseif (Test-Path -Path $Path -PathType Container) {
        # Directory mode - get all .ps1 and .psm1 files
        $files = Get-ChildItem -Path $Path -Recurse -Include "*.ps1", "*.psm1"
        
        $foundIssues = $false
        foreach ($file in $files) {
            $issues = Test-BacktickAlignmentInFile -FilePath $file.FullName
            if ($issues.Count -gt 0) {
                $foundIssues = $true
                Write-Host "Issues found in $($file.FullName):" -ForegroundColor Red
                foreach ($issue in $issues) {
                    Write-Host "Line $($issue.LineNumber): $($issue.Issue)"
                    Write-Host "  $($issue.Line)" -ForegroundColor Yellow
                }
                Write-Host ""
            }
        }
        
        if (-not $foundIssues) {
            Write-Host "No backtick alignment issues found in any PowerShell script in ${Path}" -ForegroundColor Green
            return $true
        }
        else {
            return $false
        }
    }
    else {
        Write-Error "Path not found: ${Path}"
        return $false
    }
}

# Run the main function
$result = Test-BacktickAlignment -Path $Path
if (-not $result) {
    Write-Host "`nBacktick alignment issues were found that could cause runtime errors." -ForegroundColor Red
    Write-Host "Please fix them by ensuring proper indentation after each backtick line continuation." -ForegroundColor Red
    
    # Provide guidance on fixing the issues
    Write-Host "`nHere are the PowerShell best practices for backtick line continuation:" -ForegroundColor Cyan
    Write-Host "1. Place the backtick as the last character on the line (no trailing spaces)"
    Write-Host "2. Align all continued lines with the first parameter or at least 8-10 spaces from the left margin"
    Write-Host "3. Example of proper alignment:"
    Write-Host "   Get-Something -Parameter1 Value1 `"
    Write-Host "                 -Parameter2 Value2 `"
    Write-Host "                 -Parameter3 Value3"
    
    exit 1
}
else {
    Write-Host "All backtick alignment checks passed!" -ForegroundColor Green
    exit 0
}
