# CrowdStrike Azure Cost Estimation Tool v2

This directory contains the refactored, modular version of the CrowdStrike Azure Cost Estimation Tool. The original script was refactored to avoid the 700+ line limitation while maintaining all functionality.

## Directory Structure

```
CS-Azure-Cost-Estimation-v2/
├── CS-Azure-Cost-Estimation-v2-Main.ps1       # Main script that orchestrates all modules
├── CS-Azure-Cost-Estimation-v2-Original.ps1   # Original v2 script (for reference)
├── README.md                                  # This file
├── Config/                                    # Customizable configuration files
│   ├── General.ps1                            # General settings
│   ├── Pricing.ps1                            # Pricing information
│   ├── Capacity.ps1                           # Throughput and storage settings
│   ├── Environments.ps1                       # Environment classification
│   └── Reporting.ps1                          # Reporting settings
└── Modules/                                   # Modular components
    ├── ConfigLoader.psm1                      # Loads configuration settings
    ├── Logging.psm1                           # Logging functionality
    ├── Authentication.psm1                    # Azure authentication
    ├── Pricing.psm1                           # Pricing retrieval
    ├── DataCollection.psm1                    # Azure resource data collection
    ├── CostEstimation.psm1                    # Cost calculation logic
    └── Reporting.psm1                         # Report generation
```

## How the Modules Work Together

1. **CS-Azure-Cost-Estimation-v2-Main.ps1** - The main entry point that:
   - Imports all modules
   - Processes command-line parameters
   - Orchestrates the entire cost estimation process
   - Calls the appropriate functions from each module

2. **Config.psm1** - Stores all configuration constants and defaults:
   - Default pricing by region
   - Environment classification settings
   - Throughput and storage calculation parameters

3. **Logging.psm1** - Provides logging functionality:
   - Write-Log function for consistent log formatting
   - Progress tracking with ETA estimation
   - Error handling utilities

4. **Authentication.psm1** - Handles Azure authentication:
   - Verification of required Azure modules
   - Azure PowerShell and CLI authentication
   - Subscription selection

5. **Pricing.psm1** - Manages pricing information:
   - Azure Retail Rates API integration
   - Static pricing fallbacks
   - Region-specific pricing extraction

6. **DataCollection.psm1** - Collects data from Azure:
   - Subscription metadata retrieval
   - Activity log analysis
   - Entra ID metrics collection
   - Resource inventory

7. **CostEstimation.psm1** - Performs the cost calculations:
   - Throughput requirements estimation
   - Storage needs calculation
   - Component-level cost estimation
   - Business unit cost aggregation

8. **Reporting.psm1** - Generates reports:
   - CSV export for subscription costs
   - Business unit cost summary
   - JSON data export
   - HTML report with visualizations

## Usage

The usage remains the same as the original script:

```powershell
.\CS-Azure-Cost-Estimation-v2-Main.ps1 -DaysToAnalyze 14 -SampleLogSize 200
```

All parameters from the original version are supported. The output files and format are identical to the original script.

## Customizing Configuration

One of the main benefits of this refactored version is the ease of customization. All configurable parameters are now in dedicated files in the `Config` directory:

### General.ps1
Contains general settings such as default Azure region, currency code, and default business unit name.

### Pricing.ps1
Contains pricing information including static pricing fallbacks by region, fixed costs, and Key Vault operation assumptions.

### Capacity.ps1
Contains capacity and performance settings like log sizes, throughput units, storage defaults, and parallel execution configuration.

### Environments.ps1
Contains environment classification settings with name patterns, tag keys/values, and visualization colors.

### Reporting.ps1
Contains reporting settings including log volume extrapolation factors, chart colors, and report title.

### How to Customize
To customize the configuration:

1. Edit the appropriate file in the `Config` directory
2. No recompilation or complex changes needed
3. Changes take effect the next time you run the script

### Creating Organization-Specific Configurations
For enterprise use, you can:

1. Create a copy of the Config directory with your organization's settings
2. Use the `-CustomConfigPath` parameter to specify your organization's config file
3. Store standard configurations in a central location for consistency across teams

Example using a custom config:
```powershell
.\CS-Azure-Cost-Estimation-v2-Main.ps1 -CustomConfigPath "C:\Company\CrowdStrike\custom-config.ps1"
```
