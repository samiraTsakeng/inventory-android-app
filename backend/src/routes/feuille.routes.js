const express = require("express");
const router = express.Router();
const FeuilleController = require("../controllers/feuilleController");

// GET /feuilles/:id
router.get("/:id", FeuilleController.getFeuilles);

module.exports = router;