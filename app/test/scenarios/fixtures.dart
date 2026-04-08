import 'package:latlong2/latlong.dart';
import 'package:ugly_slice_shared/club.dart';
import 'package:ugly_slice_shared/round_data.dart';
import 'package:ugly_slice/models/course.dart';

// ── Karori GC reference coords (from seed_data.dart / OSM routing lines) ─────

// H1 par 4: ~300 yards
const kKaroriH1Tee = LatLng(-41.28807, 174.68872);
const kKaroriH1Pin = LatLng(-41.28555, 174.69028);

// Approximate green polygon around H1 pin (~20 m half-width).
final kKaroriH1GreenPoints = [
  LatLng(-41.28537, 174.69004),
  LatLng(-41.28537, 174.69052),
  LatLng(-41.28573, 174.69052),
  LatLng(-41.28573, 174.69004),
  LatLng(-41.28537, 174.69004), // closed
];

// H2 par 3: ~200 yards from tee to pin
const kKaroriH2Tee = LatLng(-41.28532, 174.69103);
const kKaroriH2Pin = LatLng(-41.28514, 174.68885);

// Approximate green polygon around H2 pin (~20 m half-width).
final kKaroriH2GreenPoints = [
  LatLng(-41.28496, 174.68861),
  LatLng(-41.28496, 174.68909),
  LatLng(-41.28532, 174.68909),
  LatLng(-41.28532, 174.68861),
  LatLng(-41.28496, 174.68861), // closed
];

/// Returns a minimal 2-hole Karori course (holes 1 and 2) with real GPS coords.
/// Use this as the base for Karori scenario tests.
List<Hole> makeKaroriHoles() => [
      makeHole(
        number: 1,
        par: 4,
        pin: kKaroriH1Pin,
        greenPoints: kKaroriH1GreenPoints,
      ),
      makeHole(
        number: 2,
        par: 3,
        pin: kKaroriH2Pin,
        greenPoints: kKaroriH2GreenPoints,
      ),
    ];

// ── Generic test coords ───────────────────────────────────────────────────────

const kGenericPin = LatLng(-41.2895, 174.6938);
const kGenericFairway = LatLng(-41.2910, 174.6920); // ~200 y from pin
const kGenericOnGreen = LatLng(-41.2896, 174.6939); // just off pin

final kGenericGreenPoints = [
  LatLng(-41.2894, 174.6937),
  LatLng(-41.2894, 174.6940),
  LatLng(-41.2897, 174.6940),
  LatLng(-41.2897, 174.6937),
  LatLng(-41.2894, 174.6937), // closed
];

// ── Hole builder ──────────────────────────────────────────────────────────────

Hole makeHole({
  int number = 1,
  int par = 4,
  LatLng? pin,
  List<LatLng>? greenPoints,
}) {
  return Hole(
    holeNumber: number,
    par: par,
    pin: pin ?? kGenericPin,
    greens: greenPoints != null
        ? [Green(id: 1, points: greenPoints, tags: {'golf': 'green'})]
        : [],
  );
}

// ── Club builders ─────────────────────────────────────────────────────────────

Club makePutter() =>
    Club(name: 'Putter', brand: '', number: '', type: ClubType.putter, loft: 3);

Club makeDriver() =>
    Club(name: 'Driver', brand: '', number: '', type: ClubType.driver, loft: 10);

Club makeIron(String number) =>
    Club(name: number, brand: '', number: number, type: ClubType.iron, loft: 30);

Club makeWedge(String name) =>
    Club(name: name, brand: '', number: '', type: ClubType.iron, loft: 50);

// ── Shot builder ──────────────────────────────────────────────────────────────

Shot makeShot({
  LieType lieType = LieType.fairway,
  Club? club,
  LatLng? start,
  LatLng? end,
  bool penalty = false,
  bool isTeeShot = false,
}) {
  return Shot(
    startLocation: start ?? kGenericFairway,
    endLocation: end,
    lieType: lieType,
    club: club,
    penalty: penalty,
    isTeeShot: isTeeShot,
  );
}

// ── HolePlay builder ──────────────────────────────────────────────────────────

HolePlay makeHolePlay({int holeNumber = 1, required List<Shot> shots}) =>
    HolePlay(holeNumber: holeNumber, shots: shots);

// ── Preset hole scenarios ─────────────────────────────────────────────────────

/// Par 4: Dr (fairway) → 7i (fairway/green) → 2 putts. GIR=true, FIR=true, 4 shots.
HolePlay parGir4({int holeNumber = 1}) => makeHolePlay(
      holeNumber: holeNumber,
      shots: [
        makeShot(club: makeDriver(), lieType: LieType.fairway, isTeeShot: true),
        makeShot(club: makeIron('7'), lieType: LieType.fairway),
        makeShot(club: makePutter(), lieType: LieType.green),
        makeShot(club: makePutter(), lieType: LieType.green),
      ],
    );

/// Par 4 bogey: Dr (fairway) → rough → chip → 2 putts. GIR=false, FIR=true, 5 shots.
HolePlay bogeyMissedGir({int holeNumber = 1}) => makeHolePlay(
      holeNumber: holeNumber,
      shots: [
        makeShot(club: makeDriver(), lieType: LieType.fairway, isTeeShot: true),
        makeShot(club: makeIron('7'), lieType: LieType.rough),
        makeShot(club: makeWedge('PW'), lieType: LieType.rough),
        makeShot(club: makePutter(), lieType: LieType.green),
        makeShot(club: makePutter(), lieType: LieType.green),
      ],
    );

/// Par 3 birdie: 7i → putt. GIR=true, FIR=null (par 3), 2 shots.
HolePlay par3Birdie({int holeNumber = 1}) => makeHolePlay(
      holeNumber: holeNumber,
      shots: [
        makeShot(club: makeIron('7'), lieType: LieType.fairway, isTeeShot: true),
        makeShot(club: makePutter(), lieType: LieType.green),
      ],
    );

/// Par 4 double bogey: Dr (rough) → rough → rough → 2 putts. GIR=false, FIR=false, 6 shots.
HolePlay doubleBogeyMissedFir({int holeNumber = 1}) => makeHolePlay(
      holeNumber: holeNumber,
      shots: [
        makeShot(club: makeDriver(), lieType: LieType.rough, isTeeShot: true),
        makeShot(club: makeIron('5'), lieType: LieType.rough),
        makeShot(club: makeWedge('PW'), lieType: LieType.rough),
        makeShot(club: makePutter(), lieType: LieType.green),
        makeShot(club: makePutter(), lieType: LieType.green),
        makeShot(club: makePutter(), lieType: LieType.green),
      ],
    );

/// Empty hole — no shots recorded.
HolePlay emptyHole({int holeNumber = 1}) =>
    makeHolePlay(holeNumber: holeNumber, shots: []);

// ── 18-hole generic course ────────────────────────────────────────────────────

/// Standard par layout mirroring a typical 18-hole course (total par 72).
/// Holes are indexed 0-17; holeNumber = index + 1.
const kGenericPars = [
  4, 3, 4, 5, 4, 4, 3, // H1-H7 = 27
  4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5, // H8-H18 = 45
]; // total = 72

/// Returns a minimal 18-hole course using [kGenericPars].
/// No green polygons — distance assertions not meaningful here.
List<Hole> makeGeneric18HoleCourse() => List.generate(
      18,
      (i) => makeHole(number: i + 1, par: kGenericPars[i]),
    );

/// Par layout for a typical 9-hole course (total par 36).
const kGeneric9HolePars = [4, 3, 4, 5, 4, 4, 3, 4, 5]; // total = 36

/// Returns a minimal 9-hole course using [kGeneric9HolePars].
List<Hole> makeGeneric9HoleCourse() => List.generate(
      9,
      (i) => makeHole(number: i + 1, par: kGeneric9HolePars[i]),
    );

/// Par layout for an 18-hole par-71 course (3 par 5s, 4 par 3s, 11 par 4s).
/// Same as kGenericPars but H13 changed par 5 → par 4. Total = 71.
const kGenericPar71Pars = [
  4, 3, 4, 5, 4, 4, 3, // H1-H7 = 27
  4, 5, 4, 3, 4, 4, 4, 4, 3, 4, 5, // H8-H18 = 44
]; // total = 71

/// Returns a minimal 18-hole par-71 course using [kGenericPar71Pars].
List<Hole> makeGenericPar71Course() => List.generate(
      18,
      (i) => makeHole(number: i + 1, par: kGenericPar71Pars[i]),
    );

/// Builds a [HolePlay] for [holeNumber] with [score] shots.
///
/// Shot pattern:
///   - Last 2 shots: green lie (putts)
///   - All earlier shots: fairway lie (non-putts), first shot is tee shot
///
/// This gives deterministic GIR/FIR results for testing:
///   - GIR true  when score <= par  (first green shot at index score-2 ≤ par-2)
///   - GIR false when score > par
///   - FIR true  when score >= 4 on par-4+ (shot[1] is fairway; birdies score=3 give FIR=false)
///   - FIR null  for par 3
HolePlay holePlayForScore(int holeNumber, int par, int score) {
  assert(score > 0, 'score must be at least 1');
  final puttsCount = score >= 2 ? 2 : 1;
  final nonPutts = score - puttsCount;
  final shots = <Shot>[
    for (int i = 0; i < nonPutts; i++)
      makeShot(lieType: LieType.fairway, isTeeShot: i == 0),
    for (int i = 0; i < puttsCount; i++)
      makeShot(lieType: LieType.green, club: makePutter()),
  ];
  return makeHolePlay(holeNumber: holeNumber, shots: shots);
}
