const express = require('express');
const router = express.Router();
const db = require('../database');
const axios = require('axios');

// GET /api/ambulance
router.get('/', async (req, res) => {
  try {
    const [rows] = await db.query(
      'SELECT latitude, longitude, isBusy, updatedAt FROM ambulance_location WHERE id = 1 LIMIT 1'
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Location not found' });
    }
    const row = rows[0];
    
    // ✅ PERBAIKAN: Gunakan tracking state dari app dengan error handling
    let trackingActive = false;
    try {
      const ambulanceTracking = req.app.get('ambulanceTracking');
      trackingActive = ambulanceTracking ? ambulanceTracking.isEnabled() : false;
    } catch (error) {
      console.error('Error getting tracking status:', error);
    }
    
    res.json({
      latitude:  row.latitude,
      longitude: row.longitude,
      isBusy:    row.isBusy === 1,
      updatedAt: row.updatedAt,
      trackingActive // ✅ Status tracking yang akurat
    });
  } catch (error) {
    console.error('Get ambulance location error:', error);
    res.status(500).json({ error: 'Failed to get location' });
  }
});

// PUT /api/ambulance
router.put('/', async (req, res) => {
  const { latitude, longitude, isBusy } = req.body;
  if (latitude == null || longitude == null) {
    return res.status(400).json({ error: 'Latitude and longitude are required' });
  }

  // ✅ PERBAIKAN: Cek tracking state dengan error handling yang lebih baik
  let trackingActive = false;
  try {
    const ambulanceTracking = req.app.get('ambulanceTracking');
    trackingActive = ambulanceTracking ? ambulanceTracking.isEnabled() : false;
  } catch (error) {
    console.error('Error checking tracking status:', error);
    return res.status(500).json({ 
      error: 'Internal server error while checking tracking status',
      trackingActive: false
    });
  }

  // ✅ PERBAIKAN: Hanya blokir jika tracking benar-benar disabled DAN ini adalah update lokasi dari admin
  // Izinkan update jika tracking aktif ATAU jika ini adalah request manual dari admin
  const isAdminManualUpdate = req.headers['x-admin-update'] === 'true';
  
  if (!trackingActive && !isAdminManualUpdate) {
    return res.status(423).json({ 
      error: 'Ambulance tracking is currently disabled',
      trackingActive: false,
      message: 'Please enable tracking first before updating location'
    });
  }

  try {
    const [existing] = await db.query('SELECT id FROM ambulance_location WHERE id = 1 LIMIT 1');
    const busyValue = isBusy != null ? (isBusy ? 1 : 0) : 0;

    if (existing.length === 0) {
      await db.query(
        'INSERT INTO ambulance_location (id, latitude, longitude, isBusy, updatedAt) VALUES (1, ?, ?, ?, NOW())',
        [latitude, longitude, busyValue]
      );
    } else {
      if (isBusy != null) {
        await db.query(
          'UPDATE ambulance_location SET latitude = ?, longitude = ?, isBusy = ?, updatedAt = NOW() WHERE id = 1',
          [latitude, longitude, busyValue]
        );
      } else {
        await db.query(
          'UPDATE ambulance_location SET latitude = ?, longitude = ?, updatedAt = NOW() WHERE id = 1',
          [latitude, longitude]
        );
      }
    }

    let addressText = null;
    try {
      const nominatimUrl =
        `https://nominatim.openstreetmap.org/reverse?format=json&lat=${latitude}&lon=${longitude}`;
      const geoResp = await axios.get(nominatimUrl, {
        headers: { 'User-Agent': 'AmbulanceTracker/1.0' },
        timeout: 5000 // ✅ Tambahkan timeout untuk geocoding
      });
      addressText = geoResp.data.display_name || null;
      if (addressText) {
        await db.query(
          'UPDATE ambulance_location SET address_text = ? WHERE id = 1',
          [addressText]
        );
      }
    } catch (geErr) {
      console.error('Reverse-geocode error:', geErr);
      // Tidak menggagalkan request jika geocoding gagal
    }

    // ✅ PERBAIKAN: Emit socket dengan error handling yang lebih baik
    try {
      const io = req.app.get('io');
      if (io) {
        const socketPayload = {
          latitude,
          longitude,
          addressText,
          isBusy: busyValue === 1,
          updatedAt: new Date().toISOString(),
          trackingActive: trackingActive 
        };
        
        console.log('Emitting ambulanceLocationUpdated:', socketPayload);
        io.emit('ambulanceLocationUpdated', socketPayload);
      } else {
        console.warn('Socket.IO instance not found');
      }
    } catch (emErr) {
      console.error('Socket emit error:', emErr);
      // Tidak menggagalkan request jika emit socket gagal
    }

    res.json({ 
      success: true,
      trackingActive: trackingActive,
      location: {
        latitude,
        longitude,
        addressText,
        isBusy: busyValue === 1
      }
    });
  } catch (error) {
    console.error('Update ambulance location error:', error);
    res.status(500).json({ error: 'Failed to update location' });
  }
});

// GET /api/ambulance/:id/location-detail
router.get('/:id/location-detail', async (req, res) => {
  const { id } = req.params;
  try {
    const [rows] = await db.query(
      'SELECT latitude, longitude, address_text, isBusy, updatedAt FROM ambulance_location WHERE id = ? LIMIT 1',
      [id]
    );
    if (rows.length === 0) {
      return res.status(404).json({ error: 'Location not found' });
    }
    const row = rows[0];

    let address = row.address_text;
    if (!address) {
      try {
        const nominatimUrl =
          `https://nominatim.openstreetmap.org/reverse?format=json&lat=${row.latitude}&lon=${row.longitude}`;
        const geoResp = await axios.get(nominatimUrl, {
          headers: { 'User-Agent': 'AmbulanceTracker/1.0' },
          timeout: 5000
        });
        address = geoResp.data.display_name || null;
      } catch (geErr) {
        console.error('Geocoding error:', geErr);
        address = 'Address not available';
      }
    }

    // ✅ PERBAIKAN: Sertakan status tracking dengan error handling
    let trackingActive = false;
    try {
      const ambulanceTracking = req.app.get('ambulanceTracking');
      trackingActive = ambulanceTracking ? ambulanceTracking.isEnabled() : false;
    } catch (error) {
      console.error('Error getting tracking status:', error);
    }

    res.json({
      latitude:    row.latitude,
      longitude:   row.longitude,
      addressText: address,
      isBusy:      row.isBusy === 1,
      updatedAt:   row.updatedAt,
      trackingActive // ✅ Status tracking yang akurat
    });
  } catch (error) {
    console.error('Get ambulance location detail error:', error);
    res.status(500).json({ error: 'Failed to get location detail' });
  }
});

// ✅ PERBAIKAN: Endpoint untuk mengubah status busy tanpa lokasi - TIDAK memerlukan tracking aktif
router.put('/status', async (req, res) => {
  const { isBusy } = req.body;
  if (isBusy == null) {
    return res.status(400).json({ error: 'isBusy status is required' });
  }

  // ✅ PERBAIKAN: Status bisa diubah meski tracking nonaktif, karena admin perlu kontrol penuh
  let trackingActive = false;
  try {
    const ambulanceTracking = req.app.get('ambulanceTracking');
    trackingActive = ambulanceTracking ? ambulanceTracking.isEnabled() : false;
  } catch (error) {
    console.error('Error checking tracking status:', error);
  }

  try {
    const busyValue = isBusy ? 1 : 0;
    await db.query(
      'UPDATE ambulance_location SET isBusy = ?, updatedAt = NOW() WHERE id = 1',
      [busyValue]
    );

    // Ambil data terbaru untuk emit
    const [rows] = await db.query(
      'SELECT latitude, longitude, address_text, isBusy, updatedAt FROM ambulance_location WHERE id = 1 LIMIT 1'
    );

    if (rows.length > 0) {
      const row = rows[0];
      try {
        const io = req.app.get('io');
        if (io) {
          const socketPayload = {
            latitude: row.latitude,
            longitude: row.longitude,
            addressText: row.address_text,
            isBusy: row.isBusy === 1,
            updatedAt: new Date().toISOString(),
            trackingActive: trackingActive // ✅ Gunakan status tracking yang akurat
          };
          
          console.log('Emitting ambulanceLocationUpdated (status change):', socketPayload);
          io.emit('ambulanceLocationUpdated', socketPayload);
        }
      } catch (emErr) {
        console.error('Socket emit error:', emErr);
      }
    }

    res.json({ 
      success: true, 
      isBusy: busyValue === 1,
      trackingActive: trackingActive,
      message: `Status changed to ${busyValue === 1 ? 'busy' : 'available'}`
    });
  } catch (error) {
    console.error('Update ambulance status error:', error);
    res.status(500).json({ error: 'Failed to update status' });
  }
});

// ✅ PERBAIKAN: Endpoint untuk force emit lokasi terbaru dengan validasi
router.post('/broadcast-location', async (req, res) => {
  let trackingActive = false;
  try {
    const ambulanceTracking = req.app.get('ambulanceTracking');
    trackingActive = ambulanceTracking ? ambulanceTracking.isEnabled() : false;
  } catch (error) {
    console.error('Error checking tracking status:', error);
  }

  // ✅ PERBAIKAN: Broadcast bisa dilakukan meski tracking nonaktif untuk testing
  try {
    const [rows] = await db.query(
      'SELECT latitude, longitude, address_text, isBusy, updatedAt FROM ambulance_location WHERE id = 1 LIMIT 1'
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: 'No ambulance location found' });
    }

    const row = rows[0];
    const io = req.app.get('io');
    if (io) {
      const socketPayload = {
        latitude: row.latitude,
        longitude: row.longitude,
        addressText: row.address_text,
        isBusy: row.isBusy === 1,
        updatedAt: new Date().toISOString(),
        trackingActive: trackingActive // ✅ Gunakan status tracking yang akurat
      };
      
      console.log('Broadcasting current ambulance location:', socketPayload);
      io.emit('ambulanceLocationUpdated', socketPayload);
      
      res.json({ 
        success: true, 
        message: 'Location broadcasted',
        data: socketPayload,
        trackingActive: trackingActive
      });
    } else {
      res.status(500).json({ error: 'Socket.IO not available' });
    }
  } catch (error) {
    console.error('Broadcast location error:', error);
    res.status(500).json({ error: 'Failed to broadcast location' });
  }
});

// =========================
// ✅ Call History (tidak berubah)
// =========================

// POST /api/ambulance/call
router.post('/call', async (req, res) => {
  const { userId } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId is required' });
  try {
    const [result] = await db.query(
      'INSERT INTO call_history (user_id) VALUES (?)',
      [userId]
    );

    const [rows] = await db.query(
      `SELECT h.id, h.user_id, u.fullName AS userName, h.called_at
       FROM call_history h
       JOIN users u ON h.user_id = u.id
       WHERE h.id = ?`,
      [result.insertId]
    );

    const io = req.app.get('io');
    if (io && rows.length > 0) {
      io.emit('newCall', rows[0]);
    }

    res.json({ success: true, call: rows[0] });
  } catch (err) {
    console.error('Error saving call history:', err);
    res.status(500).json({ error: 'Failed to record call' });
  }
});

// GET /api/ambulance/history
router.get('/history', async (req, res) => {
  try {
    const [rows] = await db.query(
      `SELECT h.id, h.user_id AS userId, u.fullName AS userName, h.called_at AS calledAt
       FROM call_history h
       JOIN users u ON h.user_id = u.id
       ORDER BY h.called_at DESC`
    );
    res.json(rows);
  } catch (err) {
    console.error('Error fetching call history:', err);
    res.status(500).json({ error: 'Failed to fetch history' });
  }
});

// DELETE /api/ambulance/history/:id
router.delete('/history/:id', async (req, res) => {
  const { id } = req.params;
  try {
    await db.query('DELETE FROM call_history WHERE id = ?', [id]);

    const io = req.app.get('io');
    if (io) {
      io.emit('callDeleted', { id: parseInt(id, 10) });
    }

    res.json({ success: true });
  } catch (err) {
    console.error('Error deleting call history:', err);
    res.status(500).json({ error: 'Failed to delete history' });
  }
});

// ✅ TAMBAHKAN ENDPOINT INI KE FILE ambulance.js
// Letakkan setelah endpoint DELETE /api/ambulance/history/:id

// DELETE /api/ambulance/history/clear - ✅ ENDPOINT BARU
router.delete('/history/clear', async (req, res) => {
  try {
    // Hapus semua riwayat panggilan
    const [result] = await db.query('DELETE FROM call_history');
    
    console.log(`Cleared ${result.affectedRows} call history records`);
    
    // ✅ BROADCAST ke semua client bahwa semua riwayat telah dihapus
    const io = req.app.get('io');
    if (io) {
      io.emit('allCallsCleared', { 
        success: true, 
        clearedCount: result.affectedRows,
        timestamp: new Date().toISOString()
      });
    }
    
    res.json({ 
      success: true, 
      message: 'All call history cleared successfully',
      clearedCount: result.affectedRows
    });
  } catch (err) {
    console.error('Error clearing all call history:', err);
    res.status(500).json({ error: 'Failed to clear all call history' });
  }
});

module.exports = router;