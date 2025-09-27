import 'package:intl/intl.dart';

class CallHistoryItem {
  final int id;
  final int userId;
  final String userName;
  final DateTime calledAt;

  CallHistoryItem({
    required this.id,
    required this.userId,
    required this.userName,
    required this.calledAt,
  });

  /// Factory untuk parsing dari JSON
  factory CallHistoryItem.fromJson(Map<String, dynamic> json) {
    return CallHistoryItem(
      id: json['id'],
      userId: json['userId'] ??
          json['user_id'], // jaga-jaga jika backend kirim 'user_id'
      userName: json['userName'] ?? '',
      calledAt: DateTime.parse(json['calledAt'] ?? json['called_at']).toLocal(),
    );
  }

  /// Format waktu agar bisa langsung ditampilkan
  String get formattedDate {
    return DateFormat('dd MMM yyyy, HH:mm').format(calledAt);
  }

  /// Bisa digunakan sebagai judul utama di inbox
  String get title => userName;

  /// Bisa digunakan sebagai subtitle di inbox
  String get subtitle => formattedDate;
}
