const { app } = require('@azure/functions');
const store = require('../store');

const json = (status, jsonBody) => ({ status, jsonBody });
const parseId = (request) => {
  const id = Number(request.params.id);
  return Number.isInteger(id) ? id : NaN;
};

async function readBody(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

const getHealth = async () =>
  json(200, { status: 'healthy', timestamp: new Date().toISOString() });

const listProducts = async () => json(200, store.list());

const getProduct = async (request) => {
  const product = store.get(parseId(request));
  return product ? json(200, product) : json(404, { error: 'Product not found' });
};

const createProduct = async (request) => {
  const body = await readBody(request);
  const error = store.validate(body);
  return error ? json(400, { error }) : json(201, store.create(body));
};

const updateProduct = async (request) => {
  const body = await readBody(request);
  const error = store.validate(body);
  if (error) return json(400, { error });
  const product = store.update(parseId(request), body);
  return product ? json(200, product) : json(404, { error: 'Product not found' });
};

const deleteProduct = async (request) =>
  store.remove(parseId(request))
    ? { status: 204 }
    : json(404, { error: 'Product not found' });

app.http('getHealth', { methods: ['GET'], authLevel: 'function', route: 'health', handler: getHealth });
app.http('listProducts', { methods: ['GET'], authLevel: 'function', route: 'products', handler: listProducts });
app.http('createProduct', { methods: ['POST'], authLevel: 'function', route: 'products', handler: createProduct });
app.http('getProduct', { methods: ['GET'], authLevel: 'function', route: 'products/{id}', handler: getProduct });
app.http('updateProduct', { methods: ['PUT'], authLevel: 'function', route: 'products/{id}', handler: updateProduct });
app.http('deleteProduct', { methods: ['DELETE'], authLevel: 'function', route: 'products/{id}', handler: deleteProduct });

module.exports = { getHealth, listProducts, getProduct, createProduct, updateProduct, deleteProduct };
