const { app } = require('@azure/functions');
const { handleMessage } = require('../mcp');

const json = (status, jsonBody) => ({ status, jsonBody });

// MCP Streamable HTTP endpoint (POST /api/mcp). Stateless: no sessions and no SSE stream.
const mcp = async (request) => {
  if (request.method !== 'POST') {
    return { status: 405, headers: { Allow: 'POST' } };
  }

  let message;
  try {
    message = await request.json();
  } catch {
    return json(400, { jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } });
  }

  const response = handleMessage(message);
  return response ? json(200, response) : { status: 202 };
};

app.http('mcp', { methods: ['GET', 'POST', 'DELETE'], authLevel: 'function', route: 'mcp', handler: mcp });

module.exports = { mcp };
