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

// GET /counting/check-sheet/:sheet_id
router.get('/check-sheet/:sheet_id', CountingController.checkSheetLines);

// GET /counting/check-sheet-state/:sheet_id
router.get('/check-sheet-state/:sheet_id', CountingController.checkSheetState);

router.post('/validate-sheet', CountingController.validateSheet);
module.exports = router;