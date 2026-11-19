const test = require('node:test');
const assert = require('node:assert');
const { handleMessage } = require('../src/mcp');
const { mcp } = require('../src/functions/mcp');

const rpc = (method, params, id = 1) => handleMessage({ jsonrpc: '2.0', id, method, params });
const call = (name, args) => rpc('tools/call', { name, arguments: args }).result;
const data = (res) => JSON.parse(res.content[0].text);

test('initialize negotiates the protocol version and advertises tools', () => {
  const res = rpc('initialize', { protocolVersion: '2025-06-18' });
  assert.strictEqual(res.result.protocolVersion, '2025-06-18');
  assert.ok(res.result.capabilities.tools);
  assert.strictEqual(rpc('initialize', { protocolVersion: '1999-01-01' }).result.protocolVersion, '2025-06-18');
});

test('tools/list exposes one tool per REST operation', () => {
  const names = rpc('tools/list').result.tools.map((t) => t.name).sort();
  assert.deepStrictEqual(names, [
    'createProduct', 'deleteProduct', 'getHealth', 'getProduct', 'listProducts', 'updateProduct',
  ]);
});

test('product CRUD through tools', () => {
  assert.strictEqual(data(call('getHealth', {})).status, 'healthy');

  const created = data(call('createProduct', { name: ' Thing ', price: 5 }));
  assert.strictEqual(created.name, 'Thing');
  assert.ok(data(call('listProducts', {})).some((p) => p.id === created.id));
  assert.strictEqual(data(call('getProduct', { id: created.id })).price, 5);

  const updated = data(call('updateProduct', { id: created.id, name: 'Thing2', price: 6 }));
  assert.deepStrictEqual(updated, { id: created.id, name: 'Thing2', price: 6 });

  assert.notStrictEqual(call('deleteProduct', { id: created.id }).isError, true);
  assert.strictEqual(call('getProduct', { id: created.id }).isError, true);
});

test('tool failures are reported as isError results', () => {
  assert.strictEqual(call('createProduct', { name: '', price: 1 }).isError, true);
  assert.strictEqual(call('createProduct', { name: 'x' }).isError, true);
  assert.strictEqual(call('deleteProduct', { id: 999999 }).isError, true);
  assert.strictEqual(call('getProduct', { id: 'abc' }).isError, true);
});

test('protocol errors', () => {
  assert.strictEqual(rpc('tools/call', { name: 'nope' }).error.code, -32602);
  assert.strictEqual(rpc('nope').error.code, -32601);
  assert.strictEqual(handleMessage({ id: 1 }).error.code, -32600);
  assert.strictEqual(handleMessage({ jsonrpc: '2.0', method: 'notifications/initialized' }), null);
  assert.deepStrictEqual(rpc('ping').result, {});
});

const httpReq = (method, body) => ({
  method,
  json: async () => {
    if (body === undefined) throw new Error('no body');
    return body;
  },
});

test('HTTP handler: POST returns JSON-RPC, notifications 202, others rejected', async () => {
  const ok = await mcp(httpReq('POST', { jsonrpc: '2.0', id: 1, method: 'ping' }));
  assert.strictEqual(ok.status, 200);
  assert.deepStrictEqual(ok.jsonBody, { jsonrpc: '2.0', id: 1, result: {} });

  const note = await mcp(httpReq('POST', { jsonrpc: '2.0', method: 'notifications/initialized' }));
  assert.strictEqual(note.status, 202);

  assert.strictEqual((await mcp(httpReq('POST'))).status, 400);
  assert.strictEqual((await mcp(httpReq('GET'))).status, 405);
});
