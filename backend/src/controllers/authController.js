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
      const { email, password } = req.body;
      const db = (req.body.db || "").trim();
      // Normalise the URL: trim spaces and drop trailing slashes.
      const host = (req.body.host || "").trim().replace(/\/+$/, "");
      console.log("login attempt for:", { host, db: db || "(auto)", email });
 
      if (!host || !email || !password) {
        return res.status(400).json({ success: false, message: "host, email and password are required" });
      }
 
      // The database is optional: when empty it is detected from the Odoo URL,
      // and the same call that finds it also logs the user in (one pass, with timeouts).
      const result = db
        ? await OdooService.authenticate(host, db, email, password)
        : await OdooService.authenticateAutoDb(host, email, password);
 
      const token = crypto.randomUUID();
      const session = {
        token, host, db: result.db, email,
        uid: result.uid, name: result.name, cookie: result.sessionCookie
      };
      sessions.set(token, session);
 
      return res.json({ success: true, uid: result.uid, name: result.name, token, db: result.db });
    } catch (error) {
      console.error("LOGIN ERROR:", error.message);
      const status = error.code === "TIMEOUT" || error.code === "UNREACHABLE" ? 504 : 401;
      return res.status(status).json({ success: false, message: error.message });
    }
  }
 
  static getSessionByToken(token) { return token ? sessions.get(token) || null : null; }
  static removeSession(token) { if (token) sessions.delete(token); }
}
 
module.exports = AuthController;