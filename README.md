# azure-apim-demo

Azure API Management + CI/CD with GitHub Actions.

```
bicep/settings.bicep   shared settings: resource naming and cross-team names (imported by every template)
bicep/platform/     platform team: main.bicep (APIM, AI Gateway, storage, App Insights, VNet + private endpoints)
bicep/apps/         apps team: functionapp.bicep (Function App), api.bicep (publishes REST API + MCP server to APIM), main.bicep (deploys both, for local use)
bicep/integration/  integration team: plan.bicep (App Service plan), access.bicep + apim-config.json (APIM products and subscriptions for clients), workspace.bicep (APIM workspace + the same REST API), aigateway-mcp.bicep (registers MCP on the AI Gateway), main.bicep (deploys all, for local use)
src/functionapp/  Node.js (v4 model) Azure Function App exposing a REST API
swagger/swagger.json  OpenAPI (Swagger 2.0) definition imported into APIM
.github/workflows/    10-deploy-platform, 20-deploy-integration, 30-deploy-plan, 31-deploy-apps, 32-deploy-api, 40-test-api
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
| `10-deploy-platform.yml` | changes to `bicep/platform/**` / `bicep/settings.bicep` | lint, what-if (PRs), deploy `platform/main.bicep` (APIM, AI Gateway, storage, App Insights, network) |
| `20-deploy-integration.yml` | changes to `bicep/integration/**` (except the plan), manual, or called by 32 | deploys `access.bicep` (products and subscriptions from `bicep/integration/apim-config.json`), `workspace.bicep` (APIM workspace + API) and `aigateway-mcp.bicep` (MCP tool server on the AI Gateway); then calls `40-test-api.yml` |
| `30-deploy-plan.yml` | changes to `bicep/integration/plan.bicep`, or manual | deploys `plan.bicep` (the App Service plan the Function App needs) |
| `31-deploy-apps.yml` | changes to `src/functionapp/**` / `bicep/apps/functionapp.bicep`, or manual | tests and zips the code; deploys `functionapp.bicep` and the code |
| `32-deploy-api.yml` | changes to `swagger/**` / `bicep/apps/api.bicep`, or manual | deploys `api.bicep` (REST API and MCP server in APIM); runs 20 to complete the integration; then calls `40-test-api.yml` |
| `40-test-api.yml` | changes to `tests/**`, daily schedule, manual, or called | looks up the function key and APIM subscription key, runs `tests/` against both endpoints |

Order for a first deployment: **10 Deploy platform → 30 Deploy App Service plan → 31 Deploy apps → 32 Deploy API**. 32 needs the
function host key, which exists once the code from 31 is deployed. It then runs 20 to finish client access, the workspace and
the AI Gateway registration (they need the API), followed by the tests. 20 can also run on its own afterwards, for example when
`apim-config.json` changes; before the API exists it only creates the plan.

All workflows can also be started manually (**Actions → pick a workflow → Run workflow**). Manual inputs: `31`
has `deploy` (uncheck for build-and-test only), and `20` / `32` have `run_tests`.

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

Defined in `bicep/integration/apim-config.json` and deployed by `20-deploy-integration.yml` (edit the file, push to `main`):

- `products[]`: `name`, `displayName`, optional `description`, `state`, `subscriptionRequired`, `approvalRequired`,
  `subscriptionsLimit`. Every product exposes the Products API.
- `subscriptions[]`: `name`, `displayName`, `product` (a product `name`), optional `state`.

Keep the `demo-tests` subscription on the `demo` product; `40-test-api.yml` uses it. Subscription keys are not stored in
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

APIM defaults to the `StandardV2` SKU: MCP servers aren't supported on `Consumption` and workspaces need Basic v2,
Standard v2, Premium or Premium v2 (not Developer). Override via the `apimSku` parameter. The SKU can't be changed in
place from a classic tier (Developer/Basic/Standard/Premium) to a v2 tier; delete (and purge) the instance or use a new
`BASE_NAME`.

## MCP endpoint

The Function App also exposes the Products operations as an MCP server (Streamable HTTP, stateless, JSON responses) at
`POST /api/mcp` (`authLevel: function`, implemented in `src/functionapp/src/mcp.js`). The REST API is unchanged. Tools:
`getHealth`, `listProducts`, `getProduct`, `createProduct`, `updateProduct`, `deleteProduct`.

It is published in two places by `32-deploy-api.yml`:

| Where | Resource | Endpoint | Auth |
| --- | --- | --- | --- |
| APIM | MCP server `products-mcp` (passthrough, `api.bicep`), added to every product by `access.bicep` | `https://apim-<BASE_NAME>.azure-api.net/products-mcp/mcp` | `Ocp-Apim-Subscription-Key` |
| Azure AI Gateway (preview, `Microsoft.ApiManagement/aigateways`, created by `main.bicep` as `aigw-<BASE_NAME>`) | tool server `products` (`aigateway-mcp.bicep`) | `https://<gateway-host>/default/toolservers/products/mcp` | `Authorization: Bearer <runtime API key>` (`products-mcp-client`) |

Both inject the Function host key (`x-functions-key`) towards the backend. The AI Gateway prefixes tool names with the
namespace (`products_listProducts`). The gateway is created in `aiGatewayLocation` (`eastus2` or `swedencentral` during
preview). Get the runtime key with
`az aigateway api-key list-secrets --gateway-name aigw-<BASE_NAME> --name products-mcp-client --query primaryKey -o tsv`.

`tests/mcp.test.js` runs the same MCP scenario against the Function App, APIM (`APIM_MCP_URL`) and the AI Gateway
(`AI_GATEWAY_MCP_URL`, `AI_GATEWAY_API_KEY`); `40-test-api.yml` sets these automatically.

`.vscode/mcp.json` registers the APIM MCP server (`products-mcp`) for GitHub Copilot in VS Code. On first start it
prompts for an APIM subscription key (for example `demo-default`), which VS Code stores securely, not in the repo.

## APIM workspace

`workspace.bicep` (deployed by `20-deploy-integration.yml`) creates the workspace `products-team` and publishes the same Products API into it
(imported from `swagger/swagger.json`): its own function-key named value, API policy, product `products-team-product` and
subscription `products-team-tests`. On StandardV2 the workspace is served by the built-in gateway (`serveOn: workspaceAndDefault`).

| Where | Endpoint |
| --- | --- |
| Service level | `https://apim-<BASE_NAME>.azure-api.net/products-api` |
| Workspace | `https://apim-<BASE_NAME>.azure-api.net/ws-products-api` |

Constraints: workspaces don't support MCP servers (the MCP server stays at service level), workspace policies can't
reference service-level named values (hence the duplicated function key), and resource names must be unique across the
whole service (hence the `products-team-` prefixes and the `ws-` path). `40-test-api.yml` runs the contract tests against
the workspace endpoint (`APIM_WORKSPACE_BASE_URL`, `APIM_WORKSPACE_SUBSCRIPTION_KEY`).

Workspace APIs only accept subscription keys created **inside the workspace** (service-level subscriptions such as `demo-default` get a 401). Get the key with:

```
az rest --method post --url "https://management.azure.com/subscriptions/<SUB_ID>/resourceGroups/<RG>/providers/Microsoft.ApiManagement/service/apim-<BASE_NAME>/workspaces/products-team/subscriptions/products-team-tests/listSecrets?api-version=2024-05-01" --query primaryKey -o tsv
```
