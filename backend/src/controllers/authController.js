const crypto = require("crypto");
const OdooService = require("../services/odooServices");
const RequestSessionContext = require("../services/requestSessionContext");

// Server-side sessions are keyed by a random app token. Each token owns its
// own Odoo host/db/user/cookie, so different phones can be logged in at once.
const sessions = new Map();

class AuthController {
  static getSession(req = null) {
    if (req && req.session) return req.session;
    return RequestSessionContext.get();
  }

  static async login(req, res) {
    try {
      const { host, db, email, password } = req.body;
      console.log("login attempt for:", { host, db, email });

      if (!host || !email || !password) {
        return res.status(400).json({ success: false, message: "host, email and password are required" });
      }

      let dbName = db;
      if (!dbName || dbName === '') {
        try {
          const dbListResponse = await fetch(`${host}/web/database/list`);
          const dbListData = await dbListResponse.json();
          if (dbListData.result && dbListData.result.length > 0) {
            for (const testDb of dbListData.result) {
              try {
                const testResult = await OdooService.authenticate(host, testDb, email, password);
                if (testResult && testResult.uid) { dbName = testDb; break; }
              } catch (_) {}
            }
          }
        } catch (e) { console.log("Could not fetch database list:", e.message); }

        if (!dbName) {
          for (const testDb of ['odoo_db', 'odoo', 'postgres', 'default']) {
            try {
              const testResult = await OdooService.authenticate(host, testDb, email, password);
              if (testResult && testResult.uid) { dbName = testDb; break; }
            } catch (_) {}
          }
        }
      }

      if (!dbName) throw new Error("No valid database found. Please check your connection or specify a database name.");

      const result = await OdooService.authenticate(host, dbName, email, password);
      const token = crypto.randomUUID();
      const session = { token, host, db: dbName, email, uid: result.uid, name: result.name, cookie: result.sessionCookie };
      sessions.set(token, session);

      return res.json({ success: true, uid: result.uid, name: result.name, token });
    } catch (error) {
      console.error("LOGIN ERROR:", error.message);
      return res.status(401).json({ success: false, message: error.message });
    }
  }

  static getSessionByToken(token) { return token ? sessions.get(token) || null : null; }
  static removeSession(token) { if (token) sessions.delete(token); }
}

module.exports = AuthController;
