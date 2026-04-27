const OdooService = require("../services/odooServices");

// Session stored as module-level variable (simple, works on all Node versions)
let sessionData = null;

class AuthController {
  static getSession() {
    return sessionData;
  }

  static async login(req, res) {
    try {
      const { host, db, email, password } = req.body;

        console.log("login attempt for:", {host, db, email});
      if (!host || !email || !password) {
        return res.status(400).json({
          success: false,
          message: "host, email and password are required"
        });
      }

      const result = await OdooService.authenticate(host, db, email, password);

      sessionData = { host, db, email };

      return res.json({
        success: true,
        uid: result.uid,
        name: result.name
      });

    } catch (error) {
      console.error("LOGIN ERROR:", error.message);
      return res.status(401).json({
        success: false,
        message: error.message
      });
    }
  }
}

module.exports = AuthController;