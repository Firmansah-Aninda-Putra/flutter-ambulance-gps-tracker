// frontend/lib/config/api_config.dart

import 'dart:io' show Platform;

class ApiConfig {
  // Ganti dengan IP address komputer Anda
  static const String _localIP = '192.168.0.107'; // Ubah sesuai IP backend Anda
  static const String _port = '3000';

  /// Base URL untuk HTTP API, dengan path '/api'
  static String get _baseUrl {
    if (Platform.isAndroid) {
      // Perangkat fisik Android via USB debugging
      return 'http://$_localIP:$_port/api';
    } else if (Platform.isIOS) {
      // Perangkat fisik iOS
      return 'http://$_localIP:$_port/api';
    } else {
      // Web/desktop development
      return 'http://localhost:$_port/api';
    }
  }

  /// Alternatif: Auto-detect konfigurasi, misalnya emulator vs perangkat fisik
  /// (Tetap dipertahankan jika suatu saat ingin menggunakan compile-time flag,
  /// namun saat ini baseUrl menggunakan runtime Platform.)
  static String get _smartBaseUrl {
    const bool isPhysicalDevice =
        bool.fromEnvironment('PHYSICAL_DEVICE', defaultValue: true);

    if (isPhysicalDevice) {
      return 'http://$_localIP:$_port/api';
    } else {
      // Emulator configuration
      if (Platform.isAndroid) {
        // Android emulator default: 10.0.2.2 mengarah ke host machine
        return 'http://10.0.2.2:$_port/api';
      } else if (Platform.isIOS) {
        // iOS simulator: localhost bisa langsung digunakan
        return 'http://localhost:$_port/api';
      }
    }
    // Fallback
    return 'http://localhost:$_port/api';
  }

  /// Base URL yang dipakai aplikasi. Ubah cara memilih jika perlu.
  /// Direkomendasikan menggunakan runtime Platform agar otomatis sesuai
  /// Android/iOS device, tanpa bergantung compile-time flag.
  static String get baseUrl => _baseUrl;

  /// Endpoint untuk login: POST
  static String get login => '$_baseUrl/auth/login';

  /// Endpoint untuk register: POST
  static String get register => '$_baseUrl/auth/register';

  /// Endpoint untuk mendapatkan info user detail: GET /auth/user/:id
  static String userDetail(int id) => '$_baseUrl/auth/user/$id';

  /// Endpoint untuk mendapatkan admin info: GET /auth/admin
  static String get admin => '$_baseUrl/auth/admin';

  /// Endpoint komentar: GET/POST /comments
  static String get comments => '$_baseUrl/comments';

  /// Endpoint upload gambar: POST /upload
  static String get upload => '$_baseUrl/upload';

  /// Endpoint ambulans: GET/PUT /ambulance
  static String get ambulanceLocation => '$_baseUrl/ambulance';

  /// Endpoint chat HTTP: base untuk chat endpoints: GET/POST
  /// GET history: /chat/:userId/:targetId
  /// GET conversations: /chat/conversation/:userId
  static String get chatEndpoint => '$_baseUrl/chat';

  /// Socket.IO URL (tanpa '/api'), untuk inisialisasi koneksi real-time.
  static String get socketUrl {
    if (Platform.isAndroid) {
      return 'http://$_localIP:$_port';
    } else if (Platform.isIOS) {
      return 'http://$_localIP:$_port';
    } else {
      // Untuk Web/Desktop juga pakai IP lokal, bukan 'localhost'
      return 'http://$_localIP:$_port';
    }
  }

  /// URL untuk testing koneksi dasar
  static String getTestUrl() => baseUrl;

  // ------------------------
  // KONFIGURASI UNTUK PANEL CUACA
  // ------------------------

  /// Base URL untuk API cuaca (Open-Meteo, gratis tanpa API key)
  static const String weatherApi = 'https://api.open-meteo.com/v1/forecast';

  /// Helper untuk membangun URL permintaan cuaca berdasar koordinat
  static String weatherUrl({
    required double latitude,
    required double longitude,
  }) {
    return '$weatherApi'
        '?latitude=$latitude'
        '&longitude=$longitude'
        '&current_weather=true'
        '&daily=weathercode,temperature_2m_max,temperature_2m_min'
        '&timezone=auto';
  }

  // ------------------------
  // KONFIGURASI UNTUK TRAFFIC OVERLAY
  // ------------------------

  /// API key TomTom free-tier. Isi dengan key yang Anda dapat.
  static const String tomTomApiKey = '7aehiSsiYIGYscHYGjiDA0WdWJgVTxST';

  /// Template URL tile overlay traffic TomTom.
  /// Contoh endpoint: traffic flow relative tiles 256px.
  static String get tomTomTrafficUrlTemplate {
    if (tomTomApiKey.isEmpty) {
      throw Exception('TomTom API key belum diatur di ApiConfig.tomTomApiKey');
    }
    return 'https://api.tomtom.com/traffic/map/4/tile/flow/relative/256/{z}/{x}/{y}.png?key=$tomTomApiKey';
  }
}
