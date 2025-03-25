#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    CrowdStrike Azure Cost Estimation Main Script.

.DESCRIPTION
    This PowerShell script serves as the main entry point for the CrowdStrike
    Azure Cost Estimation tool. It authenticates to Azure, retrieves subscription
    information, and prepares for further operations.
#>

# Source required files
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$filesToSource = @(
    "$scriptPath\cs-azure-auth.ps1",
    "$scriptPath\cs-azure-subscriptions.ps1",
    "$scriptPath\cs-azure-logging.ps1"
)

foreach ($file in $filesToSource) {
    try {
        . $file
        Write-Host "Sourced file: $file" -ForegroundColor DarkGray
    }
    catch {
        Write-Error "Failed to source file $file : $_"
        exit 1
    }
}

# Display simple header
function Show-Header {
    Write-Host "CrowdStrike Azure Cost Estimation Tool v1.0" -ForegroundColor Cyan
    Write-Host "-----------------------------------------------" -ForegroundColor Cyan
}

# Main function
function Start-AzureCostEstimation {
    # Display header
    Show-Header
    
    # Create output directory
    $outputDir = New-OutputDirectory
    Write-LogEntry -Message "Starting Azure Cost Estimation Tool" -OutputDir $outputDir
    
    # Check required modules
    if (-not (Confirm-AzModules)) {
        Write-LogEntry -Message "Required Azure modules are missing. Please install them and try again." -Level ERROR -OutputDir $outputDir
        return
    }
    
    # Authenticate to Azure
    Write-LogEntry -Message "Attempting to authenticate to Azure..." -OutputDir $outputDir
    
    # Standard authentication
    $loginSuccessful = Connect-ToAzure
    
    if (-not $loginSuccessful) {
        Write-LogEntry -Message "Azure authentication failed. Please try again." -Level ERROR -OutputDir $outputDir
        return
    }
    
    Write-LogEntry -Message "Successfully authenticated to Azure." -OutputDir $outputDir
    
    # Retrieve subscription information
    Write-LogEntry -Message "Retrieving Azure subscriptions..." -OutputDir $outputDir
    $subscriptions = Get-AllSubscriptions
    
    if (-not $subscriptions -or $subscriptions.Count -eq 0) {
        Write-LogEntry -Message "No Azure subscriptions found or unable to retrieve subscriptions." -Level WARNING -OutputDir $outputDir
        return
    }
    
    # Format subscription data
    $formattedSubscriptions = Format-SubscriptionData -Subscriptions $subscriptions
    Write-LogEntry -Message "Retrieved $($subscriptions.Count) subscription(s)." -OutputDir $outputDir
    
    # Export to CSV
    $csvPath = Export-ToCsv -Data $formattedSubscriptions -OutputDir $outputDir -FileName "subscriptions"
    
    if ($csvPath) {
        # Display summary on console
        Write-Host "`nSubscription Summary:" -ForegroundColor Green
        $formattedSubscriptions | Format-Table -Property SubscriptionName, SubscriptionId, State -AutoSize
        
        Write-LogEntry -Message "Subscription data exported to CSV: $csvPath" -OutputDir $outputDir
        Write-LogEntry -Message "Azure Cost Estimation Tool completed successfully." -OutputDir $outputDir
    }
    else {
        Write-LogEntry -Message "Failed to export subscription data to CSV." -Level ERROR -OutputDir $outputDir
    }
}

# Execute the main function
Start-AzureCostEstimation
