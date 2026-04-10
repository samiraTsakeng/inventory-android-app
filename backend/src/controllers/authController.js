const OdooService = require("../services/odooServices");

class AuthController {
  static sessionData = {};

  // 🔐 LOGIN
  static async login(req, res) {
    const { host, db, email, password } = req.body;

    try {
      const result = await OdooService.authenticate(host, db, email, password);

      // ✅ SAVE SESSION
      AuthController.sessionData = { host, db, email };

      return res.json({
        success: true,
        uid: result.uid
      });

    } catch (error) {
      console.log("LOGIN ERROR:", error.message);

      return res.status(401).json({
        success: false,
        message: error.message
      });
    }
  }

  // (optional test endpoint)
  static async createUser(req, res) {
    return res.status(501).json({
      success: false,
      message: "Not implemented"
    });
  }
}

module.exports = AuthController;