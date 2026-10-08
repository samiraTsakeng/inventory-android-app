const AuthController = require("../controllers/authController");
const RequestSessionContext = require("../services/requestSessionContext");

function sessionMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({
      success: false,
      message: "No authentication token provided. Please login first."
    });
  }

  const token = authHeader.substring(7).trim();
  const session = AuthController.getSessionByToken(token);

  if (!session) {
    return res.status(401).json({
      success: false,
      message: "Invalid or expired session. Please login again."
    });
  }

  req.session = session;

  // Keep this user's Odoo session isolated to this request.
  RequestSessionContext.run(session, () => next());
}

module.exports = sessionMiddleware;