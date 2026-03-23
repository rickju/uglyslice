import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'database/app_database.dart';
import 'models/round.dart';
import 'models/course.dart';
import 'services/round_repository.dart';

// Karori Golf Club hole pars (hole 12 missing tag → treated as par 4)
const _karoriPars = [4, 3, 4, 3, 4, 3, 5, 4, 4, 4, 4, 4, 3, 5, 4, 4, 4, 4];

// Hole layout from OSM routing lines: [teeLat, teeLon, pinLat, pinLon]
// Source: karori_1.json routing-line first/last nodes
const _holeLayout = [
  [-41.28807, 174.68872, -41.28555, 174.69028], // H1  par4
  [-41.28532, 174.69103, -41.28514, 174.68885], // H2  par3
  [-41.28552, 174.68944, -41.28646, 174.68600], // H3  par4
  [-41.28693, 174.68632, -41.28704, 174.68807], // H4  par3
  [-41.28731, 174.68830, -41.28787, 174.68430], // H5  par4
  [-41.28773, 174.68392, -41.28774, 174.68249], // H6  par3
  [-41.28837, 174.68374, -41.28783, 174.68798], // H7  par5
  [-41.28840, 174.68818, -41.28908, 174.68421], // H8  par4
  [-41.28968, 174.68392, -41.28952, 174.68869], // H9  par4
  [-41.29022, 174.68811, -41.29025, 174.68426], // H10 par4
  [-41.29066, 174.68395, -41.29241, 174.68153], // H11 par4
  [-41.29356, 174.68299, -41.29437, 174.68585], // H12 par4
  [-41.29439, 174.68652, -41.29313, 174.68693], // H13 par3
  [-41.29269, 174.68733, -41.29292, 174.68269], // H14 par5
  [-41.29263, 174.68188, -41.29236, 174.68696], // H15 par4
  [-41.29170, 174.68747, -41.29165, 174.68373], // H16 par4
  [-41.29112, 174.68401, -41.29121, 174.68754], // H17 par4
  [-41.29127, 174.68823, -41.28856, 174.68888], // H18 par4
];

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

final _dummyClub = Club(
    name: '7 Iron',
    brand: 'TaylorMade',
    number: '7',
    type: ClubType.iron,
    loft: 34);

final _driver = Club(
    name: 'Driver',
    brand: 'TaylorMade',
    number: '1',
    type: ClubType.driver,
    loft: 10);

final _putter = Club(
    name: 'Putter',
    brand: 'Odyssey',
    number: 'P',
    type: ClubType.putter,
    loft: 4);

/// Interpolate between two coordinates at fraction [t] ∈ [0,1].
LatLng _lerp(double lat1, double lon1, double lat2, double lon2, double t) =>
    LatLng(lat1 + (lat2 - lat1) * t, lon1 + (lon2 - lon1) * t);

/// Generate a GPS trail for one hole with [steps] breadcrumb points.
/// A sine-wave lateral scatter is added to simulate realistic play.
List<LatLng> _holeTrail(int holeIdx, int roundIdx, {int steps = 8}) {
  final h = _holeLayout[holeIdx];
  final teeLat = h[0], teeLon = h[1], pinLat = h[2], pinLon = h[3];

  final dlat = pinLat - teeLat;
  final dlon = pinLon - teeLon;
  final len = sqrt(dlat * dlat + dlon * dlon);
  // Unit perpendicular in degree-space (rotated 90°).
  // At -41° lat: 1° lat ≈ 111 km, 1° lon ≈ 84 km, so this isn't
  // isometric — but the amplitude below compensates by targeting ~12 m.
  final perpLat = len > 0 ? -dlon / len : 0.0;
  final perpLon = len > 0 ? dlat / len : 0.0;
  // ~12–18 m lateral scatter (0.00013° ≈ 14 m in lat at this latitude)
  final amp = 0.00013 + (roundIdx * 3 + holeIdx) % 3 * 0.00003;
  final phase = (roundIdx * 7 + holeIdx * 3) * 0.4;

  return [
    for (int i = 0; i <= steps; i++)
      () {
        final t = i / steps;
        final base = _lerp(teeLat, teeLon, pinLat, pinLon, t);
        final scatter = sin(t * pi * 3 + phase) * amp;
        return LatLng(base.latitude + perpLat * scatter,
            base.longitude + perpLon * scatter);
      }(),
  ];
}

/// Build a full 18-hole GPS trail (tee→pin for each hole, joined together).
List<LatLng> _buildRoundTrail(int roundIdx) {
  final trail = <LatLng>[];
  for (int h = 0; h < 18; h++) {
    trail.addAll(_holeTrail(h, roundIdx));
  }
  return trail;
}

/// Small random jitter (~0–5 m) around a point, seeded deterministically.
LatLng _jitter(LatLng p, int seed) {
  final rng = Random(seed);
  // 0.00005° ≈ 5.5 m lat, ≈ 4.2 m lon at -41°
  return LatLng(
    p.latitude  + (rng.nextDouble() - 0.5) * 0.00005,
    p.longitude + (rng.nextDouble() - 0.5) * 0.00005,
  );
}

/// Generate hit positions for a round.
///
/// For each real shot: the watch records 1 hit (sometimes 2 if a practice
/// swing was taken). Putts are excluded — phone/watch rarely detects them.
/// A few false-positive detections are scattered along the trail at random.
List<LatLng> _buildHitPositions(int roundIdx, List<List<Shot>> holeShots) {
  final hits = <LatLng>[];
  final rng = Random(roundIdx * 31);

  for (int h = 0; h < holeShots.length; h++) {
    final shots = holeShots[h];
    for (int k = 0; k < shots.length; k++) {
      final shot = shots[k];
      // Skip putts — watch rarely triggers on putting stroke.
      if (shot.club?.type == ClubType.putter) continue;

      // Real hit — slightly jittered from the shot start position.
      hits.add(_jitter(shot.startLocation, roundIdx * 1000 + h * 100 + k));

      // ~35% chance of a practice swing (extra hit) before this shot.
      if (rng.nextDouble() < 0.35) {
        hits.add(_jitter(shot.startLocation, roundIdx * 999 + h * 97 + k + 50));
      }
    }

    // ~1 false positive per hole (watch detected a non-swing movement).
    if (shots.isNotEmpty && rng.nextDouble() < 0.6) {
      // Place it somewhere along the hole trail.
      final t = rng.nextDouble();
      final hl = _holeLayout[h];
      hits.add(_lerp(hl[0], hl[1], hl[2], hl[3], t));
    }
  }

  return hits;
}

/// Build shots for a hole. Each shot walks along the tee→pin line.
List<Shot> _buildShots(int holeIdx, int score) {
  final h = _holeLayout[holeIdx];
  final teeLat = h[0], teeLon = h[1], pinLat = h[2], pinLon = h[3];

  if (score == 1) {
    return [
      Shot(
        startLocation: LatLng(teeLat, teeLon),
        endLocation: LatLng(pinLat, pinLon),
        club: _dummyClub,
        lieType: LieType.fairway,
      ),
    ];
  }

  final shots = <Shot>[];
  // Divide hole into (score-1) approach segments, last shot is a putt to pin.
  // Breakpoints: 0, 1/(score-1), 2/(score-1), ..., 1
  for (int k = 0; k < score; k++) {
    final startT = k == 0 ? 0.0 : k / (score - 1);
    final endT = k == score - 1 ? 1.0 : (k + 1) / (score - 1);
    final start = _lerp(teeLat, teeLon, pinLat, pinLon, startT.clamp(0, 1));
    final end = _lerp(teeLat, teeLon, pinLat, pinLon, endT.clamp(0, 1));
    final Club club;
    final LieType lie;
    if (k == 0) {
      club = _driver;
      lie = LieType.fairway;
    } else if (k == score - 1) {
      club = _putter;
      lie = LieType.green;
    } else {
      club = _dummyClub;
      lie = LieType.fairway;
    }
    shots.add(Shot(
      startLocation: start,
      endLocation: end,
      club: club,
      lieType: lie,
    ));
  }
  return shots;
}

Future<void> seedKaroriRounds(AppDatabase db) async {
  final repo = RoundRepository(db);
  final course = Course.stub(id: 'course_747473941', name: 'Karori Golf Club');

  for (int r = 0; r < _rounds.length; r++) {
    final scores = _rounds[r];
    final holeShots = List.generate(18, (i) => _buildShots(i, scores[i]));
    final holePlays = List.generate(18, (i) => HolePlay(
      holeNumber: i + 1,
      shots: holeShots[i],
    ));

    final round = Round(
      player: Player(name: 'Rick'),
      course: course,
      date: _dates[r],
      holePlays: holePlays,
      trail: _buildRoundTrail(r),
      hitPositions: _buildHitPositions(r, holeShots),
      status: 'completed',
    );

    await repo.saveRound(round);
  }
}

List<int> get karoriPars => List.unmodifiable(_karoriPars);
