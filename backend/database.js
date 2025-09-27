const mysql = require('mysql2');
require('dotenv').config(); // Add dotenv for better config management

// Create a connection pool
const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || 'firmansah.31',
  database: process.env.DB_NAME || 'ambulance_tracker_db',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

// Test the connection
pool.getConnection((err, connection) => {
  if (err) {
    if (err.code === 'PROTOCOL_CONNECTION_LOST') {
      console.error('Database connection was closed.');
    }
    if (err.code === 'ER_CON_COUNT_ERROR') {
      console.error('Database has too many connections.');
    }
    if (err.code === 'ECONNREFUSED') {
      console.error('Database connection was refused.');
    }
    if (err.code === 'ER_ACCESS_DENIED_ERROR') {
      console.error('Access denied to database.');
    }
    console.error('Error connecting to database:', err);
  }
  
  if (connection) {
    console.log('Successfully connected to the database.');
    connection.release();
  }
});

// Export the pool with promise interface
module.exports = pool.promise();