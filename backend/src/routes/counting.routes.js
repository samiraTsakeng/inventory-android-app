const express = require('express');
const router = express.Router();
const CountingController = require('../controllers/countingController');

// POST /counting/lookup-product
router.post('/lookup-product', CountingController.lookupProduct);

// POST /counting/submit-scans
router.post('/submit-scans', CountingController.submitScans);

// GET /counting/sheet-state/:sheet_id
router.get('/sheet-state/:sheet_id', CountingController.getSheetState);

// POST /counting/start-sheet
router.post('/start-sheet', CountingController.startSheet);

// POST /counting/validate-sheet
router.post('/validate-sheet', CountingController.validateSheet);

// GET /counting/check-sheet/:sheet_id
router.get('/check-sheet/:sheet_id', CountingController.checkSheetLines);

// GET /counting/check-sheet-state/:sheet_id
router.get('/check-sheet-state/:sheet_id', CountingController.checkSheetState);

// POST /counting/cache-products
router.post('/cache-products', CountingController.cacheProducts);

// POST /counting/cache-products-by-barcode
router.post('/cache-products-by-barcode', CountingController.cacheProductsByBarcode);

// ✅ Shared scanning session (two team members, same sheet, different phones)
router.get('/live-items/:sheet_id', CountingController.getLiveItems);
router.post('/live-scan', CountingController.pushLiveScan);
router.post('/live-items/:sheet_id/clear', CountingController.clearLiveItems);

// ✅ Check if a barcode was already submitted to the ERP for this sheet
router.post('/check-erp-scan', CountingController.checkAlreadyInErp);

module.exports = router;