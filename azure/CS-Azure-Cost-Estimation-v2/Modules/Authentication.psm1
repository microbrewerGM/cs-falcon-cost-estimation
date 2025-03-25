# Authentication Module for CrowdStrike Azure Cost Estimation Tool

# Import required modules
Import-Module "$PSScriptRoot\Logging.psm1" -Force

# Function to initialize Azure connection with enhanced error handling
function Initialize-AzureConnection {
    Write-Log "Checking for required Azure modules..." -Level 'INFO' -Category 'Setup'
    
    # Check for Az PowerShell module with specific version requirements
    $requiredModules = @(
        @{Name = "Az.Accounts"; MinVersion = "2.5.0"},
        @{Name = "Az.Resources"; MinVersion = "5.0.0"},
        @{Name = "Az.Monitor"; MinVersion = "3.0.0"}
    )
    
    $modulesNeedingUpdate = @()
    
    foreach ($module in $requiredModules) {
        $installedModule = Get-Module -ListAvailable -Name $module.Name | Sort-Object Version -Descending | Select-Object -First 1
        
        if (-not $installedModule) {
            Write-Log "$($module.Name) module not found. Please install it using: Install-Module -Name $($module.Name) -AllowClobber -Scope CurrentUser" -Level 'ERROR' -Category 'Setup'
            return $false
        }
        
        if ([version]$installedModule.Version -lt [version]$module.MinVersion) {
            $modulesNeedingUpdate += "$($module.Name) (current: $($installedModule.Version), required: $($module.MinVersion))"
        }
    }
    
    if ($modulesNeedingUpdate.Count -gt 0) {
        Write-Log "Some modules need to be updated: $($modulesNeedingUpdate -join ', ')" -Level 'WARNING' -Category 'Setup'
        Write-Log "You can update modules using: Update-Module -Name [ModuleName]" -Level 'WARNING' -Category 'Setup'
    }
    
    # Check for Azure CLI
    try {
        $azVersion = & az version
        Write-Log "Azure CLI found. Version information: $azVersion" -Level 'INFO' -Category 'Setup'
    }
    catch {
        Write-Log "Azure CLI not found or not in PATH. Please install Azure CLI from https://docs.microsoft.com/cli/azure/install-azure-cli" -Level 'ERROR' -Category 'Setup'
        return $false
    }
    
    # Prompt for Azure login
    Write-Log "Initiating Azure login process..." -Level 'INFO' -Category 'Authentication'
    Write-Host "`nPlease log in to your Azure account. A browser window will open for authentication.`n" -ForegroundColor Yellow
    
    $azLoginResult = Test-CommandSuccess -Command { 
        & az login 
    } -ErrorMessage "Failed to login to Azure" -ContinueOnError -Category 'Authentication'
    
    $azLoginSuccess = $azLoginResult.Success
    
    # Connect with Az PowerShell module
    $azPowerShellResult = Test-CommandSuccess -Command { 
        Connect-AzAccount 
    } -ErrorMessage "Failed to connect using Az PowerShell module" -ContinueOnError -Category 'Authentication'
    
    $azPowerShellSuccess = $azPowerShellResult.Success
    
    if (-not $azLoginSuccess -and -not $azPowerShellSuccess) {
        Write-Log "Failed to authenticate with Azure. Cannot proceed." -Level 'ERROR' -Category 'Authentication'
        return $false
    }
    
    if (-not $azLoginSuccess) {
        Write-Log "Unable to authenticate with Azure CLI. Some functionality may be limited." -Level 'WARNING' -Category 'Authentication'
    }
    else {
        Write-Log "Successfully authenticated with Azure CLI" -Level 'SUCCESS' -Category 'Authentication'
    }
    
    if (-not $azPowerShellSuccess) {
        Write-Log "Unable to authenticate with Az PowerShell module. Some functionality may be limited." -Level 'WARNING' -Category 'Authentication'
    }
    else {
        Write-Log "Successfully authenticated with Az PowerShell module" -Level 'SUCCESS' -Category 'Authentication'
    }
    
    # If requested, try to connect to Azure AD for Entra ID logs
    try {
        # Import the module first if not already available
        if (-not (Get-Module -ListAvailable -Name AzureAD)) {
            Write-Log "AzureAD module not found. Some Entra ID log analysis will be limited." -Level 'WARNING' -Category 'Authentication'
        }
        else {
            Import-Module AzureAD -ErrorAction SilentlyContinue
            Connect-AzureAD -ErrorAction Stop | Out-Null
            Write-Log "Successfully connected to Azure AD" -Level 'SUCCESS' -Category 'Authentication'
        }
    }
    catch {
        Write-Log "Unable to connect to Azure AD. Entra ID log analysis will be limited: $($_.Exception.Message)" -Level 'WARNING' -Category 'Authentication'
    }
    
    return $true
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
