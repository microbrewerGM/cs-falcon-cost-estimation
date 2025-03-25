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
        Retrieves Azure subscriptions based on environment type.
    
    .DESCRIPTION
        Gets Azure subscriptions appropriate for the detected environment type.
        For tenant environments, retrieves all accessible subscriptions.
        For standalone environments, uses only the current subscription.
        
    .OUTPUTS
        [object[]] Array of subscription objects or $null if failed.
    #>
    
    # Check if we're in a tenant environment (set by Connect-ToAzure)
    if ($Script:IsTenantEnvironment) {
        Write-Host "Operating in tenant environment - retrieving all available subscriptions..." -ForegroundColor Cyan
        
        try {
            # Get all subscriptions across all tenants the user has access to
            $subscriptions = Get-AzSubscription -ErrorAction Stop
            
            # If we successfully retrieved subscriptions, return them
            if ($subscriptions -and $subscriptions.Count -gt 0) {
                Write-Host "Successfully retrieved $($subscriptions.Count) subscription(s) from tenant." -ForegroundColor Green
                return $subscriptions
            }
            else {
                Write-Host "No subscriptions found in tenant. Falling back to current context." -ForegroundColor Yellow
                throw "No subscriptions found in tenant"
            }
        }
        catch {
            # Report the error as a warning
            Write-Warning "Failed to retrieve subscriptions from tenant: $_"
            
            # Fallback to current context if tenant query fails
            Write-Host "Tenant query failed. Falling back to current subscription context." -ForegroundColor Yellow
            return Get-CurrentSubscriptionOnly
        }
    }
    else {
        # In standalone environment, just use the current subscription
        Write-Host "Operating in standalone environment - using current subscription only." -ForegroundColor Cyan
        return Get-CurrentSubscriptionOnly
    }
}

function Get-CurrentSubscriptionOnly {
    <#
    .SYNOPSIS
        Gets only the current subscription context.
    
    .DESCRIPTION
        Helper function to retrieve only the current subscription from context.
        
    .OUTPUTS
        [object[]] Array containing only the current subscription or $null if failed.
    #>
    
    try {
        $context = Get-AzContext -ErrorAction Stop
        
        if ($context -and $context.Subscription) {
            # Create a subscription object from the current context
            $currentSub = [PSCustomObject]@{
                Name = $context.Subscription.Name
                Id = $context.Subscription.Id
                TenantId = $context.Tenant.Id
                State = "Enabled" # Assume enabled since we have a context
            }
            
            Write-Host "Successfully retrieved current subscription: $($currentSub.Name)" -ForegroundColor Green
            return @($currentSub)
        }
        else {
            Write-Error "No active Azure subscription context found."
            return $null
        }
    }
    catch {
        Write-Error "Failed to retrieve current subscription context: $_"
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
