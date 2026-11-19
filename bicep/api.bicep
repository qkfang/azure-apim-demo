// Publishes the Function App's REST API and MCP server into the existing APIM instance, using swagger/swagger.json.
// Run after main.bicep and after the function code has been deployed (the host key must exist).
targetScope = 'resourceGroup'

@description('Same base name used for main.bicep.')
param baseName string

@description('APIM URL suffix for the API.')
param apiPath string = 'demo'

@description('APIM URL suffix for the MCP server.')
param mcpPath string = 'demo-mcp'

var apimName = 'apim-${baseName}'
var functionAppName = 'func-${baseName}'

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

// Function host key, forwarded by APIM as x-functions-key so the Function App is not callable anonymously.
resource functionKey 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'function-host-key'
  properties: {
    displayName: 'function-host-key'
    secret: true
    value: listKeys('${functionApp.id}/host/default', '2023-12-01').functionKeys.default
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'demo-products-api'
  properties: {
    displayName: 'Demo Products API'
    path: apiPath
    protocols: ['https']
    subscriptionRequired: true
    serviceUrl: 'https://${functionApp.properties.defaultHostName}/api'
    format: 'swagger-json'
    value: loadTextContent('../swagger/swagger.json')
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-09-01-preview' = {
  parent: api
  name: 'policy'
  dependsOn: [functionKey]
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <rate-limit calls="60" renewal-period="60" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{function-host-key}}</value>
    </set-header>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
}

// The same Products operations as an MCP server (passthrough to the Function App's /api/mcp endpoint).
// MCP servers need an APIM tier that supports them (not Consumption) and API version 2025-09-01-preview or later.
resource mcpApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: 'demo-products-mcp'
  properties: {
    type: 'mcp'
    displayName: 'Demo Products MCP'
    description: 'MCP server exposing the Products operations as tools.'
    path: mcpPath
    protocols: ['https']
    subscriptionRequired: true
    serviceUrl: 'https://${functionApp.properties.defaultHostName}/api'
    mcpProperties: {
      transportType: 'streamable'
      endpoints: [
        { name: 'message', uriTemplate: '/mcp' }
      ]
    }
  }
}

// Do not read the response body in MCP policies: it forces buffering and breaks streaming.
resource mcpPolicy 'Microsoft.ApiManagement/service/apis/policies@2025-09-01-preview' = {
  parent: mcpApi
  name: 'policy'
  dependsOn: [functionKey]
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <rate-limit calls="60" renewal-period="60" />
    <set-header name="x-functions-key" exists-action="override">
      <value>{{function-host-key}}</value>
    </set-header>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
}

// Products and subscriptions are defined in apim-config.json; every product exposes the API above.
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
  dependsOn: [products]
}]

output apiBaseUrl string = '${apim.properties.gatewayUrl}/${apiPath}'
output mcpEndpoint string = '${apim.properties.gatewayUrl}/${mcpPath}/mcp'
output products array = [for p in config.products: p.name]
output subscriptions array = [for s in config.subscriptions: s.name]
