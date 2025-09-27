import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/socket_service.dart';
import '../models/user_detail_model.dart';
import '../models/chat_message.dart';
import '../models/user_model.dart';

class UserProfileScreen extends StatefulWidget {
  final int userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<UserDetail> _futureUserDetail;
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  final SocketService _socketService = SocketService();

  File? _profileImage;
  final ImagePicker _picker = ImagePicker();

  // State untuk pesan admin
  List<ChatMessage> _adminMessages = [];
  int _unreadAdminCount = 0;
  int? _currentUserId;
  int? _adminId;
  StreamSubscription<ChatMessage>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _initializeProfile();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeProfile() async {
    // Validasi ID sebelum memanggil API
    if (widget.userId < 1) {
      _futureUserDetail = Future.error('Invalid user ID');
      return;
    }

    _futureUserDetail = _authService.getUserDetail(widget.userId);

    // Initialize untuk pesan admin jika user bukan admin
    try {
      final currentUser = await _authService.getCurrentUser();
      if (currentUser != null) {
        _currentUserId = currentUser.id;

        // Cek apakah user adalah admin
        if (!currentUser.isAdmin) {
          await _initializeAdminMessages();
        }
      }
    } catch (e) {
      debugPrint('Error initializing profile: $e');
    }
  }

  Future<void> _initializeAdminMessages() async {
    try {
      // Dapatkan admin ID
      _adminId = await _chatService.getAdminId();

      // Load pesan dari admin
      await _loadAdminMessages();

      // Initialize socket service untuk real-time
      await _socketService.initialize(_currentUserId!);

      // Listen untuk pesan baru dari admin
      _messageSubscription = _socketService.messageStream.listen((message) {
        if (message.senderId == _adminId &&
            message.receiverId == _currentUserId) {
          if (mounted) {
            setState(() {
              _adminMessages.add(message);
              _unreadAdminCount++;
            });
          }
        }
      });
    } catch (e) {
      debugPrint('Error initializing admin messages: $e');
    }
  }

  Future<void> _loadAdminMessages() async {
    if (_adminId == null || _currentUserId == null) return;

    try {
      final messages =
          await _chatService.getMessages(_currentUserId!, _adminId!);
      if (mounted) {
        setState(() {
          _adminMessages =
              messages.where((m) => m.senderId == _adminId).toList();
          _unreadAdminCount = _adminMessages.length;
        });
      }
    } catch (e) {
      debugPrint('Error loading admin messages: $e');
    }
  }

  Future<void> _pickProfileImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );

      if (image != null) {
        setState(() {
          _profileImage = File(image.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error memilih gambar: $e')),
        );
      }
    }
  }

  void _showAdminMessages() {
    if (_adminMessages.isEmpty) return;

    // Reset unread count
    setState(() {
      _unreadAdminCount = 0;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      'Pesan dari Admin',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(),
              // Messages list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _adminMessages.length,
                  itemBuilder: (context, index) {
                    final message = _adminMessages[index];
                    return _buildAdminMessageItem(message);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdminMessageItem(ChatMessage message) {
    final timestamp = message.createdAt != null
        ? DateTime.parse(message.createdAt!).toLocal()
        : DateTime.now();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.content != null)
              Text(
                message.content!,
                style: const TextStyle(fontSize: 14),
              ),
            if (message.imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    message.imageUrl!,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        const Text('Gagal memuat gambar'),
                  ),
                ),
              ),
            if (message.emoticonCode != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message.emoticonCode!,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              '${timestamp.day}/${timestamp.month}/${timestamp.year} ${TimeOfDay.fromDateTime(timestamp).format(context)}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Pengguna'),
        elevation: 0,
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<UserDetail>(
        future: _futureUserDetail,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            final errMsg = snapshot.error.toString();

            // Tangani error ID tidak valid
            if (errMsg.contains('Invalid user ID')) {
              return const Center(
                child: Text(
                  'ID pengguna tidak valid',
                  style: TextStyle(fontSize: 16, color: Colors.red),
                ),
              );
            }

            // Tangani khusus 404
            if (errMsg.contains('404') || errMsg.contains('User not found')) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.person_off,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Pengguna tidak ditemukan',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Kembali'),
                    ),
                  ],
                ),
              );
            }

            // Fallback untuk error lain
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Terjadi kesalahan: $errMsg',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.red),
                  ),
                ],
              ),
            );
          } else if (!snapshot.hasData) {
            return const Center(
              child: Text(
                'Data tidak ditemukan',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final user = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Profile Picture dan Info Container
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withAlpha(25),
                        spreadRadius: 1,
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Profile Picture
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: _profileImage != null
                                ? FileImage(_profileImage!)
                                : null,
                            child: _profileImage == null
                                ? Icon(
                                    Icons.person,
                                    size: 60,
                                    color: Colors.grey[600],
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickProfileImage,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // User Info
                      _buildInfoRow(
                        icon: Icons.person,
                        label: 'Nama Lengkap',
                        value: user.fullName,
                      ),
                      _buildInfoRow(
                        icon: Icons.account_circle,
                        label: 'Username',
                        value: user.username,
                      ),
                      _buildInfoRow(
                        icon: Icons.location_on,
                        label: 'Alamat',
                        value: user.address,
                      ),
                      _buildInfoRow(
                        icon: Icons.phone,
                        label: 'No. HP',
                        value: user.phone,
                      ),
                      _buildInfoRow(
                        icon: Icons.admin_panel_settings,
                        label: 'Status',
                        value: user.isAdmin ? 'Admin' : 'User',
                        valueColor: user.isAdmin ? Colors.red : Colors.green,
                      ),
                      _buildInfoRow(
                        icon: Icons.calendar_today,
                        label: 'Terdaftar',
                        value: user.createdAt,
                        isLastItem: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Admin Messages Card (hanya untuk user non-admin)
                if (_currentUserId != null && !user.isAdmin && _adminId != null)
                  GestureDetector(
                    onTap: _showAdminMessages,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.admin_panel_settings,
                                    color: Colors.blue[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Pesan dari Admin',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _adminMessages.isEmpty
                                    ? 'Belum ada pesan dari admin'
                                    : 'Tap untuk melihat ${_adminMessages.length} pesan',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue[600],
                                ),
                              ),
                            ],
                          ),
                          // Badge notifikasi
                          if (_unreadAdminCount > 0)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  _unreadAdminCount > 9
                                      ? '9+'
                                      : '$_unreadAdminCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool isLastItem = false,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: valueColor ?? Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!isLastItem) ...[
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
