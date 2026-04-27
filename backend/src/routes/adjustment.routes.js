const express = require('express');
const router = express.Router();
const AdjustmentController = require('../controllers/adjustment.controller');

// GET /adjustments
router.get('/', AdjustmentController.getAdjustments);

module.exports = router;