// Platform infrastructure: API Management, Azure AI Gateway, monitoring, storage and network.
// The App Service plan (integration/plan.bicep) and Function App (apps/functionapp.bicep) are deployed
// afterwards by their own teams; they consume the storage, VNet and App Insights created here.
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

@description('APIM SKU. MCP servers need a non-Consumption tier and workspaces need a v2 or Premium tier, so the default is StandardV2.')
@allowed(['Developer', 'Basic', 'Standard', 'Premium', 'BasicV2', 'StandardV2', 'PremiumV2'])
param apimSku string = 'StandardV2'

@description('Region for the Azure AI Gateway (preview: eastus2 or swedencentral).')
@allowed(['eastus2', 'swedencentral'])
param aiGatewayLocation string = 'eastus2'

var apimName = 'apim-${baseName}'
var aiGatewayName = 'aigw-${baseName}'
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
// is registered on it as a tool server by integration/aigateway-mcp.bicep.
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
