<#
.SYNOPSIS
Installs Git hooks for the CS-Azure-Cost-Estimation-v2 project.

.DESCRIPTION
This script installs a pre-commit hook that validates PowerShell syntax and 
backtick alignment before allowing a commit to proceed. This helps prevent 
syntax errors and runtime errors related to backtick misalignment from being 
committed to the repository.

.EXAMPLE
.\Install-GitHooks.ps1

.NOTES
This script must be run from the repository root directory.
#>

[CmdletBinding()]
param()

# Determine the root of the Git repository
$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Error "This script must be run from within a Git repository."
    exit 1
}

# Set paths
$hooksDir = Join-Path $repoRoot ".git\hooks"
$preCommitPath = Join-Path $hooksDir "pre-commit"
$syntaxTestScript = Join-Path $repoRoot "azure\CS-Azure-Cost-Estimation-v2\Tests\Test-ScriptSyntax.ps1"
$backtickTestScript = Join-Path $repoRoot "azure\CS-Azure-Cost-Estimation-v2\Tests\Test-BacktickAlignment.ps1"

# Ensure the hooks directory exists
if (-not (Test-Path $hooksDir)) {
    New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null
}

# Create the pre-commit hook
$preCommitContent = @"
#!/bin/sh
# Pre-commit hook to validate PowerShell syntax and backtick alignment

# Get a list of staged PowerShell files
STAGED_PS_FILES=\$(git diff --cached --name-only --diff-filter=ACM | grep -e '\.ps1$' -e '\.psm1$')

if [ -n "\$STAGED_PS_FILES" ]; then
  echo "Running PowerShell validation on staged files..."
  
  # For each PowerShell file, run the syntax validation
  for FILE in \$STAGED_PS_FILES; do
    echo "Checking syntax for \$FILE..."
    powershell -NoProfile -ExecutionPolicy Bypass -File "$syntaxTestScript" -ScriptPath "\$(pwd)/\$FILE"
    if [ \$? -ne 0 ]; then
      echo "❌ Syntax validation failed for \$FILE. Commit aborted."
      exit 1
    fi
    
    echo "Checking backtick alignment for \$FILE..."
    pwsh -Command "& '$backtickTestScript' -Path '\$(pwd)/\$FILE'" > /dev/null
    if [ \$? -ne 0 ]; then
      echo "❌ Backtick alignment validation failed for \$FILE."
      pwsh -Command "& '$backtickTestScript' -Path '\$(pwd)/\$FILE'"
      echo "Fix the backtick alignment issues to prevent 'Variable reference is not valid' runtime errors."
      exit 1
    fi
    
    echo "✅ \$FILE passed all checks"
  done
fi

exit 0
"@

# Write the hook to the file
Set-Content -Path $preCommitPath -Value $preCommitContent -Encoding UTF8

# Make the hook executable
if ($IsLinux -or $IsMacOS) {
    chmod +x $preCommitPath
} else {
    # On Windows, Git handles this automatically
}

Write-Host "✅ Git pre-commit hook installed successfully!" -ForegroundColor Green
Write-Host "PowerShell syntax and backtick alignment will now be validated before each commit." -ForegroundColor Cyan
Write-Host "This prevents 'Variable reference is not valid' runtime errors from misaligned backticks." -ForegroundColor Cyan
