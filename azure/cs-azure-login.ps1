#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    [DEPRECATED] Logs into Azure and retrieves all subscriptions in the tenant.

.DESCRIPTION
    This PowerShell script has been replaced by the modular architecture.
    Please use cs-azure-main.ps1 instead.

.NOTES
    File Name  : cs-azure-login.ps1
    Author     : CrowdStrike
    Status     : Deprecated
    Requires   : PowerShell 5.1 or later
                 Az PowerShell modules
#>

Write-Warning "This script has been deprecated. Please use cs-azure-main.ps1 instead."
exit

# The code below is kept for reference purposes only

# Check if the Az module is installed
if (-not (Get-Module -Name Az.Accounts -ListAvailable)) {
    Write-Error "The Az.Accounts module is not installed. Please install it using: Install-Module -Name Az -Force -AllowClobber"
    exit 1
}

function Connect-ToAzure {
    try {
        # Log into Azure interactively
        Write-Host "Initiating Azure login..." -ForegroundColor Cyan
        Connect-AzAccount -ErrorAction Stop
        
        return $true
    }
    catch {
        Write-Error "Failed to log into Azure: $_"
        return $false
    }
}

function Get-AllSubscriptions {
    try {
        # Get all subscriptions the user has access to
        Write-Host "Retrieving subscriptions..." -ForegroundColor Cyan
        $subscriptions = Get-AzSubscription -ErrorAction Stop
        
        return $subscriptions
    }
    catch {
        Write-Error "Failed to retrieve subscriptions: $_"
        return $null
    }
}

function Show-SubscriptionDetails {
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Subscriptions
    )
    
    if ($Subscriptions.Count -eq 0) {
        Write-Host "No subscriptions found." -ForegroundColor Yellow
        return
    }
    
    Write-Host "`nFound $($Subscriptions.Count) subscription(s):" -ForegroundColor Green
    
    # Create a table format
    $Subscriptions | Format-Table -Property Name, Id, TenantId, State -AutoSize
}

# Main script execution
$loginSuccessful = Connect-ToAzure

if ($loginSuccessful) {
    $subscriptions = Get-AllSubscriptions
    
    if ($subscriptions) {
        Show-SubscriptionDetails -Subscriptions $subscriptions
    }
}
