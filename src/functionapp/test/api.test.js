const test = require('node:test');
const assert = require('node:assert');
const api = require('../src/functions/api');

const req = (params = {}, body) => ({
  params,
  json: async () => {
    if (body === undefined) throw new Error('no body');
    return body;
  },
});

test('health returns healthy', async () => {
  const res = await api.getHealth();
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.jsonBody.status, 'healthy');
});

test('product CRUD lifecycle', async () => {
  const created = await api.createProduct(req({}, { name: 'Thing', price: 5 }));
  assert.strictEqual(created.status, 201);
  const { id } = created.jsonBody;

  assert.strictEqual((await api.getProduct(req({ id: String(id) }))).status, 200);

  const updated = await api.updateProduct(req({ id: String(id) }, { name: 'Thing2', price: 6 }));
  assert.strictEqual(updated.jsonBody.name, 'Thing2');

  assert.strictEqual((await api.deleteProduct(req({ id: String(id) }))).status, 204);
  assert.strictEqual((await api.getProduct(req({ id: String(id) }))).status, 404);
});

test('validation and not-found errors', async () => {
  assert.strictEqual((await api.createProduct(req({}, { name: '' }))).status, 400);
  assert.strictEqual((await api.createProduct(req({}))).status, 400);
  assert.strictEqual((await api.deleteProduct(req({ id: '999' }))).status, 404);
  assert.strictEqual((await api.getProduct(req({ id: 'abc' }))).status, 404);
});
