import 'package:latlong2/latlong.dart';

class AmbulanceLocationDetail {
  final LatLng position;
  final bool isBusy;
  final DateTime updatedAt;
  final String addressText;
  final bool trackingActive; // Menambahkan field trackingActive

  AmbulanceLocationDetail({
    required this.position,
    required this.isBusy,
    required this.updatedAt,
    required this.addressText,
    required this.trackingActive, // Inisialisasi field trackingActive
  });

  factory AmbulanceLocationDetail.fromJson(Map<String, dynamic> json) {
    DateTime ts = DateTime.now();
    if (json['updatedAt'] != null) {
      ts = DateTime.parse(json['updatedAt']).toLocal();
    }
    final lat = (json['latitude'] as num?)?.toDouble() ?? 0.0;
    final lon = (json['longitude'] as num?)?.toDouble() ?? 0.0;
    final address = json['addressText'] ?? json['address_text'] ?? '';
    final isBusyValue = json['isBusy'] == true || json['isBusy'] == 1;
    final trackingValue =
        json['trackingActive'] == true; // Parsing flag trackingActive

    return AmbulanceLocationDetail(
      position: LatLng(lat, lon),
      isBusy: isBusyValue,
      updatedAt: ts,
      addressText: address,
      trackingActive: trackingValue, // Set field trackingActive
    );
  }
}
