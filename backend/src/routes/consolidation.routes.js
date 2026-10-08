const express = require('express');
const router = express.Router();
const ConsolidationController = require('../controllers/consolidationController');


const sessionMiddleware = require("../middleware/sessionMiddleware");
// GET /consolidation/sheets/:adjustment_id
router.get('/sheets/:adjustment_id', sessionMiddleware, ConsolidationController.getConsolidationSheets);

// GET /consolidation/sheet/:sheet_id
router.get('/sheet/:sheet_id', sessionMiddleware, ConsolidationController.getConsolidationSheetDetail);

// POST /consolidation/update-contradictory-line
router.post('/update-contradictory-line', sessionMiddleware, ConsolidationController.updateContradictoryLine);

// POST /consolidation/validate-sheet
router.post('/validate-sheet', sessionMiddleware, ConsolidationController.validateConsolidationSheet);

router.get('/zones/:adjustment_id', sessionMiddleware, ConsolidationController.getConsolidationZones);

router.post('/create', sessionMiddleware, ConsolidationController.createConsolidationSheet);

router.post('/apply', sessionMiddleware, ConsolidationController.applyConsolidation);

router.get('/adjustment-status/:adjustment_id', sessionMiddleware, ConsolidationController.getAdjustmentStatus);

module.exports = router;