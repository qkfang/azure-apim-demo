// App Service plan that hosts the Function App (apps/functionapp.bicep). Owned by the integration team.
// Deploy after platform/main.bicep and before apps/functionapp.bicep.
targetScope = 'resourceGroup'

import { planNameFor } from '../settings.bicep'

@description('Same base name used for main.bicep.')
param baseName string

@description('Azure region.')
param location string = resourceGroup().location

// Standard (dedicated) Linux plan. Consumption/Premium need a key-based Azure Files content share,
// which is blocked when storage shared-key access is disabled.
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planNameFor(baseName)
  location: location
  kind: 'linux'
  sku: {
    name: 'S1'
    tier: 'Standard'
  }
  properties: {
    reserved: true
  }
}

output planName string = plan.name
