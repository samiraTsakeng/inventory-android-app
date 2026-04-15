const OdooService = require("../services/odooServices");
const AuthController = require("./authController");

class FeuilleController {
  static async getFeuilles(req, res) {
    try {
      const { id } = req.params;

      if (!AuthController.sessionData) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated",
        });
      }

      const { host } = AuthController.sessionData;

      const feuilles = await OdooService.fetchFeuilles(host, id);

      return res.json(feuilles);

    } catch (error) {
      console.error("FEUILLES ERROR:", error);

      return res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  }
}

module.exports = FeuilleController;