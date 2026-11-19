// Convenience entry point that deploys everything the apps team owns: the Function App and the API / MCP server.
// The pipelines deploy functionapp.bicep (workflow 31) and api.bicep (workflow 32) separately, because the API
// needs the function host key, which only exists once the function code is deployed.
// Needs platform/main.bicep and integration/plan.bicep deployed first.
targetScope = 'resourceGroup'

@description('Same base name used for platform/main.bicep.')
param baseName string

@description('Azure region.')
param location string = resourceGroup().location

module functionApp 'functionapp.bicep' = {
  name: 'functionapp'
  params: {
    baseName: baseName
    location: location
  }
}

module api 'api.bicep' = {
  name: 'api'
  params: {
    baseName: baseName
  }
  dependsOn: [functionApp]
}

output functionAppName string = functionApp.outputs.functionAppName
output functionAppHostName string = functionApp.outputs.functionAppHostName
output apiBaseUrl string = api.outputs.apiBaseUrl
output mcpEndpoint string = api.outputs.mcpEndpoint
