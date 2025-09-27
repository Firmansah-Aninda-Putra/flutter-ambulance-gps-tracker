// lib/models/weather_data.dart

/// Model untuk menyimpan data cuaca dari Open-Meteo API.
class WeatherData {
  /// Temperatur saat ini (°C)
  final double currentTemperature;

  /// Kode cuaca saat ini (sesuai standar Open-Meteo)
  final int currentWeatherCode;

  /// Daftar temperatur maksimum per hari (°C),
  /// index 0 = hari ini, 1 = esok, 2 = dua hari ke depan, dst.
  final List<double> dailyMax;

  /// Daftar temperatur minimum per hari (°C),
  /// index 0 = hari ini, 1 = esok, 2 = dua hari ke depan, dst.
  final List<double> dailyMin;

  /// Daftar kode cuaca per hari,
  /// index 0 = hari ini, 1 = esok, 2 = dua hari ke depan, dst.
  final List<int> dailyWeatherCode;

  WeatherData({
    required this.currentTemperature,
    required this.currentWeatherCode,
    required this.dailyMax,
    required this.dailyMin,
    required this.dailyWeatherCode,
  });

  /// Buat instance [WeatherData] dari JSON yang diterima Open-Meteo.
  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final current = json['current_weather'] as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>;

    // Ambil list dari setiap field daily
    final maxTemps = (daily['temperature_2m_max'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    final minTemps = (daily['temperature_2m_min'] as List)
        .map((e) => (e as num).toDouble())
        .toList();
    final codes = (daily['weathercode'] as List).map((e) => e as int).toList();

    return WeatherData(
      currentTemperature: (current['temperature'] as num).toDouble(),
      currentWeatherCode: current['weathercode'] as int,
      dailyMax: maxTemps,
      dailyMin: minTemps,
      dailyWeatherCode: codes,
    );
  }
}
