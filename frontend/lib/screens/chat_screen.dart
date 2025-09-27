// frontend/lib/screens/chat_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/socket_service.dart';
import '../models/chat_message.dart';
import '../config/api_config.dart';
import '../screens/user_profile_screen.dart';

class ChatScreen extends StatefulWidget {
  final int targetUserId;
  final String targetUsername;

  const ChatScreen({
    super.key,
    required this.targetUserId,
    required this.targetUsername,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AuthService _authService = AuthService();
  final ChatService _chatService = ChatService();
  final SocketService _socketService = SocketService(); // TAMBAH INI

  late int _currentUserId;
  bool _isLoading = true;
  bool _sending = false;
  bool _isCurrentUserAdmin = false;

  List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<ChatMessage>? _messageSubscription; // TAMBAH INI
  StreamSubscription<Map<String, dynamic>>?
      _messageDeletedSubscription; // TAMBAH INI

  // Temp state untuk attachments
  File? _selectedImageFile;
  String? _selectedEmoticon;
  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _messageDeletedSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initChat() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }
      _currentUserId = user.id;
      _isCurrentUserAdmin = user.isAdmin;
    } catch (e) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
      return;
    }

    await _fetchChatHistory();
    await _initializeSocketService(); // GANTI DENGAN INI
    _setupSocketListeners(); // TAMBAH INI
    _markMessagesAsRead();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchChatHistory() async {
    try {
      final msgs =
          await _chatService.getMessages(_currentUserId, widget.targetUserId);
      if (mounted) {
        setState(() {
          _messages = msgs;
        });
        // Scroll ke bawah setelah data muncul
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat riwayat chat: $e')),
        );
      }
    }
  }

  Future<void> _initializeSocketService() async {
    await _socketService.initialize(_currentUserId);
  }

  void _setupSocketListeners() {
    // Listen untuk pesan baru
    _messageSubscription = _socketService.messageStream.listen((message) {
      // Jika pesan antara currentUser dan targetUserId
      if ((message.senderId == _currentUserId &&
              message.receiverId == widget.targetUserId) ||
          (message.senderId == widget.targetUserId &&
              message.receiverId == _currentUserId)) {
        if (mounted) {
          setState(() {
            // Cek apakah pesan sudah ada untuk menghindari duplikasi
            final existingIndex =
                _messages.indexWhere((m) => m.id == message.id);
            if (existingIndex == -1) {
              _messages.add(message);
            }
          });
          _scrollToBottom();
        }
      }
    });

    // Listen untuk pesan yang dihapus
    _messageDeletedSubscription =
        _socketService.messageDeletedStream.listen((data) {
      try {
        final messageId = int.parse(data['id'].toString());
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m.id == messageId);
          });
        }
      } catch (e) {
        debugPrint('Error parsing messageDeleted: $e');
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage({
    String? content,
    File? imageFile,
    String? imageUrl,
    // Tambahkan parameter untuk lokasi dan emoticon
    double? latitude,
    double? longitude,
    String? emoticon,
  }) async {
    if (_sending) return;
    if ((content == null || content.trim().isEmpty) &&
        imageFile == null &&
        latitude == null &&
        emoticon == null) {
      // nothing to send
      return;
    }
    setState(() {
      _sending = true;
    });

    String? imageUrl;
    if (imageFile != null) {
      try {
        // Perbaikan: gunakan _chatService.uploadImage
        imageUrl = await _chatService.uploadImage(imageFile);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal upload gambar: $e'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        imageUrl = null;
      }
    }

    try {
      final sent = await _chatService.sendMessage(
        senderId: _currentUserId,
        receiverId: widget.targetUserId,
        content: (content != null && content.trim().isNotEmpty)
            ? content.trim()
            : null,
        imageUrl: imageUrl,
        latitude: latitude,
        longitude: longitude,
        emoticonCode: emoticon,
      );
      // Pesan baru akan di-handle via real-time socket (newMessage)
      // TIDAK PERLU MENAMBAH KE _messages KARENA SOCKET AKAN MENANGANI
      if (mounted) {
        // Clear input
        _textController.clear();
        _selectedImageFile = null;
        _selectedEmoticon = null;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim pesan: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _markMessagesAsRead() {
    // Emit event ke socket untuk menandai pesan sebagai sudah dibaca
    _socketService.emit('markAsRead', {
      'userId': _currentUserId,
      'partnerId': widget.targetUserId,
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tandai pesan sebagai sudah dibaca ketika user melihat chat
    if (!_isLoading && _currentUserId > 0) {
      _markMessagesAsRead();
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final imageFile = File(picked.path);
        final imageUrl = await _chatService.uploadImage(imageFile);
        await _sendMessage(imageFile: imageFile, imageUrl: imageUrl);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error memilih atau mengirim gambar: $e')),
        );
      }
    }
  }

  Future<void> _shareLocation() async {
    try {
      Location location = Location();
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) return;
      }
      var permissionStatus = await location.hasPermission();
      if (permissionStatus == PermissionStatus.denied) {
        permissionStatus = await location.requestPermission();
        if (permissionStatus != PermissionStatus.granted) return;
      }
      final locData = await location.getLocation();
      if (locData.latitude != null && locData.longitude != null) {
        // Kirim pesan lokasi
        await _sendMessage(
          latitude: locData.latitude,
          longitude: locData.longitude,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil lokasi: $e')),
        );
      }
    }
  }

  Future<void> _pickEmoticon() async {
    const List<String> emoticons = [
      '😀',
      '😊',
      '😷',
      '🚑',
      '❤️',
      '👍',
      '🙌',
      '😃',
      '😢',
      '😡'
    ];
    String? picked;
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return GridView.count(
          crossAxisCount: 5,
          padding: const EdgeInsets.all(8),
          children: emoticons.map((e) {
            return GestureDetector(
              onTap: () {
                picked = e;
                Navigator.of(ctx).pop();
              },
              child:
                  Center(child: Text(e, style: const TextStyle(fontSize: 24))),
            );
          }).toList(),
        );
      },
    );
    if (picked != null) {
      if (mounted) {
        // simpan emoticon terpilih
        setState(() {
          _selectedEmoticon = picked;
        });
        // Kirim emoticon langsung begitu dipilih tanpa perlu tombol kirim
        _sendMessage(emoticon: picked);
      }
    }
  }

  Future<void> _deleteMessage(int messageId) async {
    try {
      await _chatService.deleteMessage(messageId);
      setState(() {
        _messages.removeWhere((m) => m.id == messageId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pesan dihapus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus pesan: $e')),
        );
      }
    }
  }

  // FITUR BARU: Hapus semua obrolan
  Future<void> _clearAllMessages() async {
    // Tampilkan dialog konfirmasi
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Hapus Semua Obrolan'),
          content: const Text(
            'Apakah Anda yakin ingin menghapus semua pesan dalam obrolan ini? Tindakan ini tidak dapat dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Hapus Semua'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        // Hapus semua pesan dari server
        await _chatService.clearAllMessages(
            _currentUserId, widget.targetUserId);

        // Bersihkan pesan dari local state
        if (mounted) {
          setState(() {
            _messages.clear();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Semua pesan telah dihapus')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menghapus semua pesan: $e')),
          );
        }
      }
    }
  }

  // FITUR BARU: Tampilkan menu opsi
  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_sweep, color: Colors.red),
                title: const Text('Hapus Semua Obrolan'),
                onTap: () {
                  Navigator.of(context).pop();
                  _clearAllMessages();
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Batal'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageItem(ChatMessage msg) {
    final bool isMe = msg.senderId == _currentUserId;
    final alignment = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final bgColor = isMe ? Colors.blue[200] : Colors.grey[300];
    const textColor = Colors.black87;
    Widget contentWidget;

    if (msg.imageUrl != null) {
      contentWidget = GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              child: Image.network(
                msg.imageUrl!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    const Text('Gagal memuat gambar'),
              ),
            ),
          );
        },
        child: Image.network(
          msg.imageUrl!,
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) =>
              const Text('Gagal memuat gambar'),
        ),
      );
    } else if (msg.latitude != null && msg.longitude != null) {
      contentWidget = GestureDetector(
        onTap: () {
          // Anda dapat membuka peta detail ketika lokasi di-tap
        },
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on, color: Colors.red),
            Text('Lokasi: ${msg.latitude}, ${msg.longitude}',
                style: const TextStyle(color: textColor)),
          ],
        ),
      );
    } else if (msg.emoticonCode != null) {
      contentWidget = Text(
        msg.emoticonCode!,
        style: const TextStyle(fontSize: 32),
      );
    } else {
      contentWidget = Text(
        msg.content ?? '',
        style: const TextStyle(color: textColor),
      );
    }

    // Tampilkan timestamp di bawah
    DateTime ts = DateTime.now();
    if (msg.createdAt != null) {
      ts = DateTime.parse(msg.createdAt!).toLocal();
    }
    final timeText = TimeOfDay.fromDateTime(ts).format(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: contentWidget),
                  if (isMe)
                    IconButton(
                      icon: const Icon(Icons.delete, size: 16),
                      onPressed: () => _deleteMessage(msg.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              timeText,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Chat dengan ${widget.targetUsername}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          // TAMBAHKAN INI - Icon profile khusus admin
          if (_isCurrentUserAdmin)
            IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(
                      userId: widget.targetUserId,
                    ),
                  ),
                );
              },
            ),
          // FITUR BARU: Tombol menu opsi di AppBar
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showChatOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Pesan list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return _buildMessageItem(msg);
                    },
                  ),
          ),
          // Input area
          if (!_isLoading)
            SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  border: Border(top: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image),
                      onPressed: _pickImage,
                    ),
                    IconButton(
                      icon: const Icon(Icons.location_on),
                      onPressed: _shareLocation,
                    ),
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions),
                      onPressed: _pickEmoticon,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (text) {
                          // Guard: pastikan IDs valid sebelum kirim
                          if (_currentUserId <= 0 || widget.targetUserId <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('ID pengguna tidak valid')),
                            );
                            return;
                          }
                          _sendMessage(content: text);
                        },
                        decoration: const InputDecoration(
                          hintText: 'Ketik pesan...',
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: _sending
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      onPressed: () {
                        // Guard: pastikan IDs valid sebelum kirim
                        if (_currentUserId <= 0 || widget.targetUserId <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('ID pengguna tidak valid')),
                          );
                          return;
                        }
                        _sendMessage(
                          content: _textController.text,
                          imageFile: _selectedImageFile,
                          emoticon: _selectedEmoticon,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
