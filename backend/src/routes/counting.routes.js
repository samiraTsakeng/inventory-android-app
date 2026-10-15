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
// GET /counting/live-items/:sheet_id
router.get('/live-items/:sheet_id', CountingController.getLiveItems);
// POST /counting/live-scan
router.post('/live-scan', CountingController.pushLiveScan);
// POST /counting/live-items/:sheet_id/clear
router.post('/live-items/:sheet_id/clear', CountingController.clearLiveItems);
//remove an item from the shared session
router.post('/live-items/:sheet_id/remove', CountingController.removeLiveItem);

// POST /counting/check-erp-scan — is this barcode already on the sheet in the ERP?
router.post('/check-erp-scan', CountingController.checkAlreadyInErp);
// POST /counting/check-erp-scans — same check for a list of barcodes
router.post('/check-erp-scans', CountingController.checkAlreadyInErpBatch);

// ✅ Offline mode
// GET /counting/sheet-lots/:sheet_id — numbers to keep on the phone
router.get('/sheet-lots/:sheet_id', CountingController.getSheetLots);
// POST /counting/lookup-products — resolve numbers scanned offline
router.post('/lookup-products', CountingController.lookupProducts);
module.exports = router;
