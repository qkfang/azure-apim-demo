// In-memory store for demo purposes only (resets on cold start / scale-out).
const products = new Map([
  [1, { id: 1, name: 'Widget', price: 9.99 }],
  [2, { id: 2, name: 'Gadget', price: 19.5 }],
]);
let nextId = 3;

function validate(body) {
  if (!body || typeof body.name !== 'string' || body.name.trim() === '') {
    return 'name is required';
  }
  if (typeof body.price !== 'number' || !(body.price >= 0)) {
    return 'price must be a non-negative number';
  }
  return null;
}

module.exports = {
  list: () => [...products.values()],
  get: (id) => products.get(id),
  create: (body) => {
    const product = { id: nextId++, name: body.name.trim(), price: body.price };
    products.set(product.id, product);
    return product;
  },
  update: (id, body) => {
    if (!products.has(id)) return undefined;
    const product = { id, name: body.name.trim(), price: body.price };
    products.set(id, product);
    return product;
  },
  remove: (id) => products.delete(id),
  validate,
};
