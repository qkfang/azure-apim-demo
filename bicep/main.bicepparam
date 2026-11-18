using 'main.bicep'

// baseName must be globally unique (it forms the APIM / Function App host names).
param baseName = readEnvironmentVariable('BASE_NAME', 'apimdemo01')
param publisherEmail = readEnvironmentVariable('PUBLISHER_EMAIL', 'admin@example.com')
