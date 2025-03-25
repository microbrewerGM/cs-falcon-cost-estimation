#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Azure subscription operations module.

.DESCRIPTION
    This PowerShell module handles Azure subscription-related operations
    including retrieving subscription information.
#>

function Get-AllSubscriptions {
    <#
    .SYNOPSIS
        Retrieves all Azure subscriptions.
    
    .DESCRIPTION
        Gets all Azure subscriptions the authenticated user has access to.
        
    .OUTPUTS
        [object[]] Array of subscription objects or $null if failed.
    #>
    
    try {
        # Get all subscriptions the user has access to
        Write-Host "Retrieving subscriptions..." -ForegroundColor Cyan
        $subscriptions = Get-AzSubscription -ErrorAction Stop
        
        return $subscriptions
    }
    catch {
        # Report the error clearly
        Write-Error "Failed to retrieve subscriptions: $_"
        
        # If there's a tenant-specific issue, provide additional information
        if ($_.Exception.Message -like "*tenant*" -or 
            $_.Exception.Message -like "*multi-factor authentication*") {
            Write-Host "Subscription retrieval error may be related to tenant configuration." -ForegroundColor Yellow
            Write-Host "Make sure you have access to the subscriptions with your account." -ForegroundColor Yellow
        }
        
        return $null
    }
}

function Format-SubscriptionData {
    <#
    .SYNOPSIS
        Formats subscription data for output.
    
    .DESCRIPTION
        Takes subscription objects and formats them into a standardized structure
        for consistent output.
        
    .PARAMETER Subscriptions
        Array of Azure subscription objects.
        
    .OUTPUTS
        [PSCustomObject[]] Array of formatted subscription data.
    #>
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$Subscriptions
    )
    
    $formattedData = @()
    
    foreach ($sub in $Subscriptions) {
        $formattedData += [PSCustomObject]@{
            SubscriptionName = $sub.Name
            SubscriptionId = $sub.Id
            TenantId = $sub.TenantId
            State = $sub.State
            RetrievedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
    
    return $formattedData
}

# Functions are exposed via dot-sourcing
