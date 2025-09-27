// backend/routes/upload.js

const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Pastikan folder 'uploads' ada; jika belum, buat secara otomatis
const uploadDir = path.join(__dirname, '..', 'uploads');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// Konfigurasi penyimpanan Multer: simpan di folder 'uploads'
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    // Buat nama unik: timestamp + random + ekstensi asli
    const timestamp = Date.now();
    const random = Math.round(Math.random() * 1e9);
    const ext = path.extname(file.originalname) || '';
    // e.g. 1617981379123-123456789.jpg
    const filename = `${timestamp}-${random}${ext}`;
    cb(null, filename);
  },
});

// Filter file: izinkan gambar (jpg, jpeg, png, gif, webp) dan video (mp4, mov, heic)
function fileFilter(req, file, cb) {
  const allowedMimeTypes = [
    'image/jpeg',        // JPG, JPEG
    'image/png',         // PNG
    'image/gif',         // GIF
    'image/webp',        // WEBP
    'video/mp4',         // MP4
    'image/heic',        // HEIC (iPhone)
    'video/quicktime'    // MOV (iPhone)
  ];
  if (allowedMimeTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Invalid file type. Only JPG, JPEG, PNG, GIF, WEBP, MP4, HEIC, and MOV are allowed.'), false);
  }
}

const upload = multer({
  storage,
  fileFilter,
  limits: {
    fileSize: 5 * 1024 * 1024, // maksimal 5 MB per file; sesuaikan bila perlu
  },
});

/**
 * POST /api/upload
 * Endpoint untuk upload satu file (field name: 'file').
 * Mengembalikan JSON { imageUrl: '<URL akses file>' }.
 *
 * Pastikan:
 * - Variabel environment SERVER_BASE_URL telah diatur, misalnya di .env:
 *     SERVER_BASE_URL=http://<domain-atau-ip-backend>:<port>
 * - Di index.js: app.use('/uploads', express.static('uploads'));
 * - Di index.js mendaftarkan route:
 *     const uploadRoutes = require('./routes/upload');
 *     app.use('/api/upload', uploadRoutes);
 */
router.post('/', upload.single('file'), (req, res) => {
  // Jika multer mengalami error (fileFilter atau size), 
  // middleware multer otomatis men-trigger error handler; di sini asumsikan file sudah valid.
  if (!req.file) {
    return res.status(400).json({ error: 'No file uploaded' });
  }

  // Dapatkan nama file yang disimpan
  const filename = req.file.filename;

  // Bangun URL akses file:
  // Pastikan SERVER_BASE_URL di .env mencakup protokol dan host:port, misal 'http://localhost:3000'
  const baseUrl = process.env.SERVER_BASE_URL || ''; 
  // Jika SERVER_BASE_URL di-set ke 'http://localhost:3000', dan kita serve static di '/uploads',
  // maka URL akan: 'http://localhost:3000/uploads/<filename>'
  const imageUrl = `${baseUrl}/uploads/${filename}`;

  res.json({ imageUrl });
});

// Opsional: error handling khusus untuk multer
router.use((err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    // Kesalahan dari multer, misalnya ukuran file terlalu besar
    return res.status(400).json({ error: err.message });
  } else if (err) {
    // Kesalahan lain, misalnya fileFilter menolak format
    console.error('Upload error:', err);
    return res.status(400).json({ error: err.message });
  }
  next();
});

module.exports = router;