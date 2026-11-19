// Function App that implements the Products REST API / MCP server. Owned by the apps team.
// Deploy after platform/main.bicep (storage, VNet, App Insights) and integration/plan.bicep (App Service plan).
targetScope = 'resourceGroup'

@description('Same base name used for main.bicep.')
param baseName string

@description('Azure region.')
param location string = resourceGroup().location

var functionAppName = 'func-${baseName}'
// Must match the storage account name derived in platform/main.bicep.
var storageName = take('st${baseName}${uniqueString(resourceGroup().id)}', 24)

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: 'appi-${baseName}'
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: 'vnet-${baseName}'
}

resource plan 'Microsoft.Web/serverfarms@2023-12-01' existing = {
  name: 'plan-${baseName}'
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    virtualNetworkSubnetId: vnet.properties.subnets[0].id
    siteConfig: {
      linuxFxVersion: 'Node|20'
      alwaysOn: true
      vnetRouteAllEnabled: true
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

output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
