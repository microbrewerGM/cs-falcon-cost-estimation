# CrowdStrike Azure Cost Estimation Tool v3

This tool estimates the cost of implementing CrowdStrike's security solutions in Azure environments by analyzing subscription activity logs and other metrics. The estimations are based on log volume and processing requirements across all your Azure subscriptions.

## Key Improvements in v3

- **Multi-subscription analysis** - Analyzes all accessible subscriptions in a single run
- **CSV-focused reporting** - Simplified output format optimized for data analysis
- **Business unit cost breakdown** - Aggregates costs by business unit tag
- **Browser-based authentication** - Simple authentication through web browser
- **Simplified architecture** - Linear execution flow for better reliability
- **Reduced code complexity** - Eliminated redundant logic and HTML reporting
- **Smaller codebase** - Focused on core cost estimation functionality

## Requirements

- PowerShell 7.0+ (works on Windows, macOS, or Linux)
- Azure PowerShell modules:
  - Az.Accounts
  - Az.Resources
  - Az.Monitor
- Optional: AzureAD module for enhanced user count detection

## Installation

1. Clone the repository or download the files
2. Ensure you have the required PowerShell modules installed:

```powershell
# Install required modules
Install-Module -Name Az.Accounts, Az.Resources, Az.Monitor -Scope CurrentUser -Force
```

## Usage

```powershell
# Run with default settings using existing Azure context or cached credentials
./cs-azure-cost-estimation.ps1

# Specify output directory
./cs-azure-cost-estimation.ps1 -OutputDirectory "/path/to/output"

# Run with tenant ID (optional)
./cs-azure-cost-estimation.ps1 -TenantId "your-tenant-id"

# Additional parameters
./cs-azure-cost-estimation.ps1 -DaysToAnalyze 14 -LogRetentionDays 90 -ForceRefreshPricing
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| OutputDirectory | Directory to store reports and logs | Auto-generated timestamped directory |
| TenantId | Azure tenant ID | From environment or Az context |
| DaysToAnalyze | Number of days of activity logs to analyze | 7 |
| LogRetentionDays | Number of days to retain logs in storage | 30 |
| ForceRefreshPricing | Force refresh of pricing data | False |
| Quiet | Suppress non-error output | False |
| Debug | Show verbose debug information | False |

## Output Files

The tool generates the following outputs:

- **cs-azure-cost-estimate.csv** - Main cost estimates for all subscriptions
- **business-unit-costs.csv** - Aggregated costs by business unit
- **cs-azure-cost-estimate-summary.json** - Complete data in JSON format (for programmatic use)
- **cs-azure-cost-estimate.log** - Detailed execution log

## Configuration

The tool's behavior can be configured through files in the `Config` directory:

- **General.ps1** - General configuration settings
- **Environments.ps1** - Environment categorization settings
- **Pricing.ps1** - Default pricing configuration

## Authentication Method

The tool uses browser-based authentication for simplicity:

1. The script will launch a browser window for authentication if you are not already logged in
2. You can specify a tenant ID to direct the authentication to a specific tenant
3. If you are already logged in with `az login` or previous runs, it reuses your existing credentials

## Business Unit Attribution

By default, the tool looks for a tag named "BusinessUnit" on subscriptions to attribute costs. You can change this in the configuration if your organization uses a different tag name.

## Environment Detection

The tool can detect environments (Production, Development, etc.) from:
1. A tag named "Environment" on the subscription
2. Pattern matching in the subscription name

This detection is used for cost estimation, as production environments typically require more robust infrastructure.
