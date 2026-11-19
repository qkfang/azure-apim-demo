// Shared settings for all teams (platform, integration, apps): resource naming and the names the teams use to
// refer to each other's resources. Import what you need, for example:
//   import { apimNameFor } from '../settings.bicep'
// Changing a value here changes it for every team's templates.

@export()
func apimNameFor(baseName string) string => 'apim-${baseName}'

@export()
func aiGatewayNameFor(baseName string) string => 'aigw-${baseName}'

@export()
func functionAppNameFor(baseName string) string => 'func-${baseName}'

@export()
func planNameFor(baseName string) string => 'plan-${baseName}'

@export()
func appInsightsNameFor(baseName string) string => 'appi-${baseName}'

@export()
func logAnalyticsNameFor(baseName string) string => 'log-${baseName}'

@export()
func vnetNameFor(baseName string) string => 'vnet-${baseName}'

@export()
func storageNameFor(baseName string, resourceGroupId string) string => take('st${baseName}${uniqueString(resourceGroupId)}', 24)

// APIs published by the apps team and referenced by the integration team.
@export()
var productsApiName = 'products-api'

@export()
var productsMcpApiName = 'products-mcp'

@export()
var productsApiPath = 'products-api'

@export()
var productsMcpPath = 'products-mcp'

// APIM workspace owned by the integration team.
@export()
var workspaceName = 'products-team'

@export()
var workspaceApiPath = 'ws-products-api'
