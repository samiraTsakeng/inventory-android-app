const OdooService = require("../services/odooServices");
const AuthController = require("./authController");

class ConsolidationController {
  // Get all consolidation sheets for an adjustment
  static async getConsolidationSheets(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const adjustmentId = parseInt(req.params.adjustment_id);
      console.log("Fetching consolidation sheets for adjustment:", adjustmentId);

      const response = await fetch(`${session.host}/web/dataset/call_kw`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Cookie": OdooService.sessionCookie
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method: "call",
          params: {
            model: "consolidation.sheet",
            method: "search_read",
            args: [[["stock_inventory_id", "=", adjustmentId]]],
            kwargs: {
              fields: ["id", "name", "state", "zone_id", "user_id", "counting_line_ids", "counting_contradictory_line_ids"]
            }
          }
        })
      });

      const data = await response.json();
      console.log("Consolidation sheets found:", data.result?.length || 0);

      if (data.error) {
        throw new Error(data.error.data?.message || data.error.message);
      }

      return res.json(data.result || []);
    } catch (error) {
      console.error("Get consolidation sheets error:", error);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Get consolidation sheet detail with lines
  static async getConsolidationSheetDetail(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const sheetId = parseInt(req.params.sheet_id);
      console.log("Fetching consolidation sheet detail:", sheetId);

      // Get sheet with all fields
      const sheetResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Cookie": OdooService.sessionCookie
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method: "call",
          params: {
            model: "consolidation.sheet",
            method: "read",
            args: [[sheetId], ["id", "name", "state", "zone_id", "user_id"]],
            kwargs: {}
          }
        })
      });

      const sheetData = await sheetResponse.json();
      if (sheetData.error) {
        throw new Error(sheetData.error.data?.message || sheetData.error.message);
      }

      if (!sheetData.result || sheetData.result.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Consolidation sheet not found"
        });
      }

      const sheet = sheetData.result[0];

      // Get counting lines
      const linesResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Cookie": OdooService.sessionCookie
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method: "call",
          params: {
            model: "counting.sheet.line",
            method: "search_read",
            args: [[["consolidation_sheet_id", "=", sheetId]]],
            kwargs: {
              fields: ["id", "lot_id", "product_id", "counted_qty"]
            }
          }
        })
      });

      const linesData = await linesResponse.json();
      if (linesData.error) {
        throw new Error(linesData.error.data?.message || linesData.error.message);
      }

      // Get contradictory lines
      const contradictoryResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Cookie": OdooService.sessionCookie
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method: "call",
          params: {
            model: "counting.sheet.contradictory.line",
            method: "search_read",
            args: [[["sheet_id", "=", sheetId]]],
            kwargs: {
              fields: ["id", "lot_id", "product_id", "verified_qty"]
            }
          }
        })
      });

      const contradictoryData = await contradictoryResponse.json();
      if (contradictoryData.error) {
        throw new Error(contradictoryData.error.data?.message || contradictoryData.error.message);
      }

      // Get the two counting sheets for this zone to get the quantities
      // This requires additional logic to get the quantities from the original counting sheets
      // For now, we'll return what we have

      return res.json({
        ...sheet,
        counting_line_ids: linesData.result || [],
        counting_contradictory_line_ids: contradictoryData.result || []
      });

    } catch (error) {
      console.error("Get consolidation sheet detail error:", error);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Update verified quantity for a contradictory line
  static async updateContradictoryLine(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const { line_id, verified_qty } = req.body;
      console.log("Updating contradictory line:", line_id, "with qty:", verified_qty);

      const response = await fetch(`${session.host}/web/dataset/call_kw`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Cookie": OdooService.sessionCookie
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method: "call",
          params: {
            model: "counting.sheet.contradictory.line",
            method: "write",
            args: [[line_id], { verified_qty: verified_qty }],
            kwargs: {}
          }
        })
      });

      const data = await response.json();
      console.log("Update contradictory line response:", JSON.stringify(data, null, 2));

      if (data.error) {
        throw new Error(data.error.data?.message || data.error.message);
      }

      return res.json({
        success: true,
        message: "Verified quantity updated successfully"
      });

    } catch (error) {
      console.error("Update contradictory line error:", error);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Validate consolidation sheet
  static async validateConsolidationSheet(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const { sheet_id } = req.body;
      console.log("Validating consolidation sheet:", sheet_id);

      const response = await fetch(`${session.host}/web/dataset/call_kw`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Cookie": OdooService.sessionCookie
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method: "call",
          params: {
            model: "consolidation.sheet",
            method: "action_validate_contradictory",
            args: [[sheet_id]],
            kwargs: {}
          }
        })
      });

      const data = await response.json();
      console.log("Validate consolidation sheet response:", JSON.stringify(data, null, 2));

      if (data.error) {
        throw new Error(data.error.data?.message || data.error.message);
      }

      return res.json({
        success: true,
        message: "Consolidation sheet validated successfully"
      });

    } catch (error) {
      console.error("Validate consolidation sheet error:", error);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }
}

module.exports = ConsolidationController;