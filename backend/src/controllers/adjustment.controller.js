const OdooService = require("../services/odooServices");
const AuthController = require("./authController");

class AdjustmentController {
  static async getAdjustments(req, res) {
    try {
      const session = AuthController.getSession();

      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated. Please login first."
        });
      }

      const adjustments = await OdooService.fetchAdjustments(session.host);

      // Sort: "en cours" (draft/in progress) first
      adjustments.sort((a, b) => {
        const order = { draft: 0, confirm: 1, done: 2, cancel: 3 };
        return (order[a.state] ?? 9) - (order[b.state] ?? 9);
      });

      return res.json(adjustments);

    } catch (error) {
      console.error("ADJUSTMENT ERROR:", error.message);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }
}

module.exports = AdjustmentController;