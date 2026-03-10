import 'package:latlong2/latlong.dart';
import 'club.dart';

enum LieType { fairway, rough, sand, green }

class Shot {
  final LatLng startLocation;
  final LatLng? endLocation;
  final Club club;
  final LieType lieType;

  Shot({
    required this.startLocation,
    this.endLocation,
    required this.club,
    required this.lieType,
  });

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'startLat': startLocation.latitude,
      'startLng': startLocation.longitude,
      'clubName': club.name,
      'clubBrand': club.brand,
      'clubNumber': club.number,
      'clubType': club.type.name,
      'clubLoft': club.loft,
      'lieType': lieType.name,
    };
    if (endLocation != null) {
      m['endLat'] = endLocation!.latitude;
      m['endLng'] = endLocation!.longitude;
    }
    return m;
  }

  factory Shot.fromMap(Map<String, dynamic> m) => Shot(
        startLocation: LatLng(m['startLat'] as double, m['startLng'] as double),
        endLocation: m.containsKey('endLat')
            ? LatLng(m['endLat'] as double, m['endLng'] as double)
            : null,
        club: Club(
          name: m['clubName'] as String,
          brand: m['clubBrand'] as String,
          number: m['clubNumber'] as String,
          type: ClubType.values.byName(m['clubType'] as String),
          loft: (m['clubLoft'] as num).toDouble(),
        ),
        lieType: LieType.values.byName(m['lieType'] as String),
      );
}

class HolePlay {
  final int holeNumber;
  final List<Shot> shots;

  HolePlay({required this.holeNumber, this.shots = const []});

  int get score => shots.length;

  Map<String, dynamic> toMap() => {
        'holeNumber': holeNumber,
        'shots': shots.map((s) => s.toMap()).toList(),
      };

  factory HolePlay.fromMap(Map<String, dynamic> m) => HolePlay(
        holeNumber: m['holeNumber'] as int,
        shots: (m['shots'] as List? ?? [])
            .map((s) => Shot.fromMap(s as Map<String, dynamic>))
            .toList(),
      );
}
