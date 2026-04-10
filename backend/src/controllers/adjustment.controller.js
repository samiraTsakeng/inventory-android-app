const OdooService = require("../services/odooServices");
const AuthController = require("./authController");

class AdjustmentController {
  static async getAdjustments(req, res) {
    try {
      // ✅ Check session exists (VERY IMPORTANT)
      if (!AuthController.sessionData || !AuthController.sessionData.host) {
        return res.status(401).json({
          success: false,
          message: "User not authenticated",
        });
      }

      const { host } = AuthController.sessionData;

      // ✅ Fetch from Odoo
      const adjustments = await OdooService.fetchAdjustments(host);

      // ✅ Sort: "en cours" first
      adjustments.sort((a, b) => {
        if (a.state === "en cours") return -1;
        if (b.state === "en cours") return 1;
        return 0;
      });

      return res.json(adjustments);

    } catch (error) {
      console.error("ADJUSTMENT ERROR:", error);

      return res.status(500).json({
        success: false,
        message: error.message,
      });
    }
  }
}

module.exports = AdjustmentController;