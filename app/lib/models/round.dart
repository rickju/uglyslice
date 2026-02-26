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
}

class HolePlay {
  final int holeNumber;
  final List<Shot> shots;

  HolePlay({required this.holeNumber, this.shots = const []});

  int get score => shots.length;
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
}
