import 'package:latlong2/latlong.dart';

import 'database/app_database.dart';
import 'models/round.dart';
import 'models/course.dart';
import 'services/round_repository.dart';

// Karori Golf Club hole pars (hole 12 missing tag → treated as par 4)
const _karoriPars = [4, 3, 4, 3, 4, 3, 5, 4, 4, 4, 4, 4, 3, 5, 4, 4, 4, 4];

// Three realistic rounds (scores per hole, index 0 = hole 1)
const _rounds = [
  // Round 1: 82 (+12) — a rough day
  [4, 3, 5, 4, 4, 4, 6, 5, 4, 5, 4, 5, 3, 6, 5, 5, 5, 5],
  // Round 2: 78 (+8) — decent
  [5, 3, 4, 3, 5, 3, 5, 4, 5, 4, 4, 5, 3, 5, 4, 5, 4, 6],
  // Round 3: 76 (+6) — best round
  [4, 3, 4, 3, 5, 3, 5, 4, 4, 4, 4, 4, 3, 6, 4, 4, 5, 5],
];

final _dates = [
  DateTime.now().subtract(const Duration(days: 3)),
  DateTime.now().subtract(const Duration(days: 17)),
  DateTime.now().subtract(const Duration(days: 34)),
];

// Dummy tee location (Karori hole 1 tee)
final _tee = LatLng(-41.2855, 174.6894);
final _dummyClub = Club(
    name: '7 Iron',
    brand: 'TaylorMade',
    number: '7',
    type: ClubType.iron,
    loft: 34);

Future<void> seedKaroriRounds(AppDatabase db) async {
  final repo = RoundRepository(db);
  final course = Course.stub(
      id: 'course_747473941', name: 'Karori Golf Club');

  for (int r = 0; r < _rounds.length; r++) {
    final scores = _rounds[r];
    final holePlays = List.generate(18, (i) {
      final shots = List.generate(
        scores[i],
        (_) => Shot(
          startLocation: _tee,
          club: _dummyClub,
          lieType: LieType.fairway,
        ),
      );
      return HolePlay(holeNumber: i + 1, shots: shots);
    });

    final round = Round(
      player: Player(name: 'Rick'),
      course: course,
      date: _dates[r],
      holePlays: holePlays,
      status: 'completed',
    );

    await repo.saveRound(round);
  }
}

List<int> get karoriPars => List.unmodifiable(_karoriPars);
