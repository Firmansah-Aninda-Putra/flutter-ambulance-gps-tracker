// frontend/lib/services/chat_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import '../config/api_config.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import 'socket_service.dart'; // Import SocketService

class ChatService {
  final SocketService _socketService = SocketService();

  // Gunakan SocketService untuk real-time messaging
  Stream<ChatMessage> get messageStream => _socketService.messageStream;

  Future<int> getAdminId() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/admin');
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final id = data['id'];
      if (id is int) return id;
      if (id is String) return int.tryParse(id) ?? -1;
      throw Exception('Invalid admin ID format');
    } else {
      final err = (response.body.isNotEmpty
              ? jsonDecode(response.body)['error']
              : null) ??
          'Failed to get admin ID';
      throw Exception(err);
    }
  }

  Future<List<ConversationSummary>> getConversations(int userId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/conversation/$userId');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> listJson = jsonDecode(response.body) as List<dynamic>;
      return listJson
          .map((e) =>
              ConversationSummary.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      final err = (response.body.isNotEmpty
              ? jsonDecode(response.body)['error']
              : null) ??
          'Failed to load conversations';
      throw Exception(err);
    }
  }

  Future<List<ChatMessage>> getMessages(int userId, int targetId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/$userId/$targetId');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> listJson = jsonDecode(response.body) as List<dynamic>;
      return listJson
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      final err = (response.body.isNotEmpty
              ? jsonDecode(response.body)['error']
              : null) ??
          'Failed to load messages';
      throw Exception(err);
    }
  }

  Future<ChatMessage> sendMessage({
    required int senderId,
    required int receiverId,
    String? content,
    String? imageUrl,
    double? latitude,
    double? longitude,
    String? emoticonCode,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat');
    final body = <String, dynamic>{
      'senderId': senderId,
      'receiverId': receiverId,
      if (content != null && content.trim().isNotEmpty)
        'content': content.trim(),
      if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      if (latitude != null && longitude != null) ...{
        'latitude': latitude,
        'longitude': longitude,
      },
      if (emoticonCode != null && emoticonCode.isNotEmpty)
        'emoticonCode': emoticonCode,
    };

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) {
        final rawMsg = data['message'];
        if (rawMsg is Map<String, dynamic>) {
          return ChatMessage.fromJson(rawMsg);
        } else if (rawMsg is Map) {
          return ChatMessage.fromJson(Map<String, dynamic>.from(rawMsg));
        }
      }
      if (data is Map<String, dynamic>) {
        return ChatMessage.fromJson(data);
      } else if (data is Map) {
        return ChatMessage.fromJson(Map<String, dynamic>.from(data));
      }
      throw Exception('Invalid response format');
    } else {
      final err = (response.body.isNotEmpty
              ? jsonDecode(response.body)['error']
              : null) ??
          'Failed to send message';
      throw Exception(err);
    }
  }

  Future<String> uploadImage(File file) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/upload');
    final request = http.MultipartRequest('POST', uri);

    final mimeType = lookupMimeType(file.path);
    if (mimeType == null) {
      throw Exception('Tidak dapat mendeteksi tipe MIME file');
    }

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(mimeType),
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final url = data['imageUrl'];
      if (url is String) {
        return url;
      } else {
        throw Exception('Invalid imageUrl in response');
      }
    } else {
      final err = (response.body.isNotEmpty
              ? jsonDecode(response.body)['error']
              : null) ??
          'Failed to upload image';
      throw Exception(err);
    }
  }

  Future<void> deleteMessage(int messageId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/$messageId');
    final response = await http.delete(uri);

    if (response.statusCode == 200) {
      return;
    } else {
      final err = (response.body.isNotEmpty
              ? jsonDecode(response.body)['error']
              : null) ??
          'Failed to delete message';
      throw Exception(err);
    }
  }

  // FITUR BARU: Method untuk menghapus semua pesan dalam obrolan
  Future<void> clearAllMessages(int userId, int targetId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/chat/clear/$userId/$targetId');
    final response = await http.delete(uri);

    if (response.statusCode == 200) {
      return;
    } else {
      final err = (response.body.isNotEmpty
              ? jsonDecode(response.body)['error']
              : null) ??
          'Failed to clear all messages';
      throw Exception(err);
    }
  }
}

String getImageUrl(String imageUrl) {
  return '${ApiConfig.baseUrl}/images/$imageUrl';
}
