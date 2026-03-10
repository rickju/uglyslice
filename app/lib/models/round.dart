import 'package:ugly_slice_shared/player.dart';
import 'package:ugly_slice_shared/round_data.dart';
import 'course.dart';

export 'package:ugly_slice_shared/round_data.dart' show Shot, HolePlay, LieType;
export 'package:ugly_slice_shared/club.dart' show Club, ClubType;
export 'package:ugly_slice_shared/player.dart' show Player;

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
