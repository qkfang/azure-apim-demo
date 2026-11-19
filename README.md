# azure-apim-demo

Demo of Azure API Management + CI/CD with GitHub Actions.

```
bicep/        main.bicep (APIM, Function App, plan, storage, App Insights), api.bicep (publishes API to APIM)
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

Data is held in memory (demo only). Functions use `authLevel: function`; APIM injects the host key
(`x-functions-key`) via a secret named value, so callers only need an APIM subscription key
(`Ocp-Apim-Subscription-Key`).

Run locally: `cd src/functionapp && npm ci && npm test`, then copy `local.settings.sample.json` to
`local.settings.json` and `func start`.

## Workflows

| Workflow | Trigger | Does |
| --- | --- | --- |
| `01-deploy-infra.yml` | changes to `bicep/main.*` | lint, what-if (PRs), deploy `main.bicep` |
| `02-deploy-functionapp.yml` | changes to `src/functionapp/**` | test, zip, deploy to Function App, then calls `03-deploy-api.yml` |
| `03-deploy-api.yml` | changes to `swagger/**` / `api.bicep`, or called | deploys `api.bicep`: imports `swagger.json` as an APIM API, sets backend + function key policy, product, a `demo-tests` subscription; then calls `04-test-api.yml` |
| `04-test-api.yml` | changes to `tests/**`, daily schedule, manual, or called | looks up the function key and APIM subscription key, runs `tests/` against both endpoints |

Order for a first deployment: **Deploy infrastructure → Deploy Function App** (which also publishes the API and runs the tests).

## Integration tests

`tests/` uses the built-in Node test runner (no dependencies) and checks the same contract (health, product CRUD,
400/404 errors) against the Function App and APIM, plus that unauthenticated calls get 401. Suites are skipped when
their URL isn't set.

```
cd tests
$env:FUNCTION_BASE_URL = "https://func-<BASE_NAME>.azurewebsites.net/api"; $env:FUNCTION_KEY = "<function key>"
$env:APIM_BASE_URL = "https://apim-<BASE_NAME>.azure-api.net/demo";       $env:APIM_SUBSCRIPTION_KEY = "<apim key>"
npm test
```

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
curl -H "Ocp-Apim-Subscription-Key: <key>" https://apim-<BASE_NAME>.azure-api.net/demo/products
```

The Function App runs on a standard (S1) Linux plan with identity-based storage (no storage keys),
so it works in tenants where shared-key access is blocked by policy.

APIM defaults to the `Consumption` SKU (fast, cheap). Override via the `apimSku` parameter.