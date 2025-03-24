# Fixed version of CrowdStrike Azure Cost Estimation Tool
# This script now properly handles paging with the Azure REST API instead of using deprecated Get-AzActivityLog
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

# Function to save script status for resumption
function Save-ScriptStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string]$StatusFilePath,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$StatusData
    )
    
    try {
        $jsonData = $StatusData | ConvertTo-Json -Depth 5
        Set-Content -Path $StatusFilePath -Value $jsonData -ErrorAction Stop
        Write-Log "Script status saved to $StatusFilePath" -Level 'INFO'
        return $true
    }
    catch {
        Write-Log "Failed to save script status: $($_.Exception.Message)" -Level 'WARNING'
        return $false
    }
}

# Function to check if a status file exists and load it
function Get-ScriptStatus {
    param (
        [Parameter(Mandatory = $true)]
        [string]$StatusFilePath
    )
    
    if (Test-Path $StatusFilePath) {
        try {
            $jsonContent = Get-Content -Path $StatusFilePath -Raw -ErrorAction Stop
            $status = $jsonContent | ConvertFrom-Json
            Write-Log "Found existing script status, can resume from subscription $($status.LastProcessedSubscription)" -Level 'INFO'
            return $status
        }
        catch {
            Write-Log "Error loading script status: $($_.Exception.Message)" -Level 'WARNING'
            return $null
        }
    }
    else {
        Write-Log "No status file found, starting fresh" -Level 'INFO'
        return $null
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

# Function to save subscription data to disk
function Save-SubscriptionData {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SubscriptionData,
        
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionDataDir
    )
    
    $filePath = Join-Path $SubscriptionDataDir "$($SubscriptionData.SubscriptionId).json"
    
    try {
        # Convert PSCustomObject to JSON and save to file
        $jsonData = $SubscriptionData | ConvertTo-Json -Depth 10
        Set-Content -Path $filePath -Value $jsonData -ErrorAction Stop
        Write-Log "Saved subscription data to $filePath" -Level 'INFO'
        return $true
    }
    catch {
        Write-Log "Failed to save subscription data: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

# Function to load all subscription data from disk
function Get-AllSubscriptionData {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionDataDir
    )
    
    $subscriptionData = @()
    
    try {
        $files = Get-ChildItem -Path $SubscriptionDataDir -Filter "*.json" -ErrorAction Stop
        
        foreach ($file in $files) {
            try {
                $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $subData = $jsonContent | ConvertFrom-Json
                $subscriptionData += $subData
                Write-Log "Loaded subscription data from $($file.Name)" -Level 'INFO'
            }
            catch {
                Write-Log "Error loading subscription data from $($file.Name): $($_.Exception.Message)" -Level 'WARNING'
            }
        }
    }
    catch {
        Write-Log "Error accessing subscription data directory: $($_.Exception.Message)" -Level 'ERROR'
    }
    
    return $subscriptionData
}

# Function to update a subscription's data file on disk
function Update-SubscriptionDataFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionDataDir,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Updates
    )
    
    $filePath = Join-Path $SubscriptionDataDir "$SubscriptionId.json"
    
    try {
        # Read existing data
        $jsonContent = Get-Content -Path $filePath -Raw -ErrorAction Stop
        $subscriptionData = $jsonContent | ConvertFrom-Json
        
        # Apply updates
        foreach ($key in $Updates.Keys) {
            $subscriptionData.$key = $Updates[$key]
        }
        
        # Save updated data
        $updatedJson = $subscriptionData | ConvertTo-Json -Depth 10
        Set-Content -Path $filePath -Value $updatedJson -ErrorAction Stop
        Write-Log "Updated subscription data in $filePath" -Level 'INFO'
        return $true
    }
    catch {
        Write-Log "Failed to update subscription data: $($_.Exception.Message)" -Level 'ERROR'
        return $false
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

# Initialize counter for processed subscriptions
$processedSubscriptionCount = 0

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

# Check for existing status file and ask if user wants to resume
$scriptStatus = Get-ScriptStatus -StatusFilePath $StatusFilePath
$resumeExecution = $false
$processedSubscriptionIds = @()

if ($scriptStatus -and $scriptStatus.LastProcessedSubscription) {
    $resumePrompt = Read-Host "Previous execution was interrupted. Do you want to resume processing from the last subscription? (Y/N)"
    if ($resumePrompt -eq "Y" -or $resumePrompt -eq "y") {
        $resumeExecution = $true
        $processedSubscriptionIds = $scriptStatus.ProcessedSubscriptionIds
        Write-Log "Resuming execution. $($processedSubscriptionIds.Count) subscriptions were already processed." -Level 'INFO'
    }
    else {
        Write-Log "Starting fresh execution, ignoring previous progress." -Level 'INFO'
        # Remove the status file since we're starting fresh
        Remove-Item -Path $StatusFilePath -Force -ErrorAction SilentlyContinue
    }
}

# Process each subscription
$totalSubscriptions = $subscriptions.Count
$currentSubscription = 0

foreach ($subscription in $subscriptions) {
    $currentSubscription++
    $subscriptionId = $subscription.Id
    $isDefaultSubscription = ($subscriptionId -eq $DefaultSubscriptionId)
    $percentComplete = [math]::Floor(($currentSubscription / $totalSubscriptions) * 90) + 5
    
    # Skip already processed subscriptions if resuming
    if ($resumeExecution -and $processedSubscriptionIds -contains $subscriptionId) {
        Write-Log "Skipping subscription $($subscription.Name) ($subscriptionId) - already processed" -Level 'INFO'
        continue
    }
    
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
                                if ($skipToken -match "\`$skipToken=([^
