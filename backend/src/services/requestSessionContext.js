const { AsyncLocalStorage } = require("async_hooks");

// One Odoo session context per incoming HTTP request.
// This prevents one employee's Odoo cookie from replacing another employee's
// cookie when several phones use the backend at the same time.
const storage = new AsyncLocalStorage();

module.exports = {
  run(session, callback) { return storage.run(session, callback); },
  get() { return storage.getStore() || null; },
};
