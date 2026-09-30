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
    console.log("Session cookie stored successfully");

    return data.result;
  }

  // ✅ Returns EVERY adjustment in state "draft" or "confirm".
  // No per-user filtering here — any logged-in user can see the full list.
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
          args: [[["state", "in", ["draft", "in_progress"]]]],
          kwargs: {
            fields: ["id", "name", "state", "date", "manager_id"]
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

  // ✅ Returns counting sheets for one adjustment, in state "new" or
  // "progress", assigned to the given user. Fetches ALL sheets for the
  // adjustment from Odoo (no user filter at the query level, so Odoo
  // record rules / array-vs-int quirks can't silently hide everything),
  // then filters in JS where we can log what's actually happening.
  async fetchFeuilles(host, adjustmentId, userId) {
    console.log("=== FETCHING FEUILLES ===");
    console.log("Adjustment ID:", adjustmentId);
    console.log("User ID:", userId);
    console.log("Has session cookie:", !!this.sessionCookie);

    const adjId = parseInt(adjustmentId);
    console.log("Parsed adjustment ID:", adjId);

    // Step 1: get ALL sheets for this adjustment (no user/state filter).
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
          model: "counting.sheet",
          method: "search_read",
          args: [[["stock_inventory_id", "=", adjId]]],
          kwargs: {
            fields: ["id", "name", "state", "stock_inventory_id", "zone_id", "user_id"]
          }
        }
      })
    });

    const data = await response.json();
    console.log("Full Odoo response:", JSON.stringify(data, null, 2));

    if (data.error) {
      console.error("Odoo error:", data.error);
      throw new Error(data.error.data?.message || data.error.message);
    }

    const allSheets = data.result || [];
    console.log(`Found ${allSheets.length} total sheets for adjustment ${adjId}`);

    // Step 2: filter in JS — assigned to this user AND state is new/progress.
    const filtered = allSheets.filter(sheet => {
      // user_id can come back as an int, [id, name] array, or false/null.
      let sheetUserId = null;
      if (Array.isArray(sheet.user_id)) {
        sheetUserId = sheet.user_id[0];
      } else if (typeof sheet.user_id === "number") {
        sheetUserId = sheet.user_id;
      } else {
        sheetUserId = null;
      }

      const isAssignedToUser = sheetUserId === userId;
      const isRightState = sheet.state === "new" || sheet.state === "progress";

      console.log(
        `Sheet ${sheet.id} (${sheet.name}): user_id=${sheetUserId}, ` +
        `state=${sheet.state}, assigned=${isAssignedToUser}, stateOK=${isRightState}`
      );

      return isAssignedToUser && isRightState;
    });

    console.log(`Returning ${filtered.length} sheets for user ${userId}`);
    return filtered;
  }
}

// Export a single shared instance
module.exports = new OdooService();