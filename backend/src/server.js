require('dotenv').config();
const express = require('express');
const cors = require('cors');

process.on('uncaughtException', (err) => {
  console.error('💥 UNCAUGHT EXCEPTION:', err.message);
  console.error(err.stack);
});

process.on('unhandledRejection', (reason) => {
  console.error('💥 UNHANDLED REJECTION:', reason);
});

const app = express();
app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.json({ message: 'Server is alive' });
});

console.log('Loading routes...');

try {
  app.use('/auth', require('./routes/authRoutes'));
  console.log('✅ authRoutes loaded');
} catch(e) {
  console.error('❌ authRoutes failed:', e.message);
}

try {
  app.use('/adjustments', require('./routes/adjustment.routes'));
  console.log('✅ adjustment.routes loaded');
} catch(e) {
  console.error('❌ adjustment.routes failed:', e.message);
}

try {
  app.use('/feuilles',    require('./routes/feuille.routes'));
  console.log('✅ feuille.routes loaded');
} catch(e) {
  console.error('❌ feuille.routes failed:', e.message);
}

const PORT = process.env.PORT || 3001;
const server = app.listen(PORT, () => {
  console.log(`✅ Server running on port ${PORT}`);
  console.log('Server is ALIVE and waiting for requests...');
  console.log('Press Ctrl+C to stop.');
});

server.on('error', (err) => {
  console.error('💥 SERVER ERROR:', err.message);
});

server.on('close', () => {
  console.log('⚠️ Server closed');
});

// Keep process alive and log every 30 seconds
setInterval(() => {
  console.log(' ');
}, 30000);