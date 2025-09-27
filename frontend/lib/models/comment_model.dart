// frontend/lib/models/comment_model.dart

class Comment {
  final int id;
  final int userId;
  final int ambulanceId;
  final String content;
  final String? imageUrl;
  final String? emoticonCode;
  final int? parentId;
  final String createdAt;
  final String username;
  final bool isAdmin;

  Comment({
    required this.id,
    required this.userId,
    required this.ambulanceId,
    required this.content,
    this.imageUrl,
    this.emoticonCode,
    this.parentId,
    required this.createdAt,
    required this.username,
    required this.isAdmin,
  });

  /// Parsing aman untuk integer
  static int _parseInt(dynamic v, {int defaultValue = 0}) {
    if (v is int) return v;
    if (v is String) {
      return int.tryParse(v) ?? defaultValue;
    }
    return defaultValue;
  }

  /// Parsing aman untuk String
  static String _parseString(dynamic v) {
    if (v == null) return '';
    return v.toString();
  }

  /// Parsing aman untuk bool (mendukung bool, int 0/1, String "true"/"false"/"1"/"0")
  static bool _parseBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v == 1;
    if (v is String) {
      final low = v.toLowerCase();
      if (low == 'true' || low == '1') return true;
      if (low == 'false' || low == '0') return false;
    }
    return false;
  }

  /// Factory membuat Comment dari JSON Map
  factory Comment.fromJson(Map<String, dynamic> json) {
    // Parsing id
    final id = _parseInt(json['id'] ?? json['ID'], defaultValue: 0);

    // Parsing userId
    final userId =
        _parseInt(json['userId'] ?? json['user_id'], defaultValue: 0);

    // Parsing ambulanceId: backend mungkin mengirim 'ambulanceId' atau 'ambulance_id'
    final ambulanceId =
        _parseInt(json['ambulanceId'] ?? json['ambulance_id'], defaultValue: 0);

    // Parsing content
    final content = _parseString(json['content'] ?? '');

    // Parsing imageUrl: backend mungkin mengirim 'imageUrl' atau 'image_url'
    String? imageUrl;
    if (json.containsKey('imageUrl') && json['imageUrl'] != null) {
      imageUrl = _parseString(json['imageUrl']);
    } else if (json.containsKey('image_url') && json['image_url'] != null) {
      imageUrl = _parseString(json['image_url']);
    } else {
      imageUrl = null;
    }

    // Parsing emoticonCode: backend mungkin 'emoticonCode' atau 'emoticon_code'
    String? emoticonCode;
    if (json.containsKey('emoticonCode') && json['emoticonCode'] != null) {
      emoticonCode = _parseString(json['emoticonCode']);
    } else if (json.containsKey('emoticon_code') &&
        json['emoticon_code'] != null) {
      emoticonCode = _parseString(json['emoticon_code']);
    } else {
      emoticonCode = null;
    }

    // Parsing parentId (nullable)
    int? parentId;
    if (json.containsKey('parentId') && json['parentId'] != null) {
      parentId = _parseInt(json['parentId']);
    } else if (json.containsKey('parent_id') && json['parent_id'] != null) {
      parentId = _parseInt(json['parent_id']);
    } else {
      parentId = null;
    }

    // Parsing createdAt: backend mengirim timestamp sebagai String
    final createdAt =
        _parseString(json['createdAt'] ?? json['created_at'] ?? '');

    // Parsing username
    final username = _parseString(json['username'] ?? '');

    // Parsing isAdmin: backend mengirim int atau bool
    final isAdmin = _parseBool(json['isAdmin'] ?? json['is_admin']);

    return Comment(
      id: id,
      userId: userId,
      ambulanceId: ambulanceId,
      content: content,
      imageUrl: imageUrl,
      emoticonCode: emoticonCode,
      parentId: parentId,
      createdAt: createdAt,
      username: username,
      isAdmin: isAdmin,
    );
  }

  /// Jika butuh serialize kembali ke JSON (misalnya debugging), bisa pakai:
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'userId': userId,
      'ambulanceId': ambulanceId,
      'content': content,
      'createdAt': createdAt,
      'username': username,
      'isAdmin': isAdmin ? 1 : 0,
    };
    if (imageUrl != null) {
      map['imageUrl'] = imageUrl;
    }
    if (emoticonCode != null) {
      map['emoticonCode'] = emoticonCode;
    }
    if (parentId != null) {
      map['parentId'] = parentId;
    }
    return map;
  }
}
