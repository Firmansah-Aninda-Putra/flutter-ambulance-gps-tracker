// backend/routes/chat.js

const express = require('express');
const router = express.Router();
const db = require('../database'); // koneksi MySQL

router.get('/conversation/:userId', async (req, res) => {
  const userId = parseInt(req.params.userId, 10);
  if (isNaN(userId)) {
    return res.status(400).json({ error: 'Invalid userId' });
  }

  try {
    const query = `
      SELECT
        c.partnerId,
        u.fullName      AS partnerName,
        c.lastContent    AS content,
        c.lastImageUrl   AS imageUrl,
        c.lastLat        AS latitude,
        c.lastLng        AS longitude,
        c.lastEmoticon   AS emoticonCode,
        c.lastTimestamp  AS lastTimestamp
      FROM (
        SELECT
          CASE
            WHEN senderId = ? THEN receiverId
            ELSE senderId
          END AS partnerId,
          content       AS lastContent,
          imageUrl      AS lastImageUrl,
          latitude      AS lastLat,
          longitude     AS lastLng,
          emoticon_code AS lastEmoticon,
          createdAt     AS lastTimestamp
        FROM messages
        WHERE senderId = ? OR receiverId = ?
      ) AS c
      JOIN (
        SELECT
          CASE
            WHEN senderId = ? THEN receiverId
            ELSE senderId
          END AS partnerId,
          MAX(createdAt) AS maxTs
        FROM messages
        WHERE senderId = ? OR receiverId = ?
        GROUP BY partnerId
      ) AS g
        ON c.partnerId = g.partnerId
       AND c.lastTimestamp = g.maxTs
      JOIN users u
        ON u.id = c.partnerId
      ORDER BY c.lastTimestamp DESC
    `;
    const params = [userId, userId, userId, userId, userId, userId];
    const [rows] = await db.query(query, params);

    const conversations = rows.map(r => ({
      partnerId: r.partnerId,
      partnerName: r.partnerName,
      lastMessage: {
        content: r.content,
        imageUrl: r.imageUrl,
        latitude: r.latitude,
        longitude: r.longitude,
        emoticonCode: r.emoticonCode
      },
      lastTimestamp: r.lastTimestamp
    }));

    res.json(conversations);
  } catch (error) {
    console.error('Fetch conversations error:', error);
    res.status(500).json({ error: 'Failed to fetch conversations' });
  }
});

router.get('/:userId/:targetId', async (req, res) => {
  const userId = parseInt(req.params.userId, 10);
  const targetId = parseInt(req.params.targetId, 10);
  if (isNaN(userId) || isNaN(targetId)) {
    return res.status(400).json({ error: 'Invalid user IDs' });
  }
  try {
    const [rows] = await db.query(
      `SELECT
         m.id,
         m.senderId     AS senderId,
         m.receiverId   AS receiverId,
         m.content,
         m.imageUrl     AS imageUrl,
         m.latitude,
         m.longitude,
         m.emoticon_code AS emoticonCode,
         m.createdAt    AS createdAt,
         CASE WHEN m.senderId = ? THEN 'outgoing' ELSE 'incoming' END AS direction
       FROM messages m
       WHERE (m.senderId = ? AND m.receiverId = ?)
          OR (m.senderId = ? AND m.receiverId = ?)
       ORDER BY m.createdAt ASC`,
      [userId, userId, targetId, targetId, userId]
    );
    res.json(rows);
  } catch (err) {
    console.error('Fetch chat error:', err);
    res.status(500).json({ error: 'Failed to fetch chat' });
  }
});

router.post('/', async (req, res) => {
  const {
    senderId,
    receiverId,
    content,
    imageUrl,
    latitude,
    longitude,
    emoticonCode
  } = req.body;

  const sid = parseInt(senderId, 10);
  const rid = parseInt(receiverId, 10);
  if (isNaN(sid) || isNaN(rid)) {
    return res.status(400).json({ error: 'Invalid senderId or receiverId' });
  }

  const hasText = typeof content === 'string' && content.trim() !== '';
  const hasImage = typeof imageUrl === 'string' && imageUrl.trim() !== '';
  const hasLocation = latitude != null && longitude != null;
  const hasEmoticon = typeof emoticonCode === 'string' && emoticonCode.trim() !== '';

  if (!hasText && !hasImage && !hasLocation && !hasEmoticon) {
    return res.status(400).json({
      error: 'At least one of content, imageUrl, latitude+longitude, or emoticonCode must be provided'
    });
  }

  try {
    const [result] = await db.query(
      `INSERT INTO messages
         (senderId, receiverId, content, imageUrl, latitude, longitude, emoticon_code)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        sid,
        rid,
        hasText     ? content.trim()      : null,
        hasImage    ? imageUrl.trim()     : null,
        hasLocation ? latitude            : null,
        hasLocation ? longitude           : null,
        hasEmoticon ? emoticonCode.trim() : null
      ]
    );

    const [rows] = await db.query(
      `SELECT
         id,
         senderId     AS senderId,
         receiverId   AS receiverId,
         content,
         imageUrl     AS imageUrl,
         latitude,
         longitude,
         emoticon_code AS emoticonCode,
         createdAt    AS createdAt
       FROM messages
       WHERE id = ?`,
      [result.insertId]
    );
    const newMsg = rows[0];

    const io = req.app.get('io');
    if (io) {
      io.to(String(rid)).emit('newMessage', newMsg);
      io.to(String(sid)).emit('newMessage', newMsg);
    }

    res.json({ success: true, message: newMsg });
  } catch (err) {
    console.error('Post chat error:', err);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

router.delete('/:id', async (req, res) => {
  const messageId = req.params.id;
  try {
    await db.query('DELETE FROM messages WHERE id = ?', [messageId]);
    const io = req.app.get('io');
    if (io) {
      io.emit('messageDeleted', { id: messageId });
    }
    res.json({ success: true });
  } catch (error) {
    console.error('Delete message error:', error);
    res.status(500).json({ error: 'Failed to delete message' });
  }
});

// ENDPOINT BARU: Clear all messages between two users
router.delete('/clear/:userId/:targetId', async (req, res) => {
  const userId = parseInt(req.params.userId, 10);
  const targetId = parseInt(req.params.targetId, 10);
  
  if (isNaN(userId) || isNaN(targetId)) {
    return res.status(400).json({ error: 'Invalid user IDs' });
  }

  try {
    // Hapus semua pesan antara userId dan targetId
    const [result] = await db.query(
      `DELETE FROM messages 
       WHERE (senderId = ? AND receiverId = ?) 
          OR (senderId = ? AND receiverId = ?)`,
      [userId, targetId, targetId, userId]
    );

    // Emit event ke socket untuk update real-time
    const io = req.app.get('io');
    if (io) {
      // Kirim event ke kedua user bahwa obrolan sudah dibersihkan
      io.to(String(userId)).emit('conversationCleared', { 
        userId: userId, 
        targetId: targetId 
      });
      io.to(String(targetId)).emit('conversationCleared', { 
        userId: targetId, 
        targetId: userId 
      });
    }

    res.json({ 
      success: true, 
      message: 'All messages cleared successfully',
      deletedCount: result.affectedRows 
    });
  } catch (error) {
    console.error('Clear all messages error:', error);
    res.status(500).json({ error: 'Failed to clear all messages' });
  }
});

module.exports = router;