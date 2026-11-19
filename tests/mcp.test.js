// Integration tests for the MCP endpoint (Streamable HTTP). Configure with environment variables:
//   FUNCTION_BASE_URL / FUNCTION_KEY       Function App REST base URL (MCP is at <base>/mcp) and host key
//   APIM_MCP_URL / APIM_SUBSCRIPTION_KEY   e.g. https://apim-<base>.azure-api.net/products-mcp/mcp
//   AI_GATEWAY_MCP_URL / AI_GATEWAY_API_KEY e.g. https://<host>/default/toolservers/products/mcp
// A suite is skipped when its URL is not set. The gateways may prefix tool names (<namespace>_<tool>).
const { describe, test } = require('node:test');
const assert = require('node:assert');

const trim = (url) => (url || '').replace(/\/+$/, '');
const functionBase = trim(process.env.FUNCTION_BASE_URL);
const functionKey = process.env.FUNCTION_KEY;

let nextId = 1;

// The response is either plain JSON or an SSE stream carrying the JSON-RPC response.
function parseBody(contentType, text) {
  if (!text) return undefined;
  if (contentType.includes('text/event-stream')) {
    const data = text.split(/\r?\n/).filter((l) => l.startsWith('data:')).map((l) => l.slice(5).trim());
    return data.length ? JSON.parse(data[data.length - 1]) : undefined;
  }
  return JSON.parse(text);
}

function client(url, headers) {
  const post = async (message, extra = {}) => {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        accept: 'application/json, text/event-stream',
        ...headers,
        ...extra,
      },
      body: JSON.stringify({ jsonrpc: '2.0', ...message }),
    });
    const text = await res.text();
    let body;
    try {
      body = parseBody(res.headers.get('content-type') || '', text);
    } catch {
      body = undefined;
    }
    return { status: res.status, headers: res.headers, body };
  };
  const rpc = (method, params) => post({ id: nextId++, method, params });
  return { post, rpc };
}

function mcpSuite(name, url, headers) {
  describe(name, { skip: !url && 'MCP URL not configured' }, () => {
    const mcp = client(url, headers);
    let sessionHeaders = {};
    let toolNames;
    const tool = (suffix) => {
      const found = toolNames.find((n) => n === suffix || n.endsWith(`_${suffix}`));
      assert.ok(found, `tool ${suffix} not listed (have: ${toolNames})`);
      return found;
    };
    const callTool = async (suffix, args) => {
      const res = await mcp.post(
        { id: nextId++, method: 'tools/call', params: { name: tool(suffix), arguments: args } },
        sessionHeaders,
      );
      assert.strictEqual(res.status, 200);
      return res.body.result;
    };

    test('initialize and list tools', async () => {
      const init = await mcp.rpc('initialize', {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'integration-tests', version: '1.0.0' },
      });
      assert.strictEqual(init.status, 200);
      assert.ok(init.body.result.capabilities.tools);

      const sessionId = init.headers.get('mcp-session-id');
      if (sessionId) sessionHeaders = { 'mcp-session-id': sessionId };
      const note = await mcp.post({ method: 'notifications/initialized' }, sessionHeaders);
      assert.ok([200, 202].includes(note.status));

      const list = await mcp.post({ id: nextId++, method: 'tools/list' }, sessionHeaders);
      assert.strictEqual(list.status, 200);
      toolNames = list.body.result.tools.map((t) => t.name);
      for (const t of ['getHealth', 'listProducts', 'getProduct', 'createProduct', 'updateProduct', 'deleteProduct']) {
        tool(t);
      }
    });

    test('health and list tools return data', async () => {
      const health = await callTool('getHealth', {});
      assert.strictEqual(JSON.parse(health.content[0].text).status, 'healthy');
      assert.ok(Array.isArray(JSON.parse((await callTool('listProducts', {})).content[0].text)));
    });

    test('product CRUD lifecycle', async () => {
      const created = await callTool('createProduct', { name: 'MCP Widget', price: 3.5 });
      const { id } = JSON.parse(created.content[0].text);
      try {
        assert.strictEqual(JSON.parse((await callTool('getProduct', { id })).content[0].text).name, 'MCP Widget');
        const updated = await callTool('updateProduct', { id, name: 'Renamed', price: 4 });
        assert.deepStrictEqual(JSON.parse(updated.content[0].text), { id, name: 'Renamed', price: 4 });
      } finally {
        assert.notStrictEqual((await callTool('deleteProduct', { id })).isError, true);
      }
      assert.strictEqual((await callTool('getProduct', { id })).isError, true);
    });

    test('invalid input is reported as a tool error', async () => {
      assert.strictEqual((await callTool('createProduct', { name: '', price: -1 })).isError, true);
    });

    test('rejects calls without credentials', async () => {
      const res = await client(url, {}).rpc('tools/list');
      assert.ok([401, 403].includes(res.status), `unexpected status ${res.status}`);
    });
  });
}

mcpSuite(
  'Function App MCP endpoint',
  functionBase && `${functionBase}/mcp`,
  functionKey ? { 'x-functions-key': functionKey } : {},
);

mcpSuite(
  'APIM MCP server',
  trim(process.env.APIM_MCP_URL),
  process.env.APIM_SUBSCRIPTION_KEY ? { 'Ocp-Apim-Subscription-Key': process.env.APIM_SUBSCRIPTION_KEY } : {},
);

mcpSuite(
  'AI Gateway MCP server',
  trim(process.env.AI_GATEWAY_MCP_URL),
  process.env.AI_GATEWAY_API_KEY ? { Authorization: `Bearer ${process.env.AI_GATEWAY_API_KEY}` } : {},
);
