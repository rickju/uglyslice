import 'package:latlong2/latlong.dart';
import 'club.dart';

enum LieType { fairway, rough, sand, green }

class Shot {
  final LatLng startLocation;
  final LatLng? endLocation;
  final Club? club;
  final LieType lieType;
  final bool penalty;
  final bool isTeeShot;
  final bool isRecovery;

  Shot({
    required this.startLocation,
    this.endLocation,
    this.club,
    required this.lieType,
    this.penalty = false,
    this.isTeeShot = false,
    this.isRecovery = false,
  });

  Shot copyWith({
    LatLng? startLocation,
    Object? endLocation = _sentinel,
    Object? club = _sentinel,
    LieType? lieType,
    bool? penalty,
    bool? isTeeShot,
    bool? isRecovery,
  }) =>
      Shot(
        startLocation: startLocation ?? this.startLocation,
        endLocation:
            endLocation == _sentinel ? this.endLocation : endLocation as LatLng?,
        club: club == _sentinel ? this.club : club as Club?,
        lieType: lieType ?? this.lieType,
        penalty: penalty ?? this.penalty,
        isTeeShot: isTeeShot ?? this.isTeeShot,
        isRecovery: isRecovery ?? this.isRecovery,
      );

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'startLat': startLocation.latitude,
      'startLng': startLocation.longitude,
      'lieType': lieType.name,
      if (penalty) 'penalty': true,
      if (isTeeShot) 'isTeeShot': true,
      if (isRecovery) 'isRecovery': true,
    };
    if (club != null) {
      m['clubName'] = club!.name;
      m['clubBrand'] = club!.brand;
      m['clubNumber'] = club!.number;
      m['clubType'] = club!.type.name;
      m['clubLoft'] = club!.loft;
    }
    if (endLocation != null) {
      m['endLat'] = endLocation!.latitude;
      m['endLng'] = endLocation!.longitude;
    }
    return m;
  }

  factory Shot.fromMap(Map<String, dynamic> m) {
    Club? club;
    if (m.containsKey('clubType')) {
      club = Club(
        name: m['clubName'] as String? ?? '',
        brand: m['clubBrand'] as String? ?? '',
        number: m['clubNumber'] as String? ?? '',
        type: ClubType.values.byName(m['clubType'] as String),
        loft: (m['clubLoft'] as num?)?.toDouble() ?? 0,
      );
    }
    return Shot(
      startLocation: LatLng(m['startLat'] as double, m['startLng'] as double),
      endLocation: m.containsKey('endLat')
          ? LatLng(m['endLat'] as double, m['endLng'] as double)
          : null,
      club: club,
      lieType: LieType.values.byName(m['lieType'] as String),
      penalty: m['penalty'] as bool? ?? false,
      isTeeShot: m['isTeeShot'] as bool? ?? false,
      isRecovery: m['isRecovery'] as bool? ?? false,
    );
  }
}

// Sentinel for nullable copyWith parameters.
const _sentinel = Object();

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
