# azure-apim-demo

Demo of Azure API Management + CI/CD with GitHub Actions.

```
bicep/        main.bicep (APIM, Function App, plan, storage, App Insights), api.bicep (publishes API to APIM)
src/functionapp/  Node.js (v4 model) Azure Function App exposing a REST API
swagger/swagger.json  OpenAPI (Swagger 2.0) definition imported into APIM
.github/workflows/    deploy-infra, deploy-functionapp, deploy-api
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
| `deploy-infra.yml` | changes to `bicep/main.*` | lint, what-if (PRs), deploy `main.bicep` |
| `deploy-functionapp.yml` | changes to `src/functionapp/**` | test, zip, deploy to Function App, then calls `deploy-api.yml` |
| `deploy-api.yml` | changes to `swagger/**` / `api.bicep`, or called | deploys `api.bicep`: imports `swagger.json` as an APIM API, sets backend + function key policy, product |

Order for a first deployment: **Deploy infrastructure → Deploy Function App** (which also publishes the API).

## One-time setup

1. Create an Entra app registration / service principal with a federated credential for
   `repo:qkfang/azure-apim-demo:ref:refs/heads/main` (and `pull_request` for what-if), and grant it
   **Contributor** on the subscription or resource group.
2. Repository **secrets**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
3. Repository **variables**:
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