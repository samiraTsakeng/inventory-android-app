//const fetch = require("node-fetch");

class OdooService {
  static sessionCookie = "";

  static async authenticate(host, db, email, password) {
    const response = await fetch(`${host}/web/session/authenticate`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "call",
        params: {
          db: db,
          login: email,
          password: password
        }
      })
    });

    const data = await response.json();

    console.log("Odoo login response:", data);

    if (!data.result) {
      throw new Error("Authentication failed");
    }

    //  FIXED COOKIE HANDLING
    const cookies = response.headers.get('set-cookie');

    if (cookies) {
      this.sessionCookie = cookies;
    } else {
      throw new Error("No session cookie received");
    }

    return data.result;
  }
// fetch adjustments
  static async fetchAdjustments(host) {
    try {
      const url = `${host}/web/dataset/call_kw`;

      const payload = {
        jsonrpc: "2.0",
        method: "call",
        params: {
          model: "stock.inventory",
          method: "search_read",
          args: [],
          kwargs: {
            fields: [
           // "id",
            "name",
            "state",
            "date"
            //"emplacement_id",
            //"zone_id",
            //"responsable_id",
            //"equipe_id"
            ]
          }
        },
      };

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Cookie: this.sessionCookie,
        },
        body: JSON.stringify(payload),
      });

      const data = await response.json();

      // DEBUG LOG
      console.log("Odoo response:", JSON.stringify(data, null, 2));

      if (data.error) {
        throw new Error(data.error.message || "Odoo error");
      }

      return data.result || [];

    } catch (error) {
      console.error("fetchAdjustments ERROR:", error);
      throw error;
    }
  }

  static async fetchFeuilles(host, adjustmentId) {
    try {
      const url = `${host}/web/dataset/call_kw`; // ✅ FIXED

      const payload = {
        jsonrpc: "2.0",
        method: "call",
        params: {
          model: "general.adjustment", // we will confirm later
          method: "search_read",
          args: [[["inventory_id", "=", adjustmentId]]],
          kwargs: {
            fields: [
              "id",
              "name",
              "state",
              "inventory_id"
            ],
          },
        },
      };

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Cookie: this.sessionCookie,
        },
        body: JSON.stringify(payload),
      });

      const data = await response.json();

      console.log("Feuilles response:", JSON.stringify(data, null, 2));

      if (data.error) {
        throw new Error(data.error.message);
      }

      return data.result || [];

    } catch (error) {
      console.error("fetchFeuilles ERROR:", error);
      throw error;
    }
  }
}

module.exports = OdooService;