# Authentication module for CrowdStrike Azure Cost Estimation Tool v3
# Uses browser-based authentication only for simplicity

# Function to initialize Azure connection
function Initialize-AzureConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId = $env:AZURE_TENANT_ID
    )
    
    Write-Log "Starting Azure login process..." -Level 'INFO' -Category 'Authentication'
    
    # Check if required Az modules are available
    $requiredModules = @(
        "Az.Accounts",
        "Az.Resources",
        "Az.Monitor"
    )
    
    $missingModules = @()
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -Name $module -ListAvailable)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Log "The following required modules are missing:" -Level 'ERROR' -Category 'Authentication'
        foreach ($module in $missingModules) {
            Write-Log "  - $module" -Level 'ERROR' -Category 'Authentication'
        }
        Write-Log "Install missing modules with: Install-Module <ModuleName> -Force" -Level 'ERROR' -Category 'Authentication'
        return $false
    }
    
    try {
        # First check if we're already connected
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if ($context) {
            Write-Log "Already connected to Azure as $($context.Account.Id) in tenant $($context.Tenant.Id)" -Level 'INFO' -Category 'Authentication'
            return $true
        }
        
        # Browser-based authentication
        Write-Log "Launching browser-based authentication..." -Level 'INFO' -Category 'Authentication'
        if ($TenantId) {
            Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null
        }
        else {
            Connect-AzAccount -ErrorAction Stop | Out-Null
        }
        
        Write-Log "Successfully authenticated through browser" -Level 'SUCCESS' -Category 'Authentication'
        return $true
    }
    catch {
        Write-Log "Authentication failed: $($_.Exception.Message)" -Level 'ERROR' -Category 'Authentication'
        return $false
    }
}

# Function to get active subscriptions
function Get-SubscriptionList {
    [CmdletBinding()]
    param()
    
    try {
        $subscriptions = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq "Enabled" }
        Write-Log "Retrieved $($subscriptions.Count) enabled subscriptions" -Level 'INFO' -Category 'Subscriptions'
        return $subscriptions
    }
    catch {
        Write-Log "Failed to retrieve subscriptions: $($_.Exception.Message)" -Level 'ERROR' -Category 'Subscriptions'
        return @()
    }
}

# Function to get Azure Entra ID tenant information
function Get-EntraIdInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$EstimatedUserCount = 500 # Default estimate if we can't get real data
    )
    
    $entraIdInfo = @{
        TenantId = $null
        TenantName = "Unknown"
        UserCount = $EstimatedUserCount
        OrganizationSize = "Small"  # Small, Medium, Large
    }
    
    try {
        # Get current context to get tenant ID
        $context = Get-AzContext -ErrorAction Stop
        if ($context) {
            $entraIdInfo.TenantId = $context.Tenant.Id
            
            # Try to get tenant details using Azure AD module if available
            if (Get-Module -Name AzureAD -ListAvailable) {
                try {
                    Import-Module AzureAD -ErrorAction SilentlyContinue
                    
                    # Check if already connected
                    $aadContext = Get-AzureADCurrentSessionInfo -ErrorAction SilentlyContinue
                    if (-not $aadContext) {
                        # Connect using current Az context credentials (no prompt)
                        Connect-AzureAD -TenantId $context.Tenant.Id -AccountId $context.Account.Id -ErrorAction SilentlyContinue | Out-Null
                    }
                    
                    # Get organization info
                    $orgInfo = Get-AzureADTenantDetail -ErrorAction Stop
                    if ($orgInfo) {
                        $entraIdInfo.TenantName = $orgInfo.DisplayName
                    }
                    
                    # Get user count (throttled to avoid long operations)
                    $userCount = 0
                    try {
                        # This is much faster than Get-AzureADUser -All $true
                        $userCountMetric = Get-AzureADUser -Top 1 -Count userCount -ErrorAction Stop
                        $userCount = $userCountMetric
                    }
                    catch {
                        # If that fails, try a small sample to estimate
                        $users = Get-AzureADUser -Top 10 -ErrorAction SilentlyContinue
                        if ($users -and $users.Count -gt 0) {
                            # Rough estimate based on object IDs
                            $idSegments = $users | ForEach-Object { [guid]$_.ObjectId } | ForEach-Object { $_.ToString().Substring(0, 8) }
                            $uniqueSegments = ($idSegments | Sort-Object -Unique).Count
                            $estimatedTotal = $users.Count * (2^32) / $uniqueSegments
                            $userCount = [math]::Min(1000000, [math]::Max(100, [math]::Round($estimatedTotal)))
                        }
                    }
                    
                    if ($userCount -gt 0) {
                        $entraIdInfo.UserCount = $userCount
                    }
                }
                catch {
                    Write-Log "Error getting Azure AD details: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
                }
            }
            else {
                # Try Microsoft Graph API
                if (Get-Module -Name Microsoft.Graph.Identity.DirectoryManagement -ListAvailable) {
                    try {
                        Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction SilentlyContinue
                        if (Get-Module -Name Microsoft.Graph.Users -ListAvailable) {
                            Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
                        }
                        
                        # Connect to Microsoft Graph
                        $mgContext = Get-MgContext -ErrorAction SilentlyContinue
                        if (-not $mgContext) {
                            Connect-MgGraph -TenantId $context.Tenant.Id -NoWelcome -ErrorAction SilentlyContinue | Out-Null
                        }
                        
                        # Get organization info
                        $org = Get-MgOrganization -ErrorAction Stop
                        if ($org) {
                            $entraIdInfo.TenantName = $org.DisplayName
                        }
                        
                        # Get user count
                        $users = Get-MgUser -Count userCount -ConsistencyLevel eventual -Property id -ErrorAction Stop
                        if ($users) {
                            $entraIdInfo.UserCount = $users.Count
                        }
                    }
                    catch {
                        Write-Log "Error getting Microsoft Graph details: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
                    }
                }
            }
        }
    }
    catch {
        Write-Log "Error determining Azure Entra ID info: $($_.Exception.Message)" -Level 'WARNING' -Category 'EntraID'
    }
    
    # Determine organization size based on user count
    if ($entraIdInfo.UserCount -lt 1000) {
        $entraIdInfo.OrganizationSize = "Small"
    }
    elseif ($entraIdInfo.UserCount -lt 10000) {
        $entraIdInfo.OrganizationSize = "Medium"
    }
    else {
        $entraIdInfo.OrganizationSize = "Large"
    }
    
    Write-Log "Entra ID Info: Tenant $($entraIdInfo.TenantName), Size: $($entraIdInfo.OrganizationSize), Users: $($entraIdInfo.UserCount)" -Level 'INFO' -Category 'EntraID'
    
    return $entraIdInfo
}

# Export functions
Export-ModuleMember -Function Initialize-AzureConnection, Get-SubscriptionList, Get-EntraIdInfo
