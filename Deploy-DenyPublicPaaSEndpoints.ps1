#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
    Deploys the "Deny-PublicPaaSEndpoints" policy set definition (initiative) to a
    management group, handling Azure login and subscription context.

.DESCRIPTION
    This script:
      1. Signs in to Azure (interactive) if no context exists.
      2. Sets the active subscription context.
      3. Reads the initiative body from Deny-PublicPaaSEndpoints.json.
      4. Creates (or updates) the policy set definition at the target management group.
      5. Optionally assigns the initiative to the management group scope.

.PARAMETER ManagementGroupName
    The management group to create the policy set definition in. Defaults to 'IRCC'.

.PARAMETER SubscriptionId
    The subscription to use for the Azure context. Required so ARM calls have a
    subscription to operate against. If omitted, the current context subscription is used.

.PARAMETER TenantId
    Optional tenant id to use when connecting to Azure.

.PARAMETER DefinitionFile
    Path to the initiative JSON body. Defaults to Deny-PublicPaaSEndpoints.json next to this script.

.PARAMETER Assign
    Switch. When supplied, also creates a policy assignment for the initiative at the
    management group scope.

.EXAMPLE
    ./Deploy-DenyPublicPaaSEndpoints.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000'

.EXAMPLE
    ./Deploy-DenyPublicPaaSEndpoints.ps1 -ManagementGroupName 'IRCC' -SubscriptionId '<id>' -Assign
#>

[CmdletBinding()]
param(
    [string]$ManagementGroupName = 'IRCC',

    [string]$SubscriptionId,

    [string]$TenantId,

    [string]$DefinitionFile = (Join-Path $PSScriptRoot 'Deny-PublicPaaSEndpoints.json'),

    [string]$DefinitionName = 'Deny-PublicPaaSEndpoints',

    [switch]$Assign
)

$ErrorActionPreference = 'Stop'

# --- 1. Ensure Azure login ---------------------------------------------------
Write-Host 'Checking Azure context...' -ForegroundColor Cyan
$context = Get-AzContext -ErrorAction SilentlyContinue

if (-not $context) {
    Write-Host 'No Azure context found. Signing in...' -ForegroundColor Yellow
    $connectParams = @{}
    if ($TenantId)       { $connectParams['Tenant']       = $TenantId }
    if ($SubscriptionId) { $connectParams['Subscription'] = $SubscriptionId }
    Connect-AzAccount @connectParams | Out-Null
    $context = Get-AzContext
}

# --- 2. Set subscription context --------------------------------------------
if ($SubscriptionId -and $context.Subscription.Id -ne $SubscriptionId) {
    Write-Host "Setting subscription context to $SubscriptionId..." -ForegroundColor Cyan
    Set-AzContext -Subscription $SubscriptionId | Out-Null
    $context = Get-AzContext
}

Write-Host "Using account : $($context.Account.Id)"       -ForegroundColor Green
Write-Host "Subscription  : $($context.Subscription.Name) ($($context.Subscription.Id))" -ForegroundColor Green
Write-Host "Tenant        : $($context.Tenant.Id)"         -ForegroundColor Green

# --- 3. Read initiative body -------------------------------------------------
if (-not (Test-Path $DefinitionFile)) {
    throw "Definition file not found: $DefinitionFile"
}

Write-Host "Reading initiative from $DefinitionFile..." -ForegroundColor Cyan
$body = Get-Content $DefinitionFile -Raw | ConvertFrom-Json

# --- 4. Create / update the policy set definition ---------------------------
Write-Host "Creating policy set definition '$DefinitionName' at management group '$ManagementGroupName'..." -ForegroundColor Cyan

$setDefinition = New-AzPolicySetDefinition `
    -Name              $DefinitionName `
    -DisplayName       $body.displayName `
    -Description       $body.description `
    -Metadata          ($body.metadata          | ConvertTo-Json -Depth 50) `
    -Parameter         ($body.parameters        | ConvertTo-Json -Depth 50) `
    -PolicyDefinition  ($body.policyDefinitions | ConvertTo-Json -Depth 50) `
    -ManagementGroupName $ManagementGroupName

Write-Host "Policy set definition created:" -ForegroundColor Green
Write-Host "  ResourceId: $($setDefinition.ResourceId)"

# --- 5. Optional assignment --------------------------------------------------
if ($Assign) {
    $scope = "/providers/Microsoft.Management/managementGroups/$ManagementGroupName"
    Write-Host "Assigning initiative to scope $scope..." -ForegroundColor Cyan

    $assignment = New-AzPolicyAssignment `
        -Name               'deny-public-paas' `
        -DisplayName        'Deny Public PaaS Endpoints' `
        -PolicySetDefinition $setDefinition `
        -Scope              $scope

    Write-Host "Assignment created: $($assignment.ResourceId)" -ForegroundColor Green
}

Write-Host 'Done.' -ForegroundColor Green
