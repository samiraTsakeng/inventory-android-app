const express = require("express");
const app = express();
const authRoutes =  require("./routes/authRoutes");
const adjustmentRoutes = require("./routes/adjustment.routes");
const cors = require("cors");

app.use(cors());
app.use(express.json());
app.use('/auth', authRoutes);
app.use("/adjustments", adjustmentRoutes);

app.listen(3000, () => {
  console.log("Server running on port 3000");
});