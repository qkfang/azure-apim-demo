using 'main.bicep'

// baseName must be globally unique (it forms the APIM / Function App host names).
param baseName = readEnvironmentVariable('BASE_NAME', 'apimdemoqf01')
param envName = readEnvironmentVariable('ENV_NAME', 'dev')
param publisherEmail = readEnvironmentVariable('PUBLISHER_EMAIL', 'admin@example.com')
