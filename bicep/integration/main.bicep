// Convenience entry point that deploys everything the integration team owns: the App Service plan, client access
// to APIM (products and subscriptions), the APIM workspace and the MCP tool server on the AI Gateway.
// The pipelines deploy plan.bicep (workflow 30) and access / workspace / aigateway-mcp (workflow 20) separately,
// because the latter need the apps team's API and function code.
// Needs platform/main.bicep deployed first.
targetScope = 'resourceGroup'

@description('Same base name used for platform/main.bicep.')
param baseName string

@description('Azure region.')
param location string = resourceGroup().location

module plan 'plan.bicep' = {
  name: 'plan'
  params: {
    baseName: baseName
    location: location
  }
}

module access 'access.bicep' = {
  name: 'access'
  params: {
    baseName: baseName
  }
}

module workspace 'workspace.bicep' = {
  name: 'workspace'
  params: {
    baseName: baseName
  }
}

module aiGatewayMcp 'aigateway-mcp.bicep' = {
  name: 'aigateway-mcp'
  params: {
    baseName: baseName
  }
}

output planName string = plan.outputs.planName
output workspaceApiBaseUrl string = workspace.outputs.apiBaseUrl
output aiGatewayMcpEndpoint string = aiGatewayMcp.outputs.mcpEndpoint
