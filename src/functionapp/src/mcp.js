// Minimal stateless MCP server (Streamable HTTP, JSON responses) exposing the same Products
// operations as the REST API. Transport-agnostic: handleMessage takes one JSON-RPC message.
const store = require('./store');

const SERVER_INFO = { name: 'apim-demo-products', version: '1.0.0' };
const SUPPORTED_VERSIONS = ['2025-06-18', '2025-03-26', '2024-11-05'];

const idSchema = { type: 'integer', description: 'Product id' };
const productProps = {
  name: { type: 'string', description: 'Product name' },
  price: { type: 'number', minimum: 0, description: 'Product price' },
};

const result = (data) => ({ content: [{ type: 'text', text: JSON.stringify(data) }] });
const toolError = (message) => ({ content: [{ type: 'text', text: message }], isError: true });
const notFound = () => toolError('Product not found');

const tools = [
  {
    name: 'getHealth',
    description: 'Health check',
    inputSchema: { type: 'object', properties: {} },
    run: () => result({ status: 'healthy', timestamp: new Date().toISOString() }),
  },
  {
    name: 'listProducts',
    description: 'List products',
    inputSchema: { type: 'object', properties: {} },
    run: () => result(store.list()),
  },
  {
    name: 'getProduct',
    description: 'Get a product by id',
    inputSchema: { type: 'object', properties: { id: idSchema }, required: ['id'] },
    run: ({ id }) => {
      const product = store.get(id);
      return product ? result(product) : notFound();
    },
  },
  {
    name: 'createProduct',
    description: 'Create a product',
    inputSchema: { type: 'object', properties: productProps, required: ['name', 'price'] },
    run: (args) => {
      const error = store.validate(args);
      return error ? toolError(error) : result(store.create(args));
    },
  },
  {
    name: 'updateProduct',
    description: 'Update a product',
    inputSchema: {
      type: 'object',
      properties: { id: idSchema, ...productProps },
      required: ['id', 'name', 'price'],
    },
    run: (args) => {
      const error = store.validate(args);
      if (error) return toolError(error);
      const product = store.update(args.id, args);
      return product ? result(product) : notFound();
    },
  },
  {
    name: 'deleteProduct',
    description: 'Delete a product',
    inputSchema: { type: 'object', properties: { id: idSchema }, required: ['id'] },
    run: ({ id }) => (store.remove(id) ? result({ deleted: true, id }) : notFound()),
  },
];

const toolsByName = new Map(tools.map((t) => [t.name, t]));
const publicTools = tools.map(({ run, ...tool }) => tool);

const rpcError = (id, code, message) => ({ jsonrpc: '2.0', id: id ?? null, error: { code, message } });
const rpcResult = (id, value) => ({ jsonrpc: '2.0', id, result: value });

function callTool(params) {
  const tool = toolsByName.get(params?.name);
  if (!tool) return { error: [-32602, `Unknown tool: ${params?.name}`] };
  const args = params.arguments ?? {};
  if (typeof args !== 'object' || Array.isArray(args)) {
    return { error: [-32602, 'arguments must be an object'] };
  }
  for (const key of tool.inputSchema.required ?? []) {
    if (args[key] === undefined) return { value: toolError(`${key} is required`) };
  }
  if ('id' in tool.inputSchema.properties && !Number.isInteger(args.id)) {
    return { value: toolError('id must be an integer') };
  }
  return { value: tool.run(args) };
}

// Returns a JSON-RPC response, or null when the message needs no response (notifications/responses).
function handleMessage(message) {
  if (!message || typeof message !== 'object' || Array.isArray(message) || message.jsonrpc !== '2.0') {
    return rpcError(message?.id, -32600, 'Invalid Request');
  }
  const { id, method, params } = message;
  const isNotification = id === undefined;
  if (typeof method !== 'string') return isNotification ? null : rpcError(id, -32600, 'Invalid Request');
  if (isNotification) return null;

  switch (method) {
    case 'initialize': {
      const requested = params?.protocolVersion;
      return rpcResult(id, {
        protocolVersion: SUPPORTED_VERSIONS.includes(requested) ? requested : SUPPORTED_VERSIONS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER_INFO,
      });
    }
    case 'ping':
      return rpcResult(id, {});
    case 'tools/list':
      return rpcResult(id, { tools: publicTools });
    case 'tools/call': {
      const outcome = callTool(params);
      return outcome.error ? rpcError(id, ...outcome.error) : rpcResult(id, outcome.value);
    }
    default:
      return rpcError(id, -32601, `Method not found: ${method}`);
  }
}

module.exports = { handleMessage, tools: publicTools, SUPPORTED_VERSIONS };
