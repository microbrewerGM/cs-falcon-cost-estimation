# AWS Resources Created by CrowdStrike Deployment

## Overview

This document outlines the resources created by the CrowdStrike Falcon Cloud Security integration for AWS. The deployment creates resources for two main features:

1. **Indicator of Misconfiguration (IOM)** - Resources related to detecting misconfigurations in your AWS environment
2. **Indicator of Attack (IOA)** - Resources related to detecting potential attack patterns in your environment

## Deployment Scope

The deployment supports two deployment scopes:
- **Organization level** - Deploy at AWS Organizations management account level (affects all accounts)
- **Individual account level** - Deploy at individual AWS account level

## Resources Created

### Identity and Access Management (IAM) Resources

- **IAM Roles and Policies** - Created to allow CrowdStrike to access your AWS resources
  - `CrowdStrikeCSPMReader` - Role for configuration assessment (IOM)
    - Read-only permissions to assess resource configurations
  - `CrowdStrikeCSPMEventBridge` - Role for behavior assessment (IOA)
    - Permissions to read and forward CloudTrail events

### Organization-wide Resources

- **CloudTrail** - Organization-level trail (if not using an existing trail)
  - Multi-region trail configuration
  - Logs management and data events
  - Stores logs in S3 bucket in the management account

### Management Account Resources

When deployed at Organization level, these resources are created in the AWS Organizations management account:

- **EventBridge Rules**:
  - Rule Name: `cs-cloudtrail-to-crowdstrike`
  - Pattern: CloudTrail management events
  - Target: Lambda function

- **Lambda Functions**:
  - CloudTrail Processor: `cs-cloudtrail-processor-{account_id}`
    - Processes and forwards CloudTrail events to CrowdStrike
  - Account Registration: `cs-account-registration-{account_id}`
    - Registers new accounts with CrowdStrike when added to organization

- **S3 Buckets**:
  - CloudTrail Logs: `cs-cloudtrail-logs-{account_id}`
    - Stores CloudTrail logs for the organization

### All Accounts Resources

- **IAM Role**:
  - Cross-account access role: `OrganizationAccountAccessRole` or similar
  - Allows the management account to assume role in member accounts

### DSPM Components (Optional)

When Data Security Posture Management (DSPM) is enabled, these additional resources are created:

- **VPC Resources**:
  - VPC: `cs-dspm-vpc-{account_id}`
  - Subnets: Public and private subnets
  - NAT Gateway: For outbound connectivity
  - Security Groups: `cs-dspm-sg` for controlling access

- **EC2 Resources**:
  - IAM Role: `cs-dspm-execution-role`
  - Instance Type: c6a.2xlarge (or similar)
  - Temporary instances created during scanning

- **S3 Access**:
  - IAM Role: `cs-dspm-s3-access-role`
  - KMS Keys: For encryption of data during scanning

### Snapshot Components (Optional)

When Snapshot scanning is enabled, these additional resources are created:

- **AWS Batch**:
  - Compute Environment: `cs-snapshot-compute-env`
  - Job Queue: `cs-snapshot-job-queue`
  - Job Definition: `cs-snapshot-job-def`
  - Instance Type: c5.large (or similar)

- **EC2 Resources**:
  - Cross-account IAM Role: `cs-snapshot-execution-role`
  - KMS Key: For snapshot encryption

- **EBS Snapshots**:
  - Temporary snapshots created during scanning
  - Automatically deleted after analysis

## Resource Scaling and Sizing

- **Lambda Functions**:
  - Memory: 128 MB
  - Timeout: 300 seconds
  - Concurrency: Auto-scaling based on event volume

- **DSPM Scanning** (if enabled):
  - EC2 instance: c6a.2xlarge
  - Scanning schedule: Typically quarterly, configurable
  - Instance hours: Approximately 24 hours per scan

- **Snapshot Scanning** (if enabled):
  - Batch instances: c5.large
  - Scanning schedule: Typically weekly
  - Instance hours: Approximately 30 minutes per instance

## Cost Considerations

Costs for the CrowdStrike deployment will primarily come from:

1. **EventBridge Events**: $1.00 per million events
   - Based on CloudTrail event volume

2. **Data Egress**: Varies by region
   - US/EU regions: $0.09 per GB
   - Asia/ME regions: $0.11 per GB
   - South America: $0.12 per GB

3. **Lambda Functions**: Minimal cost
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

## Notes

1. Resource names with `{account_id}` will have dynamic values generated during deployment.
2. The actual resources created may vary based on deployment options and CrowdStrike features enabled.
3. When deployed at organization level, most resources are concentrated in the management account.
4. Member accounts primarily have IAM roles for cross-account access.
5. The cost estimation script (`cs-aws-cost-estimation.py`) can be used to estimate the actual AWS costs for your environment before deployment.

## Official Resources

The official CrowdStrike Terraform provider and modules are the source of truth for deployment code and cost estimation:

- **GitHub Repository**: [https://github.com/CrowdStrike/terraform-provider-crowdstrike](https://github.com/CrowdStrike/terraform-provider-crowdstrike)
- This repository contains the official Terraform provider and modules for deploying CrowdStrike resources in AWS
- All cost estimation approaches and code are based on the resources defined in this provider
