const express = require("express");
const router = express.Router();
const FeuilleController = require("../controllers/feuilleController");
const sessionMiddleware = require("../middleware/sessionMiddleware");

// GET /feuilles/:id
router.get("/:id", sessionMiddleware, FeuilleController.getFeuilles);

module.exports = router;