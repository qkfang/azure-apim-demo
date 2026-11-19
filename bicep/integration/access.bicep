// Client access to the APIs published by apps/api.bicep: APIM products and subscriptions, defined in apim-config.json.
// Owned by the integration team. Run after apps/api.bicep (the APIs must exist).
targetScope = 'resourceGroup'

import { apimNameFor, productsApiName, productsMcpApiName } from '../settings.bicep'

@description('Same base name used for platform/main.bicep.')
param baseName string

var apimName = apimNameFor(baseName)

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

resource api 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' existing = {
  parent: apim
  name: productsApiName
}

resource mcpApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' existing = {
  parent: apim
  name: productsMcpApiName
}

// Every product exposes the REST API and the MCP server.
var config = loadJsonContent('apim-config.json')

resource products 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = [for p in config.products: {
  parent: apim
  name: p.name
  properties: {
    displayName: p.displayName
    description: p.?description
    state: p.?state ?? 'published'
    subscriptionRequired: p.?subscriptionRequired ?? true
    approvalRequired: p.?approvalRequired ?? false
    subscriptionsLimit: p.?subscriptionsLimit
  }
}]

resource productApis 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = [for (p, i) in config.products: {
  parent: products[i]
  name: api.name
}]

resource productMcpApis 'Microsoft.ApiManagement/service/products/apis@2025-09-01-preview' = [for (p, i) in config.products: {
  parent: products[i]
  name: mcpApi.name
}]

// 'demo-tests' is used by the integration tests in tests/ (its key is fetched at runtime by the workflow).
resource subscriptions 'Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview' = [for s in config.subscriptions: {
  parent: apim
  name: s.name
  properties: {
    displayName: s.displayName
    scope: '${apim.id}/products/${s.product}'
    state: s.?state ?? 'active'
  }
  dependsOn: [products, productApis, productMcpApis]
}]

output products array = [for p in config.products: p.name]
output subscriptions array = [for s in config.subscriptions: s.name]
