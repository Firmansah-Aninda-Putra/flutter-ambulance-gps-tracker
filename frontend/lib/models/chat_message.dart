// frontend/lib/models/chat_message.dart

class ChatMessage {
  final int id;
  final int senderId;
  final int receiverId;
  final String? content;
  final String? imageUrl;
  final double? latitude;
  final double? longitude;
  final String? emoticonCode;
  final String? createdAt;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.content,
    this.imageUrl,
    this.latitude,
    this.longitude,
    this.emoticonCode,
    this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // parsing numeric fields dengan aman
    int parseInt(dynamic v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? 0;
      if (v is double) return v.toInt();
      return 0;
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) {
        return double.tryParse(v);
      }
      return null;
    }

    return ChatMessage(
      id: parseInt(json['id']),
      senderId: parseInt(json['senderId']),
      receiverId: parseInt(json['receiverId']),
      // Ganti explicit null check dengan null-aware operator:
      content: json['content']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      emoticonCode: json['emoticonCode']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'senderId': senderId,
      'receiverId': receiverId,
    };
    if (content != null && content!.isNotEmpty) {
      data['content'] = content;
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      data['imageUrl'] = imageUrl;
    }
    if (latitude != null && longitude != null) {
      data['latitude'] = latitude;
      data['longitude'] = longitude;
    }
    if (emoticonCode != null && emoticonCode!.isNotEmpty) {
      data['emoticonCode'] = emoticonCode;
    }
    return data;
  }
}
