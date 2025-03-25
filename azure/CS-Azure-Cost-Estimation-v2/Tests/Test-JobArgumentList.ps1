<#
.SYNOPSIS
    Tests PowerShell scripts for proper parameter passing in Start-Job commands

.DESCRIPTION
    This script analyzes PowerShell files to detect improper parameter passing in Start-Job commands
    that can cause "Variable reference is not valid" errors at runtime. It specifically looks for
    ArgumentList arrays without proper comma separation between parameters.

.PARAMETER Path
    The path to a specific script file or directory to analyze

.EXAMPLE
    .\Test-JobArgumentList.ps1 -Path ..\Modules
    Checks all .ps1 and .psm1 files in the Modules directory

.EXAMPLE
    .\Test-JobArgumentList.ps1 -Path ..\CS-Azure-Cost-Estimation-v2-Main.ps1
    Checks a specific PowerShell script file
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

function Test-StartJobArgumentListFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    # Variables to track results
    $issues = @()
    $inStartJobBlock = $false
    $inArgumentList = $false
    $argumentListStartLine = 0
    $indentLevel = 0
    $content = Get-Content -Path $FilePath
    
    # Patterns to look for
    $startJobPattern = '(?i)Start-Job\s+.*-ArgumentList'
    $argumentListStartPattern = '(?i)-ArgumentList\s*@\('
    $argumentListEndPattern = '\)' # Simple close parenthesis
    
    for ($i = 0; $i -lt $content.Count; $i++) {
        $line = $content[$i]
        $lineNumber = $i + 1
        
        # Skip comment lines
        if ($line.Trim().StartsWith('#')) {
            continue
        }
        
        # Check if we're entering a Start-Job command
        if ($line -match $startJobPattern -or ($inStartJobBlock -and $line -match $argumentListStartPattern)) {
            $inStartJobBlock = $true
            
            # Check if ArgumentList is being defined
            if ($line -match $argumentListStartPattern) {
                $inArgumentList = $true
                $argumentListStartLine = $lineNumber
                
                # Determine indentation level
                if ($line -match '^\s+') {
                    $indentLevel = $matches[0].Length
                }
            }
        }
        
        # Check argument list format while we're inside it
        if ($inArgumentList) {
            # Check if this is a parameter line
            if ($line.Trim().Length -gt 0 && !$line.Trim().StartsWith('#') && $lineNumber -gt $argumentListStartLine) {
                
                # Check for absence of trailing comma in non-final lines
                $nextLine = if ($i + 1 -lt $content.Count) { $content[$i + 1] } else { "" }
                $isLastLine = $nextLine -match $argumentListEndPattern && !$nextLine.Trim().StartsWith('$')
                
                # Skip the check for the last parameter in the list
                if (!$isLastLine) {
                    # Check if the line doesn't end with a comma
                    if (!$line.TrimEnd().EndsWith(',')) {
                        # Check if next line is a parameter (not a closing parenthesis)
                        if ($i + 1 -lt $content.Count && 
                            $nextLine.Trim().Length -gt 0 && 
                            !$nextLine.Trim().StartsWith(')') &&
                            !$nextLine.Trim().StartsWith('#')) {
                            
                            $issues += @{
                                LineNumber = $lineNumber
                                Line = $line.TrimEnd()
                                Issue = "Parameter in ArgumentList should end with a comma for proper separation"
                                Recommendation = "$($line.TrimEnd()),"
                            }
                        }
                    }
                }
            }
            
            # Check if we're exiting the ArgumentList block
            if ($line -match $argumentListEndPattern && $line.Trim() -notmatch '^[\$\w]') {
                $inArgumentList = $false
                $inStartJobBlock = $false
            }
        }
    }
    
    return $issues
}

# Main function to analyze files
function Test-JobArgumentList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    # Check if the path is a file or directory
    if (Test-Path -Path $Path -PathType Leaf) {
        # Single file mode
        $fileExt = [System.IO.Path]::GetExtension($Path).ToLower()
        if ($fileExt -eq ".ps1" -or $fileExt -eq ".psm1") {
            $issues = Test-StartJobArgumentListFormat -FilePath $Path
            if ($issues.Count -gt 0) {
                Write-Host "Issues found in ${Path}:" -ForegroundColor Red
                foreach ($issue in $issues) {
                    Write-Host "Line $($issue.LineNumber): $($issue.Issue)" -ForegroundColor Red
                    Write-Host "  Current: $($issue.Line)" -ForegroundColor Yellow
                    Write-Host "  Recommended: $($issue.Recommendation)" -ForegroundColor Green
                }
                return $false
            }
            else {
                Write-Host "No Start-Job ArgumentList issues found in ${Path}" -ForegroundColor Green
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
            $issues = Test-StartJobArgumentListFormat -FilePath $file.FullName
            if ($issues.Count -gt 0) {
                $foundIssues = $true
                Write-Host "Issues found in $($file.FullName):" -ForegroundColor Red
                foreach ($issue in $issues) {
                    Write-Host "Line $($issue.LineNumber): $($issue.Issue)" -ForegroundColor Red
                    Write-Host "  Current: $($issue.Line)" -ForegroundColor Yellow
                    Write-Host "  Recommended: $($issue.Recommendation)" -ForegroundColor Green
                }
                Write-Host ""
            }
        }
        
        if (-not $foundIssues) {
            Write-Host "No Start-Job ArgumentList issues found in any PowerShell script in ${Path}" -ForegroundColor Green
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
$result = Test-JobArgumentList -Path $Path
if (-not $result) {
    Write-Host "`nStart-Job ArgumentList issues were found that could cause runtime errors." -ForegroundColor Red
    Write-Host "Please fix them by ensuring proper comma separation between parameters in ArgumentList arrays." -ForegroundColor Red
    
    # Provide guidance on fixing the issues
    Write-Host "`nHere are the PowerShell best practices for Start-Job parameter passing:" -ForegroundColor Cyan
    Write-Host "1. Always use commas to separate parameters in ArgumentList arrays"
    Write-Host "2. Example of proper ArgumentList format:"
    Write-Host "   Start-Job -FilePath 'script.ps1' -ArgumentList @("
    Write-Host "       `$param1,"
    Write-Host "       `$param2,"
    Write-Host "       `$param3"
    Write-Host "   )"
    
    exit 1
}
else {
    Write-Host "All Start-Job ArgumentList format checks passed!" -ForegroundColor Green
    exit 0
}
