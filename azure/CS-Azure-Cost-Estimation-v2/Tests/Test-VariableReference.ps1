# Test script to validate variable reference handling in Start-Job ArgumentList
# This will help ensure arguments are passed correctly to background jobs

# Test parameters similar to those in the main script
# Use platform-neutral paths for cross-platform compatibility
$platformPath = if ($IsWindows) { "C:/Test" } elseif ($IsMacOS) { "/tmp/test" } else { "/tmp/test" }

$jobParams = @{
    SubscriptionId = "00000000-0000-0000-0000-000000000000"
    SubscriptionName = "Test Subscription"
    ProcessedCount = 1
    TotalCount = 10
    StartTimeStr = (Get-Date).ToString("o")
    DaysToAnalyze = 7
    SampleLogSize = 100
    UseRealPricing = $true
    ModulePath = Join-Path $platformPath "Modules"
    OutputDirectory = Join-Path $platformPath "Output"
}

# Create a temporary test job script
$tempDir = if ($IsMacOS -or $IsLinux) { "/tmp" } else { $env:TEMP }
$tempScriptPath = Join-Path $tempDir "TestJobScript.ps1"
@"
param(
    [Parameter(Mandatory = `$true)]
    [string]`$SubscriptionId,
    
    [Parameter(Mandatory = `$true)]
    [string]`$SubscriptionName,
    
    [Parameter(Mandatory = `$true)]
    [int]`$ProcessedCount,
    
    [Parameter(Mandatory = `$true)]
    [int]`$TotalCount,
    
    [Parameter(Mandatory = `$true)]
    [string]`$StartTimeStr,
    
    [Parameter(Mandatory = `$true)]
    [int]`$DaysToAnalyze,
    
    [Parameter(Mandatory = `$true)]
    [int]`$SampleLogSize,
    
    [Parameter(Mandatory = `$true)]
    [bool]`$UseRealPricing,
    
    [Parameter(Mandatory = `$true)]
    [string]`$ModulePath,
    
    [Parameter(Mandatory = `$true)]
    [string]`$OutputDirectory
)

# Output received parameters to verify they came through correctly
`$params = @{
    "SubscriptionId" = `$SubscriptionId
    "SubscriptionName" = `$SubscriptionName
    "ProcessedCount" = `$ProcessedCount
    "TotalCount" = `$TotalCount
    "StartTimeStr" = `$StartTimeStr
    "DaysToAnalyze" = `$DaysToAnalyze
    "SampleLogSize" = `$SampleLogSize
    "UseRealPricing" = `$UseRealPricing
    "ModulePath" = `$ModulePath
    "OutputDirectory" = `$OutputDirectory
}

return `$params
"@ | Out-File -FilePath $tempScriptPath -Force

Write-Host "Testing parameter passing to background job..." -ForegroundColor Cyan

# Test with the corrected syntax (with commas between parameters)
Write-Host "Running test with comma-separated parameters..." -ForegroundColor Green
$job = Start-Job -FilePath $tempScriptPath -ArgumentList @(
    $jobParams.SubscriptionId, 
    $jobParams.SubscriptionName, 
    $jobParams.ProcessedCount, 
    $jobParams.TotalCount, 
    $jobParams.StartTimeStr,
    $jobParams.DaysToAnalyze,
    $jobParams.SampleLogSize,
    $jobParams.UseRealPricing,
    $jobParams.ModulePath,
    $jobParams.OutputDirectory
)

# Wait for the job to complete
Wait-Job $job | Out-Null
$result = Receive-Job $job
Remove-Job $job

# Display the results
Write-Host "Job results:" -ForegroundColor Cyan
$result | Format-Table -AutoSize

# Verify each parameter was correctly passed
$success = $true
foreach ($key in $jobParams.Keys) {
    if ($result[$key] -ne $jobParams[$key]) {
        Write-Host "Error: Parameter $key was not passed correctly!" -ForegroundColor Red
        Write-Host "  Expected: $($jobParams[$key])" -ForegroundColor Red
        Write-Host "  Received: $($result[$key])" -ForegroundColor Red
        $success = $false
    }
}

if ($success) {
    Write-Host "Success! All parameters were passed correctly." -ForegroundColor Green
} else {
    Write-Host "Test failed. Some parameters were not passed correctly." -ForegroundColor Red
}

# Clean up
Remove-Item $tempScriptPath -Force
