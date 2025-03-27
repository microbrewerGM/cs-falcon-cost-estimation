# Azure Resources Created by CrowdStrike Falcon Integration (Bicep)

## Overview

This document outlines the Azure resources provisioned when integrating CrowdStrike Falcon Cloud Security using the official Bicep templates available at `https://github.com/CrowdStrike/cs-azure-integration-bicep`. The deployment primarily sets up capabilities for:

1.  **Indicator of Misconfiguration (IOM):** Allows CrowdStrike to assess Azure resource configurations against security best practices by granting necessary read permissions.
2.  **Indicator of Attack (IOA):** (Optional) Deploys infrastructure to stream Azure logs (Activity Logs, Microsoft Entra ID logs) to CrowdStrike for threat detection. This requires setting the `deployIOA` parameter to `true`.

## Deployment Scopes

The Bicep templates offer two primary deployment scopes:

1.  **Management Group Scope (`cs-deployment-managementGroup.bicep`):** Deployed at the Tenant Root Group level. This is the **recommended approach for tenants with multiple subscriptions** as it centralizes configuration and policy enforcement across all subscriptions under that management group.
2.  **Subscription Scope (`cs-deployment-subscription.bicep`):** Deployed individually to specific Azure subscriptions. RBAC and diagnostic settings only apply to the targeted subscription.

## Resources Created by Scope

The specific resources created depend on the chosen scope and whether IOA features are enabled.

### 1. Microsoft Entra ID Resources (Tenant Level)

These are created regardless of scope:

* **Application Registration & Service Principal:** An identity created in Microsoft Entra ID for CrowdStrike Falcon to authenticate and access Azure APIs.
    * **Permissions Granted (via Admin Consent):** `Application.Read.All`, `AuditLog.Read.All`, `DeviceManagementRBAC.Read.All`, `Directory.Read.All`, `Group.Read.All`, `Policy.Read.All`, `Reports.Read.All`, `RoleManagement.Read.Directory`, `User.Read.All`, `User.ReadBasic.All`, `UserAuthenticationMethod.Read.All`.
* **Microsoft Entra ID Diagnostic Setting:** (Only if `deployIOA=true`) Configures Entra ID to forward specific logs to the central Event Hub.
    * **Name:** `cs-aad-to-eventhub` (default)
    * **Logs:** AuditLogs, SignInLogs, NonInteractiveUserSignInLogs, ServicePrincipalSignInLogs, ManagedIdentitySignInLogs, ADFSSignInLogs.

### 2. Management Group Scope Resources (Only when deploying at MG Scope)

These resources configure permissions and policies across the management group:

* **Custom Role Definition:**
    * **Name:** `cs-website-reader`
    * **Permissions:** `Microsoft.Web/sites/Read`, `Microsoft.Web/sites/config/Read`, `Microsoft.Web/sites/config/list/Action`.
* **Role Assignments (at Management Group Scope):** Assigns the following roles to the CrowdStrike Service Principal:
    * Reader
    * Security Reader
    * Key Vault Reader
    * Azure Kubernetes Service RBAC Reader
    * `cs-website-reader` (Custom Role)
* **User-Assigned Managed Identity:** (Only if `deployIOA=true`)
    * **Purpose:** Grants permissions to list subscriptions under the tenant root, necessary for deploying diagnostic settings across them.
    * **Default Name Pattern:** `cs-activityLogDeployment-{subscription_id_of_deployment}`
    * **Permissions:** Assigned `Reader` role at the Tenant Root Group scope.
* **Azure Policy (Definition & Assignment):** (Only if `deployIOA=true`)
    * **Purpose:** Ensures Azure Activity Logs from all *current* and *future* subscriptions within the management group are forwarded to the central Event Hub.
    * **Policy Definition Name:** "Activity Logs must be sent to CrowdStrike for IOA assessment" (default)
    * **Policy Assignment Name:** `cs-ioa-assignment` (default)
    * **Policy Managed Identity:** The assignment uses a system-assigned managed identity with roles like `Monitoring Contributor` and `Azure Event Hubs Data Owner` to create diagnostic settings in subscriptions.

### 3. Subscription Scope Resources (Only when deploying at Subscription Scope)

These resources are created within the specific target subscription:

* **Role Assignments (at Subscription Scope):** Assigns the same roles listed under Management Group scope (Reader, Security Reader, etc.) to the CrowdStrike Service Principal, but scoped *only* to this subscription.
* **Activity Log Diagnostic Setting:** (Only if `deployIOA=true`) Created directly within this subscription to forward its Activity Logs to the Event Hub specified during deployment (typically the central one in the default subscription).

### 4. Default Subscription Resources (Only if `deployIOA=true`)

When IOA is enabled, a significant set of infrastructure is deployed into *one* designated "default subscription" (specified via the `defaultSubscriptionId` parameter). This centralizes log ingestion and processing:

* **Resource Group:** Container for all IOA resources.
    * **Name:** `cs-ioa-group` (default)
* **Event Hub Namespace & Event Hubs:** Receives logs from Entra ID and Azure Activity Logs.
    * **Namespace Name:** `cs-horizon-ns-{subscription_id}` (default)
    * **Event Hubs:** `cs-eventhub-monitor-activity-logs`, `cs-eventhub-monitor-aad-logs` (default)
    * **Authorization Rule:** `cs-eventhub-monitor-auth-rule` (default)
* **Storage Accounts:** Used for function app operations and potentially log archiving/buffering.
    * **Names (example patterns):** `cshorizonlog{randomsuffix}`, `cshorizonact{randomsuffix}`, `cshorizonaad{randomsuffix}`
* **Key Vault:** Stores secrets and keys needed by the function apps.
    * **Name:** `cs-kv-{randomsuffix}` (default)
    * **Contents:** Includes keys for storage and secrets for the App Registration (`cs-client-id`, `cs-client-secret`).
* **App Service Plans:** Hosting plans for the processing functions.
    * **Names:** `cs-activity-service-plan`, `cs-aad-service-plan` (default)
    * **Tier:** Premium V3 (P0V3) by default.
* **Function Apps:** Process logs from Event Hubs and forward them to CrowdStrike.
    * **Names:** `cs-activity-func-{subscription_id}`, `cs-aad-func-{subscription_id}` (default)
    * **Managed Identities:** Each function app has its own system-assigned managed identity.
* **Networking:** Configures network isolation using private endpoints.
    * **Virtual Network:** `cs-vnet` (default) with subnets (e.g., `cs-subnet-1`, `cs-subnet-2`, `cs-subnet-3` for functions and endpoints).
    * **Network Security Group:** `cs-nsg` (default) potentially applied to subnets.
    * **Private Endpoints:** Created for Key Vault and Storage Accounts (`kv-private-endpoint`, `log-storage-private-endpoint`, etc.) connecting them to the VNet.

### 5. All Subscriptions Resources (Effect of MG Policy or Individual Deployments)

* **Activity Log Diagnostic Settings:** (Only if `deployIOA=true`) This setting exists in *each* subscription managed by the Management Group policy or in any subscription where the template was deployed individually.
    * **Name:** `cs-monitor-activity-to-eventhub` (default)
    * **Action:** Forwards Activity Logs to the central `cs-eventhub-monitor-activity-logs` Event Hub located in the default subscription.

## Resource Naming Conventions

Resource names typically follow a pattern using `cs-` as a prefix, followed by a descriptive component and often a dynamic suffix (like a shortened subscription ID or random characters) to ensure uniqueness (e.g., `cs-horizon-ns-{subscription_id}`, `cs-kv-{randomsuffix}`).

## Scaling and Sizing (IOA Components)

* **Event Hub Namespace:** Deployed with **Standard** tier, typically configured with Auto-Inflate enabled (e.g., scaling between 2-10 Throughput Units by default).
* **Function Apps:** Deployed on **Premium V3 (P0V3)** App Service Plans by default, allowing for auto-scaling (e.g., between 1-4 instances per function by default).

## Considerations for Multi-Subscription Tenants

* **Management Group Scope:** Highly recommended for ease of management, consistent permission application, and automatic configuration of log forwarding for all subscriptions via Azure Policy.
* **Centralized IOA Infrastructure:** The log ingestion components (Event Hubs, Functions, etc.) are deployed only *once* into the default subscription, minimizing resource duplication and cost concentration.
* **Minimal Per-Subscription Impact:** Subscriptions outside the default one only incur the configuration of RBAC assignments (if applied at MG scope) and a single Diagnostic Setting for Activity Logs (if IOA is enabled).

## Cost Considerations

* **Primary Cost Center:** The majority of Azure consumption costs will originate from the **default subscription** hosting the IOA resources (Event Hubs, Function Apps, Storage, Key Vault, Networking).
* **Cost Factors:** Costs depend heavily on the volume of logs processed (Entra ID and Activity Logs), data transfer, Azure region, storage consumption, and the scaling behavior of the Event Hubs and Function Apps.
* **Other Subscriptions:** Costs in other subscriptions are negligible, primarily related to the existence of the diagnostic setting itself.
* **IOM Only:** If `deployIOA` is `false`, only the App Registration and RBAC assignments are created, resulting in minimal Azure cost.

## Source of Truth

The official CrowdStrike Bicep templates are the definitive source for the deployed resources and configurations:
**GitHub Repository:** [https://github.com/CrowdStrike/cs-azure-integration-bicep](https://github.com/CrowdStrike/cs-azure-integration-bicep)
