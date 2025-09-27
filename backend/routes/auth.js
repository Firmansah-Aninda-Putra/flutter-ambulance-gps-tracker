const express = require('express');
const router = express.Router();
const db = require('../database');
const bcrypt = require('bcrypt');

// Salt rounds for password hashing
const SALT_ROUNDS = 10;

// Daftar username admin yang disimpan di DB.
// Jika berubah, sesuaikan juga seed di schema.sql
const ADMIN_USERNAMES = ['ppidkotamadiun', 'ambulankotamadiun'];

/**
 * Validasi password sederhana: minimal 4 karakter
 */
function validatePasswordStrength(password) {
  const minLength = 4;
  if (password.length < minLength) {
    return `Password must be at least ${minLength} characters long.`;
  }
  return null;
}

// POST /api/auth/register
router.post('/register', async (req, res) => {
  const { username, password, fullName, address, phone } = req.body;
  if (!username || !password || !fullName || !address || !phone) {
    return res.status(400).json({ error: 'All fields are required' });
  }
  // Cegah registrasi dengan username admin
  if (ADMIN_USERNAMES.includes(username)) {
    return res.status(400).json({ error: 'Username not available' });
  }

  const pwdError = validatePasswordStrength(password);
  if (pwdError) {
    return res.status(400).json({ error: pwdError });
  }

  try {
    const [rows] = await db.query(
      'SELECT id FROM users WHERE username = ? LIMIT 1',
      [username]
    );
    if (rows.length > 0) {
      return res.status(400).json({ error: 'Username already exists' });
    }

    const hashedPassword = await bcrypt.hash(password, SALT_ROUNDS);
    const [result] = await db.query(
      'INSERT INTO users (username, password, fullName, address, phone, isAdmin) VALUES (?, ?, ?, ?, ?, 0)',
      [username, hashedPassword, fullName, address, phone]
    );

    res.json({ id: result.insertId, username });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password are required' });
  }

  try {
    const [rows] = await db.query(
      'SELECT id, username, password, isAdmin FROM users WHERE username = ? LIMIT 1',
      [username]
    );
    if (rows.length === 0) {
      return res.status(400).json({ error: 'User not found' });
    }

    const user = rows[0];
    const storedPassword = user.password || '';

    let passwordMatch = false;
    if (storedPassword.startsWith('$2b$') || storedPassword.startsWith('$2a$')) {
      passwordMatch = await bcrypt.compare(password, storedPassword);
    } else if (password === storedPassword) {
      passwordMatch = true;
      // Upgrade legacy plain-text to bcrypt
      try {
        const newHash = await bcrypt.hash(password, SALT_ROUNDS);
        await db.query('UPDATE users SET password = ? WHERE id = ?', [newHash, user.id]);
      } catch (e) {
        console.error('Error upgrading legacy password hash:', e);
      }
    }

    if (!passwordMatch) {
      return res.status(401).json({ error: 'Incorrect password' });
    }

    res.json({ id: user.id, username: user.username, isAdmin: user.isAdmin === 1 });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// GET /api/auth/user/:id
router.get('/user/:id', async (req, res) => {
  const userId = parseInt(req.params.id, 10);
  if (isNaN(userId) || userId < 1) {
    return res.status(400).json({ error: 'Invalid user ID' });
  }
  try {
    const [rows] = await db.query(
      'SELECT id, username, fullName, address, phone, isAdmin, createdAt FROM users WHERE id = ? LIMIT 1',
      [userId]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }
    const u = rows[0];
    res.json({
      id: u.id,
      username: u.username,
      fullName: u.fullName,
      address: u.address,
      phone: u.phone,
      isAdmin: u.isAdmin === 1,
      createdAt: u.createdAt
    });
  } catch (error) {
    console.error('Get user profile error:', error);
    res.status(500).json({ error: 'Failed to get user profile' });
  }
});

// GET /api/auth/admin
// Mengembalikan array semua admin yang ada di ADMIN_USERNAMES
router.get('/admin', async (req, res) => {
  try {
    const placeholders = ADMIN_USERNAMES.map(() => '?').join(',');
    const [rows] = await db.query(
      `SELECT id, username FROM users WHERE username IN (${placeholders})`,
      ADMIN_USERNAMES
    );
    res.json(rows); // [{id, username}, …]
  } catch (error) {
    console.error('Get admin error:', error);
    res.status(500).json({ error: 'Failed to get admin info' });
  }
});

module.exports = router;