<#
.SYNOPSIS
    Advanced PowerShell syntax validation tool for common runtime errors

.DESCRIPTION
    This script provides comprehensive syntax checking of PowerShell scripts to detect
    common errors that cause runtime failures, including:
    
    1. Variable interpolation issues in strings
    2. Backtick line continuation problems
    3. Curly brace placement in string interpolation
    4. Other common PowerShell syntax errors
    
    It helps prevent the "Variable reference is not valid" errors without requiring specific
    formatting styles.

.PARAMETER Path
    The path to a PowerShell script file or directory to analyze

.EXAMPLE
    .\Test-PowerShellSyntax.ps1 -Path ..\Modules
    Checks all .ps1 and .psm1 files in the Modules directory

.EXAMPLE
    .\Test-PowerShellSyntax.ps1 -Path ..\CS-Azure-Cost-Estimation-v2-Main.ps1
    Checks a specific PowerShell script file
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# Define patterns to check
$patterns = @(
    # Variable in quoted string ending with colon (needs proper curly braces)
    @{
        Name = "Improper variable reference with colon"
        Pattern = '["''].*?\$[a-zA-Z0-9_]+:'
        Description = "Variable references followed by colons need curly braces"
        Fix = "Replace $variable:text with `${variable}:text or `$(`$variable):text"
        Severity = "Error"
    },
    # Path concatenation without Join-Path
    @{
        Name = "Path concatenation using string operators"
        Pattern = '\$[a-zA-Z0-9_]+\s*\+\s*[''"]\\[^''"]'
        Description = "Avoid direct string concatenation for paths. Use Join-Path instead."
        Fix = "Use Join-Path instead of string concatenation for paths"
        Severity = "Warning"
    },
    # Misaligned backtick (checking indentation on next line)
    @{
        Name = "Backtick line continuation"
        Pattern = '`\s*$'
        Description = "Line ends with backtick - ensure the next line is properly indented"
        Fix = "Align the continued line with matching indentation or parameter alignment"
        Severity = "Error"
        CustomCheck = $true  # Needs special handling to check next line
    },
    # Double variable interpolation ($($var))
    @{
        Name = "Redundant variable subexpression"
        Pattern = '\$\(\$[a-zA-Z0-9_]+\)'
        Description = "Redundant subexpression notation"
        Fix = "Use $var directly instead of $($var) for simple variables"
        Severity = "Warning"
    },
    # Missing subexpression for complex expressions
    @{
        Name = "Missing subexpression"
        Pattern = '\$[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+'
        Description = "Property access within strings may need subexpression"
        Fix = "For property access in strings, use $($obj.property) instead of $obj.property"
        Severity = "Warning"
        CustomCheck = $true  # Needs special handling to check if in a string
    }
)

function Test-FileForSyntaxIssues {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    Write-Verbose "Analyzing $FilePath for PowerShell syntax issues"
    
    # Read all content
    $content = Get-Content -Path $FilePath -Raw
    $lines = Get-Content -Path $FilePath
    
    $issues = @()
    
    # Process each pattern
    foreach ($pattern in $patterns) {
        $matches = [regex]::Matches($content, $pattern.Pattern)
        
        foreach ($match in $matches) {
            # Calculate line number for this match
            $lineNumber = ($content.Substring(0, $match.Index).Split("`n")).Length
            $lineContent = $lines[$lineNumber - 1]
            
            # Skip if this is in a comment
            if ($lineContent -match '^\s*#') {
                continue
            }
            
            # Special handling for backticks
            if ($pattern.Name -eq "Backtick line continuation" -and $pattern.CustomCheck) {
                # Check indentation level
                if ($lineNumber -lt $lines.Length) {
                    $currentLine = $lineContent
                    $nextLine = $lines[$lineNumber]
                    
                    # Attempt to determine appropriate indentation
                    $currentIndent = 0
                    if ($currentLine -match '^\s+') {
                        $currentIndent = $matches[0].Length
                    }
                    
                    $expectedIndent = $currentIndent
                    # If the line has parameters, align with params (add 8-12 spaces)
                    if ($currentLine -match '-[A-Za-z]+\s+') {
                        $expectedIndent += 10
                    }
                    
                    $nextIndent = 0
                    if ($nextLine -match '^\s+') {
                        $nextIndent = $matches[0].Length
                    }
                    
                    # If indentation is insufficient
                    if ($nextIndent -lt $expectedIndent - 2) {  # Allow small variations
                        $issues += [PSCustomObject]@{
                            LineNumber = $lineNumber
                            Pattern = $pattern.Name
                            Description = "Line continuation indentation issue: Expected ~$expectedIndent spaces but found $nextIndent"
                            Content = $lineContent
                            NextLine = $nextLine
                            Severity = $pattern.Severity
                            Fix = $pattern.Fix
                        }
                    }
                }
                continue
            }
            
            # Special handling for missing subexpressions in strings
            if ($pattern.Name -eq "Missing subexpression" -and $pattern.CustomCheck) {
                # Check if this is actually inside a string
                $contextStart = [Math]::Max(0, $match.Index - 20)
                $contextLength = [Math]::Min(40, $content.Length - $contextStart)
                $context = $content.Substring($contextStart, $contextLength)
                
                # Only flag if it's inside a string (preceded by " or ' without a closing one)
                if ($context -match '["''][^"'']*\$[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+') {
                    $issues += [PSCustomObject]@{
                        LineNumber = $lineNumber
                        Pattern = $pattern.Name
                        Description = $pattern.Description
                        Content = $lineContent
                        Severity = $pattern.Severity
                        Fix = $pattern.Fix
                        MatchText = $match.Value
                    }
                }
                continue
            }
            
            # Standard pattern match
            $issues += [PSCustomObject]@{
                LineNumber = $lineNumber
                Pattern = $pattern.Name
                Description = $pattern.Description
                Content = $lineContent
                Severity = $pattern.Severity
                Fix = $pattern.Fix
                MatchText = $match.Value
            }
        }
    }
    
    # Add a check for general PowerShell syntax validity
    try {
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null)
    } 
    catch {
        $issues += [PSCustomObject]@{
            LineNumber = $_.Exception.ErrorRecord.InvocationInfo.ScriptLineNumber
            Pattern = "PowerShell Syntax Error"
            Description = $_.Exception.ErrorRecord.ErrorDetails
            Content = $lines[$_.Exception.ErrorRecord.InvocationInfo.ScriptLineNumber - 1]
            Severity = "Error"
            Fix = "Fix the PowerShell syntax error"
        }
    }
    
    # Specific check for Variable is not valid / ":" not followed errors
    # This is a common issue with path separators and string interpolation
    $colonMatches = [regex]::Matches($content, '"\$[a-zA-Z0-9_]+:')
    foreach ($match in $colonMatches) {
        $lineNumber = ($content.Substring(0, $match.Index).Split("`n")).Length
        $lineContent = $lines[$lineNumber - 1]
        
        # Skip if this is in a comment
        if ($lineContent -match '^\s*#') {
            continue
        }
        
        $issues += [PSCustomObject]@{
            LineNumber = $lineNumber
            Pattern = "Variable reference with colon"
            Description = 'Variable reference followed by colon will cause: "Variable reference is not valid. '':'' was not followed by a valid variable name character"'
            Content = $lineContent
            Severity = "Error"
            Fix = 'Use ${variable}:path or $($variable):path syntax'
            MatchText = $match.Value
        }
    }
    
    return $issues
}

function Test-PowerShellSyntax {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    $allIssues = @()
    
    # Process a single file
    if (Test-Path -Path $Path -PathType Leaf) {
        $extension = [System.IO.Path]::GetExtension($Path).ToLower()
        if ($extension -eq ".ps1" -or $extension -eq ".psm1") {
            $fileIssues = Test-FileForSyntaxIssues -FilePath $Path
            
            if ($fileIssues.Count -gt 0) {
                Write-Host "Issues found in ${Path}:" -ForegroundColor Yellow
                foreach ($issue in $fileIssues) {
                    $color = if ($issue.Severity -eq "Error") { "Red" } else { "Yellow" }
                    Write-Host "Line $($issue.LineNumber) - $($issue.Pattern): $($issue.Description)" -ForegroundColor $color
                    Write-Host "  $($issue.Content)" -ForegroundColor Cyan
                    Write-Host "  Fix: $($issue.Fix)" -ForegroundColor Green
                    Write-Host ""
                }
                $allIssues += $fileIssues
            }
            else {
                Write-Host "No syntax issues found in ${Path}" -ForegroundColor Green
            }
        }
        else {
            Write-Host "File ${Path} is not a PowerShell script (.ps1) or module (.psm1)" -ForegroundColor Yellow
        }
    }
    # Process a directory
    elseif (Test-Path -Path $Path -PathType Container) {
        $files = Get-ChildItem -Path $Path -Recurse -Include "*.ps1", "*.psm1"
        
        foreach ($file in $files) {
            $fileIssues = Test-FileForSyntaxIssues -FilePath $file.FullName
            
            if ($fileIssues.Count -gt 0) {
                Write-Host "Issues found in $($file.FullName):" -ForegroundColor Yellow
                foreach ($issue in $fileIssues) {
                    $color = if ($issue.Severity -eq "Error") { "Red" } else { "Yellow" }
                    Write-Host "Line $($issue.LineNumber) - $($issue.Pattern): $($issue.Description)" -ForegroundColor $color
                    Write-Host "  $($issue.Content)" -ForegroundColor Cyan
                    Write-Host "  Fix: $($issue.Fix)" -ForegroundColor Green
                    Write-Host ""
                }
                $allIssues += $fileIssues
            }
        }
        
        if ($allIssues.Count -eq 0) {
            Write-Host "No syntax issues found in any PowerShell script in ${Path}" -ForegroundColor Green
        }
    }
    else {
        Write-Error "Path not found: ${Path}"
        return $false
    }
    
    return ($allIssues.Count -eq 0)
}

# Print guidance for PowerShell best practices
function Show-PowerShellBestPractices {
    Write-Host "`nPowerShell Variable Reference Best Practices:" -ForegroundColor Cyan
    Write-Host "1. Simple variables can be used directly in strings: 'Value is: `$variable'"
    Write-Host "2. For properties or methods, use subexpressions: 'Size: `$(`$obj.Size)'"
    Write-Host "3. When a variable is followed by a colon or special character, use curly braces: 'Path: `${variable}:subfolder'"
    Write-Host "4. For complex expressions, use subexpressions: 'Result: `$(Get-Result -Name `$name)'"
    Write-Host "5. For paths, use Join-Path instead of string concatenation: 'Join-Path `$dir ''subfolder'''"
    Write-Host "6. For backtick line continuation, ensure the next line is properly aligned with parameters"
    Write-Host
    Write-Host "Common PowerShell Runtime Errors and How to Fix Them:" -ForegroundColor Cyan
    Write-Host "- 'Variable reference is not valid. ':' was not followed by a valid variable name character'"
    Write-Host "  Fix: Replace '`$var:text' with '`${var}:text' or '`$(`$var):text'"
    Write-Host
    Write-Host "- 'The string is missing the terminator: '"
    Write-Host "  Fix: Ensure all string quotes are properly closed or escaped"
    Write-Host
    Write-Host "- 'Unexpected token in expression or statement'"
    Write-Host "  Fix: Check for missing commas, parentheses, or braces"
}

# Run the analyzer
$result = Test-PowerShellSyntax -Path $Path

# Show best practices regardless of result
Show-PowerShellBestPractices

# Exit with appropriate code
if (-not $result) {
    Write-Host "`nPowerShell syntax issues were found that could cause runtime errors." -ForegroundColor Red
    Write-Host "Please fix them using the provided recommendations." -ForegroundColor Red
    exit 1
}
else {
    Write-Host "All PowerShell syntax checks passed!" -ForegroundColor Green
    exit 0
}
