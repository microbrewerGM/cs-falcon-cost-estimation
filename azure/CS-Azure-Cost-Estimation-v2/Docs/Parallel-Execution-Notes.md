# Notes on Parallel Execution Feature

## Current Status

As of March 2025, the parallel execution feature in the CrowdStrike Azure Cost Estimation Tool has been **disabled by default** due to persistent issues with parameter passing in PowerShell background jobs.

## Background

The parallel execution feature was designed to improve performance when analyzing many Azure subscriptions by processing them concurrently. However, this feature relies on PowerShell's `Start-Job` cmdlet and its `-ArgumentList` parameter for passing data to background jobs, which has proven to be problematic.

## The Problem

PowerShell's background job parameter passing has several issues:

1. **Inconsistent syntax behavior**: Even with the correct comma-separated syntax, PowerShell can misinterpret argument lists
2. **Environment differences**: Parameter passing behavior varies between PowerShell versions and platforms
3. **Variable reference errors**: The infamous "Variable reference is not valid" errors that occur when PowerShell fails to properly interpret the variables being passed

## Solution Implemented

Rather than continuing to attempt fixes for the problematic parallel execution code, we've taken the following approach:

1. **Disabled parallel execution by default** by changing the default value of the `ParallelExecution` parameter to `$false`
2. **Retained the sequential processing code** which is more reliable and still works for all environments
3. **Kept the parallel execution code** for users who may want to manually enable it and troubleshoot in their environment

## If You Need Parallel Execution

If processing speed is critical for your environment and you have many subscriptions to analyze, you can:

1. Pass `-ParallelExecution $true` when running the script to enable parallel processing
2. Be aware that you may encounter parameter passing issues depending on your PowerShell version
3. If issues occur, consider modifying the job parameter passing code in the `Process-Subscription-Job.ps1` file

## Future Development

If you plan to make improvements to the parallel execution feature:

1. Use the test scripts in the `Tests` directory to validate parameter passing
2. Consider alternative approaches to parallelism, such as:
   - PowerShell workflows (though these have their own limitations)
   - PowerShell runspaces for finer control over thread management
   - Separate PowerShell processes managed by the main script

## Reference Resources

For more information about the parameter passing issues and potential solutions:

- [PowerShell Start-Job Documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/start-job)
- [PowerShell ArgumentList Guidelines](./ArgumentList-Guidelines.md) in this repository
- [PowerShell Background Jobs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_jobs)
