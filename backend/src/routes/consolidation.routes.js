const express = require('express');
const router = express.Router();
const ConsolidationController = require('../controllers/consolidationController');

// GET /consolidation/sheets/:adjustment_id
router.get('/sheets/:adjustment_id', ConsolidationController.getConsolidationSheets);

// GET /consolidation/sheet/:sheet_id
router.get('/sheet/:sheet_id', ConsolidationController.getConsolidationSheetDetail);

// POST /consolidation/update-contradictory-line
router.post('/update-contradictory-line', ConsolidationController.updateContradictoryLine);

// POST /consolidation/validate-sheet
router.post('/validate-sheet', ConsolidationController.validateConsolidationSheet);

router.get('/zones/:adjustment_id', ConsolidationController.getConsolidationZones);

router.post('/create', ConsolidationController.createConsolidationSheet);

router.post('/apply', ConsolidationController.applyConsolidation);

router.get('/adjustment-status/:adjustment_id', ConsolidationController.getAdjustmentStatus);

module.exports = router;