# CrowdStrike CSPM AWS Cost Estimator

This tool helps estimate the AWS costs associated with deploying CrowdStrike Falcon Cloud Security Posture Management (CSPM) across multiple AWS accounts within an organization.

## Overview

When deploying CrowdStrike's Falcon CSPM, additional AWS resources are created that incur costs. This tool analyzes your current AWS environment to estimate these costs before deployment, helping with budgeting and planning.

The estimator focuses on:
- CloudTrail event volumes
- Data egress to CrowdStrike
- DSPM (Data Security Posture Management) scanning costs
- Snapshot scanning costs
- Additional AWS service costs

## Prerequisites

- Python 3.6+
- AWS credentials with organization access
- Required Python packages:
  - boto3
  - pandas

## Installation

1. Clone or download this repository
2. Install dependencies:
   ```
   pip install boto3 pandas
   ```
3. Ensure both scripts are in the same directory:
   - `crowdstrike_cost_estimator.py` (main script)
   - `aws_creds.py` (authentication helper)

## Usage

Run the estimator with your preferred configuration:

```
# Basic usage with default region (us-east-1)
python crowdstrike_cost_estimator.py

# Analyze specific regions
python crowdstrike_cost_estimator.py --regions us-east-1 us-west-2

# Analyze all enabled AWS regions
python crowdstrike_cost_estimator.py --all-regions

# Include DSPM and Snapshot cost estimates
python crowdstrike_cost_estimator.py --include-dspm --include-snapshot
```

### Command Line Arguments

- `--regions`: AWS regions to analyze (default: us-east-1 if not using --all-regions)
- `--output`: Output CSV file name (default: crowdstrike_cost_estimate.csv)
- `--all-regions`: Analyze all enabled regions for each account
- `--include-dspm`: Include DSPM cost estimates
- `--include-snapshot`: Include Snapshot cost estimates

## Authentication

The script uses the `aws_creds.py` helper for authentication. It supports:
1. Existing AWS credentials (from environment or ~/.aws)
2. AWS SSO login
3. IAM user (access key/secret key)
4. Role assumption

## Cost Components

The estimator calculates costs for these AWS services:

1. **EventBridge Events**: $1.00 per million events
   - Based on CloudTrail event volume

2. **Data Egress**: Varies by region
   - US/EU regions: $0.09 per GB
   - Asia/ME regions: $0.11 per GB
   - South America: $0.12 per GB

3. **Lambda Functions**: Nominal cost ($0.10/month estimate)
   - Used for account registration and event processing

4. **CloudTrail**: $0 if using existing CloudTrail
   - Additional if creating new trails

5. **DSPM** (when enabled):
   - NAT Gateway: $0.045 per hour + $0.045 per GB processed
   - EC2 instance (c6a.2xlarge): $0.34 per hour
   - Based on S3 bucket count and size

6. **Snapshot** (when enabled):
   - AWS Batch compute (c5.large): $0.085 per hour per Linux instance
   - EBS snapshot storage: $0.05 per GB-month
   - Based on Linux EC2 instance count

## Estimation Methodology

The script uses a hierarchical approach to estimating costs:

1. **Primary**: Use actual AWS CloudWatch metrics when available
   - CloudTrail event counts, byte volumes
   - S3 bucket sizes
   - EC2 instance counts

2. **Secondary**: Estimate from related metrics when primary not available
   - API call counts → CloudTrail events
   - CloudTrail events → data transfer volume

3. **Tertiary**: Estimate based on resource counts
   - Instance/user/role counts → activity level

4. **Fallback**: Conservative default assumptions
   - 1M CloudTrail events/month
   - 5 GB data transfer/month
   - 10 S3 buckets of 50 GB each
   - 20 EC2 instances (70% Linux)

## Understanding Results

The tool generates:

1. **CSV Report**: Detailed breakdown by account and region
2. **Business Unit CSV**: Cost summary by business unit (if tags available)
3. **Summary Output**:
   - Total estimated monthly cost
   - Top 10 accounts by cost
   - Cost by region
   - DSPM and Snapshot costs (if enabled)
   - Cost by business unit (if tags available)

Example output:
```
=== CrowdStrike CSPM Cost Estimation Summary ===
Total Estimated Monthly Cost: $896.50

Cost by Account (Top 10):
  Production (123456789012): $154.20/month
  Development (234567890123): $98.30/month
  ...

Cost by Region:
  us-east-1: $390.45/month
  us-west-2: $275.80/month
  ...

DSPM Costs: $125.75/month
Snapshot Costs: $95.60/month

Cost by Business Unit:
  Finance: $245.20/month
  Engineering: $352.30/month
  ...
```

## Business Unit Attribution

The tool attributes costs to business units using AWS Organization tags. 
It looks for tags with these keys:
- `BusinessUnit`
- `Business-Unit`
- `BU`

## Region Handling

The tool can handle regions in several ways:

1. **Specified Regions**: Analyze only the regions provided with `--regions`
2. **All Regions**: Analyze all available AWS regions with `--all-regions`
3. **Default**: Analyze only us-east-1 if no regions specified

For each account, the tool can detect which regions are enabled and accessible.

## Related Resources

### Terraform Module

This estimator is designed to work with the official CrowdStrike Terraform module.

**Module:** [CrowdStrike/cloud-registration/aws](https://registry.terraform.io/modules/CrowdStrike/cloud-registration/aws/latest)

The Terraform module handles deployment of the CrowdStrike Falcon CSPM components including:
- IAM roles and policies
- EventBridge rules
- CloudTrail configuration
- Lambda functions
- Cross-account access
- DSPM resources (if enabled)
- Snapshot resources (if enabled)

### Deployed Resources

When using the CrowdStrike Terraform module, these resources are created:

#### Core Components
- IAM Role (`CrowdStrikeCSPMReader`) for configuration assessment (IOM)
- IAM Role (`CrowdStrikeCSPMEventBridge`) for behavior assessment (IOA)
- EventBridge Rules for CloudTrail event forwarding
- CloudTrail (if not using existing)

#### DSPM Components (Optional)
- VPC with subnets and NAT Gateway
- Security groups
- IAM roles for DSPM integration and scanning
- KMS keys for encryption
- Temporary EC2 instances during scanning

#### Snapshot Components (Optional)
- Cross-account IAM role
- KMS key for snapshot encryption
- AWS Batch resources (compute environment, job queue)
- VPC networking components

## Troubleshooting

### Common Issues

1. **Authorization Errors**
   - Ensure your credentials have organization access
   - Try authenticating with AWS SSO

2. **Estimation Accuracy**
   - For more accurate results, ensure CloudTrail is enabled for at least 7 days
   - Default estimates are conservative and may be higher than actual usage

3. **Missing Accounts**
   - Verify your role has `organizations:ListAccounts` permission
   - Check that accounts are active in the organization

4. **Region Issues**
   - Some regions may require explicit enabling in your AWS account
   - Use `--all-regions` to automatically detect enabled regions

### Logging

The script outputs detailed information about:
- Authentication status
- Account discovery
- Per-account analysis progress
- Estimation methodology used

## License

This tool is provided under the MIT License.

## Disclaimer

Cost estimates are approximations based on current AWS pricing and observed usage patterns. Actual costs may vary based on:
- Changes in AWS pricing
- Fluctuations in usage
- Region-specific factors
- CrowdStrike-specific optimizations

AWS costs are additional to any CrowdStrike licensing costs.

