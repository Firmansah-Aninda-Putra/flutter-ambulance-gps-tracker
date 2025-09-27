// frontend/lib/widgets/map_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ambulance_model.dart';
import '../services/ambulance_service.dart';
import '../services/auth_service.dart';
import '../config/api_config.dart';

class MapWidget extends StatefulWidget {
  final bool isAdmin;
  final bool isUser;
  final bool trackingEnabled;

  const MapWidget({
    super.key,
    required this.isAdmin,
    this.isUser = false,
    required this.trackingEnabled,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> with TickerProviderStateMixin {
  final AmbulanceService _ambulanceService = AmbulanceService();
  final AuthService _authService = AuthService();

  AmbulanceLocation? _ambulanceLocation;
  LatLng? _userPosition;
  Timer? _timer; // PERBAIKAN: Jadikan nullable untuk kontrol yang lebih baik
  Timer? _locationUpdateTimer; // PERBAIKAN: Timer terpisah untuk admin
  final MapController _mapController = MapController();
  bool _hasShownBusy = false;
  String? addressText;
  bool isBusyLocal = false;
  socket_io.Socket? _socket;

  // Kontrol tampilan marker dan tracking
  bool _showAmbulanceMarker = false;
  bool _isMapReady = false;
  bool _trackingActiveFromServer = false;
  bool _isDisposed =
      false; // PERBAIKAN: Flag untuk mencegah update setelah dispose

  // TAMBAHAN: Animation controller untuk marker ambulan
  late AnimationController _ambulanceAnimationController;
  late Animation<double> _ambulanceAnimation;

  // TAMBAHAN: Pull-to-refresh controller
  bool _isRefreshing = false;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();

    // TAMBAHAN: Inisialisasi animation controller untuk marker ambulan
    _ambulanceAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _ambulanceAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _ambulanceAnimationController,
      curve: Curves.easeInOut,
    ));

    // Mulai animasi berulang
    _ambulanceAnimationController.repeat(reverse: true);

    _loadCachedData();

    // PERBAIKAN: Inisialisasi socket untuk semua user type
    _initSocket();

    // Mulai fetching data hanya jika tracking enabled atau user/admin
    if (widget.trackingEnabled || widget.isUser || widget.isAdmin) {
      _startDataFetching();
    }

    // Admin tracking terpisah
    if (widget.isAdmin) {
      _startAdminLocationTracking();
    }

    // Inisialisasi map
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMapAfterRender();
    });
  }

  @override
  void dispose() {
    _isDisposed = true; // PERBAIKAN: Set flag disposal
    _timer?.cancel();
    _locationUpdateTimer?.cancel();
    _socket?.disconnect();
    _ambulanceAnimationController
        .dispose(); // TAMBAHAN: Dispose animation controller
    super.dispose();
  }

  // TAMBAHAN: Fungsi untuk pull-to-refresh
  Future<void> _onRefresh() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
    });

    try {
      // Refresh data ambulan
      await _fetchAmbulanceLocation();
      await _fetchAmbulanceLocationDetail();

      // Jika ada user position, refresh juga
      if (_userPosition != null) {
        await _shareUserLocation();
      }

      // Tampilkan feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Peta berhasil diperbarui'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error during refresh: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memperbarui peta: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _startDataFetching() {
    _fetchAmbulanceLocation();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isDisposed) {
        // PERBAIKAN: Cek disposal
        _fetchAmbulanceLocation();
      }
    });
    _fetchAmbulanceLocationDetail();
  }

  void _initializeMapAfterRender() {
    if (_isDisposed) return; // PERBAIKAN: Cek disposal
    setState(() {
      _isMapReady = true;
    });

    if (_ambulanceLocation != null && _trackingActiveFromServer) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted && !_isDisposed) {
          _mapController.move(_ambulanceLocation!.position, 14.0);
        }
      });
    }
  }

  Future<void> _loadCachedData() async {
    if (_isDisposed) return; // PERBAIKAN: Cek disposal
    final prefs = await SharedPreferences.getInstance();

    // Muat status tracking
    final cachedTrackingActive =
        prefs.getBool('ambulanceTrackingActive') ?? true;

    // PERBAIKAN: Clear cache jika tidak ada permission untuk tracking
    if (!widget.trackingEnabled && !widget.isUser && !widget.isAdmin) {
      await _clearAmbulanceCache();
      return;
    }

    // Muat data lokasi
    final cachedLocation = prefs.getString('lastAmbulanceLocation');
    final cachedIsBusy = prefs.getBool('lastAmbulanceIsBusy') ?? false;
    final cachedAddress = prefs.getString('lastAmbulanceAddress');

    if (cachedLocation != null && cachedTrackingActive) {
      final parts = cachedLocation.split(',');
      if (parts.length == 2) {
        setState(() {
          _ambulanceLocation = AmbulanceLocation(
            position: LatLng(double.parse(parts[0]), double.parse(parts[1])),
            isBusy: cachedIsBusy,
            updatedAt: DateTime.now(),
          );
          addressText = cachedAddress;
          isBusyLocal = cachedIsBusy;
          _trackingActiveFromServer = cachedTrackingActive;
          _showAmbulanceMarker = cachedTrackingActive &&
              (widget.trackingEnabled || widget.isUser || widget.isAdmin);
        });
      }
    }
  }

  Future<void> _clearAmbulanceCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastAmbulanceLocation');
    await prefs.remove('lastAmbulanceIsBusy');
    await prefs.remove('lastAmbulanceAddress');
    await prefs.remove('ambulanceTrackingActive');

    if (!_isDisposed) {
      setState(() {
        _ambulanceLocation = null;
        addressText = null;
        isBusyLocal = false;
        _trackingActiveFromServer = false;
        _showAmbulanceMarker = false;
      });
    }
  }

  Future<void> _cacheAmbulanceLocation(
      AmbulanceLocation location, String? address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastAmbulanceLocation',
        '${location.position.latitude},${location.position.longitude}');
    await prefs.setBool('lastAmbulanceIsBusy', location.isBusy);
    await prefs.setBool('ambulanceTrackingActive', _trackingActiveFromServer);
    if (address != null) {
      await prefs.setString('lastAmbulanceAddress', address);
    }
  }

  void _initSocket() {
    _socket = socket_io.io(ApiConfig.socketUrl,
        socket_io.OptionBuilder().setTransports(['websocket']).build());

    _socket!.onConnect((_) {
      debugPrint('Map socket connected: ${_socket!.id}');
    });

    // PERBAIKAN: Handler untuk update lokasi dengan validasi tracking status
    _socket!.on('ambulanceLocationUpdated', (data) {
      if (_isDisposed) return; // PERBAIKAN: Cek disposal
      debugPrint('Received ambulanceLocationUpdated: $data');

      final trackingActive = data['trackingActive'] ?? true;

      if (!trackingActive) {
        // Jika tracking dinonaktifkan, clear data
        _handleTrackingDisabled();
        return;
      }

      setState(() {
        _ambulanceLocation = AmbulanceLocation(
          position: LatLng(data['latitude'], data['longitude']),
          isBusy: data['isBusy'],
          updatedAt: DateTime.parse(data['updatedAt']),
        );
        addressText = data['addressText'];
        isBusyLocal = data['isBusy'];
        _trackingActiveFromServer = trackingActive;
        _showAmbulanceMarker = trackingActive &&
            (widget.trackingEnabled || widget.isUser || widget.isAdmin);

        if (_isMapReady && _showAmbulanceMarker) {
          _mapController.move(_ambulanceLocation!.position, 14.0);
        }
      });

      _cacheAmbulanceLocation(_ambulanceLocation!, addressText);

      // DIHAPUS: Snackbar status ambulan busy/bebas
      // if (mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(
      //       content:
      //           Text('Status Ambulan: ${data['isBusy'] ? 'Sibuk' : 'Bebas'}'),
      //       duration: const Duration(seconds: 2),
      //     ),
      //   );
      // }
    });

    // PERBAIKAN: Handler untuk tracking disabled
    _socket!.on('ambulanceTrackingDisabled', (data) {
      if (_isDisposed) return;
      debugPrint('Received ambulanceTrackingDisabled: $data');
      _handleTrackingDisabled();
    });

    // PERBAIKAN: Handler untuk tracking enabled
    _socket!.on('ambulanceTrackingEnabled', (data) {
      if (_isDisposed) return;
      debugPrint('Received ambulanceTrackingEnabled: $data');
      setState(() {
        _trackingActiveFromServer = true;
        _showAmbulanceMarker =
            widget.trackingEnabled || widget.isUser || widget.isAdmin;
      });

      // Fetch data terbaru saat tracking diaktifkan
      if (_showAmbulanceMarker) {
        _fetchAmbulanceLocationDetail();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pelacakan ambulans diaktifkan'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });

    _socket!.onError((error) {
      debugPrint('Socket error: $error');
    });

    _socket!.connect();
  }

  // PERBAIKAN: Fungsi terpisah untuk handle tracking disabled
  void _handleTrackingDisabled() {
    setState(() {
      _trackingActiveFromServer = false;
      _showAmbulanceMarker = false;
    });

    _clearAmbulanceCache();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pelacakan ambulans dinonaktifkan'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _fetchAmbulanceLocation() async {
    if (_isDisposed) return; // PERBAIKAN: Cek disposal
    try {
      final location = await _ambulanceService.getAmbulanceLocation();

      if (!_isDisposed) {
        setState(() {
          _ambulanceLocation = location;
          isBusyLocal = location.isBusy;
          _trackingActiveFromServer = true;
          _showAmbulanceMarker =
              (widget.trackingEnabled || widget.isUser || widget.isAdmin);
        });

        _cacheAmbulanceLocation(location, addressText);

        // DIHAPUS: Snackbar status ambulan busy/bebas
        // if (location.isBusy && !_hasShownBusy) {
        //   _hasShownBusy = true;
        //   if (mounted) {
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       const SnackBar(
        //         content: Text('Ambulan sedang dalam panggilan lain'),
        //         duration: Duration(seconds: 3),
        //       ),
        //     );
        //   }
        // }
        // if (!location.isBusy) _hasShownBusy = false;
      }
    } catch (e) {
      debugPrint('Error fetching ambulance location: $e');

      // PERBAIKAN: Handle specific error untuk tracking disabled
      if (e.toString().contains('tracking is currently disabled') ||
          e.toString().contains('Ambulance tracking is currently disabled')) {
        _handleTrackingDisabled();
      } else if (!_isDisposed) {
        setState(() {
          _trackingActiveFromServer = false;
          _showAmbulanceMarker = false;
        });
      }
    }
  }

  Future<void> _fetchAmbulanceLocationDetail() async {
    if (_isDisposed) return; // PERBAIKAN: Cek disposal
    try {
      final detail = await _ambulanceService.getAmbulanceLocationDetail();

      if (!_isDisposed) {
        setState(() {
          addressText = detail.addressText;
          isBusyLocal = detail.isBusy;
          _ambulanceLocation = AmbulanceLocation(
            position: detail.position,
            isBusy: detail.isBusy,
            updatedAt: detail.updatedAt,
          );
          _trackingActiveFromServer = detail.trackingActive;
          _showAmbulanceMarker = detail.trackingActive &&
              (widget.trackingEnabled || widget.isUser || widget.isAdmin);

          if (_isMapReady && _showAmbulanceMarker) {
            _mapController.move(detail.position, 14.0);
          }
        });

        _cacheAmbulanceLocation(_ambulanceLocation!, addressText);
      }
    } catch (e) {
      debugPrint('Error fetching ambulance location detail: $e');

      // PERBAIKAN: Handle specific error untuk tracking disabled
      if (e.toString().contains('tracking is currently disabled') ||
          e.toString().contains('Ambulance tracking is currently disabled')) {
        _handleTrackingDisabled();
      } else if (!_isDisposed) {
        setState(() {
          _trackingActiveFromServer = false;
          _showAmbulanceMarker = false;
        });
      }
    }
  }

  // PERBAIKAN: Admin location tracking dengan error handling yang lebih baik
  void _startAdminLocationTracking() {
    _locationUpdateTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_isDisposed) return;

      try {
        final locationData = await _ambulanceService.getCurrentLocation();
        if (locationData != null && !_isDisposed) {
          await _ambulanceService.updateAmbulanceLocation(
            locationData.latitude!,
            locationData.longitude!,
            isBusy: _ambulanceLocation?.isBusy,
          );
        }
      } catch (e) {
        debugPrint('Error updating admin location: $e');

        // PERBAIKAN: Jangan tampilkan error untuk tracking disabled di admin mode
        if (!e.toString().contains('tracking is currently disabled')) {
          if (mounted && !_isDisposed) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error update lokasi: $e'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    });
  }

  Future<void> _shareUserLocation() async {
    if (_isDisposed) return; // PERBAIKAN: Cek disposal
    try {
      final locationData = await _ambulanceService.getCurrentLocation();
      if (locationData != null && !_isDisposed) {
        setState(() {
          _userPosition =
              LatLng(locationData.latitude!, locationData.longitude!);
          if (_isMapReady) {
            _mapController.move(_userPosition!, 14.0);
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak dapat mengakses lokasi')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error getting user location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // MODIFIKASI: Widget untuk marker ambulan dengan icon mobil ambulan dan animasi
  Widget _buildAnimatedAmbulanceMarker() {
    return AnimatedBuilder(
      animation: _ambulanceAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: 0.9 + (0.1 * _ambulanceAnimation.value),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isBusyLocal ? Colors.red : Colors.green,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: (isBusyLocal ? Colors.red : Colors.green).withAlpha(
                      ((0.4 + (0.3 * _ambulanceAnimation.value)) * 255)
                          .toInt()),
                  blurRadius: 15 + (10 * _ambulanceAnimation.value),
                  spreadRadius: 3 + (2 * _ambulanceAnimation.value),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Icon mobil ambulan
                const Positioned(
                  top: 26,
                  child: Icon(
                    Icons.local_shipping, // Menggunakan icon truk/mobil
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                // Tanda plus (palang) di atas mobil
                Positioned(
                  top: 12,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add,
                      color: isBusyLocal ? Colors.red : Colors.green,
                      size: 12,
                    ),
                  ),
                ),
                // Status text
                Positioned(
                  bottom: -18,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isBusyLocal ? Colors.red : Colors.green,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      isBusyLocal ? 'Sibuk' : 'Bebas',
                      style: TextStyle(
                        color: isBusyLocal ? Colors.red : Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const LatLng defaultLocation = LatLng(-7.6298, 111.5247);
    final LatLng ambulancePosition =
        _ambulanceLocation?.position ?? defaultLocation;

    return RefreshIndicator(
      key: _refreshIndicatorKey,
      onRefresh: _onRefresh,
      color: Colors.red,
      backgroundColor: Colors.white,
      strokeWidth: 3.0,
      displacement: 50.0,
      edgeOffset: 0.0, // TAMBAHAN: Memungkinkan refresh dari edge
      child: Stack(
        children: [
          // MODIFIKASI: Membungkus FlutterMap dengan SingleChildScrollView untuk enable pull-to-refresh
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: ambulancePosition,
                  initialZoom: 14.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all &
                        ~InteractiveFlag
                            .rotate, // TAMBAHAN: Disable rotate untuk smooth scroll
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.ambulance.tracker',
                    additionalOptions: const {
                      'attribution': '© OpenStreetMap contributors',
                    },
                  ),
                  MarkerLayer(
                    markers: [
                      if (_showAmbulanceMarker &&
                          _ambulanceLocation != null &&
                          _trackingActiveFromServer)
                        Marker(
                          point: ambulancePosition,
                          width: 80,
                          height: 80,
                          child: _buildAnimatedAmbulanceMarker(),
                        ),
                      if (_userPosition != null)
                        Marker(
                          point: _userPosition!,
                          width: 80,
                          height: 80,
                          child: const Column(
                            children: [
                              Icon(
                                Icons.person_pin_circle,
                                color: Colors.blue,
                                size: 40,
                              ),
                              Text(
                                'Anda',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Attribution
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              color: const Color.fromRGBO(255, 255, 255, 0.9),
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),

          // User location button
          if (widget.isUser)
            Positioned(
              bottom: 80,
              right: 16,
              child: FloatingActionButton(
                onPressed: _shareUserLocation,
                tooltip: 'Bagikan Lokasi Anda',
                child: const Icon(Icons.my_location),
              ),
            ),

          // MODIFIKASI: Notifikasi orange dipindah ke tengah map
          if (!_trackingActiveFromServer &&
              (widget.trackingEnabled || widget.isUser || widget.isAdmin))
            Positioned(
              top: MediaQuery.of(context).size.height *
                  0.4, // MODIFIKASI: Posisi tengah vertikal
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(240),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade700, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withAlpha(100),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Pelacakan Dinonaktifkan',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Pelacakan ambulans sedang dinonaktifkan oleh admin',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // TAMBAHAN: Indikator refresh
          if (_isRefreshing)
            Positioned(
              top: 60,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(230),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Memperbarui peta...',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
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
