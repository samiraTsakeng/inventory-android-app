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

  // Get consolidation sheet detail with lines from BOTH counting sheets
// Get consolidation sheet detail with lines from BOTH counting sheets
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
          args: [[sheetId], ["id", "name", "state", "zone_id", "user_id", "stock_inventory_id"]],
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

    // ✅ Extract IDs from arrays [id, name]
    const adjustmentId = Array.isArray(sheet.stock_inventory_id)
      ? sheet.stock_inventory_id[0]
      : sheet.stock_inventory_id;

    const zoneId = Array.isArray(sheet.zone_id)
      ? sheet.zone_id[0]
      : sheet.zone_id;

    console.log("Adjustment ID:", adjustmentId, "Zone ID:", zoneId);

    // ✅ Get the TWO counting sheets for this zone
    const countingSheetsResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Cookie": OdooService.sessionCookie
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        method: "call",
        params: {
          model: "counting.sheet",
          method: "search_read",
          args: [[
            ["stock_inventory_id", "=", adjustmentId],
            ["zone_id", "=", zoneId]
          ]],
          kwargs: {
            fields: ["id", "name", "state", "user_id", "counting_line_ids"]
          }
        }
      })
    });

    const countingSheetsData = await countingSheetsResponse.json();
    if (countingSheetsData.error) {
      throw new Error(countingSheetsData.error.data?.message || countingSheetsData.error.message);
    }

    const countingSheets = countingSheetsData.result || [];
    console.log("Counting sheets found:", countingSheets.length);

    // ✅ Get lines from counting sheet 1 (Team 1)
    let sheet1Lines = [];
    let sheet1Name = "Équipe 1";

    if (countingSheets.length >= 1) {
      sheet1Name = countingSheets[0].name || "Équipe 1";
      if (countingSheets[0].counting_line_ids) {
        const linesResponse1 = await fetch(`${session.host}/web/dataset/call_kw`, {
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
              args: [[["sheet_id", "=", countingSheets[0].id]]],
              kwargs: {
                fields: ["id", "lot_id", "product_id", "counted_qty"]
              }
            }
          })
        });
        const linesData1 = await linesResponse1.json();
        sheet1Lines = linesData1.result || [];
        console.log("Sheet 1 lines:", sheet1Lines.length);
      }
    }

    // ✅ Get lines from counting sheet 2 (Team 2)
    let sheet2Lines = [];
    let sheet2Name = "Équipe 2";

    if (countingSheets.length >= 2) {
      sheet2Name = countingSheets[1].name || "Équipe 2";
      if (countingSheets[1].counting_line_ids) {
        const linesResponse2 = await fetch(`${session.host}/web/dataset/call_kw`, {
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
              args: [[["sheet_id", "=", countingSheets[1].id]]],
              kwargs: {
                fields: ["id", "lot_id", "product_id", "counted_qty"]
              }
            }
          })
        });
        const linesData2 = await linesResponse2.json();
        sheet2Lines = linesData2.result || [];
        console.log("Sheet 2 lines:", sheet2Lines.length);
      }
    }

    // ✅ Build a map of lot_id to quantities for each sheet
    const sheet1Map = {};
    for (const line of sheet1Lines) {
      const lotId = line.lot_id ? (Array.isArray(line.lot_id) ? line.lot_id[0] : line.lot_id) : null;
      if (lotId) {
        sheet1Map[lotId] = {
          lot_id: lotId,
          product_id: line.product_id,
          counted_qty: line.counted_qty
        };
      }
    }

    const sheet2Map = {};
    for (const line of sheet2Lines) {
      const lotId = line.lot_id ? (Array.isArray(line.lot_id) ? line.lot_id[0] : line.lot_id) : null;
      if (lotId) {
        sheet2Map[lotId] = {
          lot_id: lotId,
          product_id: line.product_id,
          counted_qty: line.counted_qty
        };
      }
    }

    // ✅ Get consolidation lines (corresponding)
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

    // ✅ Get contradictory lines
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

    // ✅ ENRICH contradictory lines with quantities from both sheets
    const enrichedContradictoryLines = (contradictoryData.result || []).map(line => {
      const lotId = line.lot_id ? (Array.isArray(line.lot_id) ? line.lot_id[0] : line.lot_id) : null;

      // Get quantities from both sheets
      const sheet1Data = lotId ? sheet1Map[lotId] : null;
      const sheet2Data = lotId ? sheet2Map[lotId] : null;

      return {
        ...line,
        counted_qty_1: sheet1Data ? sheet1Data.counted_qty : 0,
        counted_qty_2: sheet2Data ? sheet2Data.counted_qty : 0,
        lot_name: line.lot_name || (sheet1Data ? sheet1Data.lot_name : null) || (sheet2Data ? sheet2Data.lot_name : null),
        product_name: line.product_name || (sheet1Data ? sheet1Data.product_name : null) || (sheet2Data ? sheet2Data.product_name : null),
      };
    });

    // ✅ Combine data for response
    const result = {
      ...sheet,
      counting_sheet_1: countingSheets.length >= 1 ? countingSheets[0] : null,
      counting_sheet_2: countingSheets.length >= 2 ? countingSheets[1] : null,
      counting_sheet_1_name: sheet1Name,
      counting_sheet_2_name: sheet2Name,
      counting_line_ids: linesData.result || [],
      counting_contradictory_line_ids: enrichedContradictoryLines,
      sheet1_lines: sheet1Lines,
      sheet2_lines: sheet2Lines,
    };

    console.log("Contradictory lines enriched:", enrichedContradictoryLines.length);

    return res.json(result);

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