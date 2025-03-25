# PowerShell Start-Job ArgumentList Parameter Handling Guidelines

## Problem Description

The CrowdStrike Azure Cost Estimation Tool experienced recurring issues with variable references in parallel execution mode. Specifically, line 451 in `CS-Azure-Cost-Estimation-v2-Main.ps1` which passes parameters to background jobs using `Start-Job -ArgumentList` was causing runtime errors with messages like:

```
Variable reference is not valid. ':' was not followed by a valid variable name character.
```

This occurs because PowerShell requires special syntax for passing multiple parameters to background jobs via the `-ArgumentList` parameter.

## Root Cause

When passing multiple parameters to a PowerShell background job, parameters must be properly comma-separated to ensure PowerShell recognizes them as distinct arguments. Without proper comma separation, PowerShell might interpret the parameters as a single argument or fail to parse the variable references correctly.

## Solution Applied

The issue was fixed by ensuring all parameters in the `-ArgumentList` array are properly comma-separated:

```powershell
# Correct syntax with commas between parameters
$job = Start-Job -FilePath $scriptPath -ArgumentList @(
    $param1,
    $param2,
    $param3
)

# Incorrect syntax without commas
$job = Start-Job -FilePath $scriptPath -ArgumentList @(
    $param1
    $param2
    $param3
)
```

## Prevention Measures

To prevent this issue from recurring, the following safeguards have been implemented:

1. **Test-JobArgumentList.ps1**: A dedicated test script that validates ArgumentList parameter passing in PowerShell scripts. It scans for improper parameter passing patterns and provides guidance for correction.

2. **Test-VariableReference.ps1**: A test script that demonstrates and tests proper parameter passing to background jobs.

3. **Enhanced Pre-commit Hook**: The git pre-commit hook has been updated to automatically check for improper ArgumentList parameter passing before allowing code to be committed.

## Guidelines for Future Development

When working with PowerShell background jobs:

1. **Always use commas** to separate parameters in ArgumentList arrays
2. Verify parameter passing with `Test-JobArgumentList.ps1` if unsure
3. Run the test scripts before committing changes to ensure compatibility
4. Consider adding to the pre-commit hook if new parameter-passing patterns are identified

## Testing Your Changes

You can validate your changes with:

```powershell
# Run the job argument list validator
./Tests/Test-JobArgumentList.ps1 -Path ./YourScript.ps1

# Test variable reference handling
./Tests/Test-VariableReference.ps1
```

## Why Parallel Execution?

The parallel execution feature is retained as it significantly improves performance for large environments with many subscriptions. The ArgumentList parameter passing has been fixed to ensure this feature works reliably.
