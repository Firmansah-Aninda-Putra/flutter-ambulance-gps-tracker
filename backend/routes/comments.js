// backend/routes/comments.js
const express = require('express');
const router = express.Router();
const db = require('../database');

/**
 * GET /api/comments
 * Optional query params:
 *   ambulanceId (filter komentar per ambulans),
 *   page (nomor halaman, default 1),
 *   limit (jumlah item per halaman, default 20)
 */
router.get('/', async (req, res) => {
  try {
    const ambulanceId = req.query.ambulanceId;
    const page       = parseInt(req.query.page, 10)  || 1;
    const limit      = parseInt(req.query.limit, 10) || 20;
    const offset     = (page - 1) * limit;

    // Bangun klausa WHERE jika ambulanceId diberikan
    let whereClause = '';
    const params = [];
    if (ambulanceId) {
      whereClause = 'WHERE c.ambulance_id = ?';
      params.push(ambulanceId);
    }

    // Hitung total untuk pagination
    const [countRows] = await db.query(
      `SELECT COUNT(*) AS total
       FROM comments c
       ${whereClause}`,
      params
    );
    const total = countRows[0].total;

    // Ambil halaman data
    const [rows] = await db.query(
      `
      SELECT
        c.id,
        c.userId,
        c.ambulance_id       AS ambulanceId,
        c.content,
        c.image_url          AS imageUrl,
        c.emoticon_code      AS emoticonCode,
        c.parentId,
        c.createdAt,
        u.username,
        u.isAdmin
      FROM comments c
      JOIN users u ON c.userId = u.id
      ${whereClause}
      ORDER BY c.createdAt DESC
      LIMIT ? OFFSET ?
      `,
      params.concat([limit, offset])
    );

    res.json({
      page,
      limit,
      total,
      comments: rows
    });
  } catch (error) {
    console.error('Fetch comments error:', error);
    res.status(500).json({ error: 'Failed to fetch comments' });
  }
});

/**
 * POST /api/comments
 * Body payload must include: userId, ambulanceId
 * Optional: content, parentId, imageUrl, emoticonCode
 * Setelah insert komentar, emit event real-time 'newComment'
 */
router.post('/', async (req, res) => {
  const { userId, content, parentId, ambulanceId, imageUrl, emoticonCode } = req.body;

  // Hanya validasi userId dan ambulanceId, content boleh kosong
  if (!userId || !ambulanceId) {
    return res.status(400).json({ error: 'userId and ambulanceId are required' });
  }

  // Validasi bahwa setidaknya ada satu konten (teks, gambar, atau emoticon)
  const hasContent   = content     && content.trim().length > 0;
  const hasImage     = imageUrl    && imageUrl.trim().length   > 0;
  const hasEmoticon  = emoticonCode&& emoticonCode.trim().length> 0;
  
  if (!hasContent && !hasImage && !hasEmoticon) {
    return res.status(400).json({ error: 'At least one content type (text, image, or emoticon) is required' });
  }

  try {
    // Insert komentar baru - parentId disimpan jika ada
    const [result] = await db.query(
      `
      INSERT INTO comments
        (userId, ambulance_id, content, image_url, emoticon_code, parentId, createdAt)
      VALUES
        (?,       ?,             ?,       ?,          ?,             ?,        NOW())
      `,
      [
        userId,
        ambulanceId,
        hasContent   ? content.trim()     : null,
        hasImage     ? imageUrl.trim()    : null,
        hasEmoticon  ? emoticonCode.trim(): null,
        parentId     || null
      ]
    );
    const insertedId = result.insertId;

    // Ambil data komentar yang baru saja disimpan, termasuk username dan isAdmin
    const [rows] = await db.query(
      `
      SELECT
        c.id,
        c.userId,
        c.ambulance_id       AS ambulanceId,
        c.content,
        c.image_url          AS imageUrl,
        c.emoticon_code      AS emoticonCode,
        c.parentId,
        c.createdAt,
        u.username,
        u.isAdmin
      FROM comments c
      JOIN users u ON c.userId = u.id
      WHERE c.id = ?
      LIMIT 1
      `,
      [insertedId]
    );

    if (rows.length === 0) {
      res.json({ success: true });
      return;
    }
    const newComment = rows[0];

    // Emit real-time ke client melalui Socket.IO
    const io = req.app.get('io');
    if (io) {
      io.emit('newComment', newComment);
    }

    res.json({ success: true, comment: newComment });
  } catch (error) {
    console.error('Post comment error:', error);
    res.status(500).json({ error: 'Failed to post comment' });
  }
});

/**
 * DELETE /api/comments/:id
 * Cancel (hapus) komentar yang sudah dikirim
 */
router.delete('/:id', async (req, res) => {
  const commentId = req.params.id;
  try {
    await db.query('DELETE FROM comments WHERE id = ?', [commentId]);
    res.json({ success: true });
  } catch (error) {
    console.error('Delete comment error:', error);
    res.status(500).json({ error: 'Failed to delete comment' });
  }
});

module.exports = router;
