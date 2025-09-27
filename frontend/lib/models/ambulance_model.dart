import 'package:latlong2/latlong.dart';

class AmbulanceLocation {
  final LatLng position;
  final bool isBusy;
  final DateTime updatedAt;
  final bool? trackingActive; // ✅ TAMBAHKAN PROPERTY INI

  AmbulanceLocation({
    required this.position,
    required this.isBusy,
    required this.updatedAt,
    this.trackingActive, // ✅ TAMBAHKAN PARAMETER INI
  });

  factory AmbulanceLocation.fromJson(Map<String, dynamic> json) {
    // Parse tanggal updatedAt jika tersedia; jika tidak, pakai now
    DateTime ts = DateTime.now();
    if (json['updatedAt'] != null) {
      ts = DateTime.parse(json['updatedAt']).toLocal();
    }
    return AmbulanceLocation(
      position: LatLng(
        (json['latitude'] as num?)?.toDouble() ?? -7.6298,
        (json['longitude'] as num?)?.toDouble() ?? 111.5247,
      ),
      isBusy: json['isBusy'] == 1 || json['isBusy'] == true,
      updatedAt: ts,
      trackingActive: json['trackingActive'] as bool?, // ✅ PARSE DARI JSON
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'isBusy': isBusy,
      if (trackingActive != null)
        'trackingActive': trackingActive, // ✅ TAMBAHKAN KE JSON
    };
  }
}
