import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import '../models/user_model.dart';
import '../models/user_detail_model.dart';
import '../models/chat_message.dart';
import '../models/call_history_item.dart';
import '../models/ambulance_location_detail_model.dart';
import '../services/auth_service.dart';
import '../services/ambulance_service.dart';
import '../services/socket_service.dart';
import '../services/chat_service.dart'; // Added for message fetching
import '../widgets/map_widget.dart';
import '../widgets/comment_widget.dart';
import '../widgets/bottom_menu_widget.dart';
import '../widgets/weather_panel.dart';
import '../widgets/traffic_map_widget.dart';
import 'login_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final AmbulanceService _ambulanceService = AmbulanceService();
  final ChatService _chatService = ChatService(); // Added ChatService instance

  User? _currentUser;
  bool _isLoading = true;
  int _selectedIndex = 2;
  bool _trackingEnabled = false;

  String _addressText = '';
  int _reloadCounter = 0;

  double? _lat;
  double? _lon;
  double? _userLat;
  double? _userLon;
  bool _userLocationShared = false;
  bool _ambulanceIsBusy = false;
  bool _ambulanceTrackingActive = false;

  String? _profilePicturePath;
  List<ChatMessage> _adminMessages = [];
  StreamSubscription<ChatMessage>? _messageSubscription;
  int? _adminId;
  Offset _fabPosition = const Offset(20, 100);

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadTrackingFlag();
    _loadFabPosition();
    _fetchLocationDetail();
    _initLocation();
    // Removed _setupMessageListener from here to sync with adminId
  }

  void _setupMessageListener() {
    _messageSubscription?.cancel();
    _messageSubscription = SocketService().messageStream.listen((message) {
      debugPrint(
          'Received message: ${message.content} from ${message.senderId}');
      debugPrint('Current user: ${_currentUser?.id}, Admin ID: $_adminId');

      if (_currentUser != null &&
          !_currentUser!.isAdmin &&
          _adminId != null &&
          message.senderId == _adminId) {
        setState(() {
          _adminMessages.add(message);
          _saveMessagesToPrefs(); // Save new message to persistence
        });
        debugPrint(
            'Admin message added. Total messages: ${_adminMessages.length}');
      }
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final loc = Location();
      if (await loc.hasPermission() != PermissionStatus.granted) {
        await loc.requestPermission();
      }
      final pos = await loc.getLocation();
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
      });
    } catch (_) {
      // ignore error
    }
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      final user = await _authService.getCurrentUser();
      if (user != null) {
        await SocketService().initialize(user.id);
        final prefs = await SharedPreferences.getInstance();
        final profilePicturePath =
            prefs.getString('profile_picture_${user.id}');
        int? adminId;
        if (!user.isAdmin) {
          adminId = await _authService.getAdminId();
        }
        setState(() {
          _currentUser = user;
          _profilePicturePath = profilePicturePath;
          _adminId = adminId;
        });

        // Fetch and load existing admin messages if not admin
        if (!user.isAdmin && adminId != null) {
          await _loadMessagesFromPrefs(); // Load persisted messages first
          try {
            final List<ChatMessage> allMessages =
                await _chatService.getMessages(user.id, adminId);
            final List<ChatMessage> adminMessages =
                allMessages.where((msg) => msg.senderId == adminId).toList();
            if (mounted) {
              setState(() {
                // Merge with existing messages to avoid duplicates
                for (var msg in adminMessages) {
                  if (!_adminMessages.any((m) => m.id == msg.id)) {
                    _adminMessages.add(msg);
                  }
                }
                _saveMessagesToPrefs(); // Persist fetched messages
              });
            }
            debugPrint('Fetched ${adminMessages.length} messages from admin');
          } catch (e) {
            debugPrint('Error fetching admin messages: $e');
          }
          _setupMessageListener(); // Set up listener after adminId is ready
        }
      } else {
        setState(() {
          _currentUser = null;
          _profilePicturePath = null;
          _adminId = null;
          _adminMessages = [];
          _saveMessagesToPrefs(); // Clear persisted messages
        });
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Load messages from SharedPreferences
  Future<void> _loadMessagesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? messagesJson =
        prefs.getString('admin_messages_${_currentUser?.id}');
    if (messagesJson != null) {
      final List<dynamic> messagesList = jsonDecode(messagesJson);
      setState(() {
        _adminMessages = messagesList
            .map((msg) => ChatMessage.fromJson(Map<String, dynamic>.from(msg)))
            .toList();
      });
      debugPrint('Loaded ${_adminMessages.length} messages from persistence');
    }
  }

  // Save messages to SharedPreferences
  Future<void> _saveMessagesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final String messagesJson =
        jsonEncode(_adminMessages.map((msg) => msg.toJson()).toList());
    await prefs.setString('admin_messages_${_currentUser?.id}', messagesJson);
    debugPrint('Saved ${_adminMessages.length} messages to persistence');
  }

// Tambahkan method ini setelah method _saveMessagesToPrefs
  Future<void> _saveFabPosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('fab_x', _fabPosition.dx);
    await prefs.setDouble('fab_y', _fabPosition.dy);
  }

  Future<void> _loadFabPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final double? x = prefs.getDouble('fab_x');
    final double? y = prefs.getDouble('fab_y');
    if (x != null && y != null) {
      setState(() {
        _fabPosition = Offset(x, y);
      });
    }
  }

  Future<void> _loadTrackingFlag() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _trackingEnabled = prefs.getBool('trackingEnabled') ?? false;
    });
  }

  Future<void> _logout() async {
    await _authService.logout();
    await SocketService().dispose();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _callAmbulance() async {
    if (_currentUser == null) {
      _goToLogin();
      return;
    }

    try {
      final CallHistoryItem call =
          await _ambulanceService.callAmbulance(_currentUser!.id);
      debugPrint('Call recorded: ID=${call.id}, User=${call.userName}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Panggilan tercatat pada ${call.formattedDate}')),
        );
      }

      final Uri telUri = Uri(scheme: 'tel', path: '112');
      if (await canLaunchUrl(telUri)) {
        await launchUrl(telUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak dapat membuka dialer')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error in callAmbulance: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mencatat panggilan: $e')),
        );
      }
    }
  }

  void _onMenuTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _goToLogin() {
    Navigator.pushNamed(context, '/login').then((_) {
      _loadUser();
    });
  }

  Future<void> _fetchLocationDetail() async {
    try {
      final AmbulanceLocationDetail detail =
          await _ambulanceService.getAmbulanceLocationDetail();
      if (!mounted) return;
      setState(() {
        _addressText = detail.addressText;
        _reloadCounter++;
        _ambulanceIsBusy = detail.isBusy;
        _ambulanceTrackingActive = detail.trackingActive;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil lokasi: $e')),
        );
      }
    }
  }

  void _onRefreshPressed() => _fetchLocationDetail();

  void _onChatPressed() async {
    if (_currentUser == null) {
      _goToLogin();
      return;
    }
    try {
      final int adminId = await _authService.getAdminId();
      String adminUsername = 'Admin';
      try {
        final adminDetail = await _authService.getUserDetail(adminId);
        adminUsername = adminDetail.username;
      } catch (_) {}
      if (!mounted) return;

      Navigator.of(context)
          .push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            targetUserId: adminId,
            targetUsername: adminUsername,
          ),
        ),
      )
          .then((_) {
        setState(() {
          _adminMessages = [];
          _saveMessagesToPrefs(); // Clear persisted messages after chat
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error membuka chat: $e')),
        );
      }
    }
  }

  void _debugAdminMessages() {
    debugPrint('=== DEBUG ADMIN MESSAGES ===');
    debugPrint('Current user: ${_currentUser?.id} (${_currentUser?.username})');
    debugPrint('Is admin: ${_currentUser?.isAdmin}');
    debugPrint('Admin ID: $_adminId');
    debugPrint('Admin messages count: ${_adminMessages.length}');
    for (int i = 0; i < _adminMessages.length; i++) {
      final msg = _adminMessages[i];
      debugPrint('Message $i: ${msg.content} from ${msg.senderId}');
    }
    debugPrint('=========================');
  }

  void _onKomentarPressed() {
    if (_currentUser == null) {
      _goToLogin();
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.8,
          child: CommentWidget(
            currentUser: _currentUser,
            ambulanceId: 1,
          ),
        ),
      );
    }
  }

  void _onPanggilSelected(String value) async {
    if (value == 'darurat') {
      _callAmbulance();
    }
  }

  Future<void> _toggleUserLocation() async {
    if (_userLocationShared) {
      setState(() {
        _userLocationShared = false;
        _userLat = null;
        _userLon = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lokasi Anda dinonaktifkan')),
        );
      }
    } else {
      try {
        final loc = Location();
        if (await loc.hasPermission() != PermissionStatus.granted) {
          await loc.requestPermission();
        }
        final pos = await loc.getLocation();
        setState(() {
          _userLat = pos.latitude;
          _userLon = pos.longitude;
          _userLocationShared = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lokasi Anda diaktifkan')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengakses lokasi: $e')),
          );
        }
      }
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  String _getDistanceText() {
    if (_userLat != null && _userLon != null && _lat != null && _lon != null) {
      double distance = _calculateDistance(_userLat!, _userLon!, _lat!, _lon!);
      return distance.toStringAsFixed(2);
    }
    return '';
  }

  void _showAmbulanceStatus() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Status Ambulan: ${_ambulanceIsBusy ? 'Sibuk' : 'Bebas'}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickProfilePicture() async {
    if (_currentUser == null) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'profile_picture_${_currentUser!.id}.jpg';
      final filePath = path.join(directory.path, fileName);
      await File(pickedFile.path).copy(filePath);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_picture_${_currentUser!.id}', filePath);
      setState(() {
        _profilePicturePath = filePath;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 360;
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bool isAdmin = _currentUser?.isAdmin ?? false;
    final bool isUser = !isAdmin && _currentUser != null;

    final List<Widget> tabs = [
      Stack(
        fit: StackFit.expand,
        children: [
          MapWidget(
            key: ValueKey(_reloadCounter),
            isAdmin: isAdmin,
            isUser: isUser,
            trackingEnabled: _trackingEnabled,
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.blue,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Saat Ini Ambulan Berada Di:',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _addressText.isNotEmpty
                          ? _addressText
                          : 'Lokasi tidak tersedia',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 11 : 13,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _ambulanceIsBusy
                            ? Colors.red.withAlpha(25)
                            : Colors.green.withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _ambulanceIsBusy ? Colors.red : Colors.green,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _ambulanceIsBusy
                                ? Icons.warning
                                : Icons.check_circle,
                            color: _ambulanceIsBusy ? Colors.red : Colors.green,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _ambulanceIsBusy
                                  ? 'MOHON TUNGGU SEBENTAR, AMBULAN SEDANG MENGANTAR PASIEN LAIN'
                                  : 'AMBULAN SEDANG TIDAK MENGANTAR PASIEN',
                              style: TextStyle(
                                color: _ambulanceIsBusy
                                    ? Colors.red
                                    : Colors.green,
                                fontSize: isSmallScreen ? 10 : 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isUser &&
                        _userLocationShared &&
                        _ambulanceTrackingActive) ...[
                      const SizedBox(height: 12),
                      if (_getDistanceText().isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.straighten,
                                color: Colors.blue,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'AMBULAN BERADA ${_getDistanceText()} KM DARI LOKASI ANDA',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: isSmallScreen ? 10 : 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info,
                                color: Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'MENUNGGU DATA LOKASI AMBULAN',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: isSmallScreen ? 10 : 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          flex: 1,
                          child: _buildActionButton(
                            icon: Icons.refresh,
                            label: 'Refresh',
                            onPressed: _onRefreshPressed,
                            color: Colors.blue,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: _buildActionButton(
                            icon: Icons.chat,
                            label: 'Chat',
                            onPressed: _onChatPressed,
                            color: Colors.green,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: _buildActionButton(
                            icon: Icons.comment,
                            label: 'Komentar',
                            onPressed: _onKomentarPressed,
                            color: Colors.orange,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: _buildActionButton(
                            icon: Icons.call,
                            label: 'Panggil',
                            onPressed: () => _onPanggilSelected('darurat'),
                            color: Colors.red,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: _buildLocationButton(
                              isUser: isUser), // GUNNAKAN METHOD HELPER
                        ),
                        Expanded(
                          flex: 1,
                          child: _buildActionButton(
                            icon: Icons.directions_car,
                            label: 'Status',
                            onPressed: _showAmbulanceStatus,
                            color: _ambulanceIsBusy ? Colors.red : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      Scaffold(
        body: CommentWidget(
          currentUser: _currentUser,
          ambulanceId: 1,
        ),
      ),
      Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/dikbud.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (_currentUser != null &&
                      !_currentUser!.isAdmin &&
                      _adminId != null)
                    GestureDetector(
                      onTap: _onChatPressed,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  Row(
                                    children: [
                                      const Text(
                                        'PPID Kota Madiun',
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      if (kDebugMode) ...[
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: _debugAdminMessages,
                                          child: const Icon(Icons.verified,
                                              size: 16, color: Colors.blue),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (_adminMessages.isNotEmpty)
                                    Positioned(
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _adminMessages.length.toString(),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_adminMessages.isNotEmpty)
                                Text(
                                  _adminMessages.last.content ?? 'Pesan Baru',
                                  style: const TextStyle(fontSize: 14),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                )
                              else
                                const Text(
                                  'Tidak ada pesan baru',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic),
                                ),
                              if (kDebugMode) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Debug: User=${_currentUser?.id}, Admin=$_adminId, Messages=${_adminMessages.length}',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_currentUser != null &&
                      !_currentUser!.isAdmin &&
                      _adminId != null)
                    const SizedBox(height: 16),
                  if (_lat != null && _lon != null)
                    WeatherPanel(latitude: _lat!, longitude: _lon!),
                  if (_lat != null && _lon != null) const SizedBox(height: 16),
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: GridView.count(
                        crossAxisCount:
                            MediaQuery.of(context).size.width < 360 ? 3 : 6,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio:
                            MediaQuery.of(context).size.width < 360 ? 1.0 : 0.8,
                        children: [
                          _dashboardTile(
                            icon: Icons.map,
                            label: 'Map',
                            color: Colors.green,
                            onTap: () => _onMenuTap(0),
                          ),
                          _dashboardTile(
                            icon: Icons.person,
                            label: 'Profil',
                            color: Colors.green,
                            onTap: () {
                              if (_currentUser == null) {
                                _goToLogin();
                              } else {
                                _onMenuTap(3);
                              }
                            },
                          ),
                          _dashboardTile(
                            icon: Icons.call,
                            label: 'Panggil',
                            color: Colors.green,
                            onTap: () => _onMenuTap(4),
                          ),
                          _dashboardTile(
                            icon: Icons.chat,
                            label: 'Chat',
                            color: Colors.green,
                            onTap: _onChatPressed,
                          ),
                          _dashboardTile(
                            icon: Icons.comment,
                            label: 'Komentar',
                            color: Colors.green,
                            onTap: _onKomentarPressed,
                          ),
                          _dashboardTile(
                            icon: Icons.login,
                            label: _currentUser == null ? 'Login' : 'Logout',
                            color: Colors.green,
                            onTap: () {
                              if (_currentUser == null) {
                                _goToLogin();
                              } else {
                                _logout();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_lat != null && _lon != null) const TrafficMapWidget(),
                  if (_lat != null && _lon != null) const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
      Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/dikbud.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: _currentUser == null
              ? const Center(child: Text('Silakan login terlebih dahulu'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      FutureBuilder<UserDetail>(
                        future: _authService.getUserDetail(_currentUser!.id),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          } else if (snapshot.hasError) {
                            return Center(
                                child: Text('Error: ${snapshot.error}'));
                          } else if (snapshot.hasData) {
                            final userDetail = snapshot.data!;
                            return Center(
                              child: Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      GestureDetector(
                                        onTap: _pickProfilePicture,
                                        child: CircleAvatar(
                                          radius: 50,
                                          backgroundImage:
                                              _profilePicturePath != null
                                                  ? FileImage(File(
                                                      _profilePicturePath!))
                                                  : null,
                                          child: _profilePicturePath == null
                                              ? const Icon(Icons.person,
                                                  size: 50)
                                              : null,
                                        ),
                                      ),
                                      if (_profilePicturePath != null)
                                        TextButton(
                                          onPressed: () async {
                                            final prefs =
                                                await SharedPreferences
                                                    .getInstance();
                                            await prefs.remove(
                                                'profile_picture_${_currentUser!.id}');
                                            if (_profilePicturePath != null) {
                                              await File(_profilePicturePath!)
                                                  .delete();
                                            }
                                            setState(() {
                                              _profilePicturePath = null;
                                            });
                                          },
                                          child:
                                              const Text('Hapus Foto Profil'),
                                        ),
                                      const SizedBox(height: 16),
                                      Text(
                                        userDetail.username,
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Status: ${userDetail.isAdmin ? 'Admin' : 'User'}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Nama Lengkap: ${userDetail.fullName}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Alamat: ${userDetail.address}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Telepon: ${userDetail.phone}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Dibuat pada: ${userDetail.createdAt}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          } else {
                            return const Center(child: Text('No data'));
                          }
                        },
                      ),
                    ],
                  ),
                ),
        ),
      ),
      Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/dikbud.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Center(
            child: ElevatedButton.icon(
              onPressed: _callAmbulance,
              icon: const Icon(Icons.call, color: Colors.red),
              label: const Text('Panggil 112',
                  style: TextStyle(color: Colors.red)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox.shrink(),
        leadingWidth: 0,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 28.0,
              right: 16.0,
              top: 8.0,
              bottom: 8.0,
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/pindai.png',
                  width: MediaQuery.of(context).size.width < 360 ? 80 : 100,
                  height: MediaQuery.of(context).size.width < 360 ? 80 : 100,
                  fit: BoxFit.contain,
                ),
                const Spacer(),
                if (_currentUser != null)
                  Text(
                    _currentUser!.username,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.exit_to_app),
                  onPressed: _logout,
                ),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: tabs,
          ),
          // DRAGGABLE FAB - PENGGANTI FLOATING ACTION BUTTON
          if (isAdmin)
            Positioned(
              left: _fabPosition.dx,
              top: _fabPosition.dy,
              child: Draggable(
                feedback: const Material(
                  elevation: 6.0,
                  shape: CircleBorder(),
                  child: FloatingActionButton(
                    onPressed: null,
                    tooltip: 'Panel Admin',
                    child: Icon(Icons.admin_panel_settings),
                  ),
                ),
                childWhenDragging: const Opacity(
                  opacity: 0.3,
                  child: FloatingActionButton(
                    onPressed: null,
                    tooltip: 'Panel Admin',
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.admin_panel_settings),
                  ),
                ),
                onDragEnd: (details) {
                  setState(() {
                    // Batasi posisi agar tidak keluar layar
                    final screenSize = MediaQuery.of(context).size;
                    double newX = details.offset.dx;
                    double newY = details.offset.dy;

                    // Batasi X axis (56 adalah lebar FAB)
                    if (newX < 0) newX = 0;
                    if (newX > screenSize.width - 56) {
                      newX = screenSize.width - 56;
                    }

                    // Batasi Y axis (200 adalah tinggi bottom nav + margin)
                    if (newY < 0) newY = 0;
                    if (newY > screenSize.height - 200) {
                      newY = screenSize.height - 200;
                    }

                    _fabPosition = Offset(newX, newY);
                  });
                  _saveFabPosition(); // Simpan posisi baru
                },
                child: FloatingActionButton(
                  onPressed: () => Navigator.pushNamed(context, '/admin'),
                  tooltip: 'Panel Admin',
                  child: const Icon(Icons.admin_panel_settings),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomMenuWidget(
        currentIndex: _selectedIndex,
        onTap: (i) {
          if ((i == 1 || i == 3) && _currentUser == null) {
            _goToLogin();
          } else {
            _onMenuTap(i);
          }
        },
      ),
    );
  }

  // Ubah method _buildActionButton
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonSize = screenWidth < 360 ? 40.0 : 48.0; // Responsif size
    final iconSize = screenWidth < 360 ? 16.0 : 20.0;
    final fontSize = screenWidth < 360 ? 8.0 : 10.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 1.5),
          ),
          child: IconButton(
            icon: Icon(icon, color: color, size: iconSize),
            onPressed: onPressed,
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            color: color,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center, // Tambahkan ini
          maxLines: 1, // Batasi 1 baris
          overflow: TextOverflow.ellipsis, // Potong jika terlalu panjang
        ),
      ],
    );
  }

  Widget _buildLocationButton({required bool isUser}) {
    if (isUser) {
      return _buildActionButton(
        icon: _userLocationShared ? Icons.location_on : Icons.location_off,
        label: _userLocationShared ? 'Lokasi On' : 'Lokasi Off',
        onPressed: _toggleUserLocation,
        color: _userLocationShared ? Colors.green : Colors.grey,
      );
    } else {
      return _buildActionButton(
        icon: Icons.location_disabled,
        label: 'N/A',
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fitur khusus user')),
          );
        },
        color: Colors.grey,
      );
    }
  }

  // Ubah method _dashboardTile
  Widget _dashboardTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final iconSize = screenWidth < 360 ? 24.0 : 28.0;
    final fontSize = screenWidth < 360 ? 10.0 : 12.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: Colors.white),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: Colors.white, fontSize: fontSize),
              textAlign: TextAlign.center,
              maxLines: 1, // Batasi 1 baris
              overflow: TextOverflow.ellipsis, // Potong jika panjang
            ),
          ],
        ),
      ),
    );
  }
}
