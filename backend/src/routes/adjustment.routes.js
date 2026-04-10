const express = require("express");
const router = express.Router();
const adjustmentController = require("../controllers/adjustment.controller");

router.get("/", adjustmentController.getAdjustments);

module.exports = router;