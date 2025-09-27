// frontend/lib/services/auth_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user_model.dart';
import '../models/user_detail_model.dart';

class AuthService {
  /// Login: simpan session di SharedPreferences
  Future<User> login(String username, String password) async {
    final response = await http.post(
      Uri.parse(ApiConfig.login),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final userData = jsonDecode(response.body);
      final user = User.fromJson(userData);

      // Simpan data login ke SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('userId', user.id);
      await prefs.setString('username', user.username);
      await prefs.setBool('isAdmin', user.isAdmin);

      return user;
    } else {
      String msg = 'Login failed';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] != null) {
          msg = data['error'];
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// Register user baru
  Future<User> register(String username, String password, String fullName,
      String address, String phone) async {
    final response = await http.post(
      Uri.parse(ApiConfig.register),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'fullName': fullName,
        'address': address,
        'phone': phone,
      }),
    );

    if (response.statusCode == 200) {
      final userData = jsonDecode(response.body);
      return User(
        id: userData['id'] ?? 0,
        username: userData['username'] ?? '',
        isAdmin: false,
      );
    } else {
      String msg = 'Registration failed';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] != null) {
          msg = data['error'];
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// Ambil user yang sedang login (session) dari SharedPreferences
  Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    final username = prefs.getString('username');
    final isAdmin = prefs.getBool('isAdmin');

    if (userId != null && username != null && isAdmin != null) {
      return User(id: userId, username: username, isAdmin: isAdmin);
    }
    return null;
  }

  /// Logout: hapus session
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('username');
    await prefs.remove('isAdmin');
  }

  /// GET User Detail by ID (profil lengkap)
  /// Endpoint: GET /api/auth/user/:id
  Future<UserDetail> getUserDetail(int userId) async {
    // Validasi sebelum request: userId harus ≥ 1
    if (userId < 1) {
      throw Exception('Invalid user ID');
    }

    final response = await http.get(Uri.parse(ApiConfig.userDetail(userId)));

    if (response.statusCode == 200) {
      return UserDetail.fromJson(jsonDecode(response.body));
    } else {
      String msg = 'Failed to get user detail';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] != null) {
          msg = data['error'];
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// Cek apakah user sudah login
  Future<bool> isLoggedIn() async {
    final user = await getCurrentUser();
    return user != null;
  }

  /// GET admin info untuk chat: ambil admin ID via GET /api/auth/admin
  Future<int> getAdminId() async {
    final uri = Uri.parse(ApiConfig.admin);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      try {
        // Respons adalah List of { id, username }
        final List<dynamic> dataList = jsonDecode(response.body);
        if (dataList.isEmpty) {
          throw Exception('No admin users found');
        }
        final first = dataList[0];
        final dynamic rawId = first['id'];
        if (rawId is int) {
          return rawId;
        } else if (rawId is String) {
          return int.tryParse(rawId) ?? -1;
        } else {
          throw Exception('Invalid admin ID format');
        }
      } catch (e) {
        throw Exception('Failed to parse admin ID: $e');
      }
    } else {
      String msg = 'Failed to get admin info';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] != null) {
          msg = data['error'];
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }
}
