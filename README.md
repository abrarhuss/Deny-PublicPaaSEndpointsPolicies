# Deny Public PaaS Endpoints — Azure Policy Initiative

A custom Azure Policy **initiative** (policy set definition) that prevents the creation of Azure PaaS services with exposed public network endpoints. It bundles Azure built-in policies so that public network access is denied (or audited) across a broad set of PaaS services.

> Adapted from the [Azure Enterprise-Scale (ALZ)](https://github.com/Azure/Enterprise-Scale/) `Deny-PublicPaaSEndpoints` initiative, restructured for direct deployment via Azure CLI / PowerShell / portal.

## Contents

- [`Deny-PublicPaaSEndpoints.json`](Deny-PublicPaaSEndpoints.json) — the policy set definition body (properties only, no ARM wrapper).

## What it does

The initiative groups built-in policies that each disable or audit public network access for a specific service. Each policy is controlled by its own `effect` parameter, so you can tune enforcement per service.

| Category | Services covered |
| --- | --- |
| Data & databases | Cosmos DB, Azure SQL, SQL Managed Instance, PostgreSQL (single & flexible), MySQL (single & flexible), MariaDB, Synapse |
| Storage & disks | Storage accounts, Azure File Sync, Managed Disks |
| Compute & containers | AKS, Container Registry (ACR), Container Apps & environment, Batch, App Service, App Service slots, App Service Environment, Function apps & slots |
| Integration & messaging | Event Grid (domains & topics), Event Hubs, Service Bus |
| AI & analytics | Machine Learning, Cognitive Services, Cognitive Search, Azure Data Explorer (ADX), Data Factory (ADF), Grafana |
| Security & management | Key Vault, Key Vault Managed HSM, App Configuration, Automation accounts, Recovery Services vaults, Bot Service, API Management |
| Virtual Desktop | AVD host pools, AVD workspaces |

## Parameters

Every service has a dedicated effect parameter (e.g. `CosmosPublicIpDenyEffect`, `storageAccountsPublicAccess`). Allowed values are typically `Audit`, `Deny`, `Disabled`.

**Default values:**
- Most parameters default to `Deny`.
- `managedDiskPublicNetworkAccess` defaults to `Audit` (allowed values: `Audit`, `Disabled`).
- `ApiManPublicIpDenyEffect` defaults to `AuditIfNotExists` (allowed values: `AuditIfNotExists`, `Disabled`).

## Deploy

### PowerShell (Az module)

```powershell
$body = Get-Content '.\Deny-PublicPaaSEndpoints.json' -Raw | ConvertFrom-Json

New-AzPolicySetDefinition `
  -Name "Deny-PublicPaaSEndpoints" `
  -DisplayName $body.displayName `
  -Description $body.description `
  -Metadata ($body.metadata | ConvertTo-Json -Depth 50) `
  -Parameter ($body.parameters | ConvertTo-Json -Depth 50) `
  -PolicyDefinition ($body.policyDefinitions | ConvertTo-Json -Depth 50) `
  -ManagementGroupName 'IRCC'
```

Drop `-ManagementGroupName` to create it at the current subscription scope, or use `-SubscriptionId <id>`.

### Azure CLI

```powershell
$body = Get-Content '.\Deny-PublicPaaSEndpoints.json' -Raw | ConvertFrom-Json
$body.policyDefinitions | ConvertTo-Json -Depth 50 | Set-Content '.\definitions.json'
$body.parameters        | ConvertTo-Json -Depth 50 | Set-Content '.\params.json'

az policy set-definition create `
  --name "Deny-PublicPaaSEndpoints" `
  --display-name "Public network access should be disabled for PaaS services" `
  --description "This policy initiative is a group of policies that prevents creation of Azure PaaS services with exposed public endpoints" `
  --management-group "IRCC" `
  --definitions "@definitions.json" `
  --params "@params.json"
```

### Assign the initiative

After the definition is created, assign it to a scope (management group, subscription, or resource group):

```powershell
$def = Get-AzPolicySetDefinition -Name "Deny-PublicPaaSEndpoints" -ManagementGroupName 'IRCC'

New-AzPolicyAssignment `
  -Name "deny-public-paas" `
  -DisplayName "Deny Public PaaS Endpoints" `
  -PolicySetDefinition $def `
  -Scope "/providers/Microsoft.Management/managementGroups/IRCC"
```

## Notes

- **No ARM wrapper.** The JSON contains only the policy set definition body (`policyType`, `displayName`, `description`, `metadata`, `parameters`, `policyDefinitions`, `policyDefinitionGroups`). This avoids the `Could not find member 'name' ... Path 'properties.name'` deserialization error.
- **Parameter references use single brackets** (`[parameters('...')]`), which is correct for direct CLI/PowerShell/portal deployment. The ALZ double-bracket escaping (`[[parameters('...')]`) is only needed when the JSON is embedded inside an ARM template.
- **Logic App policy removed.** The original ALZ initiative referenced a custom `Deny-LogicApp-Public-Network` definition that only exists in ALZ-managed environments. It was removed so the initiative deploys against built-in policies only. To re-add it, first create that custom policy definition in your management group, then add a corresponding `policyDefinitions` entry and parameter.
- All referenced policies use floating `definitionVersion` values (e.g. `1.*.*`) to pick up the latest compatible built-in policy version.

## Customizing enforcement

To change the effect for a service at assignment time, pass parameter values. For example, to audit (rather than deny) storage:

```powershell
New-AzPolicyAssignment `
  -Name "deny-public-paas" `
  -PolicySetDefinition $def `
  -Scope "/providers/Microsoft.Management/managementGroups/IRCC" `
  -PolicyParameterObject @{ storageAccountsPublicAccess = "Audit" }
```
