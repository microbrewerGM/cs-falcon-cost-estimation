# Authentication Module for CrowdStrike Azure Cost Estimation Tool

# Simple function to initialize Azure connection
function Initialize-AzureConnection {
    Write-Log "Starting Azure login process..." -Level 'INFO' -Category 'Authentication'
    
    try {
        # Connect with Az PowerShell module
        Connect-AzAccount -ErrorAction Stop
        Write-Log "Successfully authenticated with Azure" -Level 'SUCCESS' -Category 'Authentication'
        return $true
    }
    catch {
        Write-Log "Authentication failed: $($_.Exception.Message)" -Level 'ERROR' -Category 'Authentication'
        return $false
    }
}

# Function to prompt user to select a subscription
function Select-AzureSubscription {
    param (
        [Parameter(Mandatory = $false)]
        [string]$DefaultId
    )

    if ($DefaultId) {
        $subscription = Get-AzSubscription -SubscriptionId $DefaultId -ErrorAction SilentlyContinue
        if ($subscription) {
            return $subscription
        }
        Write-Log "Specified default subscription $DefaultId not found or not accessible." -Level 'WARNING' -Category 'Subscription'
    }

    Write-Log "Please select a subscription to use as the default deployment subscription:" -Level 'INFO' -Category 'Subscription'
    $subscriptions = Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Enabled" }

    if ($null -eq $subscriptions -or $subscriptions.Count -eq 0) {
        Write-Log "No enabled subscriptions found. Please check your permissions." -Level 'ERROR' -Category 'Subscription'
        exit 1
    }

    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "[$i] $($subscriptions[$i].Name) ($($subscriptions[$i].Id))"
    }

    $validSelection = $false
    while (-not $validSelection) {
        $selection = Read-Host "Enter number [0-$($subscriptions.Count - 1)]"
        if ($selection -match '^\d+$' -and [int]$selection -ge 0 -and [int]$selection -lt $subscriptions.Count) {
            $validSelection = $true
        }
        else {
            Write-Host "Invalid selection. Please try again."
        }
    }

    return $subscriptions[[int]$selection]
}

# Export functions
Export-ModuleMember -Function Initialize-AzureConnection, Select-AzureSubscription
