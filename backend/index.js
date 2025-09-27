// index.js
const express = require('express');
const cors = require('cors');
require('dotenv').config();    // ← Memuat variabel dari .env
require('./cron');             // ← Menjalankan scheduler

const path = require('path');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const authRoutes = require('./routes/auth');
const commentsRoutes = require('./routes/comments');
const ambulanceRoutes = require('./routes/ambulance');
const chatRoutes = require('./routes/chat');
const uploadRoutes = require('./routes/upload');

// Baca konfigurasi origin dari .env
// ALLOWED_ORIGINS di .env: e.g. "http://localhost:3000,http://192.168.0.107:3000"
const allowedOriginsEnv = process.env.ALLOWED_ORIGINS || '';
const allowedOrigins = allowedOriginsEnv
  .split(',')
  .map(s => s.trim())
  .filter(s => s && s !== '*'); // jika ada '*' di env, bisa diabaikan atau ditangani tersendiri

// Middleware CORS
app.use(cors({
  origin: allowedOrigins.length > 0 ? allowedOrigins : '*',
  credentials: true,
  methods: ['GET','POST','PUT','DELETE','OPTIONS'],
  allowedHeaders: ['Content-Type','Authorization']
}));

// Jika anda sempat menggunakan wildcard '*' bersama credentials,
// perlu diperhatikan bahwa browser tidak mengizinkan wildcard dengan credentials:
// jika ingin allow credentials, ALLOWED_ORIGINS harus diisi daftar origin secara eksplisit.

// Body parser
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// ✅ PERBAIKAN: Global tracking state untuk ambulance dengan class untuk state management
class AmbulanceTrackingState {
  constructor() {
    this.isActive = true; // Default tracking aktif
    this.lastToggleTime = Date.now();
  }

  toggle(enabled) {
    this.isActive = enabled === true;
    this.lastToggleTime = Date.now();
    console.log(`🚨 Ambulance tracking ${this.isActive ? 'ENABLED' : 'DISABLED'} at ${new Date().toISOString()}`);
    return this.isActive;
  }

  getStatus() {
    return {
      trackingActive: this.isActive,
      lastToggleTime: this.lastToggleTime,
      timestamp: new Date().toISOString()
    };
  }

  isEnabled() {
    return this.isActive;
  }
}

const ambulanceTracking = new AmbulanceTrackingState();

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'Ambulance Tracker API is running',
    timestamp: new Date().toISOString(),
    ambulanceTrackingActive: ambulanceTracking.isEnabled(), // ✅ Gunakan state manager
    endpoints: {
      auth: '/api/auth',
      comments: '/api/comments',
      ambulance: '/api/ambulance',
      chat: '/api/chat',
      upload: '/api/upload'
    }
  });
});

// Daftarkan route sesuai struktur yang ada
app.use('/api/auth', authRoutes);
app.use('/api/comments', commentsRoutes);
app.use('/api/ambulance', ambulanceRoutes);
app.use('/api/chat', chatRoutes);
app.use('/api/upload', uploadRoutes);

// Static folder untuk file yang diupload
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Error handler umum
app.use((err, req, res, next) => {
  console.error('Error:', err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});
// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Baca konfigurasi server
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

// Buat HTTP server dan Socket.IO dengan konfigurasi CORS dinamis
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: allowedOrigins.length > 0 ? allowedOrigins : '*',
    methods: ['GET','POST']
  }
});

// Simpan instance io dan tracking state di app supaya bisa diakses dari route
app.set('io', io);
app.set('ambulanceTracking', ambulanceTracking); // ✅ Gunakan state manager

// ✅ PERBAIKAN: Endpoint untuk mengontrol tracking status dengan validasi
app.post('/api/ambulance/tracking/toggle', (req, res) => {
  const { enabled } = req.body;
  
  try {
    const trackingActive = ambulanceTracking.toggle(enabled);
    
    // Emit event ke semua client dengan status terbaru
    const statusData = ambulanceTracking.getStatus();
    
    if (trackingActive) {
      io.emit('ambulanceTrackingEnabled', statusData);
    } else {
      io.emit('ambulanceTrackingDisabled', statusData);
    }
    
    res.json({ 
      success: true, 
      ambulanceTrackingActive: trackingActive,
      message: `Tracking ${trackingActive ? 'enabled' : 'disabled'}`,
      ...statusData
    });
  } catch (error) {
    console.error('Toggle tracking error:', error);
    res.status(500).json({
      error: 'Failed to toggle tracking',
      ambulanceTrackingActive: ambulanceTracking.isEnabled()
    });
  }
});

// ✅ PERBAIKAN: Endpoint untuk mendapatkan status tracking dengan info detail
app.get('/api/ambulance/tracking/status', (req, res) => {
  try {
    const statusData = ambulanceTracking.getStatus();
    res.json({
      ambulanceTrackingActive: statusData.trackingActive,
      ...statusData
    });
  } catch (error) {
    console.error('Get tracking status error:', error);
    res.status(500).json({
      error: 'Failed to get tracking status',
      ambulanceTrackingActive: false
    });
  }
});

// Socket.IO connection handler
io.on('connection', socket => {
  console.log('🔌 Socket connected:', socket.id);

  // ✅ PERBAIKAN: Kirim status tracking saat client connect
  try {
    const statusData = ambulanceTracking.getStatus();
    socket.emit('trackingStatus', statusData);
  } catch (error) {
    console.error('Error sending tracking status to new client:', error);
  }

  // User akan emit 'join' dengan userId untuk bergabung ke room-nya
  socket.on('join', userId => {
    socket.join(userId);
    console.log(`➡️ Socket ${socket.id} joined room ${userId}`);
  });

  // ✅ PERBAIKAN: Handler untuk admin mengontrol tracking dengan error handling
  socket.on('toggleAmbulanceTracking', (data) => {
    try {
      const { enabled } = data;
      const trackingActive = ambulanceTracking.toggle(enabled);
      
      console.log(`🚨 Socket: Ambulance tracking ${trackingActive ? 'ENABLED' : 'DISABLED'}`);
      
      // Broadcast ke semua client
      const statusData = ambulanceTracking.getStatus();
      
      if (trackingActive) {
        io.emit('ambulanceTrackingEnabled', statusData);
      } else {
        io.emit('ambulanceTrackingDisabled', statusData);
      }
      
      // Confirm ke sender
      socket.emit('trackingToggleConfirm', {
        success: true,
        trackingActive: trackingActive,
        ...statusData
      });
    } catch (error) {
      console.error('Socket toggle tracking error:', error);
      socket.emit('trackingToggleConfirm', {
        success: false,
        error: 'Failed to toggle tracking',
        trackingActive: ambulanceTracking.isEnabled()
      });
    }
  });

  socket.on('disconnect', () => {
    console.log('❌ Socket disconnected:', socket.id);
  });
});

// Jalankan server
server.listen(PORT, HOST, () => {
  // Cetak berdasarkan SERVER_BASE_URL agar tahu alamat akses device
  const serverBaseUrl = process.env.SERVER_BASE_URL || `http://${HOST}:${PORT}`;
  console.log(`🚀 Server running on http://${HOST}:${PORT}`);
  console.log(`🌐 SERVER_BASE_URL is set to: ${serverBaseUrl}`);
  console.log(`🚨 Ambulance tracking is ${ambulanceTracking.isEnabled() ? 'ENABLED' : 'DISABLED'}`);
  // Jika Anda ingin mencetak contoh akses:
  allowedOrigins.forEach(origin => {
    console.log(`✅ CORS allowed for origin: ${origin}`);
  });
});

// Tangani sinyal untuk shutdown graceful
process.on('SIGTERM', () => {
  console.log('SIGTERM received. Shutting down gracefully...');
  server.close(() => process.exit(0));
});
process.on('SIGINT', () => {
  console.log('SIGINT received. Shutting down gracefully...');
  server.close(() => process.exit(0));
});