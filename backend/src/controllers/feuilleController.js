const OdooService = require("../services/odooServices");
const AuthController = require("./authController");

class FeuilleController {
  static async getFeuilles(req, res) {
    try {
      const session = AuthController.getSession();

      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const feuilles = await OdooService.fetchFeuilles(
        session.host,
        req.params.id
      );

      return res.json(feuilles);

    } catch (error) {
      console.error("FEUILLES ERROR:", error.message);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }
}

module.exports = FeuilleController;