# AWS Resources Created by CrowdStrike Falcon Integration (Terraform)

## Overview

This document outlines the AWS resources provisioned when integrating CrowdStrike Falcon Cloud Security using the official CrowdStrike Terraform provider and modules, primarily `CrowdStrike/crowdstrike` provider and the `CrowdStrike/cloud-registration/aws` module. The deployment sets up capabilities based on the features enabled in the `crowdstrike_cloud_aws_account` resource configuration:

1.  **Asset Inventory (`asset_inventory.enabled`):** Allows CrowdStrike basic read access to discover and inventory AWS assets.
2.  **Real-time Visibility / Indicator of Attack (IOA) (`realtime_visibility.enabled`):** Deploys infrastructure to stream AWS CloudTrail events to CrowdStrike for threat detection.
3.  **Data Security Posture Management (DSPM) (`dspm.enabled`):** (Optional) Deploys resources necessary for CrowdStrike to scan data stores (like S3) for sensitive data and misconfigurations.
4.  **Identity Protection (IDP) (`idp.enabled`):** (Optional) Enables integration features related to identity threat detection within AWS (details primarily configured within Falcon).
5.  **Sensor Management (`sensor_management.enabled`):** (Optional) Facilitates deployment and management of Falcon sensors on EC2 instances, potentially leveraging AWS Systems Manager (SSM).

## Deployment Scopes & Terraform Configuration

The Terraform configuration supports two primary deployment patterns:

1.  **Organization Level:** Configured by specifying the AWS `organization_id` and using the management account's ID as the `account_id` in the `crowdstrike_cloud_aws_account` resource. This approach is **recommended for multi-account environments** as it leverages AWS Organizations for broader configuration and potential cross-account access. Resources like central CloudTrail processing are typically deployed in the management account.
2.  **Individual Account Level:** Configured by specifying only the `account_id` without an `organization_id`. Resources and permissions are contained within the single target account.

## Resources Created by Feature and Scope

The specific AWS resources created depend heavily on the features enabled in the Terraform configuration (`enabled = true`) and the chosen scope (Organization vs. Individual Account).

### 1. Core IAM Resources (Management or Individual Account)

These roles and policies are fundamental for Falcon's access, created in the management account (for Org scope) or the individual account. Role names can often be customized via Terraform resource attributes (e.g., `asset_inventory.role_name`).

* **IAM Role for Asset Inventory & Core Read Access:** Grants CrowdStrike necessary read-only permissions to assess resource configurations.
    * *Terraform Attribute:* `iam_role_name` / `iam_role_arn` (output from `crowdstrike_cloud_aws_account`)
    * *Default/Common Name Concept:* `CrowdStrikeCSPMReader` (as mentioned in user docs, actual name based on TF output)
    * *Trust Policy:* Allows Falcon (`ExternalId` provided by `crowdstrike_cloud_aws_account`) to assume this role. An `intermediate_role_arn` can also be specified.
* **IAM Policy:** Attached to the core role, granting permissions required for enabled features (e.g., `ec2:DescribeInstances`, `s3:ListAllMyBuckets`, `iam:ListAccountAliases`, etc., for IOM/Asset Inventory).

### 2. Real-time Visibility / IOA Resources (`realtime_visibility.enabled = true`)

Primarily deployed in the **management account** for Org scope, or the individual account.

* **CloudTrail Configuration:**
    * Leverages an existing organization/account CloudTrail if `use_existing_cloudtrail = true`.
    * If `false`, the module *may* create a new multi-region CloudTrail.
    * **S3 Bucket:** Stores CloudTrail logs. The name is referenced via `cloudtrail_bucket_name` (output from `crowdstrike_cloud_aws_account`). May use an existing bucket or create `cs-cloudtrail-logs-{account_id}` (example).
* **EventBridge (CloudWatch Events):**
    * **Event Bus:** An EventBridge event bus ARN (`eventbus_arn` from `crowdstrike_cloud_aws_account`) is used as the target for CloudTrail events. This might be a custom bus created by the module or an existing one.
    * **Rule:** Filters CloudTrail management events (e.g., `cs-cloudtrail-to-crowdstrike`).
    * **IAM Role for Event Forwarding:** Grants permissions for EventBridge/related services to process and forward events.
        * *Default/Common Name Concept:* `CrowdStrikeCSPMEventBridge` (as mentioned in user docs)
* **Lambda Function (Likely):** Although not explicitly defined in the provided resource/module schemas, a Lambda function is typically used to process events from EventBridge and forward them to the CrowdStrike API endpoint.
    * *Conceptual Name:* `cs-cloudtrail-processor-{account_id}`
    * Requires an associated IAM execution role.

### 3. Data Security Posture Management (DSPM) Resources (`dspm.enabled = true`)

These resources are often deployed regionally based on the `dspm_regions` list specified in the Terraform module.

* **IAM Roles:**
    * **DSPM Integration Role:** Assumed by CrowdStrike for DSPM orchestration.
        * *Terraform Attribute:* `dspm.role_name` (input), `dspm_role_name` / `dspm_role_arn` (output from `crowdstrike_cloud_aws_account`). Default concept `CrowdStrikeDSPMIntegrationRole`.
    * **DSPM Scanner Role:** Assumed by the scanning instances/services.
        * *Default/Common Name Concept:* `CrowdStrikeDSPMScannerRole`.
    * **S3 Access Role:** Specific role potentially created for accessing S3 data during scans.
        * *Default/Common Name Concept:* `cs-dspm-s3-access-role`.
* **VPC & Networking (Per DSPM Region):** Creates an isolated environment for scanning tasks.
    * **VPC:** e.g., `cs-dspm-vpc-{account_id}`
    * **Subnets:** Public and Private subnets.
    * **NAT Gateway:** For outbound internet access from private subnets (e.g., to send results to Falcon).
    * **Security Groups:** e.g., `cs-dspm-sg` to control traffic to scanning resources.
* **Compute Resources (Likely EC2 or ECS/Fargate):** Resources launched temporarily to perform scanning tasks, assuming the `CrowdStrikeDSPMScannerRole`.
    * *Instance Type Example:* `c6a.2xlarge` (as mentioned in user docs, actual type may vary).
* **KMS Keys:** Potentially created for encrypting data during the scanning process.

### 4. Identity Protection (IDP) Resources (`idp.enabled = true`)

* Enabling IDP via Terraform primarily registers the AWS account for this feature within the Falcon platform.
* It *may* involve adjustments to IAM permissions within the core `CrowdStrikeCSPMReader` role but typically does not create significant additional AWS infrastructure compared to IOA or DSPM. Status is readable via `idp.status`.

### 5. Sensor Management Resources (`sensor_management.enabled = true`)

* Enabling this likely adjusts IAM permissions to allow Falcon to interact with services like AWS Systems Manager (SSM) for deploying/managing the Falcon sensor on EC2 instances.
* May involve creating SSM Documents or configurations. Requires specific API scopes (`CSPM sensor management`, `Installation tokens`, `Sensor download`).

### 6. Member Account Resources (Org Scope)

When deployed at the Organization level, member accounts typically require fewer direct resources:

* **IAM Role for Cross-Account Access:** A role (e.g., `OrganizationAccountAccessRole`) might be expected or created in member accounts, allowing the IAM roles/services in the management account to assume it and perform necessary actions (like reading configurations or deploying diagnostic settings if applicable). The primary reader role (`CrowdStrikeCSPMReader`) deployed in the management account might also be configured with trust policies allowing assumption by specific member account identities if needed, or vice-versa. *Note: The exact cross-account mechanism depends on the module's implementation.*
* **CloudTrail:** Member accounts need to have CloudTrail enabled and logging to the central S3 bucket configured by the Organization trail (if used).

*(Note: The "Snapshot Scanning" components mentioned in the initial user markdown, involving AWS Batch and specific EBS snapshot handling, are not explicitly detailed in the provided Terraform resource/module documentation snippets (`crowdstrike_cloud_aws_account`, `CrowdStrike/cloud-registration/aws` module overview). They might be part of a different module, a more detailed aspect of DSPM not covered here, or configured separately. This updated document focuses on resources directly implied or confirmed by the provided Terraform details.)*

## Resource Naming Conventions

Resource names often include dynamic elements like the AWS Account ID (`{account_id}`) or region, alongside standard prefixes (e.g., `cs-`, `CrowdStrike-`). Specific names are determined by the Terraform module defaults or customizations.

## Scaling and Sizing (Example Defaults)

*(Based on typical configurations or details from the initial user markdown)*

* **Lambda Functions (IOA):** Often configured with moderate memory (e.g., 128 MB) and timeouts (e.g., 300 seconds), scaling concurrency based on event volume.
* **DSPM Scanning Compute:** May use instance types like `c6a.2xlarge` temporarily during scheduled scans.
* **CloudTrail/EventBridge:** Scale automatically based on AWS service limits and usage.

## Cost Considerations

AWS costs are influenced by enabled features and usage volume:

* **Real-time Visibility / IOA:**
    * **EventBridge Events:** Costs per million events processed.
    * **Lambda Execution:** Costs based on requests and duration (often minimal).
    * **CloudTrail:** Potential costs for trail delivery and S3 storage (often minimal if within free tier or using existing trail).
    * **Data Egress:** If Lambda sends data outside the AWS region to CrowdStrike.
* **DSPM (`dspm.enabled = true`):**
    * **NAT Gateway:** Hourly charges plus data processing fees. Can be significant if scanning large amounts of data frequently.
    * **Compute (EC2/ECS/Fargate):** Costs for instance hours during scans (e.g., `c6a.2xlarge` hourly rate).
    * **KMS:** Key usage costs.
    * **S3 API Calls:** Costs associated with listing/accessing S3 objects during scans.
* **Other Costs:** S3 storage (CloudTrail, potentially DSPM outputs), Data Transfer.

## Official Resources & Source of Truth

The official CrowdStrike Terraform provider documentation and module source code are the definitive sources for deployed resources and configurations:

* **Terraform Provider Registry:** [registry.terraform.io/providers/crowdstrike/crowdstrike](https://registry.terraform.io/providers/crowdstrike/crowdstrike)
* **Provider GitHub Repository:** [https://github.com/CrowdStrike/terraform-provider-crowdstrike](https://github.com/CrowdStrike/terraform-provider-crowdstrike)
* **AWS Registration Module:** Likely within the provider repository or referenced, e.g., `CrowdStrike/cloud-registration/aws`.
