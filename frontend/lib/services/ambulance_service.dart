// frontend/lib/services/ambulance_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:location/location.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:permission_handler/permission_handler.dart' as permission;
import '../config/api_config.dart';
import '../models/ambulance_model.dart';
import '../models/ambulance_location_detail_model.dart';
import '../models/call_history_item.dart'; // <- import model riwayat

class AmbulanceService {
  /// Ambil lokasi ambulans lengkap (latitude, longitude, isBusy, updatedAt)
  Future<AmbulanceLocation> getAmbulanceLocation() async {
    final urlStr = ApiConfig.ambulanceLocation;
    try {
      debugPrint('DEBUG getAmbulanceLocation: GET URL=$urlStr');
      final response = await http.get(Uri.parse(urlStr));
      debugPrint(
          'DEBUG getAmbulanceLocation response status=${response.statusCode}, body=${response.body}');

      if (response.statusCode == 200) {
        return AmbulanceLocation.fromJson(jsonDecode(response.body));
      } else if (response.statusCode == 423) {
        throw Exception('Tracking disabled by server');
      } else {
        String errorMsg = 'Unknown error';
        try {
          final bodyJson = jsonDecode(response.body);
          errorMsg = bodyJson['error'] ?? errorMsg;
        } catch (_) {}
        throw Exception('Failed to load ambulance location: $errorMsg');
      }
    } catch (e) {
      debugPrint('Error in getAmbulanceLocation: $e');
      throw Exception('Network error: $e');
    }
  }

  /// Tambahan: Ambil detail lokasi ambulans, termasuk addressText
  Future<AmbulanceLocationDetail> getAmbulanceLocationDetail() async {
    final urlStr = '${ApiConfig.ambulanceLocation}/1/location-detail';
    try {
      debugPrint('DEBUG getAmbulanceLocationDetail: GET URL=$urlStr');
      final response = await http.get(Uri.parse(urlStr));
      debugPrint(
          'DEBUG getAmbulanceLocationDetail response status=${response.statusCode}, body=${response.body}');
      if (response.statusCode == 423) {
        throw Exception('Tracking disabled by server');
      }
      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return AmbulanceLocationDetail.fromJson(json);
      } else {
        String errorMsg = 'Unknown error';
        try {
          final bodyJson = jsonDecode(response.body);
          errorMsg = bodyJson['error'] ?? errorMsg;
        } catch (_) {}
        throw Exception('Failed to load ambulance location detail: $errorMsg');
      }
    } catch (e) {
      debugPrint('Error in getAmbulanceLocationDetail: $e');
      throw Exception('Network error: $e');
    }
  }

  /// Update lokasi ambulans.
  /// Jika parameter [isBusy] diberikan, sertakan ke JSON; jika tidak, hanya kirim latitude & longitude.
  Future<void> updateAmbulanceLocation(
    double latitude,
    double longitude, {
    bool? isBusy,
  }) async {
    final urlStr = ApiConfig.ambulanceLocation;
    // Bangun body JSON
    final Map<String, dynamic> body = {
      'latitude': latitude,
      'longitude': longitude,
      if (isBusy != null) 'isBusy': isBusy ? 1 : 0,
    };
    try {
      debugPrint('DEBUG updateAmbulanceLocation: PUT URL=$urlStr, body=$body');
      final response = await http.put(
        Uri.parse(urlStr),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      debugPrint(
          'DEBUG updateAmbulanceLocation response status=${response.statusCode}, body=${response.body}');
      if (response.statusCode != 200) {
        String errorMsg = 'Unknown error';
        try {
          final bodyJson = jsonDecode(response.body);
          errorMsg = bodyJson['error'] ?? errorMsg;
        } catch (_) {}
        throw Exception('Failed to update location: $errorMsg');
      }
    } catch (e) {
      debugPrint('Error in updateAmbulanceLocation: $e');
      throw Exception('Network error: $e');
    }
  }

// ✅ PERBAIKAN: Method untuk update lokasi sebagai admin (bypass tracking check)
  Future<void> updateAmbulanceLocationAsAdmin(
    double latitude,
    double longitude, {
    bool? isBusy,
  }) async {
    // ✅ PERBAIKAN: Gunakan ApiConfig.ambulanceLocation yang sudah benar
    final urlStr = ApiConfig.ambulanceLocation;
    try {
      debugPrint('DEBUG updateAmbulanceLocationAsAdmin: PUT URL=$urlStr');
      final response = await http.put(
        Uri.parse(urlStr),
        headers: {
          'Content-Type': 'application/json',
          'x-admin-update': 'true', // ✅ Header khusus untuk admin
        },
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          if (isBusy != null) 'isBusy': isBusy,
        }),
      );

      debugPrint(
          'DEBUG updateAmbulanceLocationAsAdmin response status=${response.statusCode}, body=${response.body}');

      if (response.statusCode != 200) {
        String errorMsg = 'Unknown error';
        try {
          final bodyJson = jsonDecode(response.body);
          errorMsg = bodyJson['error'] ?? errorMsg;
        } catch (_) {}
        throw Exception('Failed to update location: $errorMsg');
      }
    } catch (e) {
      debugPrint('Error in updateAmbulanceLocationAsAdmin: $e');
      throw Exception('Network error: $e');
    }
  }

// ✅ PERBAIKAN: Method untuk update status ambulan saja (tanpa lokasi)
  Future<void> updateAmbulanceStatus(bool isBusy) async {
    // ✅ PERBAIKAN: Gunakan endpoint yang benar untuk update status
    final urlStr = '${ApiConfig.ambulanceLocation}/status';
    try {
      debugPrint(
          'DEBUG updateAmbulanceStatus: PUT URL=$urlStr, isBusy=$isBusy');
      final response = await http.put(
        Uri.parse(urlStr),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'isBusy': isBusy,
        }),
      );

      debugPrint(
          'DEBUG updateAmbulanceStatus response status=${response.statusCode}, body=${response.body}');

      if (response.statusCode != 200) {
        String errorMsg = 'Unknown error';
        try {
          final bodyJson = jsonDecode(response.body);
          errorMsg = bodyJson['error'] ?? errorMsg;
        } catch (_) {}
        throw Exception('Failed to update status: $errorMsg');
      }
    } catch (e) {
      debugPrint('Error in updateAmbulanceStatus: $e');
      throw Exception('Network error: $e');
    }
  }

  /// Dapatkan lokasi device saat ini (user atau admin).
  Future<LocationData?> getCurrentLocation() async {
    Location location = Location();
    bool serviceEnabled;

    // Cek apakah service lokasi aktif
    try {
      serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          debugPrint('Location service not enabled');
          return null;
        }
      }

      // Cek izin lokasi
      var permissionStatus = await location.hasPermission();
      if (permissionStatus == PermissionStatus.denied) {
        permissionStatus = await location.requestPermission();
        if (permissionStatus != PermissionStatus.granted) {
          // Coba permission_handler sebagai alternatif
          var status = await permission.Permission.location.request();
          if (status != permission.PermissionStatus.granted) {
            debugPrint('Location permission not granted');
            return null;
          }
        }
      }

      // Ambil lokasi sekarang
      final locData = await location.getLocation();
      debugPrint(
          'DEBUG getCurrentLocation: lat=${locData.latitude}, lon=${locData.longitude}');
      return locData;
    } catch (e) {
      debugPrint('Error getting location: $e');
      return null;
    }
  }

  // =====================================
  //      Fitur Riwayat Panggilan
  // =====================================

  /// Ambil daftar riwayat panggilan, terurut berdasarkan waktu terbaru
  Future<List<CallHistoryItem>> getCallHistory() async {
    final urlStr = '${ApiConfig.ambulanceLocation}/history';
    try {
      debugPrint('DEBUG getCallHistory: GET URL=$urlStr');
      final response = await http.get(Uri.parse(urlStr));
      debugPrint(
          'DEBUG getCallHistory response status=${response.statusCode}, body=${response.body}');
      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(response.body);
        return list
            .map((e) => CallHistoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Failed to load call history');
      }
    } catch (e) {
      debugPrint('Error in getCallHistory: $e');
      throw Exception('Network error: $e');
    }
  }

  /// Hapus satu item riwayat panggilan berdasarkan ID
  Future<void> deleteCallHistory(int id) async {
    final urlStr = '${ApiConfig.ambulanceLocation}/history/$id';
    try {
      debugPrint('DEBUG deleteCallHistory: DELETE URL=$urlStr');
      final response = await http.delete(Uri.parse(urlStr));
      debugPrint(
          'DEBUG deleteCallHistory response status=${response.statusCode}, body=${response.body}');
      if (response.statusCode != 200) {
        throw Exception('Failed to delete call history');
      }
    } catch (e) {
      debugPrint('Error in deleteCallHistory: $e');
      throw Exception('Network error: $e');
    }
  }

  /// ✅ TAMBAHAN: Hapus semua riwayat panggilan (clear all)
  Future<void> clearAllCallHistory() async {
    final urlStr = '${ApiConfig.ambulanceLocation}/history/clear';
    try {
      debugPrint('DEBUG clearAllCallHistory: DELETE URL=$urlStr');
      final response = await http.delete(Uri.parse(urlStr));
      debugPrint(
          'DEBUG clearAllCallHistory response status=${response.statusCode}, body=${response.body}');
      if (response.statusCode != 200) {
        throw Exception('Failed to clear all call history');
      }
    } catch (e) {
      debugPrint('Error in clearAllCallHistory: $e');
      throw Exception('Network error: $e');
    }
  }

  /// Catat panggilan ambulans oleh user dengan userId
  Future<CallHistoryItem> callAmbulance(int userId) async {
    final urlStr = '${ApiConfig.ambulanceLocation}/call';
    try {
      debugPrint('DEBUG callAmbulance: POST URL=$urlStr, userId=$userId');
      final response = await http.post(
        Uri.parse(urlStr),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': userId}),
      );
      debugPrint(
          'DEBUG callAmbulance response status=${response.statusCode}, body=${response.body}');
      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return CallHistoryItem.fromJson(json['call'] as Map<String, dynamic>);
      } else {
        throw Exception('Failed to record call');
      }
    } catch (e) {
      debugPrint('Error in callAmbulance: $e');
      throw Exception('Network error: $e');
    }
  }
}
