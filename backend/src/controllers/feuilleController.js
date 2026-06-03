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

      // req.params.id contains the adjustment ID from the URL
      const feuilles = await OdooService.fetchFeuilles(
        session.host,
        req.params.id,  // ← This is the adjustmentId
        session.uid
      );

      return res.json(feuilles);

    } catch (error) {
      console.error("FEUILLES ERROR:", error.message);

      //extract clean error message
      let cleanMessage = error.message;

      //check if it is an access error and format nicely
      if (error.message.includes("Désolé, vous n'êtes pas autorisé")) {
      cleanMessage = "Désolé, vous n'êtes pas autorisé à accéder à ce document. Seuls les utilisateurs avec les niveaux d'accès suivants sont actuellement autorisés à faire cela:\n- Ajustement Général/Resp. Comptage\n- Ajustement Général/Resp. Ajustement";
      }
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }
}

module.exports = FeuilleController;