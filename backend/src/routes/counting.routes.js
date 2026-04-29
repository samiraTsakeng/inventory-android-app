const express = require('express');
const router = express.Router();
const CountingController = require('../controllers/countingController');

// POST /counting/lookup-product
router.post('/lookup-product', CountingController.lookupProduct);

// POST /counting/submit-scans
router.post('/submit-scans', CountingController.submitScans);

module.exports = router;