import 'dart:async';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../services/socket_service.dart';
import '../services/ambulance_service.dart';
import '../services/auth_service.dart';
import '../models/chat_message.dart';
import '../models/call_history_item.dart';
import '../config/api_config.dart';
import 'chat_screen.dart';
import 'conversation_list_screen.dart';
import 'user_profile_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with WidgetsBindingObserver {
  final AmbulanceService _ambulanceService = AmbulanceService();
  final AuthService _authService = AuthService();
  final SocketService _socketService = SocketService();

  bool _isLocationTrackingEnabled = false;
  bool _isBusy = false;
  String _locationStatus = 'Lokasi tidak aktif';
  bool _isTrackingServerEnabled = true;

  late int _adminId;
  late int _currentUserId;

  // SUBSCRIPTION VARIABLES
  StreamSubscription<ChatMessage>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _ambulanceLocationSubscription;
  StreamSubscription<Map<String, dynamic>>? _trackingStatusSubscription;
  StreamSubscription<CallHistoryItem>? _newCallSubscription;
  StreamSubscription<Map<String, dynamic>>? _callDeletedSubscription;
  StreamSubscription<Map<String, dynamic>>? _allCallsClearedSubscription;
  List<CallHistoryItem> _callHistory = [];
  Timer? _periodicTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAdminPanel();
    _initializeAdminSocket();
    _setupSocketListeners();
    _fetchCallHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();

    // Cancel subscriptions
    _messageSubscription?.cancel();
    _ambulanceLocationSubscription?.cancel();
    _trackingStatusSubscription?.cancel();
    _newCallSubscription?.cancel();
    _callDeletedSubscription?.cancel();
    _allCallsClearedSubscription?.cancel();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _socketService.handleAppLifecycleChange(state);
    if (state == AppLifecycleState.resumed) {
      _initializeAdminPanel();
    }
  }

  Future<void> _initializeAdminPanel() async {
    await _fetchInitialStatus();
    await _loadSavedTrackingFlag();
    await _checkLocationService();
  }

  Future<void> _fetchInitialStatus() async {
    try {
      final ambLoc = await _ambulanceService.getAmbulanceLocation();
      debugPrint(
          'Initial status from server: isBusy=${ambLoc.isBusy}, trackingActive=${ambLoc.trackingActive}');

      setState(() {
        _isBusy = ambLoc.isBusy;
        _isTrackingServerEnabled = ambLoc.trackingActive ?? true;
      });
    } catch (e) {
      debugPrint('Error fetching initial status: $e');
      setState(() {
        _isTrackingServerEnabled = true;
      });
    }
  }

  Future<void> _loadSavedTrackingFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('trackingEnabled') ?? false;

      if (enabled && _isTrackingServerEnabled) {
        setState(() {
          _isLocationTrackingEnabled = true;
          _locationStatus = 'Pelacakan lokasi dilanjutkan';
        });
        _startPeriodicUpdates();
      } else {
        setState(() {
          _isLocationTrackingEnabled = false;
          _locationStatus = enabled && !_isTrackingServerEnabled
              ? 'Pelacakan server dinonaktifkan'
              : 'Pelacakan lokasi dinonaktifkan';
        });
      }
    } catch (e) {
      debugPrint('Error loading tracking flag: $e');
    }
  }

  Future<void> _checkLocationService() async {
    try {
      final loc = Location();
      bool serviceEnabled = await loc.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await loc.requestService();
      }
      PermissionStatus permissionGranted = await loc.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await loc.requestPermission();
      }
      if (serviceEnabled && permissionGranted == PermissionStatus.granted) {
        final location = await loc.getLocation();
        setState(() {
          _locationStatus =
              'Lokasi terdeteksi: ${location.latitude}, ${location.longitude}';
        });
      } else {
        setState(() {
          _locationStatus = 'Izin lokasi ditolak atau layanan mati';
        });
      }
    } catch (e) {
      setState(() {
        _locationStatus = 'Error cek layanan lokasi: $e';
      });
    }
  }

  Future<void> _toggleLocationTracking() async {
    final prefs = await SharedPreferences.getInstance();

    if (_isLocationTrackingEnabled) {
      _periodicTimer?.cancel();
      await prefs.setBool('trackingEnabled', false);

      setState(() {
        _isLocationTrackingEnabled = false;
        _locationStatus = 'Pelacakan lokasi dinonaktifkan';
      });

      _socketService.emit('toggleAmbulanceTracking', {'enabled': false});
    } else {
      if (!_isTrackingServerEnabled) {
        _socketService.emit('toggleAmbulanceTracking', {'enabled': true});
        await Future.delayed(const Duration(milliseconds: 500));
      }

      try {
        final loc = Location();
        bool serviceEnabled = await loc.serviceEnabled();
        if (!serviceEnabled) {
          serviceEnabled = await loc.requestService();
        }
        PermissionStatus permissionGranted = await loc.hasPermission();
        if (permissionGranted == PermissionStatus.denied) {
          permissionGranted = await loc.requestPermission();
        }
        if (!(serviceEnabled &&
            permissionGranted == PermissionStatus.granted)) {
          setState(() {
            _locationStatus = 'Izin lokasi tidak diberikan';
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Izin lokasi diperlukan untuk melacak lokasi.')),
          );
          return;
        }

        final location = await loc.getLocation();
        if (location.latitude != null && location.longitude != null) {
          await _ambulanceService.updateAmbulanceLocationAsAdmin(
            location.latitude!,
            location.longitude!,
            isBusy: _isBusy,
          );

          await prefs.setBool('trackingEnabled', true);

          if (!mounted) return;
          setState(() {
            _isLocationTrackingEnabled = true;
            _isTrackingServerEnabled = true;
            _locationStatus =
                'Pelacakan lokasi diaktifkan: ${location.latitude}, ${location.longitude}';
          });

          _startPeriodicUpdates();
          _socketService.emit('toggleAmbulanceTracking', {'enabled': true});
        } else {
          setState(() {
            _locationStatus = 'Tidak dapat mengakses lokasi';
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal mengakses lokasi.')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _locationStatus = 'Error: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengaktifkan pelacakan lokasi: $e')),
        );
      }
    }
  }

  void _startPeriodicUpdates() {
    _periodicTimer?.cancel();

    _periodicTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_isLocationTrackingEnabled || !mounted) {
        timer.cancel();
        return;
      }

      try {
        final loc = Location();
        final location = await loc.getLocation();
        if (location.latitude != null && location.longitude != null) {
          await _ambulanceService.updateAmbulanceLocationAsAdmin(
            location.latitude!,
            location.longitude!,
            isBusy: _isBusy,
          );

          if (mounted) {
            setState(() {
              _locationStatus =
                  'Lokasi diperbarui: ${location.latitude}, ${location.longitude}';
            });
          }
        }
      } catch (e) {
        debugPrint('Error updating location: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memperbarui lokasi: $e')),
          );
        }
      }
    });
  }

  Future<void> _toggleIsBusy(bool value) async {
    setState(() => _isBusy = value);

    try {
      await _ambulanceService.updateAmbulanceStatus(value);

      final ambLoc = await _ambulanceService.getAmbulanceLocation();
      if (mounted) {
        setState(() {
          _isBusy = ambLoc.isBusy;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Status diubah menjadi ${value ? 'Sibuk' : 'Bebas'}')),
        );
      }
    } catch (e) {
      debugPrint('Error updating isBusy: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memperbarui status: $e')),
      );

      setState(() => _isBusy = !value);
    }
  }

  Future<void> _initializeAdminSocket() async {
    try {
      final user = await _authService.getCurrentUser();
      if (user == null) return;
      _currentUserId = user.id;
      _adminId = _currentUserId;

      await _socketService.initialize(_adminId);
    } catch (e) {
      debugPrint('Error initializing admin socket: $e');
    }
  }

  void _setupSocketListeners() {
    // Listen untuk pesan baru
    _messageSubscription = _socketService.messageStream.listen((message) {
      if (message.receiverId == _adminId && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Pesan baru dari userId ${message.senderId}: ${_previewMessage(message)}'),
            action: SnackBarAction(
              label: 'Buka Chat',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      targetUserId: message.senderId,
                      targetUsername: 'User ${message.senderId}',
                    ),
                  ),
                );
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });

    // Listen untuk ambulance location updates
    _ambulanceLocationSubscription =
        _socketService.ambulanceLocationStream.listen((data) {
      debugPrint('Received ambulanceLocationUpdated in admin: $data');
      if (!mounted) return;
      setState(() {
        _locationStatus = '(${data['latitude']}, ${data['longitude']}) • '
            '${data['isBusy'] ? 'Sibuk' : 'Bebas'} • '
            '${data['addressText'] ?? '-'}';
        _isBusy = data['isBusy'];
        if (data['trackingActive'] != null) {
          _isTrackingServerEnabled = data['trackingActive'];
        }
      });
    });

    // Listen untuk tracking status updates
    _trackingStatusSubscription =
        _socketService.trackingStatusStream.listen((data) {
      debugPrint('Received tracking status update: $data');
      if (!mounted) return;
      setState(() {
        _isTrackingServerEnabled = data['trackingActive'] ?? true;
        if (data['trackingActive'] == false && _isLocationTrackingEnabled) {
          _periodicTimer?.cancel();
          _isLocationTrackingEnabled = false;
          SharedPreferences.getInstance().then((prefs) {
            prefs.setBool('trackingEnabled', false);
          });
        }
      });
    });

    // Listen untuk new call
    _newCallSubscription = _socketService.newCallStream.listen((call) {
      setState(() {
        _callHistory.insert(0, call);
        _callHistory.sort((a, b) => b.calledAt.compareTo(a.calledAt));
      });
    });

    // Listen untuk call deleted
    _callDeletedSubscription = _socketService.callDeletedStream.listen((data) {
      try {
        final id = data['id'];
        setState(() {
          _callHistory.removeWhere((c) => c.id == id);
          _callHistory.sort((a, b) => b.calledAt.compareTo(a.calledAt));
        });
      } catch (e) {
        debugPrint('Error parsing callDeleted: $e');
      }
    });
  }

  String _previewMessage(ChatMessage msg) {
    if (msg.content != null && msg.content!.isNotEmpty) {
      return msg.content!.length <= 30
          ? msg.content!
          : '${msg.content!.substring(0, 30)}...';
    }
    if (msg.imageUrl != null) return '[Gambar]';
    if (msg.latitude != null && msg.longitude != null) return '[Lokasi]';
    if (msg.emoticonCode != null) return msg.emoticonCode!;
    return '[Pesan baru]';
  }

  void _openInboxChat() async {
    try {
      final user = await _authService.getCurrentUser();
      if (!mounted) {
        return;
      }
      if (user != null && user.isAdmin) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConversationListScreen(
              currentUserId: user.id,
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session admin tidak valid')),
        );
      }
    } catch (e) {
      debugPrint('Error membuka inbox chat: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka inbox: $e')),
      );
    }
  }

  Future<void> _fetchCallHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isCallHistoryCleared =
          prefs.getBool('isCallHistoryCleared') ?? false;

      if (!isCallHistoryCleared) {
        final history = await _ambulanceService.getCallHistory();
        setState(() {
          _callHistory = history;
          _callHistory.sort((a, b) => b.calledAt.compareTo(a.calledAt));
        });
      } else {
        setState(() {
          _callHistory = [];
        });
      }
    } catch (e) {
      debugPrint('Error fetching call history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat riwayat panggilan: $e')),
        );
      }
    }
  }

  Future<void> _deleteCallHistory(int id) async {
    try {
      await _ambulanceService.deleteCallHistory(id);
      setState(() {
        _callHistory.removeWhere((c) => c.id == id);
        _callHistory.sort((a, b) => b.calledAt.compareTo(a.calledAt));
      });
    } catch (e) {
      debugPrint('Error deleting call history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus riwayat panggilan: $e')),
        );
      }
    }
  }

  Future<void> _clearAllCallHistory() async {
    // Tampilkan dialog konfirmasi
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Konfirmasi'),
          content: const Text(
            'Apakah Anda yakin ingin menghapus semua riwayat panggilan ambulan di sisi frontend?\n\nTindakan ini tidak dapat dibatalkan.',
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

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isCallHistoryCleared', false);

      setState(() {
        _callHistory.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Semua riwayat panggilan berhasil dihapus di sisi frontend'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error clearing all call history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus semua riwayat panggilan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToUserProfile(int userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Admin Ambulan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.inbox),
            tooltip: 'Inbox Chat',
            onPressed: _openInboxChat,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Panel Kontrol Ambulan',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status Lokasi GPS',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_locationStatus),
                      const SizedBox(height: 4),
                      Text(
                        'Server Tracking: ${_isTrackingServerEnabled ? 'Aktif' : 'Nonaktif'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isTrackingServerEnabled
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Switch(
                            value: _isLocationTrackingEnabled,
                            onChanged: (value) => _toggleLocationTracking(),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isLocationTrackingEnabled
                                      ? 'Pelacakan Aktif'
                                      : 'Pelacakan Nonaktif',
                                ),
                                if (!_isTrackingServerEnabled)
                                  const Text(
                                    'Server tracking dinonaktifkan',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Switch(
                            value: _isBusy,
                            onChanged: (value) => _toggleIsBusy(value),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isBusy
                                ? 'Status: Sibuk (Panggilan Lain)'
                                : 'Status: Bebas',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _initializeAdminPanel,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Status'),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Riwayat Panggilan',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_callHistory.isNotEmpty)
                            TextButton.icon(
                              onPressed: _clearAllCallHistory,
                              icon: const Icon(
                                Icons.clear_all,
                                size: 16,
                                color: Colors.red,
                              ),
                              label: const Text(
                                'Bersihkan Semua',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _callHistory.isEmpty
                          ? const Text('Belum ada riwayat panggilan')
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _callHistory.length,
                              itemBuilder: (context, index) {
                                final call = _callHistory[index];
                                return ListTile(
                                  title: InkWell(
                                    onTap: () =>
                                        _navigateToUserProfile(call.userId),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.person,
                                            size: 16, color: Colors.blue),
                                        const SizedBox(width: 4),
                                        Text(
                                          call.userName,
                                          style: const TextStyle(
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  subtitle: Text(call.formattedDate),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () =>
                                        _deleteCallHistory(call.id),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Informasi Penggunaan:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '1. Aktifkan pelacakan lokasi untuk mengirim posisi ambulan ke server',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                '2. Posisi akan diperbarui secara otomatis setiap 10 detik',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                '3. Gunakan switch "Sibuk" untuk mengatur status ketersediaan',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                '4. Pastikan GPS perangkat aktif untuk akurasi yang baik',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
