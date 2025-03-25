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
        Simply reports any errors if they occur.
        
    .OUTPUTS
        [bool] True if login was successful, False otherwise.
    #>
    
    try {
        # Log into Azure interactively
        Write-Host "Initiating Azure login..." -ForegroundColor Cyan
        
        # Standard Azure login with browser-based authentication
        Connect-AzAccount -ErrorAction Stop
        
        return $true
    }
    catch {
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
