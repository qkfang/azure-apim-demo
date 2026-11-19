// Registers the Function App's MCP endpoint (/api/mcp) as an MCP tool server on the Azure AI Gateway
// created by main.bicep. Run after the function code has been deployed (the host key must exist).
// Clients call https://<gateway-host>/default/toolservers/<serverName>/mcp with a gateway runtime API key;
// tools are published as <namespace>_<tool> (for example products_listProducts).
targetScope = 'resourceGroup'

import { aiGatewayNameFor, functionAppNameFor } from '../settings.bicep'

@description('Same base name used for platform/main.bicep.')
param baseName string

@description('MCP server name; part of the endpoint URL and cannot be changed after creation.')
param serverName string = 'products'

@description('Namespace prefix for the backend tools.')
param namespace string = 'products'

var aiGatewayName = aiGatewayNameFor(baseName)
var functionAppName = functionAppNameFor(baseName)

#disable-next-line BCP081
resource gateway 'Microsoft.ApiManagement/aigateways@2026-11-01' existing = {
  name: aiGatewayName
}

#disable-next-line BCP081
resource workspace 'Microsoft.ApiManagement/aigateways/workspaces@2026-11-01' existing = {
  parent: gateway
  name: 'default'
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

#disable-next-line BCP081
resource toolServer 'Microsoft.ApiManagement/aigateways/workspaces/toolServers@2026-11-01' = {
  parent: workspace
  name: serverName
  properties: {
    displayName: 'Products MCP'
    description: 'Products operations (health, list, get, create, update, delete) from the Function App.'
    toolServerType: 'mcp'
    endpoints: [
      {
        namespace: namespace
        kind: 'mcp'
        mode: 'failClosed'
        mcp: {
          endpoint: {
            url: 'https://${functionApp.properties.defaultHostName}/api/mcp'
          }
          transport: 'streamableHttp'
        }
        // Function host key sent to the backend; the gateway stores it and clients never see it.
        authentication: {
          headers: [
            {
              name: 'x-functions-key'
              value: listKeys('${functionApp.id}/host/default', '2023-12-01').functionKeys.default
            }
          ]
        }
      }
    ]
  }
}

// Runtime key for MCP clients (value is never an output; read it with `az aigateway api-key list-secrets`).
#disable-next-line BCP081
resource apiKey 'Microsoft.ApiManagement/aigateways/apiKeys@2026-11-01' = {
  parent: gateway
  name: 'products-mcp-client'
  properties: {
    displayName: 'Products MCP client'
  }
}

output toolServerId string = toolServer.id
output mcpEndpoint string = 'https://${gateway.properties.frontend.defaultHostname}/default/toolservers/${serverName}/mcp'
