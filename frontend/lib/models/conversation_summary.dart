// frontend/lib/models/conversation_summary.dart

import 'package:flutter/foundation.dart';
import 'chat_message.dart';

/// Model summary untuk satu percakapan dengan partner tertentu.
/// Digunakan di layar daftar percakapan (inbox).
class ConversationSummary {
  final int partnerId;
  final String? partnerName; // ← Ditambahkan untuk nama partner
  final ChatMessage? lastMessage;
  final DateTime? lastTimestamp;
  final int? unreadCount; // ← Field untuk jumlah pesan yang belum dibaca

  ConversationSummary({
    required this.partnerId,
    this.partnerName, // ← Constructor menerima partnerName
    this.lastMessage,
    this.lastTimestamp,
    this.unreadCount, // ← Constructor menerima unreadCount
  });

  /// Buat instance dari JSON hasil GET /api/chat/conversation/:userId
  /// JSON diharapkan memiliki format:
  /// {
  ///   "partnerId": number,
  ///   "partnerName": string,             // ← Nama partner
  ///   "lastMessage": { … },
  ///   "lastTimestamp": string|null,
  ///   "unreadCount": number              // ← Jumlah pesan belum dibaca
  /// }
  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    // Parse partnerId
    final dynamic pid = json['partnerId'];
    int partnerId;
    if (pid is int) {
      partnerId = pid;
    } else if (pid is String) {
      partnerId = int.tryParse(pid) ?? 0;
    } else {
      partnerId = 0;
    }

    // Parse partnerName jika ada
    String? partnerName;
    if (json['partnerName'] != null) {
      final dynamic name = json['partnerName'];
      partnerName = name is String ? name : name.toString();
    }

    // Parse lastMessage jika ada
    ChatMessage? lastMsg;
    if (json['lastMessage'] != null && json['lastMessage'] is Map) {
      try {
        lastMsg = ChatMessage.fromJson(
            Map<String, dynamic>.from(json['lastMessage'] as Map));
      } catch (e) {
        if (kDebugMode) {
          print('ConversationSummary.fromJson: error parsing lastMessage: $e');
        }
        lastMsg = null;
      }
    }

    // Parse lastTimestamp jika ada
    DateTime? lastTs;
    if (json['lastTimestamp'] != null) {
      final dynamic ts = json['lastTimestamp'];
      String tsStr;
      if (ts is String) {
        tsStr = ts;
      } else {
        tsStr = ts.toString();
      }
      try {
        lastTs = DateTime.parse(tsStr).toLocal();
      } catch (e) {
        if (kDebugMode) {
          print(
              'ConversationSummary.fromJson: error parsing lastTimestamp: $e');
        }
        lastTs = null;
      }
    }

    // ✅ PERBAIKAN: Parse unreadCount jika ada
    int? unreadCount;
    if (json['unreadCount'] != null) {
      final dynamic count = json['unreadCount'];
      if (count is int) {
        unreadCount = count;
      } else if (count is String) {
        unreadCount = int.tryParse(count) ?? 0;
      } else {
        unreadCount = 0;
      }
    }

    return ConversationSummary(
      partnerId: partnerId,
      partnerName: partnerName, // ← Masukkan ke constructor
      lastMessage: lastMsg,
      lastTimestamp: lastTs,
      unreadCount: unreadCount, // ← Masukkan ke constructor
    );
  }
}
