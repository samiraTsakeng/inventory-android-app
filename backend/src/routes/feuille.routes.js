const express = require("express");
const router = express.Router();
const FeuilleController = require("../controllers/feuilleController");

router.get("/feuilles", FeuilleController.getFeuilles);

module.exports = router;