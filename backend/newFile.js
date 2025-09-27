const cors = require('cors');
const { app } = require('.');

// CORS configuration untuk akses dari perangkat fisik
app.use(cors({
  origin: ['http://localhost:3000', 'http://10.101.14.222:3000', 'http://192.168.0.107:3000', '*'],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
