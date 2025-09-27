// backend/cron.js
const cron = require('node-cron');
const db = require('./database');

// Jadwalkan eksekusi setiap hari pukul 00:00 (waktu server lokal)
cron.schedule('0 0 * * *', async () => {
  console.log(`[${new Date().toISOString()}] Cron: Menghapus semua komentar.`);
  try {
    await db.query('DELETE FROM comments');
    console.log(`[${new Date().toISOString()}] Cron: Semua komentar berhasil dihapus.`);
  } catch (err) {
    console.error(`[${new Date().toISOString()}] Cron: Gagal menghapus komentar:`, err);
  }
});

// Pesan ini akan muncul sekali saat cron.js dimuat
console.log('Cron scheduler dijalankan: penghapusan komentar otomatis setiap pukul 00:00.');
