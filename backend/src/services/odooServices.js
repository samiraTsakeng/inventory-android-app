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
    console.log("Odoo login:", data.result?.uid ? `uid ${data.result.uid}` : "failed");

    if (!data.result || !data.result.uid) {
      throw new Error("Authentication failed: wrong credentials");
    }

    // Extract and store the session cookie correctly
    const cookies = response.headers.get("set-cookie");
    if (!cookies) throw new Error("No session cookie received from Odoo");

    // Store the full cookie string
    this.sessionCookie = cookies;
    console.log("Session cookie stored successfully");

    return data.result;
  }

  async _call(host, model, method, args, kwargs = {}) {
    const response = await fetch(`${host}/web/dataset/call_kw`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Cookie": this.sessionCookie
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "call",
        params: { model, method, args, kwargs }
      })
    });
    const data = await response.json();
    if (data.error) throw new Error(data.error.data?.message || data.error.message);
    return data.result;
  }

  // Draft / in progress adjustments the user works on: the ones they are
  // responsible for (Resp. Ajustement) and the ones where they have a
  // counting sheet (Resp. Comptage).
  async fetchAdjustments(host, userId) {
    const sheets = await this._call(host, "counting.sheet", "search_read",
      [[["user_id", "=", userId]]], { fields: ["stock_inventory_id"] });
    const countedIds = [...new Set((sheets || [])
      .map((s) => Array.isArray(s.stock_inventory_id) ? s.stock_inventory_id[0] : s.stock_inventory_id)
      .filter(Boolean))];

    const adjustments = await this._call(host, "stock.inventory", "search_read", [[
      ["state", "in", ["draft", "in_progress"]],
      "|", ["manager_id", "=", userId], ["id", "in", countedIds]
    ]], { fields: ["id", "name", "state", "date", "manager_id"] });

    console.log(`Adjustments for user ${userId}: ${adjustments?.length || 0}`);
    return adjustments || [];
  }

  async fetchFeuilles(host, adjustmentId, userId) {
    console.log("=== FETCHING FEUILLES ===");
    console.log("Adjustment ID:", adjustmentId);
    console.log("User ID:", userId);
    console.log("Has session cookie:", !!this.sessionCookie);

    // Ensure adjustmentId is a number
    const adjId = parseInt(adjustmentId);
    console.log("Parsed adjustment ID:", adjId);

    const requestBody = {
      jsonrpc: "2.0",
      method: "call",
      params: {
        model: "counting.sheet",
        method: "search_read",
        args: [
          [["stock_inventory_id", "=", adjId], ["user_id", "=", userId]]
        ],
        kwargs: {
          fields: ["id", "name", "state", "stock_inventory_id", "zone_id", "user_id"]
        }
      }
    };


    const response = await fetch(`${host}/web/dataset/call_kw`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Cookie": this.sessionCookie
      },
      body: JSON.stringify(requestBody)
    });

    const data = await response.json();

    if (data.error) {
      console.error("Odoo error:", data.error);
      throw new Error(data.error.data?.message || data.error.message);
    }

    console.log(`Found ${data.result?.length || 0} feuilles for adjustment ${adjId} where user is responsible`);

    return data.result || [];
  }
}

// Export a single shared instance
module.exports = new OdooService();