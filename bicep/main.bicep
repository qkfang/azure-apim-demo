// Core infrastructure: API Management, Azure AI Gateway, Function App (+ plan, storage, App Insights).
// The API / MCP server are published to APIM and the AI Gateway by api.bicep and aigateway-mcp.bicep
// after the function code is deployed.
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

@description('APIM SKU. MCP servers in APIM are not supported on Consumption, so the default is Developer.')
@allowed(['Developer', 'Basic', 'Standard', 'Premium', 'BasicV2', 'StandardV2', 'PremiumV2'])
param apimSku string = 'Developer'

@description('Region for the Azure AI Gateway (preview: eastus2 or swedencentral).')
@allowed(['eastus2', 'swedencentral'])
param aiGatewayLocation string = 'eastus2'

var apimName = 'apim-${baseName}'
var aiGatewayName = 'aigw-${baseName}'
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
    // Public access is forced off by policy; the Function App reaches storage through private endpoints.
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-${baseName}'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.20.0.0/16'] }
    subnets: [
      {
        name: 'snet-integration'
        properties: {
          addressPrefix: '10.20.1.0/24'
          delegations: [
            {
              name: 'web'
              properties: { serviceName: 'Microsoft.Web/serverFarms' }
            }
          ]
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: { addressPrefix: '10.20.2.0/24' }
      }
    ]
  }
}

var storageServices = ['blob', 'queue', 'table']

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for svc in storageServices: {
  name: 'privatelink.${svc}.${environment().suffixes.storage}'
  location: 'global'
}]

resource dnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (svc, i) in storageServices: {
  parent: dnsZones[i]
  name: 'link-${baseName}'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}]

resource storageEndpoints 'Microsoft.Network/privateEndpoints@2024-01-01' = [for svc in storageServices: {
  name: 'pe-${storageName}-${svc}'
  location: location
  properties: {
    subnet: { id: vnet.properties.subnets[1].id }
    privateLinkServiceConnections: [
      {
        name: svc
        properties: {
          privateLinkServiceId: storage.id
          groupIds: [svc]
        }
      }
    ]
  }
}]

resource endpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = [for (svc, i) in storageServices: {
  parent: storageEndpoints[i]
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: svc
        properties: { privateDnsZoneId: dnsZones[i].id }
      }
    ]
  }
}]

// Standard (dedicated) Linux plan. Consumption/Premium need a key-based Azure Files content share,
// which is blocked when storage shared-key access is disabled.
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-${baseName}'
  location: location
  kind: 'linux'
  sku: {
    name: 'S1'
    tier: 'Standard'
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
  dependsOn: [endpointDns]
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
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Azure AI Gateway (preview): a separate resource type from APIM. The Function App's MCP endpoint
// is registered on it as a tool server by aigateway-mcp.bicep (after the function code is deployed).
#disable-next-line BCP081
resource aiGateway 'Microsoft.ApiManagement/aigateways@2026-11-01' = {
  name: aiGatewayName
  location: aiGatewayLocation
  identity: { type: 'SystemAssigned' }
  properties: {}
}

output apimName string = apim.name
output aiGatewayName string = aiGateway.name
output aiGatewayUrl string = 'https://${aiGateway.properties.frontend.defaultHostname}'
output apimGatewayUrl string = apim.properties.gatewayUrl
output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
