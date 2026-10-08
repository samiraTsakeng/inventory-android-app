const fetch = require("node-fetch");
const RequestSessionContext = require("./requestSessionContext");

class OdooService {
  async authenticate(host, db, email, password) {
    const response = await fetch(`${host}/web/session/authenticate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", method: "call", params: { db, login: email, password } })
    });
    const data = await response.json();
    console.log("Odoo login response:", JSON.stringify(data, null, 2));
    if (!data.result || !data.result.uid) throw new Error("Authentication failed: wrong credentials");
    const cookies = response.headers.get("set-cookie");
    if (!cookies) throw new Error("No session cookie received from Odoo");
    return { ...data.result, sessionCookie: cookies };
  }

  // Backward-compatible property, but now request-scoped rather than global.
  get sessionCookie() {
    return RequestSessionContext.get()?.cookie || "";
  }

  async fetchAdjustments(host, uid) {
    const response = await fetch(`${host}/web/dataset/call_kw`, {
      method: "POST", headers: { "Content-Type": "application/json", "Cookie": this.sessionCookie },
      body: JSON.stringify({ jsonrpc: "2.0", method: "call", params: {
        model: "stock.inventory", method: "search_read",
        args: [[ ["state", "in", ["draft", "in_progress"]] ]],
        kwargs: { fields: ["id", "name", "state", "date", "manager_id"] }
      }})
    });
    const data = await response.json();
    if (data.error) throw new Error(data.error.data?.message || data.error.message);
    return data.result || [];
  }

  async fetchFeuilles(host, adjustmentId, userId) {
    const response = await fetch(`${host}/web/dataset/call_kw`, {
      method: "POST", headers: { "Content-Type": "application/json", "Cookie": this.sessionCookie },
      body: JSON.stringify({ jsonrpc: "2.0", method: "call", params: {
        model: "counting.sheet", method: "search_read",
        args: [[ ["stock_inventory_id", "=", parseInt(adjustmentId)] ]],
        kwargs: { fields: ["id", "name", "state", "stock_inventory_id", "zone_id", "user_id"] }
      }})
    });
    const data = await response.json();
    if (data.error) throw new Error(data.error.data?.message || data.error.message);
    const allSheets = data.result || [];
    return allSheets.filter(sheet => {
      const sheetUserId = Array.isArray(sheet.user_id) ? sheet.user_id[0] : (typeof sheet.user_id === "number" ? sheet.user_id : null);
      return sheetUserId === userId && (sheet.state === "new" || sheet.state === "progress");
    });
  }
}
module.exports = new OdooService();
