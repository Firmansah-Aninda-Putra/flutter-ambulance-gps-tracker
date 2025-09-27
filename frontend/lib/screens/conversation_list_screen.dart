// frontend/lib/screens/conversation_list_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../models/chat_message.dart';
import '../models/conversation_summary.dart';
import '../services/socket_service.dart';
import 'chat_screen.dart';

class ConversationListScreen extends StatefulWidget {
  final int currentUserId;

  const ConversationListScreen({super.key, required this.currentUserId});

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final SocketService _socketService = SocketService();
  final ChatService _chatService = ChatService();

  bool _isLoading = true;
  List<ConversationSummary> _conversations = [];
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<Map<String, dynamic>>? _messageDeletedSub;

  // ✅ TAMBAHAN: Set untuk menyimpan conversation yang memiliki unread messages
  final Set<int> _unreadConversations = <int>{};

  @override
  void initState() {
    super.initState();
    _initializeRealTimeFeatures();
  }

  Future<void> _initializeRealTimeFeatures() async {
    // Inisialisasi socket connection
    await _socketService.initialize(widget.currentUserId);

    // Load conversations pertama kali
    await _loadConversations();

    // Setup real-time listeners
    _subscribeToMessages();
    _subscribeToMessageDeleted();
  }

  void _subscribeToMessages() {
    _msgSub = _socketService.messageStream.listen((msg) {
      // ✅ PERBAIKAN: Handle pesan masuk secara real-time
      if (msg.receiverId == widget.currentUserId ||
          msg.senderId == widget.currentUserId) {
        debugPrint('New message received in conversation list, refreshing...');

        // Jika pesan diterima oleh current user, tandai sebagai unread
        if (msg.receiverId == widget.currentUserId) {
          setState(() {
            _unreadConversations.add(msg.senderId);
          });
        }

        // Refresh conversations untuk update last message
        _loadConversations();
      }
    });
  }

  void _subscribeToMessageDeleted() {
    _messageDeletedSub = _socketService.messageDeletedStream.listen((data) {
      // ✅ Refresh conversations ketika ada pesan yang dihapus
      debugPrint('Message deleted, refreshing conversations...');
      _loadConversations();
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _messageDeletedSub?.cancel();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      final convs = await _chatService.getConversations(widget.currentUserId);
      if (mounted) {
        setState(() {
          _conversations = convs;
          _isLoading = false;

          // ✅ PERBAIKAN: Update unread conversations berdasarkan data dari server
          _unreadConversations.clear();
          for (var conv in convs) {
            if ((conv.unreadCount ?? 0) > 0) {
              _unreadConversations.add(conv.partnerId);
            }
          }
        });

        debugPrint('Conversations loaded: ${convs.length}');
        debugPrint('Unread conversations: $_unreadConversations');

        // Debug unread counts
        for (var conv in convs) {
          debugPrint(
              'Partner ${conv.partnerId}: ${conv.unreadCount} unread messages');
        }
      }
    } catch (e) {
      debugPrint('Error loading conversations: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat inbox: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // ✅ TAMBAHAN: Method untuk menandai conversation sebagai sudah dibaca
  void _markConversationAsRead(int partnerId) {
    setState(() {
      _unreadConversations.remove(partnerId);
    });

    // Update conversation di list untuk menghilangkan unread count
    setState(() {
      _conversations = _conversations.map((conv) {
        if (conv.partnerId == partnerId) {
          return ConversationSummary(
            partnerId: conv.partnerId,
            partnerName: conv.partnerName,
            lastMessage: conv.lastMessage,
            lastTimestamp: conv.lastTimestamp,
            unreadCount: 0, // Reset unread count
          );
        }
        return conv;
      }).toList();
    });
  }

  void _clearConversations() {
    setState(() {
      _conversations.clear();
      _unreadConversations.clear();
    });
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return TimeOfDay.fromDateTime(dt).format(context);
    } else {
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} '
          '${TimeOfDay.fromDateTime(dt).format(context)}';
    }
  }

  String _previewLastMessage(ConversationSummary conv) {
    final lastMsg = conv.lastMessage;
    if (lastMsg == null) return '';
    if (lastMsg.content != null && lastMsg.content!.isNotEmpty) {
      final text = lastMsg.content!;
      return text.length <= 30 ? text : '${text.substring(0, 30)}...';
    } else if (lastMsg.imageUrl != null && lastMsg.imageUrl!.isNotEmpty) {
      return '[Gambar]';
    } else if (lastMsg.latitude != null && lastMsg.longitude != null) {
      return '[Lokasi]';
    } else if (lastMsg.emoticonCode != null &&
        lastMsg.emoticonCode!.isNotEmpty) {
      return lastMsg.emoticonCode!;
    }
    return '[Pesan baru]';
  }

  // ✅ PERBAIKAN: Widget untuk badge unread message yang dapat diklik
  Widget _buildUnreadBadge(int partnerId, int unreadCount) {
    // Gabungkan unread count dari server dan local state
    final hasUnread =
        _unreadConversations.contains(partnerId) || unreadCount > 0;
    final displayCount = unreadCount > 0
        ? unreadCount
        : (_unreadConversations.contains(partnerId) ? 1 : 0);

    if (!hasUnread) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        // ✅ TAMBAHAN: Ketika badge diklik, tandai sebagai sudah dibaca
        _markConversationAsRead(partnerId);

        // Show feedback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pesan ditandai sebagai sudah dibaca'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        constraints: const BoxConstraints(
          minWidth: 20,
          minHeight: 20,
        ),
        child: Text(
          displayCount > 99 ? '99+' : displayCount.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Bersihkan Inbox',
            onPressed: _clearConversations,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _isLoading = true);
              _loadConversations();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Belum ada percakapan',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadConversations,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _conversations.length,
                    separatorBuilder: (_, __) => Divider(
                      color: Colors.grey.shade300,
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final conv = _conversations[index];
                      final partnerId = conv.partnerId;
                      final titleText = conv.partnerName ?? 'User $partnerId';
                      final subtitleText = _previewLastMessage(conv);
                      final timeText = _formatTimestamp(conv.lastTimestamp);

                      // ✅ PERBAIKAN: Gabungkan unread count dari server dan local state
                      final serverUnreadCount = conv.unreadCount ?? 0;
                      final hasLocalUnread =
                          _unreadConversations.contains(partnerId);
                      final hasUnread = hasLocalUnread || serverUnreadCount > 0;
                      final displayUnreadCount = serverUnreadCount > 0
                          ? serverUnreadCount
                          : (hasLocalUnread ? 1 : 0);

                      return ListTile(
                        title: Text(
                          titleText,
                          style: TextStyle(
                            fontWeight:
                                hasUnread ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: subtitleText.isNotEmpty
                            ? Text(
                                subtitleText,
                                style: TextStyle(
                                  fontWeight: hasUnread
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: hasUnread
                                      ? Colors.black87
                                      : Colors.grey[600],
                                ),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (timeText.isNotEmpty)
                              Text(
                                timeText,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hasUnread ? Colors.green : Colors.grey,
                                  fontWeight: hasUnread
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            _buildUnreadBadge(partnerId, displayUnreadCount),
                          ],
                        ),
                        tileColor: hasUnread ? Colors.blue.withAlpha(25) : null,
                        onTap: () {
                          if (partnerId <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Partner ID tidak valid')),
                            );
                            return;
                          }

                          // ✅ TAMBAHAN: Tandai sebagai sudah dibaca ketika conversation dibuka
                          _markConversationAsRead(partnerId);

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                targetUserId: partnerId,
                                targetUsername: titleText,
                              ),
                            ),
                          ).then((_) {
                            // Refresh conversations setelah kembali dari chat
                            _loadConversations();
                          });
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
