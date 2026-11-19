// Everything the integration team deploys: the App Service plan, client access to APIM (products and
// subscriptions), the APIM workspace and the MCP tool server on the AI Gateway.
// Needs platform/main.bicep deployed first. Access, workspace and AI Gateway registration need the apps team's
// API and function code, so deploy with deployAppIntegration=false to create only the plan (before the Function
// App exists) and with the default afterwards.
targetScope = 'resourceGroup'

@description('Same base name used for platform/main.bicep.')
param baseName string

@description('Azure region.')
param location string = resourceGroup().location

@description('Deploy the pieces that depend on the apps team deployment (access, workspace, AI Gateway MCP).')
param deployAppIntegration bool = true

module plan 'plan.bicep' = {
  name: 'plan'
  params: {
    baseName: baseName
    location: location
  }
}

module access 'access.bicep' = if (deployAppIntegration) {
  name: 'access'
  params: {
    baseName: baseName
  }
}

module workspace 'workspace.bicep' = if (deployAppIntegration) {
  name: 'workspace'
  params: {
    baseName: baseName
  }
}

module aiGatewayMcp 'aigateway-mcp.bicep' = if (deployAppIntegration) {
  name: 'aigateway-mcp'
  params: {
    baseName: baseName
  }
}

output planName string = plan.outputs.planName
output workspaceApiBaseUrl string = workspace.?outputs.apiBaseUrl ?? ''
output aiGatewayMcpEndpoint string = aiGatewayMcp.?outputs.mcpEndpoint ?? ''
