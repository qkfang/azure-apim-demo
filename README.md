# azure-apim-demo

Azure API Management + CI/CD with GitHub Actions.

```
bicep/        main.bicep (APIM, AI Gateway, Function App, plan, storage, App Insights), api.bicep (publishes REST API + MCP server to APIM), aigateway-mcp.bicep (registers MCP on the AI Gateway)
src/functionapp/  Node.js (v4 model) Azure Function App exposing a REST API
swagger/swagger.json  OpenAPI (Swagger 2.0) definition imported into APIM
.github/workflows/    01-deploy-infra, 02-deploy-functionapp, 03-deploy-api, 04-test-api
tests/                integration tests for the deployed Function App and APIM endpoints
```

## REST API (Function App)

| Method | Route | Description |
| --- | --- | --- |
| GET | `/health` | Health check |
| GET | `/products` | List products |
| POST | `/products` | Create product (`{name, price}`) |
| GET | `/products/{id}` | Get product |
| PUT | `/products/{id}` | Update product |
| DELETE | `/products/{id}` | Delete product |

Data is held in memory (in-memory only). Functions use `authLevel: function`; APIM injects the host key
(`x-functions-key`) via a secret named value, so callers only need an APIM subscription key
(`Ocp-Apim-Subscription-Key`).

Run locally: `cd src/functionapp && npm ci && npm test`, then copy `local.settings.sample.json` to
`local.settings.json` and `func start`.

## Workflows

| Workflow | Trigger | Does |
| --- | --- | --- |
| `01-deploy-infra.yml` | changes to `bicep/main.*` | lint, what-if (PRs), deploy `main.bicep` |
| `02-deploy-functionapp.yml` | changes to `src/functionapp/**` | test, zip, deploy to Function App (does not touch APIM) |
| `03-deploy-api.yml` | changes to `swagger/**` / `api.bicep` / `aigateway-mcp.bicep` / `apim-config.json`, or manual | deploys `api.bicep`: imports `swagger.json` as an APIM API, publishes the MCP server, sets backend + function key policy, and creates the products and subscriptions from `bicep/apim-config.json`; deploys `aigateway-mcp.bicep` (MCP tool server on the AI Gateway); then calls `04-test-api.yml` |
| `04-test-api.yml` | changes to `tests/**`, daily schedule, manual, or called | looks up the function key and APIM subscription key, runs `tests/` against both endpoints |

Order for a first deployment: **01 Deploy infrastructure → 02 Deploy Function App → 03 Publish API to APIM** (which also
runs the tests). 03 needs the function code deployed so the function host key exists; run it manually after 02, or after
changing `swagger/`, `bicep/api.bicep` or `bicep/apim-config.json` (those pushes trigger it automatically).

All workflows can also be started manually (**Actions → pick a workflow → Run workflow**). Manual inputs: `01` and `02`
have `deploy` (uncheck for what-if / build-and-test only), and `03` has `run_tests`.

## Integration tests

`tests/` uses the built-in Node test runner (no dependencies) and checks the same contract (health, product CRUD,
400/404 errors) against the Function App and APIM, plus that unauthenticated calls get 401. Suites are skipped when
their URL isn't set.

```
cd tests
$env:FUNCTION_BASE_URL = "https://func-<BASE_NAME>.azurewebsites.net/api"; $env:FUNCTION_KEY = "<function key>"
$env:APIM_BASE_URL = "https://apim-<BASE_NAME>.azure-api.net/products-api";       $env:APIM_SUBSCRIPTION_KEY = "<apim key>"
npm test
```

## APIM products and subscriptions

Defined in `bicep/apim-config.json` and deployed by `03-deploy-api.yml` (edit the file, push to `main`):

- `products[]`: `name`, `displayName`, optional `description`, `state`, `subscriptionRequired`, `approvalRequired`,
  `subscriptionsLimit`. Every product exposes the Products API.
- `subscriptions[]`: `name`, `displayName`, `product` (a product `name`), optional `state`.

Keep the `demo-tests` subscription on the `demo` product; `04-test-api.yml` uses it. Subscription keys are not stored in
the repo; read them from the portal or `az rest ... /subscriptions/<name>/listSecrets`.

## One-time setup

1. Create a service principal with **Contributor** on the resource group and save its JSON
   (`az ad sp create-for-rbac --sdk-auth ...`) as the secret `AZURE_CREDENTIALS` in the GitHub
   environment **dev** (all deploy/test jobs use `environment: dev`).
2. Repository **variables**:
   - `AZURE_RESOURCE_GROUP` – e.g. `rg-apim-demo`
   - `AZURE_LOCATION` – e.g. `australiaeast`
   - `BASE_NAME` – globally unique 3–12 chars (lowercase/digits); resources are `apim-<BASE_NAME>`, `func-<BASE_NAME>`
   - `PUBLISHER_EMAIL` – APIM publisher e-mail
4. Run the workflows in the order above. Then create an APIM subscription on the **Demo** product and call:

```
curl -H "Ocp-Apim-Subscription-Key: <key>" https://apim-<BASE_NAME>.azure-api.net/products-api/products
```

The Function App runs on a standard (S1) Linux plan with identity-based storage (no storage keys). Storage public
network access is disabled (enforced by policy in this tenant), so `main.bicep` also creates a VNet, VNet integration for
the Function App, and private endpoints + private DNS zones for blob/queue/table storage.

APIM defaults to the `Developer` SKU because APIM MCP servers aren't supported on `Consumption`. Provisioning takes
30-60 minutes. Override via the `apimSku` parameter (any tier except Consumption). An existing Consumption instance
can't be changed in place; delete it or use a new `BASE_NAME`.

## MCP endpoint

The Function App also exposes the Products operations as an MCP server (Streamable HTTP, stateless, JSON responses) at
`POST /api/mcp` (`authLevel: function`, implemented in `src/functionapp/src/mcp.js`). The REST API is unchanged. Tools:
`getHealth`, `listProducts`, `getProduct`, `createProduct`, `updateProduct`, `deleteProduct`.

It is published in two places by `03-deploy-api.yml`:

| Where | Resource | Endpoint | Auth |
| --- | --- | --- | --- |
| APIM | MCP server `products-mcp` (passthrough, `api.bicep`), added to every product | `https://apim-<BASE_NAME>.azure-api.net/products-mcp/mcp` | `Ocp-Apim-Subscription-Key` |
| Azure AI Gateway (preview, `Microsoft.ApiManagement/aigateways`, created by `main.bicep` as `aigw-<BASE_NAME>`) | tool server `products` (`aigateway-mcp.bicep`) | `https://<gateway-host>/default/toolservers/products/mcp` | `Authorization: Bearer <runtime API key>` (`products-mcp-client`) |

Both inject the Function host key (`x-functions-key`) towards the backend. The AI Gateway prefixes tool names with the
namespace (`products_listProducts`). The gateway is created in `aiGatewayLocation` (`eastus2` or `swedencentral` during
preview). Get the runtime key with
`az aigateway api-key list-secrets --gateway-name aigw-<BASE_NAME> --name products-mcp-client --query primaryKey -o tsv`.

`tests/mcp.test.js` runs the same MCP scenario against the Function App, APIM (`APIM_MCP_URL`) and the AI Gateway
(`AI_GATEWAY_MCP_URL`, `AI_GATEWAY_API_KEY`); `04-test-api.yml` sets these automatically.