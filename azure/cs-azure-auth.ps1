#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Azure authentication module.

.DESCRIPTION
    This PowerShell module handles Azure authentication functionality.
#>

function Confirm-AzModules {
    <#
    .SYNOPSIS
        Confirms that required Az modules are installed.
    
    .DESCRIPTION
        Checks if the Az.Accounts module is installed and available.
        
    .OUTPUTS
        [bool] True if modules are installed, False otherwise.
    #>
    
    if (-not (Get-Module -Name Az.Accounts -ListAvailable)) {
        Write-Error "The Az.Accounts module is not installed. Please install it using: Install-Module -Name Az -Force -AllowClobber"
        return $false
    }
    
    return $true
}

function Connect-ToAzure {
    <#
    .SYNOPSIS
        Connects to Azure using interactive login.
    
    .DESCRIPTION
        Initiates a standard interactive Azure login process.
        Detects if a subscription is part of a larger tenant or standalone.
        
    .OUTPUTS
        [bool] True if login was successful, False otherwise.
        
    .NOTES
        Sets $Script:IsTenantEnvironment to indicate if the subscription is part of a tenant.
    #>
    
    # Set default tenant status to false (assume standalone until proven otherwise)
    $Script:IsTenantEnvironment = $false
    
    try {
        # Log into Azure interactively with standard authentication
        Write-Host "Initiating Azure login..." -ForegroundColor Cyan
        $loginResult = Connect-AzAccount -ErrorAction Stop
        
        # Verify we have a valid context
        $context = Get-AzContext
        if ($null -eq $context -or $null -eq $context.Subscription) {
            throw "Authentication succeeded but no valid subscription context was established."
        }
        
        Write-Host "Successfully authenticated as: $($context.Account.Id)" -ForegroundColor Green
        Write-Host "Current subscription context: $($context.Subscription.Name)" -ForegroundColor Green
        
        # Always assume we're in a tenant environment unless explicitly proven otherwise
        # This ensures we'll try to get all subscriptions by default
        $Script:IsTenantEnvironment = $true
        
        try {
            # Check tenant information
            $tenants = Get-AzTenant -ErrorAction Stop
            
            # Log tenant detection information
            if ($tenants -and $tenants.Count -gt 0) {
                if ($tenants.Count -gt 1) {
                    Write-Host "Detected multiple tenants ($($tenants.Count)). This is an organizational tenant environment." -ForegroundColor Cyan
                    
                    # Log tenant information
                    $tenants | Select-Object Id, Name, DefaultDomain | Format-Table -AutoSize
                } else {
                    Write-Host "Detected single tenant ($($tenants[0].Name)) with ID: $($tenants[0].Id)" -ForegroundColor Cyan
                    Write-Host "Will still attempt to retrieve all subscriptions within this tenant." -ForegroundColor Cyan
                }
            }
        }
        catch {
            Write-Host "Unable to query tenant information, but will still attempt to retrieve all accessible subscriptions." -ForegroundColor Yellow
            Write-Host "Error details: $_" -ForegroundColor DarkGray
        }
        
        return $true
    }
    catch {
        # Try to get current context - if we have one, we can proceed even if tenant-level auth failed
        try {
            $context = Get-AzContext -ErrorAction Stop
            if ($null -ne $context -and $null -ne $context.Subscription) {
                Write-Host "Initial authentication failed, but found existing context." -ForegroundColor Yellow
                Write-Host "Using current subscription context: $($context.Subscription.Name)" -ForegroundColor Yellow
                
                # Always assume we're in a tenant environment unless explicitly proven otherwise
                $Script:IsTenantEnvironment = $true
                Write-Host "Will attempt to retrieve all accessible subscriptions." -ForegroundColor Cyan
                
                return $true
            }
        }
        catch {
            # No context available, continue with error flow
        }
        
        Write-Error "Failed to log into Azure: $_"
        
        # If there's a tenant-specific issue, provide clear error message
        if ($_.Exception.Message -like "*Authentication failed against tenant*" -or 
            $_.Exception.Message -like "*multi-factor authentication*") {
            Write-Host "Authentication error detected. This may be due to tenant-specific requirements." -ForegroundColor Yellow
            Write-Host "Please ensure you complete any MFA prompts if requested." -ForegroundColor Yellow
        }
        
        return $false
    }
}

# Functions are exposed via dot-sourcing
