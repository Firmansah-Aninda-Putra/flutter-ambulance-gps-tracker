import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../models/comment_model.dart';
import '../models/user_model.dart';
import '../services/comment_service.dart';
import '../services/auth_service.dart'; // Import untuk AuthService
import '../screens/user_profile_screen.dart';
import '../config/api_config.dart';

class CommentWidget extends StatefulWidget {
  final User? currentUser;
  final int ambulanceId;

  const CommentWidget({
    super.key,
    required this.currentUser,
    required this.ambulanceId,
  });

  @override
  State<CommentWidget> createState() => _CommentWidgetState();
}

class _CommentWidgetState extends State<CommentWidget> {
  final CommentService _commentService = CommentService();
  final TextEditingController _commentController = TextEditingController();
  List<Comment> _comments = [];
  bool _isLoading = true;
  bool _isRefreshing = false; // Flag untuk menandakan sedang refresh

  socket_io.Socket? _socket;

  File? _selectedImageFile;
  String? _selectedImageUrl;
  String? _selectedEmoticonCode;

  int? _replyToCommentId;
  String? _replyToUsername;

  @override
  void initState() {
    super.initState();

    // ✅ Tambahan validasi keamanan: redirect jika belum login
    if (widget.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/login');
      });
      return;
    }

    _fetchComments();
    _initSocket();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _commentController.dispose();
    super.dispose();
  }

  void _initSocket() {
    try {
      _socket = socket_io.io(ApiConfig.socketUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
      });

      _socket?.connect();

      _socket?.on('connect', (_) {
        debugPrint('Socket connected to ${ApiConfig.socketUrl}');
      });

      _socket?.on('disconnect', (_) {
        debugPrint('Socket disconnected');
      });

      _socket?.on('newComment', (data) {
        debugPrint('Received new comment: $data');
        if (mounted && data != null) {
          try {
            final newComment = Comment.fromJson(data as Map<String, dynamic>);
            setState(() {
              _comments.insert(0, newComment);
            });
          } catch (e) {
            debugPrint('Error parsing new comment: $e');
          }
        }
      });

      _socket?.on('deletedComment', (data) {
        if (mounted && data != null && data['id'] != null) {
          final commentId = data['id'] as int;
          setState(() {
            _comments.removeWhere((c) => c.id == commentId);
          });
        }
      });

      _socket?.on('connect_error', (error) {
        debugPrint('Socket connection error: $error');
      });
    } catch (e) {
      debugPrint('Error initializing socket: $e');
    }
  }

  Future<void> _fetchComments() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final comments = await _commentService.getComments();
      setState(() {
        _comments = comments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load comments: $e')),
      );
    }
  }

  // ✅ Fungsi khusus untuk refresh yang dipanggil oleh RefreshIndicator
  Future<void> _refreshComments() async {
    if (_isRefreshing) return; // Hindari multiple refresh bersamaan

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Fetch komentar terbaru dari server
      final comments = await _commentService.getComments();

      if (mounted) {
        setState(() {
          _comments = comments;
          _isRefreshing = false;
        });

        // Tampilkan feedback bahwa refresh berhasil
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Komentar berhasil diperbarui'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui komentar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        setState(() {
          _selectedImageFile = File(picked.path);
        });
        try {
          final url = await _commentService.uploadImage(_selectedImageFile!);
          setState(() {
            _selectedImageUrl = url;
          });
        } catch (e) {
          setState(() {
            _selectedImageFile = null;
            _selectedImageUrl = null;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal mengunggah gambar: $e')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error memilih gambar: $e')),
        );
      }
    }
  }

  Future<void> _pickEmoticon() async {
    final List<String> emoticons = [
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
      setState(() {
        _selectedEmoticonCode = picked;
      });
    }
  }

  String get _contentText => _commentController.text.trim();

  bool get _canSend {
    if (widget.currentUser == null) return false;
    final hasText = _contentText.isNotEmpty;
    final hasImage = _selectedImageUrl != null;
    final hasEmoticon = _selectedEmoticonCode != null;
    return hasText || hasImage || hasEmoticon;
  }

  Future<void> _postComment() async {
    if (!_canSend) return;
    final contentText = _contentText;
    setState(() {
      _isLoading = true;
    });

    try {
      await _commentService.postComment(
        widget.currentUser!.id,
        content: contentText.isNotEmpty ? contentText : null,
        ambulanceId: widget.ambulanceId,
        parentId: _replyToCommentId,
        imageUrl: _selectedImageUrl,
        emoticonCode: _selectedEmoticonCode,
      );

      final now = DateTime.now().toUtc().toIso8601String();
      final newComment = Comment(
        id: -1,
        userId: widget.currentUser!.id,
        ambulanceId: widget.ambulanceId,
        content: contentText,
        imageUrl: _selectedImageUrl,
        emoticonCode: _selectedEmoticonCode,
        parentId: _replyToCommentId,
        createdAt: now,
        username: widget.currentUser!.username,
        isAdmin: widget.currentUser!.isAdmin,
      );

      setState(() {
        _comments.insert(0, newComment);
        _commentController.clear();
        _selectedImageFile = null;
        _selectedImageUrl = null;
        _selectedEmoticonCode = null;
        _replyToCommentId = null;
        _replyToUsername = null;
      });

      // Refresh setelah posting komentar untuk memastikan sinkronisasi
      await Future.delayed(const Duration(milliseconds: 500));
      await _refreshComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to post comment: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startReply(Comment comment) {
    setState(() {
      _replyToCommentId = comment.id;
      _replyToUsername = comment.username;
      _commentController.text = '@${comment.username} ';
    });
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToUsername = null;
      _commentController.clear();
    });
  }

  void _showDeleteConfirmation(int commentId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Komentar'),
        content: const Text('Apakah Anda yakin ingin menghapus komentar ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deleteComment(commentId);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteComment(int commentId) async {
    try {
      await _commentService.deleteComment(commentId);
      setState(() {
        _comments.removeWhere((c) => c.id == commentId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Komentar dihapus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus komentar: $e')),
        );
      }
    }
  }

  void _showFullScreenImage(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                height: MediaQuery.of(context).size.height,
                width: MediaQuery.of(context).size.width,
                errorBuilder: (context, error, stackTrace) {
                  return const Text('Gagal memuat gambar');
                },
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _isLoading && _comments.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _comments.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Belum ada komentar'),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _refreshComments,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      // ✅ Tambahkan RefreshIndicator untuk pull-to-refresh
                      onRefresh: _refreshComments,
                      backgroundColor: Colors.white,
                      color: Theme.of(context).primaryColor,
                      strokeWidth: 2.0,
                      displacement: 40.0,
                      child: ListView.builder(
                        physics:
                            const AlwaysScrollableScrollPhysics(), // Penting untuk pull-to-refresh
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final comment = _comments[index];
                          DateTime ts =
                              DateTime.tryParse(comment.createdAt)?.toLocal() ??
                                  DateTime.now();
                          final formattedDate =
                              DateFormat('dd MMM yyyy, HH:mm').format(ts);

                          return GestureDetector(
                            onTap: () {
                              // Cek apakah pengguna adalah admin
                              if (widget.currentUser != null &&
                                  widget.currentUser!.isAdmin) {
                                if (comment.userId < 1) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('ID pengguna tidak valid'),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (ctx) => UserProfileScreen(
                                        userId: comment.userId),
                                  ),
                                );
                              } else {
                                // Jika bukan admin, tampilkan pesan
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Hanya admin yang dapat melihat profil pengguna.'),
                                  ),
                                );
                              }
                            },
                            child: ListTile(
                              title: Row(
                                children: [
                                  Text(
                                    comment.username,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  if (comment.isAdmin)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4.0),
                                      child: Icon(
                                        Icons.verified,
                                        color: Colors.blue,
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (comment.imageUrl != null)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 4.0),
                                      child: GestureDetector(
                                        onTap: () => _showFullScreenImage(
                                            comment.imageUrl!),
                                        child: Image.network(
                                          comment.imageUrl!,
                                          width: 100,
                                          height: 100,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stack) {
                                            return const Text(
                                                'Gagal memuat gambar');
                                          },
                                        ),
                                      ),
                                    ),
                                  if (comment.emoticonCode != null)
                                    Text(
                                      comment.emoticonCode!,
                                      style: const TextStyle(fontSize: 24),
                                    ),
                                  if (comment.content.isNotEmpty)
                                    Text(comment.content),
                                  const SizedBox(height: 4),
                                  Text(
                                    formattedDate,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.reply, size: 20),
                                    tooltip: 'Balas komentar',
                                    onPressed: () => _startReply(comment),
                                  ),
                                  if (widget.currentUser != null &&
                                      (widget.currentUser!.id ==
                                              comment.userId ||
                                          widget.currentUser!.isAdmin))
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 20),
                                      tooltip: 'Hapus komentar',
                                      onPressed: () =>
                                          _showDeleteConfirmation(comment.id),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
        // ✅ Tambahkan status indicator ketika sedang refresh
        if (_isRefreshing)
          Container(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Memperbarui komentar...',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        if (widget.currentUser != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                // === Preview Reply & Tombol Batal Reply ===
                if (_replyToCommentId != null && _replyToUsername != null)
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    margin: const EdgeInsets.only(bottom: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('Membalas @$_replyToUsername'),
                        ),
                        GestureDetector(
                          onTap: _cancelReply,
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                if (_selectedImageFile != null || _selectedEmoticonCode != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        if (_selectedImageFile != null)
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              Image.file(
                                _selectedImageFile!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedImageFile = null;
                                    _selectedImageUrl = null;
                                  });
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (_selectedEmoticonCode != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Stack(
                              alignment: Alignment.topRight,
                              children: [
                                Text(
                                  _selectedEmoticonCode!,
                                  style: const TextStyle(fontSize: 32),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedEmoticonCode = null;
                                    });
                                  },
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.image),
                      tooltip: 'Attach gambar',
                      onPressed: _pickImage,
                    ),
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions),
                      tooltip: 'Pilih emotikon',
                      onPressed: _pickEmoticon,
                    ),
                    // ✅ Tambahkan tombol refresh manual
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: _isRefreshing ? Colors.grey : null,
                      ),
                      tooltip: 'Refresh komentar',
                      onPressed: _isRefreshing ? null : _refreshComments,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        decoration: const InputDecoration(
                          hintText: 'Ketik komentar...',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (text) {
                          setState(() {});
                        },
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.send,
                        color: _canSend
                            ? Theme.of(context).primaryColor
                            : Colors.grey,
                      ),
                      onPressed: _canSend ? _postComment : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
