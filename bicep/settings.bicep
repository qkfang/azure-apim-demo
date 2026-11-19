// Shared settings for all teams (platform, integration, apps): resource naming and the names the teams use to
// refer to each other's resources. Import what you need, for example:
//   import { apimNameFor } from '../settings.bicep'
// Changing a value here changes it for every team's templates.

// Deployment environments. Every resource name carries the environment, so environments never collide
// (even when they share a resource group or subscription).
@export()
type envType = 'dev' | 'uat' | 'prd'

@export()
func apimNameFor(baseName string, envName envType) string => 'apim-${baseName}-${envName}'

@export()
func aiGatewayNameFor(baseName string, envName envType) string => 'aigw-${baseName}-${envName}'

@export()
func functionAppNameFor(baseName string, envName envType) string => 'func-${baseName}-${envName}'

@export()
func planNameFor(baseName string, envName envType) string => 'plan-${baseName}-${envName}'

@export()
func appInsightsNameFor(baseName string, envName envType) string => 'appi-${baseName}-${envName}'

@export()
func logAnalyticsNameFor(baseName string, envName envType) string => 'log-${baseName}-${envName}'

@export()
func vnetNameFor(baseName string, envName envType) string => 'vnet-${baseName}-${envName}'

@export()
func storageNameFor(baseName string, envName envType, resourceGroupId string) string => take('st${baseName}${envName}${uniqueString(resourceGroupId)}', 24)

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
