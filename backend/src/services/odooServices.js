const fetch = require("node-fetch");

class OdooService {
  constructor() {
    this.sessionCookie = "";
  }

  async authenticate(host, db, email, password) {
    const response = await fetch(`${host}/web/session/authenticate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "call",
        params: { db, login: email, password }
      })
    });

    const data = await response.json();
    console.log("Odoo login response:", JSON.stringify(data, null, 2));

    if (!data.result || !data.result.uid) {
      throw new Error("Authentication failed: wrong credentials");
    }

    const cookies = response.headers.get("set-cookie");
    if (!cookies) throw new Error("No session cookie received from Odoo");

    this.sessionCookie = cookies;
    return data.result;
  }

  async fetchAdjustments(host) {
    const response = await fetch(`${host}/web/dataset/call_kw`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Cookie: this.sessionCookie
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "call",
        params: {
          model: "stock.inventory",
          method: "search_read",
          args: [],
          kwargs: {
            fields: ["id", "name", "state", "date"]
          }
        }
      })
    });

    const data = await response.json();
    console.log("Adjustments response:", JSON.stringify(data, null, 2));

    if (data.error) throw new Error(data.error.data?.message || data.error.message);
    return data.result || [];
  }

  async fetchFeuilles(host, adjustmentId) {
    const response = await fetch(`${host}/web/dataset/call_kw`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Cookie: this.sessionCookie
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "call",
        params: {
          model: "counting.sheet",
          method: "search_read",
          args: [[]],
          kwargs: {
            fields: ["id", "name", "state", "stock_inventory_id", "zone_id", "user_id"]
          }
        }
      })
    });

    const data = await response.json();
    console.log("Feuilles response:", JSON.stringify(data, null, 2));

    if (data.error) throw new Error(data.error.data?.message || data.error.message);
    return data.result || [];
  }
}

// Export a single shared instance
module.exports = new OdooService();