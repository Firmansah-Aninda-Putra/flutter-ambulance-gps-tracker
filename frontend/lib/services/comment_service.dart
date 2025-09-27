// frontend/lib/services/comment_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // Untuk tipe MIME gambar
import 'package:mime/mime.dart'; // Untuk mendeteksi mimeType dari file
import '../config/api_config.dart';
import '../models/comment_model.dart';

class CommentService {
  /// Ambil semua komentar (ordered by backend DESC)
  Future<List<Comment>> getComments() async {
    final response = await http.get(Uri.parse(ApiConfig.comments));

    if (response.statusCode == 200) {
      // JSON backend berbentuk:
      // { "page": 1, "limit": 20, "total": X, "comments": [ ... ] }
      final Map<String, dynamic> data =
          jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> commentsJson = data['comments'] as List<dynamic>;
      return commentsJson
          .map((json) => Comment.fromJson(json as Map<String, dynamic>))
          .toList();
    } else {
      throw Exception('Failed to load comments');
    }
  }

  /// Post komentar baru dengan mandatory ambulanceId, optional content, parentId, imageUrl, emoticonCode
  Future<void> postComment(
    int userId, {
    String? content, // content sekarang bersifat optional
    required int ambulanceId,
    int? parentId,
    String? imageUrl,
    String? emoticonCode,
  }) async {
    // Build body JSON; hanya masukkan field jika ada isinya
    final Map<String, dynamic> body = {
      'userId': userId,
      'ambulanceId': ambulanceId,
      if (content != null && content.trim().isNotEmpty)
        'content': content.trim(),
      if (parentId != null) 'parentId': parentId,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (emoticonCode != null) 'emoticonCode': emoticonCode,
    };

    final response = await http.post(
      Uri.parse(ApiConfig.comments),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      String msg = 'Failed to post comment';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] != null) {
          msg = data['error'];
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// Delete komentar (cancel setelah terkirim)
  Future<void> deleteComment(int commentId) async {
    final uri = Uri.parse('${ApiConfig.comments}/$commentId');
    final response = await http.delete(uri);

    if (response.statusCode != 200) {
      String msg = 'Failed to delete comment';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['error'] != null) {
          msg = data['error'];
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  /// Upload gambar ke backend dan kembalikan URL-nya
  Future<String> uploadImage(File file) async {
    final uri = Uri.parse(ApiConfig.upload);
    final mimeType = lookupMimeType(file.path);
    final mimeParts = mimeType?.split('/') ?? ['image', 'jpeg'];

    final request = http.MultipartRequest('POST', uri);
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType(mimeParts[0], mimeParts[1]),
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map && data['imageUrl'] != null) {
        return data['imageUrl'] as String;
      } else {
        throw Exception('Server tidak mengembalikan URL gambar');
      }
    } else {
      String msg = 'Upload image failed';
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

// Jika butuh serialize kembali ke JSON (misalnya debugging), bisa pakai:
