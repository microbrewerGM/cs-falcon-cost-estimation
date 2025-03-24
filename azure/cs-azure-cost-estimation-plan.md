# CrowdStrike Azure Cost Estimation Plan

## Updated Implementation in PowerShell

The cost estimation plan has been implemented in PowerShell as `cs-azure-cost-estimation.ps1`. This script provides a comprehensive approach to estimating costs for the CrowdStrike Falcon Cloud Security integration in Azure.

## Key Features Implemented

1. **Robust Authentication and Error Handling**
   - Interactive `az login` authentication using both Azure CLI and Az PowerShell modules
   - Progressive fallback mechanisms when permissions are limited
   - Comprehensive logging to both console and log file
   - Graceful handling of permission issues (continues execution rather than failing)

2. **Flexible Data Collection**
   - Parameterized analysis window (default 7 days, configurable via parameter)
   - Region-aware pricing calculations
   - Default subscription selection with interactive fallback
   - Resource count analysis by subscription

3. **Metrics Collection and Estimation**
   - Activity Log volume analysis across all subscriptions
   - Entra ID log volume estimation (with permissions-based fallback)
   - Resource count analysis for scaling considerations
   - Estimates with reasonable defaults when direct measurement fails

4. **Detailed Cost Analysis**
   - Calculates Event Hub throughput requirements (with auto-scaling considerations)
   - Estimates storage requirements for log retention
   - Models Function App scaling patterns based on event volume
   - Component-by-component cost breakdown for every subscription

5. **Comprehensive Output**
   - CSV export with rich metadata (subscription, region, business unit placeholder)
   - Resource type breakdown per subscription
   - Itemized costs by component type 
   - Executive summary in terminal and log

## Usage

```powershell
# Run with default settings (7-day analysis window)
.\cs-azure-cost-estimation.ps1

# Specify analysis window
.\cs-azure-cost-estimation.ps1 -DaysToAnalyze 14

# Specify default subscription
.\cs-azure-cost-estimation.ps1 -DefaultSubscriptionId "00000000-0000-0000-0000-000000000000"

# Specify custom output paths
.\cs-azure-cost-estimation.ps1 -OutputFilePath "custom-path.csv" -LogFilePath "custom-log.log"
```

## Script Workflow

1. **Initialization and Authentication**
   - Validate prerequisites (Az module, Azure CLI)
   - Perform Azure authentication
   - Create log file and start logging

2. **Subscription Discovery**
   - Collect all enabled subscriptions
   - Prompt for or validate default subscription selection

3. **Data Collection (per subscription)**
   - Set subscription context
   - Determine primary region
   - Analyze Activity Log volumes
   - Count resources by type
   - Calculate daily event metrics

4. **Tenant-wide Analysis**
   - Estimate Entra ID log volumes
   - Calculate combined metrics for default subscription

5. **Cost Calculation**
   - Apply region-specific pricing
   - Calculate component-level costs
   - Estimate resource scaling requirements
   - Project total monthly costs

6. **Output Generation**
   - Prepare comprehensive CSV data
   - Export to specified path
   - Display summary in terminal and log

## Resource Cost Calculation

The script calculates costs for the following CrowdStrike Azure resources:

| Resource Type | Scaling Factor | Cost Basis |
|---------------|----------------|------------|
| Event Hub Namespace | Traffic volume | Throughput Units (2-10) |
| Storage Accounts | Log retention size | GB per month |
| Function Apps | Event processing rate | P0V3 instances (1-4) |
| Key Vault | Operation count | 10,000 operations |
| Private Endpoints | Fixed count | Hourly rate |
| Networking | Fixed components | Estimated monthly cost |

## CSV Output Structure

* **Metadata Columns**
  - SubscriptionId
  - SubscriptionName
  - Region
  - BusinessUnit (placeholder)
  - ResourceCount
  - ActivityLogCount
  - DailyAverage

* **Resource-specific Columns** (for each resource type)
  - {ResourceType}_Count
  - {ResourceType}_UnitCost
  - {ResourceType}_MonthlyCost

* **Summary Column**
  - EstimatedMonthlyCost

## Error Handling and Fallbacks

The script implements a graceful degradation approach:

1. If Azure PowerShell authentication fails, attempts Azure CLI
2. If subscription context fails, uses reasonable defaults
3. If Activity Log access fails, uses estimates based on subscription size
4. If Entra ID metrics cannot be accessed, uses conservative defaults

## Permission Requirements

For optimal results, the script requires:
- Read access to all subscriptions
- Activity Log reader permissions
- Microsoft Entra ID reader permissions (Global Reader, Security Reader, or higher)

However, the script will continue execution with limited functionality if all permissions are not available.
