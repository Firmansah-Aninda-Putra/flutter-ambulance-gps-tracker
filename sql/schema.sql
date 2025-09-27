-- ============================
-- Tabel users
-- ============================
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(50) NOT NULL UNIQUE,
  password VARCHAR(100) NOT NULL,
  fullName VARCHAR(100) NOT NULL,
  address TEXT NOT NULL,
  phone VARCHAR(20) NOT NULL,
  isAdmin BOOLEAN DEFAULT FALSE,
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================
-- Tabel ambulance_location
-- ============================
CREATE TABLE IF NOT EXISTS ambulance_location (
  id INT PRIMARY KEY,
  latitude DOUBLE NOT NULL,
  longitude DOUBLE NOT NULL,
  isBusy BOOLEAN DEFAULT FALSE,
  updatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  address_text TEXT NULL
);

INSERT IGNORE INTO ambulance_location (id, latitude, longitude)
VALUES (1, -7.6298, 111.5247);

-- ============================
-- Tabel comments (DIPERBAIKI: content sekarang NULL untuk mendukung image/emoticon only)
-- ============================
CREATE TABLE IF NOT EXISTS comments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  userId INT NOT NULL,
  ambulance_id INT NOT NULL,
  content TEXT NULL,
  image_url TEXT NULL,
  emoticon_code VARCHAR(100) NULL,
  parentId INT NULL,
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (userId) REFERENCES users(id),
  FOREIGN KEY (parentId) REFERENCES comments(id),
  FOREIGN KEY (ambulance_id) REFERENCES ambulance_location(id)
);

-- ============================
-- Tabel messages
-- ============================
CREATE TABLE IF NOT EXISTS messages (
  id INT AUTO_INCREMENT PRIMARY KEY,
  senderId INT NOT NULL,
  receiverId INT NOT NULL,
  content TEXT NULL,
  imageUrl TEXT NULL,
  latitude DOUBLE NULL,
  longitude DOUBLE NULL,
  emoticon_code VARCHAR(100) NULL,
  createdAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (senderId) REFERENCES users(id),
  FOREIGN KEY (receiverId) REFERENCES users(id)
);

-- ============================
-- Tabel ambulance_calls (RIWAYAT PANGGILAN)
-- ============================
CREATE TABLE IF NOT EXISTS call_history (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  ambulance_id INT NOT NULL DEFAULT 1,
  called_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

-- ============================
-- Seed admin user lama
INSERT IGNORE INTO users (username, password, fullName, address, phone, isAdmin)
VALUES (
  'ppidkotamadiun',
  '$2b$10$y04ex9B66W4nx2LQiU/1w.A4ysa2o4u0RswDEHBDHmLTRSwDSX0ES',
  'PPID Kota Madiun',
  'Jalan Perintis Kemerdekaan No. 32, Kelurahan Kartoharjo, Kecamatan Kartoharjo, Kota Madiun, Jawa Timur, 63119',
  '(0351) 467327',
  TRUE
);

-- Seed admin user baru
INSERT IGNORE INTO users (username, password, fullName, address, phone, isAdmin)
VALUES (
  'ambulankotamadiun',
  '$2a$10$j0lDL/2tD4utYOhuEWz0zeWRV.UL2y0cNF7mYN.9qlBQTkaSO.UVK',
  'Ambulan Kota Madiun',
  'Jalan Perintis Kemerdekaan No. 32, Kelurahan Kartoharjo, Kecamatan Kartoharjo, Kota Madiun, Jawa Timur, 63119',
  '(0351) 467327',
  TRUE
);