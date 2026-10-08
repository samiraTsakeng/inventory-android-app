const express = require('express');
const router = express.Router();
const CountingController = require('../controllers/countingController');
const sessionMiddleware = require("../middleware/sessionMiddleware");

// POST /counting/lookup-product
router.post('/lookup-product', sessionMiddleware, CountingController.lookupProduct);

// POST /counting/lookup-products-batch
router.post('/lookup-products-batch', sessionMiddleware, CountingController.lookupProductsBatch);

// POST /counting/submit-scans
router.post('/submit-scans', sessionMiddleware, CountingController.submitScans);

// GET /counting/sheet-state/:sheet_id
router.get('/sheet-state/:sheet_id', sessionMiddleware, CountingController.getSheetState);

// POST /counting/start-sheet
router.post('/start-sheet', sessionMiddleware, CountingController.startSheet);

// POST /counting/validate-sheet
router.post('/validate-sheet', sessionMiddleware, CountingController.validateSheet);

// GET /counting/check-sheet/:sheet_id
router.get('/check-sheet/:sheet_id', sessionMiddleware, CountingController.checkSheetLines);

// GET /counting/check-sheet-state/:sheet_id
router.get('/check-sheet-state/:sheet_id', sessionMiddleware, CountingController.checkSheetState);

// POST /counting/cache-products
router.post('/cache-products', sessionMiddleware, CountingController.cacheProducts);

// POST /counting/cache-products-by-barcode
router.post('/cache-products-by-barcode', sessionMiddleware, CountingController.cacheProductsByBarcode);

// ✅ Check if a barcode was already submitted to the ERP for this sheet
router.post('/check-erp-scan', sessionMiddleware, CountingController.checkAlreadyInErp);

module.exports = router;