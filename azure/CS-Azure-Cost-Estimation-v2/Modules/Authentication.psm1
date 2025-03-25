# Authentication Module for CrowdStrike Azure Cost Estimation Tool

# Function to verify required modules are installed
function Test-RequiredModules {
    [CmdletBinding()]
    param()
    
    $requiredModules = @(
        @{Name = "Az.Accounts"; Description = "Azure PowerShell core module"},
        @{Name = "Az.Resources"; Description = "Azure Resources module"},
        @{Name = "Az.Monitor"; Description = "Azure Monitor module for activity logs"},
        @{Name = "AzureAD"; Description = "Azure Active Directory module"; Optional = $true}
    )
    
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        $moduleExists = Get-Module -Name $module.Name -ListAvailable
        
        if (-not $moduleExists -and -not $module.Optional) {
            $missingModules += "$($module.Name) - $($module.Description)"
        }
        elseif (-not $moduleExists -and $module.Optional) {
            Write-Log "Optional module $($module.Name) not found. Some features may be limited." -Level 'WARNING' -Category 'ModuleCheck'
        }
        else {
            Write-Log "Found required module: $($module.Name)" -Level 'DEBUG' -Category 'ModuleCheck'
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Log "Missing required modules:" -Level 'ERROR' -Category 'ModuleCheck'
        foreach ($module in $missingModules) {
            Write-Log "  - $module" -Level 'ERROR' -Category 'ModuleCheck'
        }
        Write-Log "Please install missing modules using: Install-Module <ModuleName> -Scope CurrentUser" -Level 'ERROR' -Category 'ModuleCheck'
        return $false
    }
    
    return $true
}

# Initialize Azure connection
function Initialize-AzureConnection {
    [CmdletBinding()]
    param()
    
    Write-Log "Starting Azure login process..." -Level 'INFO' -Category 'Authentication'
    
    # First verify required modules are installed
    if (-not (Test-RequiredModules)) {
        Write-Log "Cannot proceed without required modules. Exiting." -Level 'ERROR' -Category 'Authentication'
        return $false
    }
    
    try {
        # Connect with Az PowerShell module
        Connect-AzAccount -ErrorAction Stop
        Write-Log "Successfully authenticated with Azure" -Level 'SUCCESS' -Category 'Authentication'
        
        # Check if AzureAD module is available and connect
        if (Get-Module -Name AzureAD -ListAvailable) {
            try {
                Write-Log "Connecting to Azure AD..." -Level 'INFO' -Category 'Authentication'
                Connect-AzureAD -ErrorAction Stop
                Write-Log "Successfully connected to Azure AD" -Level 'SUCCESS' -Category 'Authentication'
            }
            catch {
                Write-Log "Azure AD authentication failed: $($_.Exception.Message)" -Level 'WARNING' -Category 'Authentication'
                Write-Log "Some Azure AD-specific features may not be available" -Level 'WARNING' -Category 'Authentication'
            }
        }
        
        return $true
    }
    catch {
        Write-Log "Authentication failed: $($_.Exception.Message)" -Level 'ERROR' -Category 'Authentication'
        return $false
    }
}

# Function to prompt user to select a subscription
function Select-AzureSubscription {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$DefaultId
    )

    if ($DefaultId) {
        $subscription = Get-AzSubscription -SubscriptionId $DefaultId -ErrorAction SilentlyContinue
        if ($subscription) {
            Write-Log "Setting context to subscription: $($subscription.Name) ($($subscription.Id))" -Level 'INFO' -Category 'Subscription'
            Set-AzContext -Subscription $subscription.Id
            return $subscription
        }
        Write-Log "Specified default subscription $DefaultId not found or not accessible." -Level 'WARNING' -Category 'Subscription'
    }

    Write-Log "Please select a subscription to use for cost estimation:" -Level 'INFO' -Category 'Subscription'
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

    $selectedSubscription = $subscriptions[[int]$selection]
    Write-Log "Setting context to subscription: $($selectedSubscription.Name) ($($selectedSubscription.Id))" -Level 'INFO' -Category 'Subscription'
    Set-AzContext -Subscription $selectedSubscription.Id
    return $selectedSubscription
}

# Function to get Azure AD users (if AzureAD module is available)
function Get-EntraDirectoryUsers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MaxResults = 1000
    )
    
    # Check if AzureAD module is available
    if (-not (Get-Module -Name AzureAD -ListAvailable)) {
        Write-Log "AzureAD module not available. Cannot retrieve user information." -Level 'WARNING' -Category 'Authentication'
        return $null
    }
    
    try {
        Write-Log "Retrieving user information from Azure AD (limited to $MaxResults users)..." -Level 'INFO' -Category 'Authentication'
        $users = Get-AzureADUser -Top $MaxResults
        Write-Log "Successfully retrieved $($users.Count) users from Azure AD" -Level 'SUCCESS' -Category 'Authentication'
        return $users
    }
    catch {
        Write-Log "Failed to retrieve Azure AD users: $($_.Exception.Message)" -Level 'ERROR' -Category 'Authentication'
        return $null
    }
}

# Export functions
Export-ModuleMember -Function Initialize-AzureConnection, Select-AzureSubscription, Get-EntraDirectoryUsers, Test-RequiredModules
