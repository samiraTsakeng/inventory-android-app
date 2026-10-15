const fetch = require("node-fetch");
const RequestSessionContext = require("./requestSessionContext");

const AUTH_TIMEOUT_MS = 10000; // one Odoo authenticate attempt
const DBLIST_TIMEOUT_MS = 5000; // listing databases

// fetch() with a hard timeout, so a dead/unreachable host can never hang a request.
async function fetchWithTimeout(url, options = {}, timeoutMs = AUTH_TIMEOUT_MS) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } catch (e) {
    if (e.name === "AbortError") {
      const err = new Error("The Odoo server took too long to respond");
      err.code = "TIMEOUT";
      throw err;
    }
    const err = new Error(`Cannot reach the Odoo server (${e.message})`);
    err.code = "UNREACHABLE";
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

class OdooService {
  // Single authenticate attempt against ONE database.
  // Error codes: BAD_CREDENTIALS (db exists, wrong login/password),
  // DB_ERROR (db does not exist / Odoo error), NO_COOKIE, TIMEOUT, UNREACHABLE.
  async authenticate(host, db, email, password) {
    const response = await fetchWithTimeout(`${host}/web/session/authenticate`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", method: "call", params: { db, login: email, password } })
    });

    let data;
    try {
      data = await response.json();
    } catch (_) {
      const err = new Error("The server did not return a valid Odoo response. Check the URL.");
      err.code = "DB_ERROR";
      throw err;
    }

    if (data.error) {
      const err = new Error(data.error.data?.message || data.error.message || "Odoo error");
      err.code = "DB_ERROR";
      throw err;
    }
    if (!data.result || !data.result.uid) {
      const err = new Error("Wrong email or password");
      err.code = "BAD_CREDENTIALS";
      throw err;
    }
    const cookies = response.headers.get("set-cookie");
    if (!cookies) {
      const err = new Error("No session cookie received from Odoo");
      err.code = "NO_COOKIE";
      throw err;
    }
    // Deliberately NOT logging data.result: it contains session_id and user details.
    return { ...data.result, db, sessionCookie: cookies };
  }

  // Odoo 11 exposes /web/database/list as a JSON-RPC route: it must be a POST
  // with a JSON-RPC body (a plain GET does not work). Returns [] if disabled.
  async listDatabases(host) {
    try {
      const response = await fetchWithTimeout(`${host}/web/database/list`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", method: "call", params: {} })
      }, DBLIST_TIMEOUT_MS);
      const data = await response.json();
      return Array.isArray(data.result) ? data.result : [];
    } catch (_) {
      return [];
    }
  }

  // Guess database names from the URL, e.g. https://acme.example.com -> "acme".
  guessDatabasesFromHost(host) {
    try {
      const hostname = new URL(host).hostname;
      if (/^\d+\.\d+\.\d+\.\d+$/.test(hostname)) return [];
      const parts = hostname.split(".");
      return [parts[0], hostname].filter(Boolean);
    } catch (_) {
      return [];
    }
  }

  // Detect the database from the Odoo URL and authenticate in ONE pass.
  // Candidates are tried in parallel, and the first success wins.
  async authenticateAutoDb(host, email, password) {
    const listed = await this.listDatabases(host);
    const candidates = [...new Set(
      listed.length > 0
        ? listed
        : [...this.guessDatabasesFromHost(host), "odoo_db", "odoo", "default"]
    )].slice(0, 10);

    try {
      return await Promise.any(
        candidates.map((db) => this.authenticate(host, db, email, password))
      );
    } catch (agg) {
      const errors = agg.errors || [];
      if (errors.some((e) => e.code === "BAD_CREDENTIALS")) {
        throw new Error("Wrong email or password");
      }
      if (errors.length && errors.every((e) => e.code === "UNREACHABLE" || e.code === "TIMEOUT")) {
        throw new Error(errors[0].message);
      }
      throw new Error("No matching Odoo database found for this server URL.");
    }
  }

  // Backward-compatible property, but now request-scoped rather than global.
  get sessionCookie() {
    return RequestSessionContext.get()?.cookie || "";
  }

   async fetchAdjustments(host, uid) {
      // An adjustment is visible to an employee only when at least one active
      // counting sheet belonging to that adjustment is assigned to that Odoo
      // user. The assignment is stored on counting.sheet.user_id.
      const headers = {
        "Content-Type": "application/json",
        "Cookie": this.sessionCookie,
      };

      const callKw = async (model, domain, fields) => {
        const response = await fetch(`${host}/web/dataset/call_kw`, {
          method: "POST",
          headers,
          body: JSON.stringify({
            jsonrpc: "2.0",
            method: "call",
            params: {
              model,
              method: "search_read",
              args: [domain],
              kwargs: { fields },
            },
          }),
        });
        const data = await response.json();
        if (!response.ok || data.error) {
          throw new Error(data.error?.data?.message || data.error?.message || `Odoo ${model} request failed`);
        }
        return data.result || [];
      };

      const sheets = await callKw(
        "counting.sheet",
        [["user_id", "=", uid], ["state", "in", ["new", "progress"]]],
        ["id", "stock_inventory_id", "user_id", "state"]
      );

      const assignedAdjustmentIds = new Set(
        sheets
          .map((sheet) => Array.isArray(sheet.stock_inventory_id)
            ? sheet.stock_inventory_id[0]
            : sheet.stock_inventory_id)
          .filter((id) => Number.isInteger(Number(id)) && Number(id) > 0)
          .map(Number)
      );

      if (assignedAdjustmentIds.size === 0) return [];

      const adjustments = await callKw(
        "stock.inventory",
        [["id", "in", [...assignedAdjustmentIds]], ["state", "in", ["draft", "in_progress"]]],
        ["id", "name", "state", "date", "manager_id"]
      );
      return adjustments;
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