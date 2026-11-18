// Publishes the Function App's REST API into the existing APIM instance, using swagger/swagger.json.
// Run after main.bicep and after the function code has been deployed (the host key must exist).
targetScope = 'resourceGroup'

@description('Same base name used for main.bicep.')
param baseName string

@description('APIM URL suffix for the API.')
param apiPath string = 'demo'

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

resource product 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apim
  name: 'demo'
  properties: {
    displayName: 'Demo'
    description: 'Demo product exposing the Products API.'
    state: 'published'
    subscriptionRequired: true
    approvalRequired: false
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: product
  name: api.name
}

output apiBaseUrl string = '${apim.properties.gatewayUrl}/${apiPath}'
