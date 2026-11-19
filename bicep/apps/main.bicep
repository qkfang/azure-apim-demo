// Everything the apps team deploys: the Function App and the API / MCP server published to APIM.
// Needs platform/main.bicep and integration/main.bicep (App Service plan) deployed first.
// The API publish step reads the function host key, which only exists once the function code is deployed,
// so deploy with deployApi=false before the first code deployment and with the default afterwards.
targetScope = 'resourceGroup'

@description('Same base name used for platform/main.bicep.')
param baseName string

@description('Azure region.')
param location string = resourceGroup().location

@description('Publish the REST API and MCP server to APIM (needs the function code deployed).')
param deployApi bool = true

module functionApp 'functionapp.bicep' = {
  name: 'functionapp'
  params: {
    baseName: baseName
    location: location
  }
}

module api 'api.bicep' = if (deployApi) {
  name: 'api'
  params: {
    baseName: baseName
  }
  dependsOn: [functionApp]
}

output functionAppName string = functionApp.outputs.functionAppName
output functionAppHostName string = functionApp.outputs.functionAppHostName
output apiBaseUrl string = api.?outputs.apiBaseUrl ?? ''
output mcpEndpoint string = api.?outputs.mcpEndpoint ?? ''
