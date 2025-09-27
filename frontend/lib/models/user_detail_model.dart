class UserDetail {
  final int id;
  final String username;
  final String fullName;
  final String address;
  final String phone;
  final bool isAdmin;
  final String createdAt;

  UserDetail({
    required this.id,
    required this.username,
    required this.fullName,
    required this.address,
    required this.phone,
    required this.isAdmin,
    required this.createdAt,
  });

  factory UserDetail.fromJson(Map<String, dynamic> json) {
    // Validasi ID user harus ≥ 1
    final rawId = json['id'];
    final id = (rawId is int && rawId >= 1)
        ? rawId
        : throw const FormatException('Invalid user ID in JSON');

    return UserDetail(
      id: id,
      username: json['username'] ?? '',
      fullName: json['fullName'] ?? '',
      address: json['address'] ?? '',
      phone: json['phone'] ?? '',
      isAdmin: json['isAdmin'] == 1 || json['isAdmin'] == true,
      createdAt: json['createdAt'] ?? '',
    );
  }
}
