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

    // Extract and store the session cookie correctly
    const cookies = response.headers.get("set-cookie");
    if (!cookies) throw new Error("No session cookie received from Odoo");

    // Store the full cookie string
    this.sessionCookie = cookies;
    console.log("Session cookie stored successfully");

    return data.result;
  }

  async fetchAdjustments(host) {

    console.log("Has session cookie:", this.sessionCookie ? "Yes" : "No");

    const response = await fetch(`${host}/web/dataset/call_kw`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Cookie": this.sessionCookie
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "call",
        params: {
          model: "stock.inventory",
          method: "search_read",
          args: [[["state", "in", ["draft", "confirm"]]]],
          kwargs: {
            fields: ["id", "name", "state", "date"]
          }
        }
      })
    });

    const data = await response.json();
    console.log("Adjustments response status:", response.status);
    console.log("Adjustment found:", data.result?.length || 0);

    if (data.error) throw new Error(data.error.data?.message || data.error.message);
    return data.result || [];
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

    console.log("Request body:", JSON.stringify(requestBody, null, 2));

    const response = await fetch(`${host}/web/dataset/call_kw`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Cookie": this.sessionCookie
      },
      body: JSON.stringify(requestBody)
    });

    const data = await response.json();
    console.log("Full Odoo response:", JSON.stringify(data, null, 2));

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