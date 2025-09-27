// frontend/lib/widgets/traffic_map_widget.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../config/api_config.dart';

class TrafficMapWidget extends StatefulWidget {
  const TrafficMapWidget({super.key});

  @override
  State<TrafficMapWidget> createState() => _TrafficMapWidgetState();
}

class _TrafficMapWidgetState extends State<TrafficMapWidget> {
  late Timer _timer;
  int _cacheBuster = DateTime.now().millisecondsSinceEpoch;
  DateTime _lastUpdated = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    // Set initial waktu update dan cacheBuster
    _lastUpdated = DateTime.now();
    _cacheBuster = DateTime.now().millisecondsSinceEpoch;

    // Jadwalkan timer untuk refresh setiap 15 menit
    _timer = Timer.periodic(
      const Duration(minutes: 15),
      (timer) {
        setState(() {
          _lastUpdated = DateTime.now();
          _cacheBuster = DateTime.now().millisecondsSinceEpoch;
        });
      },
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _formattedUpdateTime {
    try {
      // Format waktu lokal Indonesia
      return DateFormat('HH:mm – d MMM yyyy', 'id_ID').format(_lastUpdated);
    } catch (_) {
      // Jika locale belum di-setup, fallback tanpa locale spesifik
      return DateFormat('HH:mm – d MMM yyyy').format(_lastUpdated);
    }
  }

  void _openFullscreenMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullscreenTrafficMap(
          cacheBuster: _cacheBuster,
          lastUpdated: _lastUpdated,
        ),
      ),
    );
  }

  Widget _buildTrafficLegend() {
    // Warna standar TomTom Traffic API berdasarkan dokumentasi
    final List<TrafficLegendItem> trafficLevels = [
      TrafficLegendItem(
        color: const Color(0xFF00FF00), // Hijau terang
        label: 'Sangat Lancar',
        description: 'Lalu lintas sangat lancar, kecepatan optimal',
        speed: '> 80 km/jam',
      ),
      TrafficLegendItem(
        color: const Color(0xFF32CD32), // Hijau
        label: 'Lancar',
        description: 'Lalu lintas lancar, kecepatan baik',
        speed: '60-80 km/jam',
      ),
      TrafficLegendItem(
        color: const Color(0xFFFFFF00), // Kuning
        label: 'Normal',
        description: 'Lalu lintas normal, kecepatan sedang',
        speed: '40-60 km/jam',
      ),
      TrafficLegendItem(
        color: const Color(0xFFFF8C00), // Orange
        label: 'Ramai',
        description: 'Lalu lintas mulai ramai, kecepatan menurun',
        speed: '20-40 km/jam',
      ),
      TrafficLegendItem(
        color: const Color(0xFFFF0000), // Merah
        label: 'Macet',
        description: 'Lalu lintas macet parah, kecepatan sangat lambat',
        speed: '< 20 km/jam',
      ),
      TrafficLegendItem(
        color: const Color(0xFF800080), // Ungu
        label: 'Sangat Macet',
        description: 'Lalu lintas sangat macet, hampir tidak bergerak',
        speed: '< 10 km/jam',
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Keterangan Kondisi Lalu Lintas:',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              GestureDetector(
                onTap: _openFullscreenMap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).primaryColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fullscreen,
                        size: 14,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Fullscreen',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            children: trafficLevels
                .map((item) => _buildLegendListItem(item))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'Data diperbarui setiap 15 menit dari TomTom Traffic API',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLegendListItem(TrafficLegendItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: item.color,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.grey[400]!, width: 0.5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${item.description} (${item.speed})',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: ikon, judul, dan waktu update
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.traffic,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  'Lalu Lintas Real Time',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Text(
                  _formattedUpdateTime,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          // Peta dengan gesture detector untuk fullscreen
          GestureDetector(
            onTap: _openFullscreenMap,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(0),
                  topRight: Radius.circular(0),
                ),
                border: Border.all(color: Colors.grey[300]!, width: 0.5),
              ),
              child: Stack(
                children: [
                  FlutterMap(
                    options: const MapOptions(
                      initialCenter: LatLng(-7.6298, 111.5239),
                      initialZoom: 13.0,
                      interactionOptions: InteractionOptions(
                        flags: InteractiveFlag.drag |
                            InteractiveFlag.pinchZoom |
                            InteractiveFlag.flingAnimation |
                            InteractiveFlag.doubleTapZoom,
                      ),
                    ),
                    children: [
                      // Base layer OpenStreetMap dengan cache busting
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png?ts=$_cacheBuster',
                        userAgentPackageName:
                            'com.yourcompany.ambulance_tracker',
                        tileProvider: NetworkTileProvider(),
                      ),
                      // Overlay traffic TomTom dengan cache busting
                      TileLayer(
                        urlTemplate:
                            '${ApiConfig.tomTomTrafficUrlTemplate}&ts=$_cacheBuster',
                        tileProvider: NetworkTileProvider(),
                      ),
                      // Marker pusat kota (opsional)
                      const MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(-7.6298, 111.5239),
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_on,
                              color: Colors.redAccent,
                              size: 32,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Overlay untuk menunjukkan bahwa peta bisa diklik
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.fullscreen,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Legend/Keterangan
          _buildTrafficLegend(),
        ],
      ),
    );
  }
}

// Model untuk item legend
class TrafficLegendItem {
  final Color color;
  final String label;
  final String description;
  final String speed;

  TrafficLegendItem({
    required this.color,
    required this.label,
    required this.description,
    required this.speed,
  });
}

// Widget untuk fullscreen map
class _FullscreenTrafficMap extends StatelessWidget {
  final int cacheBuster;
  final DateTime lastUpdated;

  const _FullscreenTrafficMap({
    required this.cacheBuster,
    required this.lastUpdated,
  });

  String get _formattedUpdateTime {
    try {
      return DateFormat('HH:mm – d MMM yyyy', 'id_ID').format(lastUpdated);
    } catch (_) {
      return DateFormat('HH:mm – d MMM yyyy').format(lastUpdated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Lalu Lintas'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                _formattedUpdateTime,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(-7.6298, 111.5239),
          initialZoom: 13.0,
          interactionOptions: InteractionOptions(
            flags: InteractiveFlag.drag |
                InteractiveFlag.pinchZoom |
                InteractiveFlag.flingAnimation |
                InteractiveFlag.doubleTapZoom,
          ),
        ),
        children: [
          // Base layer OpenStreetMap
          TileLayer(
            urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png?ts=$cacheBuster',
            userAgentPackageName: 'com.yourcompany.ambulance_tracker',
            tileProvider: NetworkTileProvider(),
          ),
          // Overlay traffic TomTom
          TileLayer(
            urlTemplate:
                '${ApiConfig.tomTomTrafficUrlTemplate}&ts=$cacheBuster',
            tileProvider: NetworkTileProvider(),
          ),
          // Marker pusat kota
          const MarkerLayer(
            markers: [
              Marker(
                point: LatLng(-7.6298, 111.5239),
                width: 40,
                height: 40,
                child: Icon(
                  Icons.location_on,
                  color: Colors.redAccent,
                  size: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
