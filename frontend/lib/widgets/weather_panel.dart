// lib/widgets/weather_panel.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/weather_data.dart'; // ← model dipisah

class WeatherPanel extends StatefulWidget {
  final double latitude;
  final double longitude;

  const WeatherPanel({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<WeatherPanel> createState() => WeatherPanelState();
}

class WeatherPanelState extends State<WeatherPanel> {
  bool _loading = true;
  String? _error;
  WeatherData? _weather;
  late final Timer _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
    // Refresh cuaca setiap 15 menit
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _fetchWeather(),
    );
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  Future<void> _fetchWeather() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final url = ApiConfig.weatherUrl(
      latitude: widget.latitude,
      longitude: widget.longitude,
    );

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        throw Exception('Server returned ${res.statusCode}');
      }
      final data = jsonDecode(res.body);
      setState(() {
        _weather = WeatherData.fromJson(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Gagal memuat cuaca';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null
                ? Center(
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)))
                : _buildContent(context)),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final w = _weather!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cuaca Hari Ini',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              _mapWeatherCodeToIcon(w.currentWeatherCode),
              size: 48,
              color: _mapWeatherCodeToColor(w.currentWeatherCode),
            ),
            const SizedBox(width: 12),
            Text(
              '${w.currentTemperature.toStringAsFixed(1)}°C',
              style: Theme.of(context).textTheme.displayLarge,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _mapWeatherCodeToDescription(w.currentWeatherCode),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Divider(height: 24),
        Text(
          'Perkiraan Esok Hari',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildDailyTile(
              day: 'Esok',
              max: w.dailyMax[1],
              min: w.dailyMin[1],
              code: w.dailyWeatherCode[1],
            ),
            _buildDailyTile(
              day: '2 Hari',
              max: w.dailyMax[2],
              min: w.dailyMin[2],
              code: w.dailyWeatherCode[2],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailyTile({
    required String day,
    required double max,
    required double min,
    required int code,
  }) {
    return Column(
      children: [
        Text(day, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Icon(
          _mapWeatherCodeToIcon(code),
          color: _mapWeatherCodeToColor(code),
        ),
        const SizedBox(height: 4),
        Text('↑${max.toStringAsFixed(0)}°  ↓${min.toStringAsFixed(0)}°'),
      ],
    );
  }

  IconData _mapWeatherCodeToIcon(int code) {
    if (code == 0) return Icons.wb_sunny;
    if (code >= 1 && code <= 3) return Icons.cloud;
    if (code >= 45 && code <= 48) return Icons.grain;
    if (code >= 51 && code <= 67) return Icons.grain;
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    if (code >= 80 && code <= 82) return Icons.umbrella;
    if (code >= 95) return Icons.thunderstorm;
    return Icons.help_outline;
  }

  Color _mapWeatherCodeToColor(int code) {
    if (code == 0) return Colors.orangeAccent;
    if (code >= 1 && code <= 3) return Colors.blueGrey;
    if (code >= 45 && code <= 48) return Colors.grey;
    if (code >= 51 && code <= 67) return Colors.lightBlueAccent;
    if (code >= 71 && code <= 77) return Colors.cyan;
    if (code >= 80 && code <= 82) return Colors.blue;
    if (code >= 95) return Colors.deepPurple;
    return Colors.black;
  }

  String _mapWeatherCodeToDescription(int code) {
    if (code == 0) return 'Cerah';
    if (code >= 1 && code <= 3) return 'Berawan';
    if (code >= 45 && code <= 48) return 'Berkabut';
    if (code >= 51 && code <= 67) return 'Hujan Ringan';
    if (code >= 71 && code <= 77) return 'Salju';
    if (code >= 80 && code <= 82) return 'Hujan Sedang';
    if (code >= 95) return 'Badai Petir';
    return 'Tidak Diketahui';
  }
}
