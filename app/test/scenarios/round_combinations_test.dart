// Parameterized round scenarios.
//
// Every [_RoundScenario] is run against every [_TestCourse].
// To add a new combination just append to either list — no other changes needed.
//
// Assertions are computed from the course + scoring function, so there are no
// hardcoded expected values that need updating when you add courses or scenarios.

import 'package:test/test.dart';
import 'package:ugly_slice/models/course.dart';
import 'package:ugly_slice/viewmodels/round_view_model.dart';
import 'package:ugly_slice/viewmodels/scorecard_view_model.dart';
import 'package:ugly_slice_shared/round_data.dart';

import 'fixtures.dart';

// ── Course catalogue ──────────────────────────────────────────────────────────

class _TestCourse {
  final String name;
  final List<Hole> holes;
  _TestCourse(this.name, this.holes);

  int get holeCount => holes.length;
  Map<int, int> get pars => {for (final h in holes) h.holeNumber: h.par};
  int get totalPar => holes.fold(0, (s, h) => s + h.par);
}

final _courses = <_TestCourse>[
  _TestCourse('18-hole par 72', makeGeneric18HoleCourse()),
  _TestCourse('18-hole par 71', makeGenericPar71Course()),
  _TestCourse('9-hole par 36', makeGeneric9HoleCourse()),
];

// ── Scenario catalogue ────────────────────────────────────────────────────────

/// [startHoleFor] returns the 1-based hole number to start on, given the
/// course hole count — so a "middle hole" scenario works on any course size.
class _RoundScenario {
  final String name;
  final int Function(int holeCount) startHoleFor;

  /// Returns the score (stroke count) for a given hole.
  final int Function(int holeNumber, int par) scoreFor;

  const _RoundScenario({
    required this.name,
    required this.startHoleFor,
    required this.scoreFor,
  });
}

final _scenarios = <_RoundScenario>[
  _RoundScenario(
    name: 'all par, start hole 1',
    startHoleFor: (_) => 1,
    scoreFor: (_, par) => par,
  ),
  _RoundScenario(
    name: 'all bogeys, start hole 1',
    startHoleFor: (_) => 1,
    scoreFor: (_, par) => par + 1,
  ),
  _RoundScenario(
    name: 'all birdies, start hole 1',
    startHoleFor: (_) => 1,
    scoreFor: (_, par) => par - 1,
  ),
  _RoundScenario(
    name: 'alternating birdie/bogey, start hole 1',
    startHoleFor: (_) => 1,
    // odd holes: birdie, even holes: bogey → net even
    scoreFor: (holeNum, par) => holeNum.isOdd ? par - 1 : par + 1,
  ),
  _RoundScenario(
    name: 'mid-round start (hole 5 or halfway), all par',
    startHoleFor: (n) => n >= 9 ? 5 : (n ~/ 2) + 1,
    scoreFor: (_, par) => par,
  ),
  _RoundScenario(
    name: 'start last hole then wrap, all par',
    startHoleFor: (n) => n, // start at final hole, wrap to hole 1
    scoreFor: (_, par) => par,
  ),
  _RoundScenario(
    // Start at hole 5; bogey on hole 5 (first played) and hole 1.
    // Play order on 18-hole: 5→6→…→18→1→2→3→4 (last is hole 4, not hole 1).
    // Play order on 9-hole:  5→6→7→8→9→1→2→3→4 (same — last is hole 4).
    name: 'start hole 5, bogey on holes 5 and 1',
    startHoleFor: (n) => n >= 9 ? 5 : (n ~/ 2) + 1,
    scoreFor: (holeNum, par) =>
        (holeNum == 5 || holeNum == 1) ? par + 1 : par,
  ),
];

// ── Expected value computation ────────────────────────────────────────────────

class _Expected {
  final int totalScore;
  final int totalPar;
  final int relToPar;
  final int totalPutts;
  final int girHit;
  final int girTotal;
  final int firHit;
  final int firTotal;

  _Expected({
    required this.totalScore,
    required this.totalPar,
    required this.relToPar,
    required this.totalPutts,
    required this.girHit,
    required this.girTotal,
    required this.firHit,
    required this.firTotal,
  });

  /// Derive all expected values from [course] and [scenario].
  ///
  /// Uses the same shot pattern as [holePlayForScore]:
  ///   - 2 putts always → totalPutts = 2 × holeCount
  ///   - GIR = true iff score ≤ par  (first putt lands at index score-2 ≤ par-2)
  ///   - FIR = true for all par-4+ holes (shot[1] is always fairway)
  factory _Expected.compute(_TestCourse course, _RoundScenario scenario) {
    int totalScore = 0;
    int girHitCount = 0;
    int firHitCount = 0;
    int firTotalCount = 0;

    for (final hole in course.holes) {
      final score = scenario.scoreFor(hole.holeNumber, hole.par);
      totalScore += score;

      // GIR: first green shot at index (score-2). GIR iff score-2 <= par-2, i.e. score <= par.
      if (score <= hole.par) girHitCount++;

      // FIR: not applicable for par 3.
      // In holePlayForScore, shots = [nonPutts × fairway, 2 × green].
      // shots[1] is fairway only when nonPutts >= 2, i.e. score - 2 >= 2, i.e. score >= 4.
      // For birdies (score = par-1 = 3 on par 4) shots[1] is green → FIR=false.
      if (hole.par >= 4) {
        firTotalCount++;
        if (score >= 4) firHitCount++;
      }
    }

    return _Expected(
      totalScore: totalScore,
      totalPar: course.totalPar,
      relToPar: totalScore - course.totalPar,
      totalPutts: course.holeCount * 2,
      girHit: girHitCount,
      girTotal: course.holeCount,
      firHit: firHitCount,
      firTotal: firTotalCount,
    );
  }
}

// ── Play-order simulation ─────────────────────────────────────────────────────

/// Simulates the user playing the round: navigates and enters scores.
/// Returns the strokes map (holeIndex → stroke count).
Map<int, int> _simulateRound(_TestCourse course, _RoundScenario scenario) {
  final n = course.holeCount;
  final startHoleNum = scenario.startHoleFor(n);
  var holeIndex = startHoleNum - 1; // convert to 0-based
  final strokes = <int, int>{};

  for (int played = 0; played < n; played++) {
    final hole = course.holes[holeIndex];
    strokes[holeIndex] = scenario.scoreFor(hole.holeNumber, hole.par);
    holeIndex = (holeIndex + 1) % n; // advance (wraps after last hole)
  }

  return strokes;
}

// ── Build final HolePlays from strokes map ────────────────────────────────────

List<HolePlay> _buildHolePlays(_TestCourse course, Map<int, int> strokes) {
  return List.generate(course.holeCount, (i) {
    final hole = course.holes[i];
    final score = strokes[i];
    if (score == null) return HolePlay(holeNumber: hole.holeNumber, shots: []);
    return holePlayForScore(hole.holeNumber, hole.par, score);
  });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  for (final course in _courses) {
    for (final scenario in _scenarios) {
      group('${course.name} | ${scenario.name}', () {
        final n = course.holeCount;
        final startHoleNum = scenario.startHoleFor(n);
        final expected = _Expected.compute(course, scenario);
        late Map<int, int> strokes;
        late List<HolePlay> holePlays;

        setUp(() {
          strokes = _simulateRound(course, scenario);
          holePlays = _buildHolePlays(course, strokes);
        });

        // ── Navigation ────────────────────────────────────────────────────

        test('starts at hole $startHoleNum', () {
          final startIndex = startHoleNum - 1;
          final disp = RoundViewModel.computeStrokeDisplay(
            holes: course.holes,
            holeIndex: startIndex,
            strokes: const {},
          );
          expect(disp.holeNumber, startHoleNum);
        });

        test('unvisited holes default to par', () {
          // Check every hole with an empty strokes map.
          for (int i = 0; i < n; i++) {
            final disp = RoundViewModel.computeStrokeDisplay(
              holes: course.holes,
              holeIndex: i,
              strokes: const {},
            );
            expect(disp.strokes, disp.par,
                reason: 'hole ${i + 1} should default to par before score entry');
          }
        });

        test('after entering scores, each hole shows the correct stroke count', () {
          for (int i = 0; i < n; i++) {
            final hole = course.holes[i];
            final disp = RoundViewModel.computeStrokeDisplay(
              holes: course.holes,
              holeIndex: i,
              strokes: strokes,
            );
            final expected = scenario.scoreFor(hole.holeNumber, hole.par);
            expect(disp.strokes, expected,
                reason: 'hole ${hole.holeNumber} should show score $expected');
          }
        });

        test('all $n holes scored', () {
          expect(strokes.length, n,
              reason: 'every hole index 0-${n - 1} should have a score');
        });

        test('play order visits every hole exactly once', () {
          final visited = strokes.keys.toSet();
          expect(visited, equals({for (int i = 0; i < n; i++) i}),
              reason: 'all hole indices 0..${n - 1} should be visited');
        });

        test('navigation wraps correctly (no negative or out-of-range index)', () {
          // Simulate navigation step by step, verify index stays in [0, n).
          int idx = startHoleNum - 1;
          for (int step = 0; step < n + 3; step++) {
            expect(idx, inInclusiveRange(0, n - 1));
            idx = (idx + 1) % n;
          }
        });

        // ── Scorecard totals ──────────────────────────────────────────────

        test('total score = ${expected.totalScore}', () {
          final summary = ScorecardViewModel.buildSummary(
            holePlays: holePlays,
            pars: course.pars,
          );
          expect(summary.totalScore, expected.totalScore);
        });

        test('total par = ${expected.totalPar}', () {
          final summary = ScorecardViewModel.buildSummary(
            holePlays: holePlays,
            pars: course.pars,
          );
          expect(summary.totalPar, expected.totalPar);
        });

        test('relToPar = ${expected.relToPar}', () {
          final summary = ScorecardViewModel.buildSummary(
            holePlays: holePlays,
            pars: course.pars,
          );
          expect(summary.totalRelToPar, expected.relToPar);
        });

        test('total putts = ${expected.totalPutts} (2 per hole)', () {
          final summary = ScorecardViewModel.buildSummary(
            holePlays: holePlays,
            pars: course.pars,
          );
          expect(summary.totalPutts, expected.totalPutts);
        });

        test('GIR: ${expected.girHit}/${expected.girTotal} holes', () {
          final summary = ScorecardViewModel.buildSummary(
            holePlays: holePlays,
            pars: course.pars,
          );
          expect(summary.girHit, expected.girHit,
              reason: 'GIR hit count mismatch');
          expect(summary.girTotal, expected.girTotal,
              reason: 'GIR total (measurable holes) mismatch');
        });

        test('FIR: ${expected.firHit}/${expected.firTotal} par-4+ holes', () {
          final summary = ScorecardViewModel.buildSummary(
            holePlays: holePlays,
            pars: course.pars,
          );
          expect(summary.firHit, expected.firHit);
          expect(summary.firTotal, expected.firTotal);
        });

        // ── Per-hole spot checks ──────────────────────────────────────────

        test('scorecard has $n rows in hole-number order', () {
          final rows = ScorecardViewModel.buildRows(
            holePlays: holePlays,
            pars: course.pars,
          );
          expect(rows.length, n);
          for (int i = 0; i < n; i++) {
            expect(rows[i].holeNumber, i + 1,
                reason: 'row $i should be hole ${i + 1}');
          }
        });

        test('each scorecard row shows correct score and par', () {
          final rows = ScorecardViewModel.buildRows(
            holePlays: holePlays,
            pars: course.pars,
          );
          for (final row in rows) {
            final expectedScore =
                scenario.scoreFor(row.holeNumber, course.pars[row.holeNumber]!);
            expect(row.score, expectedScore,
                reason: 'hole ${row.holeNumber} score mismatch');
            expect(row.par, course.pars[row.holeNumber],
                reason: 'hole ${row.holeNumber} par mismatch');
          }
        });
      });
    }
  }
}
