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

      // First search for product by barcode (product.product)
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
              fields: ["id", "name", "barcode", "default_code", "product_tmpl_id"]
            }
          }
        })
      });

      const data = await response.json();
      console.log("Product lookup response:", JSON.stringify(data, null, 2));

      if (data.result && data.result.length > 0) {
        const product = data.result[0];
        let productTmplId = null;

        if (product.product_tmpl_id) {
          if (Array.isArray(product.product_tmpl_id)) {
            productTmplId = product.product_tmpl_id[0];
          } else {
            productTmplId = product.product_tmpl_id;
          }
        }

        let tracking = 'none';

        // Fetch tracking from product.template
        if (productTmplId) {
          const templateResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Cookie": OdooService.sessionCookie
            },
            body: JSON.stringify({
              jsonrpc: "2.0",
              method: "call",
              params: {
                model: "product.template",
                method: "read",
                args: [[productTmplId], ["tracking"]],
                kwargs: {}
              }
            })
          });

          const templateData = await templateResponse.json();
          console.log("Template tracking response:", JSON.stringify(templateData, null, 2));

          if (templateData.result && templateData.result.length > 0) {
            tracking = templateData.result[0].tracking || 'none';
          }
        }

        console.log("Product " + product.name + " has tracking: " + tracking);

        return res.json({
          success: true,
          product: {
            id: product.id,
            name: product.name,
            barcode: product.barcode,
            default_code: product.default_code,
            tracking: tracking
          }
        });
      } else {
        // Try searching by default_code
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
              args: [["default_code", "=", barcode]],
              kwargs: {
                fields: ["id", "name", "barcode", "default_code", "product_tmpl_id"]
              }
            }
          })
        });

        const data2 = await response2.json();
        console.log("Product lookup by default_code:", JSON.stringify(data2, null, 2));

        if (data2.result && data2.result.length > 0) {
          const product = data2.result[0];
          let productTmplId = null;

          if (product.product_tmpl_id) {
            if (Array.isArray(product.product_tmpl_id)) {
              productTmplId = product.product_tmpl_id[0];
            } else {
              productTmplId = product.product_tmpl_id;
            }
          }

          let tracking = 'none';

          if (productTmplId) {
            const templateResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "Cookie": OdooService.sessionCookie
              },
              body: JSON.stringify({
                jsonrpc: "2.0",
                method: "call",
                params: {
                  model: "product.template",
                  method: "read",
                  args: [[productTmplId], ["tracking"]],
                  kwargs: {}
                }
              })
            });

            const templateData = await templateResponse.json();
            if (templateData.result && templateData.result.length > 0) {
              tracking = templateData.result[0].tracking || 'none';
            }
          }

          return res.json({
            success: true,
            product: {
              id: product.id,
              name: product.name,
              barcode: product.barcode,
              default_code: product.default_code,
              tracking: tracking
            }
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

  // Validate a counting sheet (finish counting)
  static async validateSheet(req, res) {
    try {
      const session = AuthController.getSession();
      if (!session || !session.host) {
        return res.status(401).json({
          success: false,
          message: "Not authenticated"
        });
      }

      const { sheet_id } = req.body;
      console.log("Validating sheet ID:", sheet_id);

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
            method: "action_validate",
            args: [[parseInt(sheet_id)]],
            kwargs: {}
          }
        })
      });

      const data = await response.json();
      console.log("Validate sheet response:", JSON.stringify(data, null, 2));

      if (data.error) {
        throw new Error(data.error.data?.message || data.error.message || "Failed to validate sheet");
      }

      return res.json({
        success: true,
        message: "Counting sheet validated successfully"
      });
    } catch (error) {
      console.error("Validate sheet error:", error);
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

      // Check the current state of the counting sheet
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

      // If sheet is in 'new' state, start it
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
            console.log("Sheet started successfully!");
          } else if (startData.error.data?.message && startData.error.data.message.includes("terminer le comptage pr\u00e9c\u00e9dent")) {
            return res.status(400).json({
              success: false,
              message: startData.error.data.message,
              requires_attention: true
            });
          }
        } catch (err) {
          console.error("Error starting sheet:", err.message);
        }
      }

      // Find matching products for each barcode
      const itemsToCreate = [];
      for (const item of items) {
        let matchedProductId = null;

        // Try to find product by barcode
        const matchResponse = await fetch(`${session.host}/web/dataset/call_kw`, {
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
              args: [[["barcode", "=", item.barcode]]],
              kwargs: {
                fields: ["id", "name"]
              }
            }
          })
        });
        const matchData = await matchResponse.json();

        if (matchData.result && matchData.result.length > 0) {
          matchedProductId = matchData.result[0].id;
          console.log("Found product for barcode " + item.barcode + ": " + matchData.result[0].name + " (ID: " + matchedProductId + ")");

          itemsToCreate.push({
            number: item.barcode,
            product_id: matchedProductId,
            counted_qty: item.quantity,
            sheet_id: counting_sheet_id
          });
        } else {
          console.log("No product found for barcode " + item.barcode + " - skipping");
        }
      }

      if (itemsToCreate.length === 0) {
        return res.status(400).json({
          success: false,
          message: "No valid products found. Please ensure barcodes match existing products."
        });
      }

      console.log("Creating " + itemsToCreate.length + " counting sheet lines...");

      // Create counting sheet lines ONE BY ONE
      const createdLineIds = [];
      const failedItems = [];

      for (const lineData of itemsToCreate) {
        console.log("Creating line:", JSON.stringify(lineData, null, 2));

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
          failedItems.push(lineData.number);
          continue;
        }

        if (lineResult.error) {
          console.error("Error creating line:", lineResult.error);
          failedItems.push(lineData.number);
        } else {
          createdLineIds.push(lineResult.result);
          console.log("Created line with ID: " + lineResult.result);
        }
      }

      console.log("Successfully created " + createdLineIds.length + " lines, failed: " + failedItems.length);

      if (createdLineIds.length === 0) {
        return res.status(400).json({
          success: false,
          message: "Failed to create any counting lines",
          failed_items: failedItems
        });
      }

      // Update counting sheet state if max items reached (50)
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
          console.log("Sheet confirmed successfully!");
        } else {
          console.warn("Failed to update sheet state:", updateData.error);
        }
      }

      return res.json({
        success: true,
        message: createdLineIds.length + " items submitted successfully",
        submitted_count: createdLineIds.length,
        failed_items: failedItems
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