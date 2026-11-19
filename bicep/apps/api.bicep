// Publishes the Function App's REST API and MCP server into the existing APIM instance, using swagger/swagger.json.
// Run after main.bicep and after the function code has been deployed (the host key must exist).
targetScope = 'resourceGroup'

import { apimNameFor, functionAppNameFor, productsApiName, productsMcpApiName, productsApiPath, productsMcpPath } from '../settings.bicep'

@description('Same base name used for main.bicep.')
param baseName string

var apiPath = productsApiPath
var mcpPath = productsMcpPath
var apimName = apimNameFor(baseName)
var functionAppName = functionAppNameFor(baseName)

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
  name: productsApiName
  properties: {
    displayName: 'Products API'
    path: apiPath
    protocols: ['https']
    subscriptionRequired: true
    serviceUrl: 'https://${functionApp.properties.defaultHostName}/api'
    format: 'swagger-json'
    value: loadTextContent('../../swagger/swagger.json')
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
// A passthrough ("existing MCP server") needs a backend entity linked via backendId; with only serviceUrl,
// APIM treats the API as a plain API and serves an empty tool list itself.
resource mcpBackend 'Microsoft.ApiManagement/service/backends@2025-09-01-preview' = {
  parent: apim
  name: 'products-mcp-backend'
  properties: {
    description: 'Function App hosting the MCP endpoint'
    url: 'https://${functionApp.properties.defaultHostName}/api'
    protocol: 'http'
  }
}

resource mcpApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: apim
  name: productsMcpApiName
  properties: {
    type: 'mcp'
    displayName: 'Products MCP'
    description: 'MCP server exposing the Products operations as tools.'
    path: mcpPath
    protocols: ['https']
    subscriptionRequired: true
    // Not yet in the published Bicep types, but required for passthrough MCP servers.
    #disable-next-line BCP037
    backendId: mcpBackend.name
    mcpProperties: {
      transportType: 'streamable'
      // The service expects a dictionary keyed by endpoint name (the published Bicep type says array).
      #disable-next-line BCP036
      endpoints: {
        mcp: { uriTemplate: '/mcp' }
      }
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

output apiBaseUrl string = '${apim.properties.gatewayUrl}/${apiPath}'
output mcpEndpoint string = '${apim.properties.gatewayUrl}/${mcpPath}/mcp'
