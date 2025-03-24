<#
.SYNOPSIS
CrowdStrike Azure Cost Estimation Tool

.DESCRIPTION
This script estimates the costs of deploying CrowdStrike Falcon Cloud Security integration in Azure.
It analyzes subscription data, activity logs, Entra ID logs, and resource counts to provide
cost estimates for the deployment based on the official CrowdStrike Bicep templates.

.PARAMETER DaysToAnalyze
Number of days of logs to analyze. Default is 7.

.PARAMETER DefaultSubscriptionId
The subscription ID where CrowdStrike resources will be deployed. If not specified, the script
will prompt for selection.

.PARAMETER OutputDirectory
Path to the directory where output files will be saved. Default is "cs-azure-cost-estimate-<timestamp>" in the current directory.

.PARAMETER OutputFilePath
Path to the CSV output file. Default is "<OutputDirectory>/cs-azure-cost-estimate.csv".

.PARAMETER LogFilePath
Path to the log file. Default is "<OutputDirectory>/cs-azure-cost-estimate.log".

.EXAMPLE
.\cs-azure-cost-estimation.ps1 -DaysToAnalyze 14

.NOTES
Requires Azure PowerShell module and appropriate permissions to query:
- Subscriptions
- Activity Logs
- Entra ID logs (requires Global Reader, Security Reader, or higher permissions)
- Resource information
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$DaysToAnalyze = 7,

    [Parameter(Mandatory = $false)]
    [string]$DefaultSubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = "",

    [Parameter(Mandatory = $false)]
    [string]$OutputFilePath = "",

    [Parameter(Mandatory = $false)]
    [string]$LogFilePath = ""
)

# Create timestamped output directory if not specified
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = "cs-azure-cost-estimate-$timestamp"
}

# Create the output directory if it doesn't exist
if (-not (Test-Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    Write-Host "Created output directory: $OutputDirectory" -ForegroundColor Green
}

# Create a subdirectory for subscription data files
$SubscriptionDataDir = Join-Path $OutputDirectory "subscription-data"
if (-not (Test-Path $SubscriptionDataDir)) {
    New-Item -Path $SubscriptionDataDir -ItemType Directory -Force | Out-Null
    Write-Host "Created subscription data directory: $SubscriptionDataDir" -ForegroundColor Green
}

# Set default file paths if not specified
if ([string]::IsNullOrWhiteSpace($OutputFilePath)) {
    $OutputFilePath = Join-Path $OutputDirectory "cs-azure-cost-estimate.csv"
}

if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
    $LogFilePath = Join-Path $OutputDirectory "cs-azure-cost-estimate.log"
}

# Path for the summary JSON file and status file
$SummaryJsonPath = Join-Path $OutputDirectory "summary.json"
$StatusFilePath = Join-Path $OutputDirectory "script-status.json"

# Function to write to log file
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $LogFilePath -Value $logMessage -ErrorAction SilentlyContinue
    
    # Also write to console with color
    switch ($Level) {
        'INFO' { Write-Host $logMessage -ForegroundColor Cyan }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'ERROR' { Write-Host $logMessage -ForegroundColor Red }
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
    }
}

# Function to check if a command executed successfully
function Test-CommandSuccess {
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [switch]$ContinueOnError
    )
    
    try {
        & $Command
        return $true
    }
    catch {
        if ($ContinueOnError) {
            Write-Log "$ErrorMessage - $($_.Exception.Message)" -Level 'WARNING'
            return $false
        }
        else {
            Write-Log "$ErrorMessage - $($_.Exception.Message)" -Level 'ERROR'
            throw
        }
    }
}

# Function to show progress
function Show-Progress {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Activity,
        
        [Parameter(Mandatory = $true)]
        [int]$PercentComplete,
        
        [Parameter(Mandatory = $false)]
        [string]$Status = ""
    )
    
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    Write-Log "$Activity - $Status ($PercentComplete%)" -Level 'INFO'
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
        Write-Log "Specified default subscription $DefaultId not found or not accessible." -Level 'WARNING'
    }
    
    Write-Log "Please select a subscription to use as the default deployment subscription:" -Level 'INFO'
    $subscriptions = Get-AzSubscription -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Enabled" }
    
    if ($null -eq $subscriptions -or $subscriptions.Count -eq 0) {
        Write-Log "No enabled subscriptions found. Please check your permissions." -Level 'ERROR'
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

# Function to get regional pricing information
function Get-RegionPricing {
    # This is a simplified pricing model. In a production environment, you would
    # query the Azure Retail Prices API or maintain an up-to-date pricing table.
    $pricing = @{
        "eastus" = @{
            EventHubTU = 20.73  # $/TU/month
            StorageGB = 0.0184  # $/GB/month
            FunctionAppP0V3 = 56.58  # $/instance/month
            KeyVault = 0.03 # $/10,000 operations
            PrivateEndpoint = 0.01 # $/hour
            VnetGateway = 0.30 # $/hour
        }
        "westus" = @{
            EventHubTU = 20.73  # $/TU/month
            StorageGB = 0.0184  # $/GB/month
            FunctionAppP0V3 = 56.58  # $/instance/month
            KeyVault = 0.03 # $/10,000 operations
            PrivateEndpoint = 0.01 # $/hour
            VnetGateway = 0.30 # $/hour
        }
        "centralus" = @{
            EventHubTU = 19.72  # $/TU/month
            StorageGB = 0.0177  # $/GB/month
            FunctionAppP0V3 = 53.75  # $/instance/month
            KeyVault = 0.03 # $/10,000 operations
            PrivateEndpoint = 0.01 # $/hour
            VnetGateway = 0.29 # $/hour
        }
        "default" = @{
            EventHubTU = 22.00  # $/TU/month (higher estimate for unknown regions)
            StorageGB = 0.02  # $/GB/month
            FunctionAppP0V3 = 60.00  # $/instance/month
            KeyVault = 0.03 # $/10,000 operations
            PrivateEndpoint = 0.01 # $/hour
            VnetGateway = 0.32 # $/hour
        }
    }
    
    return $pricing
}

# Function to get pricing for a specific region
function Get-PricingForRegion {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Region,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$PricingData
    )
    
    $regionKey = $Region.ToLower()
    if ($PricingData.ContainsKey($regionKey)) {
        return $PricingData[$regionKey]
    }
    else {
        Write-Log "No specific pricing found for region $Region. Using default pricing." -Level 'WARNING'
        return $PricingData["default"]
    }
}

# Function to estimate costs for CrowdStrike resources in a subscription
function Get-CrowdStrikeResourceCost {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SubscriptionData,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Pricing,
        
        [Parameter(Mandatory = $false)]
        [bool]$IsDefaultSubscription = $false
    )
    
    $costs = @{}
    
    # Only calculate resource costs for the default subscription
    if ($IsDefaultSubscription) {
        # Event Hub costs
        $eventHubTUs = $SubscriptionData.EstimatedEventHubTUs
        $eventHubCost = $eventHubTUs * $Pricing.EventHubTU
        $costs["Event Hub Namespace"] = @{
            Count = 1
            UnitPrice = $Pricing.EventHubTU
            UnitType = "Throughput Units x Month"
            Units = $eventHubTUs
            MonthlyCost = $eventHubCost
        }
        
        # Storage costs
        $storageCost = $SubscriptionData.EstimatedStorageGB * $Pricing.StorageGB
        $costs["Storage Accounts"] = @{
            Count = 3
            UnitPrice = $Pricing.StorageGB
            UnitType = "GB x Month"
            Units = $SubscriptionData.EstimatedStorageGB
            MonthlyCost = $storageCost
        }
        
        # Function App costs
        $functionAppInstances = $SubscriptionData.EstimatedFunctionAppInstances
        $functionAppCost = $functionAppInstances * $Pricing.FunctionAppP0V3 * 2  # 2 function apps
        $costs["Function Apps"] = @{
            Count = 2
            UnitPrice = $Pricing.FunctionAppP0V3
            UnitType = "Instance x Month"
            Units = $functionAppInstances
            MonthlyCost = $functionAppCost
        }
        
        # Key Vault costs - assuming 100,000 operations per month
        $keyVaultCost = 10 * $Pricing.KeyVault  # 10 x 10,000 operations
        $costs["Key Vault"] = @{
            Count = 1
            UnitPrice = $Pricing.KeyVault
            UnitType = "10,000 Operations"
            Units = 10
            MonthlyCost = $keyVaultCost
        }
        
        # Private Endpoint costs
        $privateEndpointCount = 4  # From the resource template
        $privateEndpointCost = $privateEndpointCount * $Pricing.PrivateEndpoint * 730  # 730 hours per month
        $costs["Private Endpoints"] = @{
            Count = $privateEndpointCount
            UnitPrice = $Pricing.PrivateEndpoint
            UnitType = "Hour"
            Units = 730
            MonthlyCost = $privateEndpointCost
        }
        
        # Network costs - VNET is free, but we'll add NSG and other components
        $networkCost = 30  # Estimate for NSG, IP addresses, etc.
        $costs["Networking"] = @{
            Count = 1
            UnitPrice = 30
            UnitType = "Fixed Cost"
            Units = 1
            MonthlyCost = $networkCost
        }
    }
    else {
        # Non-default subscriptions only have diagnostic settings - no direct Azure cost
        # However, there might be indirect costs like data processing
        $costs["Diagnostic Settings"] = @{
            Count = 1
            UnitPrice = 0
            UnitType = "N/A"
            Units = 0
            MonthlyCost = 0
        }
    }
    
    return $costs
}

# Start script execution
$startTime = Get-Date
$scriptSuccess = $true

# Create the log file
if (-not (Test-Path $LogFilePath)) {
    New-Item -Path $LogFilePath -ItemType File -Force | Out-Null
}

# Log script start
Write-Log "CrowdStrike Azure Cost Estimation Tool started" -Level 'INFO'
Write-Log "Parameters: DaysToAnalyze=$DaysToAnalyze, OutputFilePath=$OutputFilePath, LogFilePath=$LogFilePath" -Level 'INFO'

# Check for Az PowerShell module
if (-not (Get-Module -ListAvailable Az.Accounts)) {
    Write-Log "Azure PowerShell module not found. Please install it using: Install-Module -Name Az -AllowClobber -Scope CurrentUser" -Level 'ERROR'
    exit 1
}

# Ensure we have Azure CLI installed
try {
    $azVersion = & az version
    Write-Log "Azure CLI found. Version information: $azVersion" -Level 'INFO'
}
catch {
    Write-Log "Azure CLI not found or not in PATH. Please install Azure CLI from https://docs.microsoft.com/cli/azure/install-azure-cli" -Level 'ERROR'
    exit 1
}

# Prompt for Azure login
Write-Log "Initiating Azure login process..." -Level 'INFO'
Write-Host "`nPlease log in to your Azure account. A browser window will open for authentication.`n" -ForegroundColor Yellow

$azLoginSuccess = Test-CommandSuccess -Command { 
    & az login 
} -ErrorMessage "Failed to login to Azure" -ContinueOnError

if (-not $azLoginSuccess) {
    Write-Log "Unable to authenticate with Azure. Attempting to continue with limited functionality." -Level 'WARNING'
    $scriptSuccess = $false
}
else {
    Write-Log "Successfully authenticated with Azure CLI" -Level 'SUCCESS'
}

# Connect with Az PowerShell module
$azPowerShellSuccess = Test-CommandSuccess -Command { 
    Connect-AzAccount 
} -ErrorMessage "Failed to connect using Az PowerShell module" -ContinueOnError

if (-not $azPowerShellSuccess) {
    Write-Log "Unable to authenticate with Az PowerShell module. Attempting to continue with limited functionality." -Level 'WARNING'
    $scriptSuccess = $false
}
else {
    Write-Log "Successfully authenticated with Az PowerShell module" -Level 'SUCCESS'
}

# Initialize results array
$results = @()

# Get all subscriptions
Show-Progress -Activity "Collecting data" -PercentComplete 5 -Status "Getting subscriptions"
$subscriptionsSuccess = $false
$subscriptions = @()

try {
    $subscriptions = Get-AzSubscription -ErrorAction Stop | Where-Object { $_.State -eq "Enabled" }
    if ($subscriptions.Count -gt 0) {
        $subscriptionsSuccess = $true
        Write-Log "Found $($subscriptions.Count) enabled subscriptions" -Level 'SUCCESS'
    }
    else {
        Write-Log "No enabled subscriptions found. Please check your permissions." -Level 'WARNING'
    }
}
catch {
    Write-Log "Error retrieving subscriptions: $($_.Exception.Message)" -Level 'WARNING'
}

# If we failed to get subscriptions via Az, try using Azure CLI
if (-not $subscriptionsSuccess) {
    try {
        $subscriptionsJson = & az account list --query "[?state=='Enabled']" | ConvertFrom-Json
        if ($subscriptionsJson.Count -gt 0) {
            $subscriptions = $subscriptionsJson | ForEach-Object {
                [PSCustomObject]@{
                    Id = $_.id
                    Name = $_.name
                    State = 'Enabled'
                }
            }
            $subscriptionsSuccess = $true
            Write-Log "Found $($subscriptions.Count) enabled subscriptions using Azure CLI" -Level 'SUCCESS'
        }
        else {
            Write-Log "No enabled subscriptions found using Azure CLI. Please check your permissions." -Level 'WARNING'
        }
    }
    catch {
        Write-Log "Error retrieving subscriptions using Azure CLI: $($_.Exception.Message)" -Level 'ERROR'
        exit 1
    }
}

# Select default subscription if not provided
if (-not $DefaultSubscriptionId) {
    $defaultSubscription = Select-AzureSubscription
    $DefaultSubscriptionId = $defaultSubscription.Id
    Write-Log "Selected default subscription: $($defaultSubscription.Name) ($DefaultSubscriptionId)" -Level 'INFO'
}
else {
    $defaultSubscription = $subscriptions | Where-Object { $_.Id -eq $DefaultSubscriptionId }
    if (-not $defaultSubscription) {
        Write-Log "Specified default subscription $DefaultSubscriptionId not found or not accessible. Please select another." -Level 'WARNING'
        $defaultSubscription = Select-AzureSubscription
        $DefaultSubscriptionId = $defaultSubscription.Id
    }
    Write-Log "Using default subscription: $($defaultSubscription.Name) ($DefaultSubscriptionId)" -Level 'INFO'
}

# Get regional pricing information
$regionPricing = Get-RegionPricing

# Process each subscription
$totalSubscriptions = $subscriptions.Count
$currentSubscription = 0

foreach ($subscription in $subscriptions) {
    $currentSubscription++
    $subscriptionId = $subscription.Id
    $isDefaultSubscription = ($subscriptionId -eq $DefaultSubscriptionId)
    $percentComplete = [math]::Floor(($currentSubscription / $totalSubscriptions) * 90) + 5
    
    Show-Progress -Activity "Processing subscription" -PercentComplete $percentComplete -Status "$($subscription.Name) ($currentSubscription of $totalSubscriptions)"
    
    Write-Log "Processing subscription: $($subscription.Name) ($subscriptionId)" -Level 'INFO'
    
    # Set context to current subscription
    $contextSet = $false
    try {
        Set-AzContext -Subscription $subscriptionId -ErrorAction Stop | Out-Null
        $contextSet = $true
        Write-Log "Successfully set context to subscription $($subscription.Name)" -Level 'INFO'
    }
    catch {
        Write-Log "Failed to set context to subscription $($subscription.Name): $($_.Exception.Message)" -Level 'WARNING'
    }
    
    # Initialize subscription data object
    $subscriptionData = [PSCustomObject]@{
        SubscriptionId = $subscriptionId
        SubscriptionName = $subscription.Name
        Region = ""
        BusinessUnit = ""  # Placeholder for manual mapping
        ActivityLogCount = 0
        ResourceCount = 0
        DailyAverage = 0
        EstimatedEventHubTUs = 0
        EstimatedStorageGB = 0
        EstimatedDailyEventHubIngress = 0
        EstimatedDailyEventCount = 0
        EstimatedFunctionAppInstances = 0
        CostDetails = @{}
        EstimatedMonthlyCost = 0
    }
    
    # Get subscription region
    if ($contextSet) {
        try {
            $resourceGroups = Get-AzResourceGroup -ErrorAction Stop
            $locations = $resourceGroups | Select-Object -ExpandProperty Location | Sort-Object -Unique
            $subscriptionData.Region = $locations -join ','
            
            if ([string]::IsNullOrWhiteSpace($subscriptionData.Region)) {
                $subscriptionData.Region = "unknown"
            }
            
            Write-Log "Subscription regions: $($subscriptionData.Region)" -Level 'INFO'
        }
        catch {
            Write-Log "Failed to get resource groups for subscription $($subscription.Name): $($_.Exception.Message)" -Level 'WARNING'
            $subscriptionData.Region = "unknown"
        }
    }
    else {
        # Try with Azure CLI
        try {
            $locationJson = & az account list-locations --query "[].name" | ConvertFrom-Json
            if ($locationJson -and $locationJson.Count -gt 0) {
                $subscriptionData.Region = $locationJson[0]  # Default to first available region
            }
            else {
                $subscriptionData.Region = "eastus"  # Default if can't determine
            }
        }
        catch {
            $subscriptionData.Region = "eastus"  # Default if command fails
            Write-Log "Failed to get locations using Azure CLI: $($_.Exception.Message)" -Level 'WARNING'
        }
    }
    
    # Get Activity Log count for time period
    if ($contextSet) {
        $startTime = (Get-Date).AddDays(-$DaysToAnalyze)
        $endTime = Get-Date
        
        try {
            # This might fail due to permissions, but we'll continue
            # Use Az REST API instead of the deprecated Get-AzActivityLog cmdlet
            # Implement paging to handle more than 1000 results (the default page size)
            
            $activityLogs = @()
            $pageCount = 0
            $totalLogsRetrieved = 0
            $filter = "eventTimestamp ge '${startTime}' and eventTimestamp le '${endTime}'"
            $skipToken = $null
            
            Write-Log "Starting activity log retrieval for subscription $($subscription.Name)" -Level 'INFO'
            Write-Log "Time range: $startTime to $endTime" -Level 'INFO'
            
            # First, try to get an estimate of total logs (API may not support count)
            try {
                $estimateUri = "/subscriptions/$subscriptionId/providers/Microsoft.Insights/eventtypes/management/values?api-version=2017-03-01-preview&`$filter=$filter&`$top=1"
                $estimateResponse = Invoke-AzRestMethod -Method GET -Path $estimateUri -ErrorAction Stop
                
                if ($estimateResponse.StatusCode -eq 200) {
                    $estimateContent = $estimateResponse.Content | ConvertFrom-Json
                    if ($estimateContent.nextLink -and $estimateContent.nextLink -match "skipToken") {
                        Write-Log "Activity log query will require multiple pages (default page size is ~1000 records)" -Level 'INFO'
                    }
                }
            }
            catch {
                Write-Log "Could not determine total log count: $($_.Exception.Message)" -Level 'WARNING'
            }
            
            do {
                $pageCount++
                
                # Build the request URL with proper paging
                $apiVersion = "2017-03-01-preview"
                $requestURI = "/subscriptions/$subscriptionId/providers/Microsoft.Insights/eventtypes/management/values?api-version=$apiVersion&`$filter=$filter"
                
                # Add skipToken for pagination if it exists
                if ($skipToken) {
                    $requestURI += "&`$skipToken=$skipToken"
                }
                
                try {
                    Write-Log "Retrieving activity logs page $pageCount..." -Level 'INFO'
                    
                    # Make the REST API call
                    $response = Invoke-AzRestMethod -Method GET -Path $requestURI -ErrorAction Stop
                    
                    # Check if the call was successful
                    if ($response.StatusCode -eq 200) {
                        $responseContent = $response.Content | ConvertFrom-Json
                        
                        if ($responseContent.value) {
                            $logsPage = $responseContent.value
                            $activityLogs += $logsPage
                            $totalLogsRetrieved += $logsPage.Count
                            
                            # Log page details with operation types breakdown
                            $operationTypes = $logsPage | Group-Object -Property OperationName | 
                                              Select-Object Name, Count | Sort-Object -Property Count -Descending
                            
                            $topOperations = $operationTypes | Select-Object -First 3
                            $topOperationsText = ($topOperations | ForEach-Object { "$($_.Name): $($_.Count)" }) -join ", "
                            
                            Write-Log "Page ${pageCount}: Retrieved $($logsPage.Count) activity logs (Total: $totalLogsRetrieved)" -Level 'INFO'
                            Write-Log "  Top operations: ${topOperationsText}" -Level 'INFO'
                            
                            # Get the skipToken for the next page, if present
                            $skipToken = $responseContent.nextLink
                            if ($skipToken) {
                                # Extract the skipToken from the nextLink URL
                                if ($skipToken -match "\`$skipToken=([^&]+)") {
                                    $skipToken = $Matches[1]
                                }
                                else {
                                    $skipToken = $null
                                }
                            }
                        }
                        else {
                            $logsPage = @()
                        }
                    }
                    else {
                        Write-Log "Failed to retrieve activity logs: StatusCode $($response.StatusCode)" -Level 'WARNING'
                        break
                    }
                }
                catch {
                    Write-Log "Error calling Azure REST API: $($_.Exception.Message)" -Level 'WARNING'
                    break
                }
                
                # Continue until we don't have any more logs or a skipToken
            } while ($logsPage.Count -gt 0 -and $skipToken)
            
            $activityLogCount = $activityLogs.Count
            $subscriptionData.ActivityLogCount = $activityLogCount
            
            # Calculate daily average
            $subscriptionData.DailyAverage = [math]::Round($activityLogCount /, $DaysToAnalyze, 2)
            
            Write-Log "Total activity log count: $activityLogCount, Daily average: $($subscriptionData.DailyAverage)" -Level 'INFO'
        }
        catch {
            Write-Log "Failed to get activity logs for subscription $($subscription.Name): $($_.Exception.Message)" -Level 'WARNING'
            # Estimate based on subscription type and size
            $subscriptionData.ActivityLogCount = 1000  # Default estimate
            $subscriptionData.DailyAverage = [math]::Round(1000 /, $DaysToAnalyze, 2)
        }
    }
    else {
        # Estimate since we couldn't set context
        $subscriptionData.ActivityLogCount = 1000  # Default estimate
        $subscriptionData.DailyAverage = [math]::Round(1000 /, $DaysToAnalyze, 2)
        Write-Log "Using estimated activity log count of 1000 for subscription $($subscription.Name)" -Level 'WARNING'
    }
    
    # Get resource counts
    if ($contextSet) {
        try {
            $resources = Get-AzResource -ErrorAction Stop
            $subscriptionData.ResourceCount = $resources.Count
            
            # Group resources by type
            $resourceCounts = $resources | Group-Object -Property ResourceType | 
                            Select-Object @{Name="ResourceType"; Expression={$_.Name}}, Count
            
            Write-Log "Resource count: $($subscriptionData.ResourceCount)" -Level 'INFO'
            
            # Log resource breakdown
            foreach ($resourceType in $resourceCounts) {
                Write-Log "  - $($resourceType.ResourceType): $($resourceType.Count)" -Level 'INFO'
            }
        }
        catch {
            Write-Log "Failed to get resources for subscription $($subscription.Name): $($_.Exception.Message)" -Level 'WARNING'
            $subscriptionData.ResourceCount = 100  # Default estimate
        }
    }
    else {
        # Estimate since we couldn't set context
        $subscriptionData.ResourceCount = 100  # Default estimate
        Write-Log "Using estimated resource count of 100 for subscription $($subscription.Name)" -Level 'WARNING'
    }
    
    # Activity logs - assume avg size of 1KB per log
    $activityLogSizeKB = $subscriptionData.DailyAverage * 1  # 1KB per log estimate
    
    # Calculate ingress events per day (each log is an event)
    $ingressEventsPerDay = $subscriptionData.DailyAverage
    
    # Add to results
    $subscriptionData.EstimatedDailyEventHubIngress = $activityLogSizeKB
    $subscriptionData.EstimatedDailyEventCount = $ingressEventsPerDay
    
    # Store the subscription data in results array
    $results += $subscriptionData
}

# Get Entra ID log metrics (tenant-wide)
Show-Progress -Activity "Collecting data" -PercentComplete 95 -Status "Retrieving Entra ID log metrics"

$startTime = (Get-Date).AddDays(-$DaysToAnalyze)
$endTime = Get-Date

# Initialize tenant metrics with default estimates
$tenantMetrics = @{
    SignInLogCount = 10000  # Default estimate
    AuditLogCount = 5000    # Default estimate
    SignInDailyAverage = [math]::Round(10000 /, $DaysToAnalyze, 2)
    AuditDailyAverage = [math]::Round(5000 /, $DaysToAnalyze, 2)
}

# Try to get actual metrics if we have permissions
try {
    Connect-AzureAD -ErrorAction Stop
    
    Write-Log "Successfully connected to Azure AD. Retrieving sign-in and audit log metrics..." -Level 'INFO'
    
    # This is a simplified approach - in reality, you would use the Microsoft Graph API
    # or Azure AD PowerShell to get actual metrics, but this requires high permissions
    
    # For demonstration, we'll estimate based on organization size
    $users = Get-AzureADUser -All $true | Measure-Object | Select-Object -ExpandProperty Count
    $signInEstimate = $users * 2 * $DaysToAnalyze  # Assume 2 sign-ins per user per day
    $auditEstimate = $users * 0.5 * $DaysToAnalyze  # Assume 0.5 audit events per user per day
    
    $tenantMetrics.SignInLogCount = $signInEstimate
    $tenantMetrics.AuditLogCount = $auditEstimate
    $tenantMetrics.SignInDailyAverage = [math]::Round($signInEstimate /, $DaysToAnalyze, 2)
    $tenantMetrics.AuditDailyAverage = [math]::Round($auditEstimate /, $DaysToAnalyze, 2)
    
    Write-Log "Estimated sign-in logs: $signInEstimate, Daily average: $($tenantMetrics.SignInDailyAverage)" -Level 'INFO'
    Write-Log "Estimated audit logs: $auditEstimate, Daily average: $($tenantMetrics.AuditDailyAverage)" -Level 'INFO'
}
catch {
    Write-Log "Failed to connect to Azure AD or retrieve metrics: $($_.Exception.Message)" -Level 'WARNING'
    Write-Log "Using default estimates for Entra ID logs" -Level 'WARNING'
}

# Update default subscription with Entra ID log data
$defaultSubResult = $results | Where-Object { $_.SubscriptionId -eq $DefaultSubscriptionId }

if ($defaultSubResult) {
    $defaultSubResult.EstimatedDailyEventHubIngress += ($tenantMetrics.SignInDailyAverage + $tenantMetrics.AuditDailyAverage) * 2  # 2KB per Entra ID log estimate
    $defaultSubResult.EstimatedDailyEventCount += ($tenantMetrics.SignInDailyAverage + $tenantMetrics.AuditDailyAverage)
    
    Write-Log "Updated default subscription with Entra ID log estimates" -Level 'INFO'
    Write-Log "Total estimated daily Event Hub ingress: $($defaultSubResult.EstimatedDailyEventHubIngress) KB" -Level 'INFO'
    Write-Log "Total estimated daily event count: $($defaultSubResult.EstimatedDailyEventCount)" -Level 'INFO'
}
else {
    Write-Log "Default subscription not found in results! This is unexpected." -Level 'ERROR'
}

# Calculate and update additional metrics for all subscriptions
Show-Progress -Activity "Calculating costs" -PercentComplete 97 -Status "Computing resource requirements and costs"

foreach ($subscriptionResult in $results) {
    # Convert KB to MB per second for Event Hub throughput calculation
    $mbPerDay = $subscriptionResult.EstimatedDailyEventHubIngress / 1024
    $mbPerSecond = $mbPerDay / 86400  # seconds in a day
    
    # Event Hub TUs (min 2, max 10)
    $estimatedTUs = [Math]::Max(2, [Math]::Min(10, [Math]::Ceiling($mbPerSecond)))
    $subscriptionResult.EstimatedEventHubTUs = $estimatedTUs
    
    # Calculate storage needed for log retention (30 days)
    $activityLogStorageGB = ($subscriptionResult.EstimatedDailyEventHubIngress * 30) / (1024 * 1024)  # Convert KB to GB
    $subscriptionResult.EstimatedStorageGB = [math]::Round($activityLogStorageGB, 2)
    
    # If this is the default subscription, add storage for Entra ID logs
    if ($subscriptionResult.SubscriptionId -eq $DefaultSubscriptionId) {
        $entraIdLogStorageGB = (($tenantMetrics.SignInDailyAverage + $tenantMetrics.AuditDailyAverage) * 2 * 30) / (1024 * 1024)  # Convert KB to GB
        $subscriptionResult.EstimatedStorageGB += [math]::Round($entraIdLogStorageGB, 2)
        
        # Calculate events per second for Function App scaling
        $eventsPerSecond = $subscriptionResult.EstimatedDailyEventCount / 86400
        
        # Function App instance calculation (P0V3 can handle ~50 events/second per instance)
        $eventsPerInstancePerSecond = 50  # Estimate - would need benchmarking for accuracy
        $estimatedInstances = [Math]::Max(1, [Math]::Min(4, [Math]::Ceiling($eventsPerSecond / $eventsPerInstancePerSecond)))
        $subscriptionResult.EstimatedFunctionAppInstances = $estimatedInstances
    }
    
    # Get appropriate pricing for subscription's region
    $region = $subscriptionResult.Region.Split(',')[0].ToLower()
    $pricing = Get-PricingForRegion -Region $region -PricingData $regionPricing
    
    # Calculate detailed costs
    $isDefault = ($subscriptionResult.SubscriptionId -eq $DefaultSubscriptionId)
    $subscriptionResult.CostDetails = Get-CrowdStrikeResourceCost -SubscriptionData $subscriptionResult -Pricing $pricing -IsDefaultSubscription $isDefault
    
    # Calculate total monthly cost
    $totalCost = 0
    foreach ($costItem in $subscriptionResult.CostDetails.Values) {
        $totalCost += $costItem.MonthlyCost
    }
    $subscriptionResult.EstimatedMonthlyCost = [math]::Round($totalCost, 2)
    
    Write-Log "Estimated monthly cost for subscription $($subscriptionResult.SubscriptionName): $($subscriptionResult.EstimatedMonthlyCost)" -Level 'INFO'
}

# Prepare CSV data
Show-Progress -Activity "Preparing output" -PercentComplete 98 -Status "Generating CSV data"

# Create a list to hold the resource types
$resourceTypes = @()
foreach ($sub in $results) {
    foreach ($resourceType in $sub.CostDetails.Keys) {
        if ($resourceTypes -notcontains $resourceType) {
            $resourceTypes += $resourceType
        }
    }
}

# Create CSV data
$csvData = @()
foreach ($sub in $results) {
    $row = [ordered]@{
        SubscriptionId = $sub.SubscriptionId
        SubscriptionName = $sub.SubscriptionName
        Region = $sub.Region
        BusinessUnit = $sub.BusinessUnit
        ResourceCount = $sub.ResourceCount
        ActivityLogCount = $sub.ActivityLogCount
        DailyAverage = $sub.DailyAverage
        EstimatedMonthlyCost = $sub.EstimatedMonthlyCost
    }
    
    # Add resource-specific cost details
    foreach ($resourceType in $resourceTypes) {
        if ($sub.CostDetails.ContainsKey($resourceType)) {
            $row["${resourceType}_Count"] = $sub.CostDetails[$resourceType].Count
            $row["${resourceType}_UnitCost"] = $sub.CostDetails[$resourceType].UnitPrice
            $row["${resourceType}_MonthlyCost"] = $sub.CostDetails[$resourceType].MonthlyCost
        }
        else {
            $row["${resourceType}_Count"] = 0
            $row["${resourceType}_UnitCost"] = 0
            $row["${resourceType}_MonthlyCost"] = 0
        }
    }
    
    $csvData += [PSCustomObject]$row
}

# Export to CSV
Show-Progress -Activity "Exporting results" -PercentComplete 99 -Status "Writing to $OutputFilePath"

try {
    $csvData | Export-Csv -Path $OutputFilePath -NoTypeInformation
    Write-Log "Successfully exported cost estimation data to $OutputFilePath" -Level 'SUCCESS'
}
catch {
    Write-Log "Failed to export CSV data: $($_.Exception.Message)" -Level 'ERROR'
    $scriptSuccess = $false
}

# Generate summary
$totalCost = ($results | Measure-Object -Property EstimatedMonthlyCost -Sum).Sum
$defaultSubCost = ($results | Where-Object { $_.SubscriptionId -eq $DefaultSubscriptionId }).EstimatedMonthlyCost
$otherSubsCost = $totalCost - $defaultSubCost

Write-Log "Cost Estimation Summary:" -Level 'INFO'
Write-Log "------------------------" -Level 'INFO'
Write-Log "Total estimated monthly cost: $([math]::Round($totalCost, 2))" -Level 'INFO'
Write-Log "  Default subscription ($($defaultSubscription.Name)): $([math]::Round($defaultSubCost, 2))" -Level 'INFO'
Write-Log "  Other subscriptions: $([math]::Round($otherSubsCost, 2))" -Level 'INFO'
Write-Log "------------------------" -Level 'INFO'

# Calculate and log execution time
$endTime = Get-Date
$executionTime = $endTime - $startTime
Write-Log "Script execution completed in $($executionTime.TotalSeconds) seconds" -Level 'INFO'

# Display final status
if ($scriptSuccess) {
    Write-Log "CrowdStrike Azure Cost Estimation completed successfully. Results saved to $OutputFilePath" -Level 'SUCCESS'
}
else {
    Write-Log "CrowdStrike Azure Cost Estimation completed with warnings. Some data may be incomplete. Results saved to $OutputFilePath" -Level 'WARNING'
}

Write-Host "`nDetailed results can be found in:`n- CSV: $OutputFilePath`n- Log: $LogFilePath" -ForegroundColor Cyan
