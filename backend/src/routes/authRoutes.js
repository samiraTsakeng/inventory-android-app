const express = require("express");
const router = express.Router();
const AuthController = require("../controllers/authController");

// LOGIN ROUTE
router.post("/login", AuthController.login);

module.exports = router;