// Core infrastructure: API Management, Function App (+ plan, storage, App Insights).
// The API itself is published to APIM by api.bicep after the function code is deployed.
targetScope = 'resourceGroup'

@description('Short, globally-unique base name used to derive resource names (3-12 lowercase letters/digits).')
@minLength(3)
@maxLength(12)
param baseName string

@description('Azure region.')
param location string = resourceGroup().location

@description('APIM publisher e-mail.')
param publisherEmail string

@description('APIM publisher name.')
param publisherName string = 'APIM Demo'

@description('APIM SKU. Consumption is the cheapest and fastest to provision.')
@allowed(['Consumption', 'Developer', 'Basic', 'Standard', 'Premium'])
param apimSku string = 'Consumption'

var apimName = 'apim-${baseName}'
var functionAppName = 'func-${baseName}'
var storageName = take('st${baseName}${uniqueString(resourceGroup().id)}', 24)

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${baseName}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${baseName}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false // key auth is blocked by policy in many tenants; use managed identity
    supportsHttpsTrafficOnly: true
  }
}

// Standard (dedicated) Linux plan. Consumption/Premium need a key-based Azure Files content share,
// which is blocked when storage shared-key access is disabled.
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-${baseName}'
  location: location
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Node|20'
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'AzureWebJobsStorage__accountName', value: storage.name }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'node' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION', value: '~20' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
      ]
    }
  }
}

// Blob Data Owner, Queue Data Contributor, Table Data Contributor
var storageRoleIds = [
  'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
]

resource storageRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in storageRoleIds: {
  scope: storage
  name: guid(storage.id, functionApp.id, roleId)
  properties: {
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
  }
}]

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: apimSku
    capacity: apimSku == 'Consumption' ? 0 : 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
