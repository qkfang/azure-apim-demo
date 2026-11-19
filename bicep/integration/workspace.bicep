// Creates an APIM workspace and publishes the same Products REST API (swagger/swagger.json) into it,
// with its own named value, product and subscription. Run after main.bicep and the function code deployment.
// Workspaces need a Basic v2, Standard v2, Premium or Premium v2 APIM service and don't support MCP servers,
// so only the REST API is published here (the MCP server stays at service level in api.bicep).
// Resource names must be unique across the whole APIM service, hence the 'ws-' / workspace-name prefixes.
targetScope = 'resourceGroup'

@description('Same base name used for main.bicep.')
param baseName string

@description('APIM URL suffix for the workspace copy of the API (paths must be unique per gateway).')
param apiPath string = 'ws-products-api'

// Also used to prefix the resources created in the workspace.
var workspaceName = 'products-team'
var apimName = 'apim-${baseName}'
var functionAppName = 'func-${baseName}'

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' existing = {
  name: apimName
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

// 'serveOn' (v2 tiers) routes the workspace through the service's default managed gateway; it isn't in the
// published Bicep types yet.
resource workspace 'Microsoft.ApiManagement/service/workspaces@2024-05-01' = {
  parent: apim
  name: workspaceName
  properties: {
    displayName: 'Products team'
    description: 'Workspace owned by the Products API team.'
    #disable-next-line BCP037
    serveOn: 'workspaceAndDefault'
  }
}

// Workspace policies can't reference service-level named values, so the function host key is duplicated here.
resource functionKey 'Microsoft.ApiManagement/service/workspaces/namedValues@2024-05-01' = {
  parent: workspace
  name: '${workspaceName}-function-host-key'
  properties: {
    displayName: '${workspaceName}-function-host-key'
    secret: true
    value: listKeys('${functionApp.id}/host/default', '2023-12-01').functionKeys.default
  }
}

resource api 'Microsoft.ApiManagement/service/workspaces/apis@2024-05-01' = {
  parent: workspace
  name: '${workspaceName}-products-api'
  properties: {
    displayName: 'Products API (${workspaceName})'
    path: apiPath
    protocols: ['https']
    subscriptionRequired: true
    serviceUrl: 'https://${functionApp.properties.defaultHostName}/api'
    format: 'swagger-json'
    value: loadTextContent('../swagger/swagger.json')
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/workspaces/apis/policies@2024-05-01' = {
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
      <value>{{products-team-function-host-key}}</value>
    </set-header>
  </inbound>
  <backend><base /></backend>
  <outbound><base /></outbound>
  <on-error><base /></on-error>
</policies>
'''
  }
}

resource product 'Microsoft.ApiManagement/service/workspaces/products@2024-05-01' = {
  parent: workspace
  name: '${workspaceName}-product'
  properties: {
    displayName: 'Products team'
    description: 'Workspace product exposing the Products API.'
    state: 'published'
    subscriptionRequired: true
    approvalRequired: false
  }
}

resource productApi 'Microsoft.ApiManagement/service/workspaces/products/apiLinks@2024-05-01' = {
  parent: product
  name: 'products-api'
  properties: {
    apiId: api.id
  }
}

// 'products-team-tests' is used by the integration tests in tests/ (its key is fetched at runtime by the workflow).
resource subscription 'Microsoft.ApiManagement/service/workspaces/subscriptions@2024-05-01' = {
  parent: workspace
  name: '${workspaceName}-tests'
  properties: {
    displayName: 'Workspace integration tests'
    scope: product.id
    state: 'active'
  }
  dependsOn: [productApi]
}

output workspaceName string = workspace.name
output apiBaseUrl string = '${apim.properties.gatewayUrl}/${apiPath}'
output subscriptionName string = subscription.name
