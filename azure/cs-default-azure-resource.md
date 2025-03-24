# Azure Resources Created by CrowdStrike Deployment

## Overview

This document outlines the resources created by the CrowdStrike Falcon Cloud Security integration for Azure. The deployment creates resources for two main features:

1. **Indicator of Misconfiguration (IOM)** - Resources related to detecting misconfigurations in your Azure environment
2. **Indicator of Attack (IOA)** - Resources related to detecting potential attack patterns in your environment

## Deployment Scope

The Bicep templates support two deployment scopes:
- **Management Group level** - Deploy at tenant root management group level (affects all subscriptions)
- **Subscription level** - Deploy at individual subscription level

## Resources Created

### Microsoft Entra ID (Azure AD) Resources

- **Application Registration and Service Principal** - Created to allow CrowdStrike to access your Azure resources
  - Permissions requested:
    - Application.Read.All
    - AuditLog.Read.All
    - DeviceManagementRBAC.Read.All
    - Directory.Read.All
    - Group.Read.All
    - Policy.Read.All
    - Reports.Read.All
    - RoleManagement.Read.Directory
    - User.Read.All
    - User.ReadBasic.All
    - UserAuthenticationMethod.Read.All

### Tenant-wide Resources

- **Microsoft Entra ID Diagnostic Settings** - Forwards sign-in and audit logs to the EventHub
  - Diagnostic Setting Name: `cs-aad-to-eventhub`
  - Logs Collected:
    - AuditLogs
    - SignInLogs
    - NonInteractiveUserSignInLogs
    - ServicePrincipalSignInLogs
    - ManagedIdentitySignInLogs
    - ADFSSignInLogs

### Management Group Resources (when deployed at Management Group scope)

- **Custom Role Definition** - `cs-website-reader` role with permissions:
  - Microsoft.Web/sites/Read
  - Microsoft.Web/sites/config/Read
  - Microsoft.Web/sites/config/list/Action

- **Role Assignments** at Management Group scope:
  - Reader role
  - Security Reader role
  - Key Vault Reader role
  - Azure Kubernetes Service RBAC Reader role
  - cs-website-reader custom role

- **Azure Policy Definition and Assignment** - Ensures activity logs are forwarded to CrowdStrike
  - Policy Name: "Activity Logs must be sent to CrowdStrike for IOA assessment"
  - Policy Assignment Name: "cs-ioa-assignment"
  - System-assigned Managed Identity with roles:
    - Monitoring Contributor
    - Lab Services Reader
    - Azure Event Hubs Data Owner

### Default Subscription Resources

All of the following resources are created in the designated "default subscription" specified during deployment:

- **Resource Group**: `cs-ioa-group`

- **Virtual Network and Networking**:
  - Virtual Network: `cs-vnet`
  - Network Security Group: `cs-nsg`
  - Subnets:
    - `cs-subnet-1` - Used for Activity Logs function app
    - `cs-subnet-2` - Used for Entra ID Logs function app
    - `cs-subnet-3` - Used for private endpoints

- **Event Hub**:
  - Namespace: `cs-horizon-ns-{subscription_id}`
  - Event Hubs:
    - `cs-eventhub-monitor-activity-logs` - For Azure Activity Logs
    - `cs-eventhub-monitor-aad-logs` - For Microsoft Entra ID Logs
  - Authorization Rule: `cs-eventhub-monitor-auth-rule`

- **Key Vault**:
  - Name: `cs-kv-{randomsuffix}`
  - Keys:
    - `cs-log-storage-key`
    - `cs-activity-storage-key`
    - `cs-aad-storage-key`
  - Secrets:
    - `cs-client-id`
    - `cs-client-secret`

- **Storage Accounts**:
  - Log Storage Account: `cshorizonlog{randomsuffix}`
  - Activity Function Storage: `cshorizonact{randomsuffix}`
  - Entra ID Function Storage: `cshorizonaad{randomsuffix}`

- **App Service Plans**:
  - Activity Logs App Service Plan: `cs-activity-service-plan`
  - Entra ID Logs App Service Plan: `cs-aad-service-plan`

- **Function Apps**:
  - Activity Logs Function App: `cs-activity-func-{subscription_id}`
  - Entra ID Logs Function App: `cs-aad-func-{subscription_id}`

- **Managed Identities**:
  - Activity Logs Function Identity: `cs-activity-func-{subscription_id}`
  - Entra ID Logs Function Identity: `cs-aad-func-{subscription_id}`
  - If deployed at Management Group scope: `cs-activityLogDeployment-{subscription_id}`

- **Private Endpoints**:
  - Key Vault Private Endpoint: `kv-private-endpoint`
  - Log Storage Private Endpoint: `log-storage-private-endpoint`
  - Activity Storage Private Endpoint: `activity-storage-private-endpoint`
  - Entra ID Storage Private Endpoint: `aad-storage-private-endpoint`

### All Subscriptions Resources

- **Activity Log Diagnostic Settings** - Created in each subscription in the tenant
  - Name: `cs-monitor-activity-to-eventhub`
  - Forwards logs to the Event Hub in the default subscription

## Resource Scaling and Sizing

- **Event Hub Namespace**: 
  - Initially provisions 2 throughput units
  - Auto-scales between 2-10 throughput units

- **Function Apps**:
  - Premium V3 tier (P0V3)
  - Auto-scales between 1-4 instances per function app

## Cost Considerations

Costs for the CrowdStrike deployment will primarily be concentrated in the default subscription where most resources are deployed. The actual costs will depend on various factors including:

- Azure region used for deployment
- Volume of logs and events being processed
- Number of resources in your environment
- Auto-scaling activity of components
- Data egress costs

## Notes

1. The costs are primarily concentrated in the default subscription.
2. All other subscriptions only have diagnostic settings configured.
3. Resource names with `{subscription_id}` or `{randomsuffix}` will have dynamic values generated during deployment.
