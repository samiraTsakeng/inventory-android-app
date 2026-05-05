const OdooService = require("../services/odooServices");

// Session stored as module-level variable
let sessionData = null;

class AuthController {
  static getSession() {
    return sessionData;
  }

  static async login(req, res) {
    try {
      const { host, db, email, password } = req.body;

      console.log("login attempt for:", { host, db, email });

      if (!host || !email || !password) {
        return res.status(400).json({
          success: false,
          message: "host, email and password are required"
        });
      }

      let dbName = db;

      // If no database specified, try to detect
      if (!dbName || dbName === '') {
        // First, try to get list of databases
        try {
          const dbListResponse = await fetch(`${host}/web/database/list`);
          const dbListData = await dbListResponse.json();

          if (dbListData.result && dbListData.result.length > 0) {
            // Try each database to find one that works
            for (const testDb of dbListData.result) {
              try {
                const testResult = await OdooService.authenticate(host, testDb, email, password);
                if (testResult && testResult.uid) {
                  dbName = testDb;
                  console.log("Found working database:", dbName);
                  break;
                }
              } catch (e) {
                continue;
              }
            }
          }
        } catch (e) {
          console.log("Could not fetch database list:", e.message);
        }

        // If still no database, try common names
        if (!dbName) {
          const commonDbs = ['odoo_db', 'odoo', 'postgres', 'default'];
          for (const testDb of commonDbs) {
            try {
              const testResult = await OdooService.authenticate(host, testDb, email, password);
              if (testResult && testResult.uid) {
                dbName = testDb;
                console.log("Found working database from common list:", dbName);
                break;
              }
            } catch (e) {
              continue;
            }
          }
        }
      }

      if (!dbName) {
        throw new Error("No valid database found. Please check your connection or specify a database name.");
      }

      const result = await OdooService.authenticate(host, dbName, email, password);

      sessionData = { host, db: dbName, email, uid: result.uid };

      return res.json({
        success: true,
        uid: result.uid,
        name: result.name
      });

    } catch (error) {
      console.error("LOGIN ERROR:", error.message);
      return res.status(401).json({
        success: false,
        message: error.message
      });
    }
  }
}

module.exports = AuthController;