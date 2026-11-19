// Integration tests against the deployed API. Configure with environment variables:
//   FUNCTION_BASE_URL     e.g. https://func-<base>.azurewebsites.net/api  (or http://localhost:7071/api)
//   FUNCTION_KEY          function/host key (omit for local `func start`)
//   APIM_BASE_URL         e.g. https://apim-<base>.azure-api.net/products-api
//   APIM_SUBSCRIPTION_KEY APIM subscription key for the Demo product
// A suite is skipped when its base URL is not set.
const { describe, test } = require('node:test');
const assert = require('node:assert');

const trim = (url) => (url || '').replace(/\/+$/, '');
const functionBase = trim(process.env.FUNCTION_BASE_URL);
const functionKey = process.env.FUNCTION_KEY;
const apimBase = trim(process.env.APIM_BASE_URL);
const apimKey = process.env.APIM_SUBSCRIPTION_KEY;

async function call(base, headers, method, path, body) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: { 'content-type': 'application/json', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : undefined;
  } catch {
    json = undefined;
  }
  return { status: res.status, json };
}

// Same behavioural contract (swagger/swagger.json) is expected from both endpoints.
function contractSuite(name, base, headers) {
  describe(name, { skip: !base && 'base URL not configured' }, () => {
    const api = (method, path, body) => call(base, headers, method, path, body);

    test('GET /health returns healthy', async () => {
      const res = await api('GET', '/health');
      assert.strictEqual(res.status, 200);
      assert.strictEqual(res.json.status, 'healthy');
      assert.ok(!Number.isNaN(Date.parse(res.json.timestamp)));
    });

    test('GET /products returns a list', async () => {
      const res = await api('GET', '/products');
      assert.strictEqual(res.status, 200);
      assert.ok(Array.isArray(res.json));
      for (const p of res.json) {
        assert.strictEqual(typeof p.id, 'number');
        assert.strictEqual(typeof p.name, 'string');
        assert.strictEqual(typeof p.price, 'number');
      }
    });

    test('product CRUD lifecycle', async () => {
      const created = await api('POST', '/products', { name: 'Integration Widget', price: 12.5 });
      assert.strictEqual(created.status, 201);
      assert.strictEqual(created.json.name, 'Integration Widget');
      const { id } = created.json;

      try {
        const fetched = await api('GET', `/products/${id}`);
        assert.strictEqual(fetched.status, 200);
        assert.strictEqual(fetched.json.price, 12.5);

        const updated = await api('PUT', `/products/${id}`, { name: 'Renamed', price: 15 });
        assert.strictEqual(updated.status, 200);
        assert.deepStrictEqual(updated.json, { id, name: 'Renamed', price: 15 });
      } finally {
        const deleted = await api('DELETE', `/products/${id}`);
        assert.strictEqual(deleted.status, 204);
      }

      assert.strictEqual((await api('GET', `/products/${id}`)).status, 404);
    });

    test('POST /products rejects invalid input', async () => {
      const res = await api('POST', '/products', { name: '', price: -1 });
      assert.strictEqual(res.status, 400);
      assert.ok(res.json.error);
    });

    test('unknown product returns 404', async () => {
      const res = await api('GET', '/products/999999');
      assert.strictEqual(res.status, 404);
      assert.ok(res.json.error);
    });
  });
}

contractSuite(
  'Function App endpoint',
  functionBase,
  functionKey ? { 'x-functions-key': functionKey } : {},
);

describe('Function App security', { skip: !(functionBase && functionKey) && 'FUNCTION_KEY not set' }, () => {
  test('rejects calls without a function key', async () => {
    const res = await call(functionBase, {}, 'GET', '/products');
    assert.strictEqual(res.status, 401);
  });
});

contractSuite('APIM endpoint', apimBase, apimKey ? { 'Ocp-Apim-Subscription-Key': apimKey } : {});

describe('APIM security', { skip: !apimBase && 'APIM_BASE_URL not configured' }, () => {
  test('rejects calls without a subscription key', async () => {
    const res = await call(apimBase, {}, 'GET', '/products');
    assert.strictEqual(res.status, 401);
  });
});
