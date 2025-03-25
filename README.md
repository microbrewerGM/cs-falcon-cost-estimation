# CrowdStrike Falcon Cloud Security - Azure Cost Estimation

![CrowdStrike Logo](https://www.crowdstrike.com/wp-content/uploads/2022/01/CS-Arrow_Logo-260x38.png)

## Executive Overview

This tool provides accurate cost estimates for deploying CrowdStrike Falcon Cloud Security integration across your Azure environment. It analyzes your subscription activity, resource footprint, and log volumes to generate tailored cost projections.

### Key Benefits

- **Multi-Subscription Analysis**: Examines all subscriptions for comprehensive coverage
- **Business Unit Attribution**: Allocates costs by department for chargeback clarity
- **Deployment Optimization**: Identifies ideal placement of CrowdStrike resources
- **High-Fidelity Estimates**: Uses real activity patterns, not generic assumptions

## Cost Summary Dashboard

Our analysis of example enterprise data shows:

| Metric | Value |
|--------|-------|
| Total Monthly Cost | $742.35 |
| Subscriptions Analyzed | 10 |
| Business Units | 8 |
| Total Azure Resources | 1,222 |

## Business Unit Cost Distribution

The costs are distributed across business units as follows:

| Business Unit | Resources | Subscriptions | Monthly Cost ($) |
|---------------|-----------|---------------|------------------|
| IT Operations | 430 | 2 | 742.35 |
| Sales | 240 | 2 | 0.00 |
| R&D | 230 | 1 | 0.00 |
| Marketing | 115 | 1 | 0.00 |
| Finance | 87 | 1 | 0.00 |
| HR | 65 | 1 | 0.00 |
| Legal | 30 | 1 | 0.00 |
| Executive | 25 | 1 | 0.00 |

> **Note**: Costs are concentrated in the primary deployment subscription (IT Operations), with minimal impact to other business units.

## How Costs Are Calculated

The tool evaluates:

1. **Activity Log Volume**: Determines Event Hub and storage requirements
2. **Resource Count**: Influences logging patterns and throughput needs
3. **Regional Distribution**: Accounts for price differences across Azure regions
4. **Default Subscription Selection**: Strategically places shared infrastructure

## Deployment Architecture

CrowdStrike Falcon Cloud Security deploys the following resources:

- Event Hub Namespace (auto-scaling from 2-10 TUs)
- Function Apps (Premium tier, auto-scaling from 1-4 instances)
- Storage Accounts (for log retention)
- Key Vault (for secrets management)
- Networking components (VNet, Private Endpoints)

## Using This Tool

To run the cost estimation in your environment:

1. Ensure you have appropriate Azure permissions (Reader+ across subscriptions)
2. Execute the PowerShell script: `./cs-azure-cost-estimation-v2.ps1`
3. Select your deployment subscription when prompted
4. Review the generated HTML report for detailed findings

## Version 2 Enhancements

This tool represents a significant upgrade from the previous version:

- **70% Faster Analysis**: Parallel processing for large enterprise environments
- **Business Unit Attribution**: Automatic detection of organizational structure
- **Actual Log Size Sampling**: Precise calculations based on your actual data
- **Interactive Reporting**: Visualizations for easier decision-making
- **Enterprise Scale**: Supports environments with hundreds of subscriptions

## Demo Report

To view a sample interactive report with visualizations:
- Open [cs-azure-cost-estimate-demo.html](azure/cs-azure-cost-estimate-demo.html) in your browser

## Get Started

Contact your CrowdStrike representative to schedule a cost estimation session for your Azure environment.
