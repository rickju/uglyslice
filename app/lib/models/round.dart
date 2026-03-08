import 'package:latlong2/latlong.dart';
import 'player.dart';
import 'club.dart';
import 'course.dart';

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

class Round {
  final Player player;
  final Course course;
  final DateTime date;
  final List<HolePlay> holePlays;
  String status;

  Round({
    required this.player,
    required this.course,
    required this.date,
    this.holePlays = const [],
    this.status = 'in_progress',
  });

  int get totalScore {
    return holePlays.fold(0, (total, holePlay) => total + holePlay.score);
  }

  Map<String, dynamic> toMap() => {
        'courseId': course.id,
        'courseName': course.name,
        'playerName': player.name,
        'playerHandicap': player.handicap,
        'date': date,
        'status': status,
        'holePlays': holePlays.map((hp) => hp.toMap()).toList(),
      };

  // Reconstructs a Round with a stub Course — sufficient for scorecard display.
  static Round fromScoreMap(Map<String, dynamic> m) => Round(
        player: Player(
          name: m['playerName'] as String,
          handicap: (m['playerHandicap'] as num).toDouble(),
        ),
        course: Course.stub(
          id: m['courseId'] as String,
          name: m['courseName'] as String,
        ),
        date: (m['date'] as DateTime),
        status: m['status'] as String? ?? 'completed',
        holePlays: (m['holePlays'] as List? ?? [])
            .map((hp) => HolePlay.fromMap(hp as Map<String, dynamic>))
            .toList(),
      );
}
