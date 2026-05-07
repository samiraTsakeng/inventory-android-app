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
      console.log("Looking up product with barcode:", barcode);

      // Search for product by barcode
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
      console.log("Product lookup response:", JSON.stringify(data, null, 2));

      if (data.result && data.result.length > 0) {
        return res.json({
          success: true,
          product: data.result[0]
        });
      } else {
        // Try searching by default_code if not found by barcode
        const response2 = await fetch(`${session.host}/web/dataset/call_kw`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Cookie": OdooService.sessionCookie
          },
          body: JSON.stringify({
            jsonrpc: "2.0",
            method: "call",
            params: {
              model: "product.product",
              method: "search_read",
              args: [[["default_code", "=", barcode]]],
              kwargs: {
                fields: ["id", "name", "barcode", "default_code"]
              }
            }
          })
        });

        const data2 = await response2.json();
        console.log("Product lookup by default_code:", JSON.stringify(data2, null, 2));

        if (data2.result && data2.result.length > 0) {
          return res.json({
            success: true,
            product: data2.result[0]
          });
        }

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

  // Check counting sheet state
  static async getSheetState(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const { sheet_id } = req.params;
      console.log("Getting state for sheet ID:", sheet_id);

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
            model: "counting.sheet",
            method: "read",
            args: [[parseInt(sheet_id)], ["id", "name", "state", "zone_id", "user_id"]],
            kwargs: {}
          }
        })
      });

      const data = await response.json();
      console.log("Sheet state response:", JSON.stringify(data, null, 2));

      if (data.error) {
        throw new Error(data.error.message);
      }

      return res.json({
        success: true,
        sheet: data.result ? data.result[0] : null
      });
    } catch (error) {
      console.error("Get sheet state error:", error);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  // Start a counting sheet
  static async startSheet(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const { sheet_id } = req.body;
      console.log("Starting sheet ID:", sheet_id);

      // Call the action_begin method on the counting sheet
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
            model: "counting.sheet",
            method: "action_begin",
            args: [[parseInt(sheet_id)]],
            kwargs: {}
          }
        })
      });

      const data = await response.json();
      console.log("Start sheet response:", JSON.stringify(data, null, 2));

      if (data.error) {
        throw new Error(data.error.data?.message || data.error.message || "Failed to start sheet");
      }

      return res.json({
        success: true,
        message: "Counting sheet started successfully"
      });
    } catch (error) {
      console.error("Start sheet error:", error);
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

      console.log("=== SUBMITTING SCANS ===");
      console.log("Counting Sheet ID:", counting_sheet_id);
      console.log("Adjustment ID:", adjustment_id);
      console.log("Items count:", items.length);

      if (!items || items.length === 0) {
        return res.status(400).json({
          success: false,
          message: "No items to submit"
        });
      }

      // FIRST: Check the current state of the counting sheet
      let sheetState = null;
      try {
        const stateResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
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
              method: "read",
              args: [[counting_sheet_id], ["id", "name", "state"]],
              kwargs: {}
            }
          })
        });
        const stateData = await stateResponse.json();
        if (stateData.result && stateData.result.length > 0) {
          sheetState = stateData.result[0].state;
          console.log("Current sheet state:", sheetState);
        }
      } catch (err) {
        console.warn("Could not fetch sheet state:", err.message);
      }

      // SECOND: If sheet is in 'new' state, start it
      let sheetStarted = false;
      if (sheetState === 'new') {
        console.log("Sheet is in 'new' state, attempting to start it...");
        try {
          const startResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
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
                method: "action_begin",
                args: [[counting_sheet_id]],
                kwargs: {}
              }
            })
          });
          const startData = await startResponse.json();
          if (!startData.error) {
            sheetStarted = true;
            console.log("Sheet started successfully!");
          } else {
            console.error("Failed to start sheet:", startData.error);
            // Check if it's because another sheet is in progress
            if (startData.error.data?.message && startData.error.data.message.includes("terminer le comptage précédent")) {
              return res.status(400).json({
                success: false,
                message: startData.error.data.message,
                requires_attention: true
              });
            }
          }
        } catch (err) {
          console.error("Error starting sheet:", err.message);
        }
      }

      // THIRD: Get a valid product ID from Odoo
      let defaultProductId = null;
      try {
        const productResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Cookie": OdooService.sessionCookie
          },
          body: JSON.stringify({
            jsonrpc: "2.0",
            method: "call",
            params: {
              model: "product.product",
              method: "search_read",
              args: [[]],
              kwargs: {
                fields: ["id"],
                limit: 1
              }
            }
          })
        });
        const productData = await productResponse.json();
        if (productData.result && productData.result.length > 0) {
          defaultProductId = productData.result[0].id;
          console.log("Found default product ID:", defaultProductId);
        }
      } catch (err) {
        console.warn("Could not fetch default product:", err.message);
      }

      if (!defaultProductId) {
        return res.status(400).json({
          success: false,
          message: "No products found in Odoo. Please add products first."
        });
      }

      // FOURTH: Create counting sheet lines ONE BY ONE
      const createdLineIds = [];
      const failedItems = [];

      for (const item of items) {
        console.log("Processing item:", item.barcode, "Product ID:", item.product_id);

        const lineData = {
          number: item.barcode,
          product_id: item.product_id && item.product_id !== 0 ? item.product_id : defaultProductId,
          counted_qty: item.quantity,
          sheet_id: counting_sheet_id
        };

        console.log("Creating line with sheet_id:", counting_sheet_id);
        console.log("Line data:", JSON.stringify(lineData, null, 2));

        const createResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
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
              method: "create",
              args: [lineData],
              kwargs: {}
            }
          })
        });

        const responseText = await createResponse.text();
        let lineResult;

        try {
          lineResult = JSON.parse(responseText);
        } catch (e) {
          console.error("Failed to parse response:", responseText);
          failedItems.push(item.barcode);
          continue;
        }

        if (lineResult.error) {
          console.error("Error creating line:", lineResult.error);
          failedItems.push(item.barcode);
        } else {
          createdLineIds.push(lineResult.result);
          console.log(`Created line with ID: ${lineResult.result}`);
        }
      }

      console.log(`Successfully created ${createdLineIds.length} lines, failed: ${failedItems.length}`);

      if (createdLineIds.length === 0) {
        return res.status(400).json({
          success: false,
          message: "Failed to create any counting lines",
          failed_items: failedItems
        });
      }

      // FIFTH: Update counting sheet state to confirm if max items reached (50)
      let sheetConfirmed = false;
      if (items.length >= 50) {
        console.log("Reached 50 items limit, updating counting sheet state to confirm");
        const updateResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
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
              method: "write",
              args: [[counting_sheet_id], { state: "confirm" }],
              kwargs: {}
            }
          })
        });

        const updateData = await updateResponse.json();
        if (!updateData.error) {
          sheetConfirmed = true;
          console.log("Sheet confirmed successfully!");
        } else {
          console.warn("Failed to update sheet state:", updateData.error);
        }
      }

      return res.json({
        success: true,
        message: `${createdLineIds.length} items submitted successfully`,
        submitted_count: createdLineIds.length,
        failed_items: failedItems,
        sheet_started: sheetStarted,
        sheet_confirmed: sheetConfirmed
      });

    } catch (error) {
      console.error("Submit error:", error);
      console.error("Error stack:", error.stack);
      return res.status(500).json({
        success: false,
        message: error.message || "Failed to submit scans"
      });
    }
  }

  // Debug: Check counting sheet lines
  static async checkSheetLines(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const { sheet_id } = req.params;
      console.log("Checking lines for sheet ID:", sheet_id);

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
            model: "counting.sheet.line",
            method: "search_read",
            args: [[["sheet_id", "=", parseInt(sheet_id)]]],
            kwargs: {
              fields: ["id", "number", "product_id", "counted_qty", "sheet_id"]
            }
          }
        })
      });

      const data = await response.json();
      console.log("Lines found:", JSON.stringify(data, null, 2));

      return res.json({
        success: true,
        lines: data.result || []
      });
    } catch (error) {
      console.error("Check lines error:", error);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }

  static async checkSheetState(req, res) {
    try {
      const session = AuthController.getSession();
      const { sheet_id } = req.params;

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
            model: "counting.sheet",
            method: "search_read",
            args: [[["id", "=", parseInt(sheet_id)]]],
            kwargs: {
              fields: ["id", "name", "state", "counting_line_ids", "zone_id", "user_id"]
            }
          }
        })
      });

      const data = await response.json();
      console.log("Sheet state:", JSON.stringify(data, null, 2));

      return res.json({
        success: true,
        sheet: data.result ? data.result[0] : null
      });
    } catch (error) {
      console.error("Check sheet error:", error);
      return res.status(500).json({
        success: false,
        message: error.message
      });
    }
  }
}

module.exports = CountingController;