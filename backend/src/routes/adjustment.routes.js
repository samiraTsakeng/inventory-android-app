
const express = require("express");
const router = express.Router();

const AdjustmentController = require("../controllers/adjustment.controller");
const sessionMiddleware = require("../middleware/sessionMiddleware");

// GET /adjustments
router.get("/", sessionMiddleware, AdjustmentController.getAdjustments);

module.exports = router;