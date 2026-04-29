const OdooService = require("../services/odooServices");
const AuthController = require("./authController");

class CountingController {
  // Look up product by barcode
  static async lookupProduct(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const { barcode } = req.body;

      // Search for product by barcode
      const response = await fetch(`${session.host}/web/dataset/call_kw`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Cookie: OdooService.sessionCookie
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method: "call",
          params: {
            model: "product.product",
            method: "search_read",
            args: [[["barcode", "=", barcode]]],
            kwargs: {
              fields: ["id", "name", "barcode", "default_code"]
            }
          }
        })
      });

      const data = await response.json();

      if (data.result && data.result.length > 0) {
        return res.json({
          success: true,
          product: data.result[0]
        });
      } else {
        return res.json({
          success: false,
          message: "Product not found"
        });
      }
    } catch (error) {
      console.error("Lookup error:", error);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Submit scanned items to counting sheet
  static async submitScans(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const { counting_sheet_id, adjustment_id, items } = req.body;

      console.log("Submitting scans for sheet:", counting_sheet_id);
      console.log("Items count:", items.length);

      // Create counting sheet lines in Odoo
      const lines = [];
      for (const item of items) {
        // First, find or create the product/lot
        let lotId = null;

        if (item.lot_number) {
          // Search for existing lot
          const lotSearch = await fetch(`${session.host}/web/dataset/call_kw`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Cookie: OdooService.sessionCookie
            },
            body: JSON.stringify({
              jsonrpc: "2.0",
              method: "call",
              params: {
                model: "stock.production.lot",
                method: "search_read",
                args: [[["name", "=", item.lot_number]]],
                kwargs: { fields: ["id"] }
              }
            })
          });

          const lotData = await lotSearch.json();
          if (lotData.result && lotData.result.length > 0) {
            lotId = lotData.result[0].id;
          }
        }

        lines.push({
          number: item.barcode,
          product_id: item.product_id,
          lot_id: lotId,
          counted_qty: item.quantity
        });
      }

      // Create the counting sheet lines
      const createResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Cookie: OdooService.sessionCookie
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method: "call",
          params: {
            model: "counting.sheet.line",
            method: "create",
            args: [lines],
            kwargs: {}
          }
        })
      });

      const data = await createResponse.json();

      if (data.error) {
        throw new Error(data.error.data?.message || data.error.message);
      }

      // Update counting sheet state to confirm if needed
      if (items.length >= 50) {
        await fetch(`${session.host}/web/dataset/call_kw`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Cookie: OdooService.sessionCookie
          },
          body: JSON.stringify({
            jsonrpc: "2.0",
            method: "call",
            params: {
              model: "counting.sheet",
              method: "write",
              args: [[counting_sheet_id], { state: "confirm" }],
              kwargs: {}
            }
          })
        });
      }

      return res.json({
        success: true,
        message: `${items.length} items submitted successfully`
      });

    } catch (error) {
      console.error("Submit error:", error);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }
}

module.exports = CountingController;