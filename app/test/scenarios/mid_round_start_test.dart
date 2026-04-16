// Scenario: user finds a gap and joins at hole 8, plays through to hole 18,
// then continues from hole 1 to hole 7 to complete the round.
//
// All assertions check what the user actually sees after each action:
//   - Hole number, par, and default/entered score on the display bar
//   - Correct navigation wrap from hole 18 → hole 1
//   - Final scorecard totals and per-hole stats
//
// Course: 18-hole generic (par 72).
// Play order: H8 → H9 → … → H18 → H1 → H2 → … → H7.
// Scores: all at par except H8 and H1 (both bogeys → round total +2).

import 'package:test/test.dart';
import 'package:ugly_slice/viewmodels/round_view_model.dart';
import 'package:ugly_slice/viewmodels/scorecard_view_model.dart';

import 'fixtures.dart';

// ── Planned scores for the round ──────────────────────────────────────────────

// Play order and scores. Key: holeNumber → strokes.
// H8 and H1 are bogeys; the rest are level par.
const _plannedScores = {
  1: 5, // par 4, bogey
  2: 3, // par 3, par
  3: 4, // par 4, par
  4: 5, // par 5, par
  5: 4, // par 4, par
  6: 4, // par 4, par
  7: 3, // par 3, par
  8: 5, // par 4, bogey ← round starts here
  9: 5, // par 5, par
  10: 4, // par 4, par
  11: 3, // par 3, par
  12: 4, // par 4, par
  13: 5, // par 5, par
  14: 4, // par 4, par
  15: 4, // par 4, par
  16: 3, // par 3, par
  17: 4, // par 4, par
  18: 5, // par 5, par
};

// Expected totals
const _expectedTotalScore = 74; // 72 par + 2 bogeys
const _expectedTotalPar = 72;
const _expectedRelToPar = 2; // +2
const _expectedTotalPutts = 36; // 2 putts × 18 holes
// GIR: 16 out of 18 (H1 and H8 missed — score > par for both)
const _expectedGirHit = 16;
const _expectedGirTotal = 18;
// FIR: all 14 par-4+ holes (all fairways, bogeys hit fairway too)
const _expectedFirHit = 14;
const _expectedFirTotal = 14;

// Play order: start at hole 8 (index 7), wrap after hole 18 → hole 1, end at hole 7.
const _playOrder = [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 1, 2, 3, 4, 5, 6, 7];

void main() {
  final holes = makeGeneric18HoleCourse();
  final pars = {for (final h in holes) h.holeNumber: h.par};

  // ── Simulate the full round step by step ──────────────────────────────────

  group('mid-round start at hole 8: navigation and score entry', () {
    // App state mirrors what round_page.dart maintains.
    var currentHoleIndex = 7; // hole 8 (0-based)
    final strokes = <int, int>{}; // holeIndex → stroke count

    // Helper: what the score display bar shows right now.
    HoleStrokeDisplaySnapshot snapshot() {
      final disp = RoundViewModel.computeStrokeDisplay(
        holes: holes,
        holeIndex: currentHoleIndex,
        strokes: strokes,
      );
      return HoleStrokeDisplaySnapshot(
        holeNumber: disp.holeNumber,
        par: disp.par,
        strokes: disp.strokes,
      );
    }

    // ── Step 1: App opens at hole 8 ─────────────────────────────────────────

    test('1. app opens at hole 8 — display shows hole 8, par 4, default to par', () {
      final s = snapshot();
      expect(s.holeNumber, 8, reason: 'first hole shown is hole 8');
      expect(s.par, 4);
      expect(s.strokes, 4, reason: 'no score entered yet → defaults to par');
    });

    // ── Step 2: User taps "+" once → score 5 (bogey) on hole 8 ────────────

    test('2. user taps + to enter bogey (5) on hole 8', () {
      strokes[currentHoleIndex] = (strokes[currentHoleIndex] ?? pars[8]!) + 1;
      final s = snapshot();
      expect(s.holeNumber, 8);
      expect(s.strokes, 5, reason: 'score updated to bogey');
    });

    // ── Step 3: Navigate forward to hole 9 ────────────────────────────────

    test('3. navigate → next: hole 9, par 5, no score yet', () {
      currentHoleIndex = (currentHoleIndex + 1) % 18; // 7 → 8
      final s = snapshot();
      expect(s.holeNumber, 9);
      expect(s.par, 5);
      expect(s.strokes, 5, reason: 'hole 9 not touched → defaults to par 5');
    });

    test('3b. enter par on hole 9', () {
      strokes[currentHoleIndex] = pars[9]!; // 5
      final s = snapshot();
      expect(s.strokes, 5);
    });

    // ── Step 4-10: Play holes 10–16, enter par on each ────────────────────

    for (final holeNum in [10, 11, 12, 13, 14, 15, 16]) {
      test('navigate to hole $holeNum and enter par', () {
        currentHoleIndex = (currentHoleIndex + 1) % 18;
        final s = snapshot();
        expect(s.holeNumber, holeNum, reason: 'navigated to hole $holeNum');
        expect(s.strokes, pars[holeNum]!,
            reason: 'default shows par before entry');
        // Enter par score.
        strokes[currentHoleIndex] = pars[holeNum]!;
        expect(snapshot().strokes, pars[holeNum]!);
      });
    }

    // ── Step 11: Navigate to hole 17 ──────────────────────────────────────

    test('navigate to hole 17 and enter par', () {
      currentHoleIndex = (currentHoleIndex + 1) % 18;
      final s = snapshot();
      expect(s.holeNumber, 17);
      strokes[currentHoleIndex] = pars[17]!;
      expect(snapshot().strokes, pars[17]!);
    });

    // ── Step 12: Navigate to hole 18 (last hole of course) ────────────────

    test('navigate to hole 18 and enter par', () {
      currentHoleIndex = (currentHoleIndex + 1) % 18;
      final s = snapshot();
      expect(s.holeNumber, 18);
      expect(currentHoleIndex, 17, reason: 'index 17 = hole 18');
      strokes[currentHoleIndex] = pars[18]!;
      expect(snapshot().strokes, pars[18]!);
    });

    // ── Step 13: Navigate past hole 18 → wraps back to hole 1 ─────────────

    test('13. navigate past hole 18 → wraps to hole 1', () {
      currentHoleIndex = (currentHoleIndex + 1) % 18; // 17 → 0
      final s = snapshot();
      expect(currentHoleIndex, 0, reason: 'index wraps to 0');
      expect(s.holeNumber, 1, reason: 'wrap shows hole 1');
      expect(s.par, 4);
      expect(s.strokes, 4, reason: 'hole 1 not scored yet → defaults to par');
    });

    // ── Step 14: Enter bogey on hole 1 ────────────────────────────────────

    test('14. enter bogey on hole 1', () {
      // User taps "+" once.
      strokes[currentHoleIndex] = (strokes[currentHoleIndex] ?? pars[1]!) + 1;
      final s = snapshot();
      expect(s.strokes, 5, reason: 'bogey on par 4');
      expect(s.relToPar, 1, reason: '+1 vs par');
    });

    // ── Step 15-20: Play holes 2–7, enter par on each ─────────────────────

    for (final holeNum in [2, 3, 4, 5, 6, 7]) {
      test('navigate to hole $holeNum and enter par', () {
        currentHoleIndex = (currentHoleIndex + 1) % 18;
        final s = snapshot();
        expect(s.holeNumber, holeNum);
        expect(s.strokes, pars[holeNum]!, reason: 'default to par');
        strokes[currentHoleIndex] = pars[holeNum]!;
        expect(snapshot().strokes, pars[holeNum]!);
      });
    }

    // ── Step 21: Verify all 18 holes have scores ───────────────────────────

    test('21. all 18 holes scored — strokes map has 18 entries', () {
      expect(strokes.length, 18,
          reason: 'every hole index 0-17 should have a score');
    });

    test('21b. scores match planned values', () {
      for (int i = 0; i < 18; i++) {
        final holeNum = i + 1;
        expect(strokes[i], _plannedScores[holeNum],
            reason: 'hole $holeNum score should be ${_plannedScores[holeNum]}');
      }
    });
  });

  // ── Final scorecard ────────────────────────────────────────────────────────
  //
  // Build HolePlays from the planned scores using the same shot-pattern as the
  // app (fairway + 2 putts), then verify the numbers shown on the scorecard.

  group('final scorecard after completing all 18 holes', () {
    // Build HolePlays in hole-number order (1-18) from planned scores.
    final holePlays = List.generate(18, (i) {
      final holeNum = i + 1;
      final score = _plannedScores[holeNum]!;
      final par = kGenericPars[i];
      return holePlayForScore(holeNum, par, score);
    });

    late List<dynamic> rows;
    late dynamic summary;

    setUp(() {
      rows = ScorecardViewModel.buildRows(holePlays: holePlays, pars: pars);
      summary = ScorecardViewModel.buildSummary(holePlays: holePlays, pars: pars);
    });

    // ── Per-hole checks ──────────────────────────────────────────────────────

    test('scorecard has 18 rows', () {
      expect(rows.length, 18);
    });

    test('rows are in hole-number order (1 … 18)', () {
      for (int i = 0; i < 18; i++) {
        expect(rows[i].holeNumber, i + 1);
      }
    });

    test('hole 8 row: par 4, score 5, relToPar +1', () {
      final row = rows[7]; // holeNumber 8 = index 7
      expect(row.par, 4);
      expect(row.score, 5);
      expect(row.relToPar, 1);
      expect(ScorecardViewModel.relDisplay(row.relToPar), '+1');
    });

    test('hole 1 row: par 4, score 5, relToPar +1', () {
      final row = rows[0];
      expect(row.par, 4);
      expect(row.score, 5);
      expect(row.relToPar, 1);
    });

    test('hole 9 row: par 5, score 5, relToPar E', () {
      final row = rows[8];
      expect(row.par, 5);
      expect(row.score, 5);
      expect(row.relToPar, 0);
      expect(ScorecardViewModel.relDisplay(row.relToPar), 'E');
    });

    test('all par-3 holes: 2 putts each', () {
      final par3Indices = [1, 6, 10, 15]; // holes 2,7,11,16
      for (final i in par3Indices) {
        expect(rows[i].putts, 2, reason: 'hole ${i + 1} should have 2 putts');
      }
    });

    test('hole 8 GIR is false (bogey on par 4)', () {
      expect(rows[7].gir, isFalse);
    });

    test('hole 1 GIR is false (bogey on par 4)', () {
      expect(rows[0].gir, isFalse);
    });

    test('hole 9 GIR is true (par on par 5)', () {
      expect(rows[8].gir, isTrue);
    });

    test('par 3 holes have null FIR', () {
      final par3Indices = [1, 6, 10, 15];
      for (final i in par3Indices) {
        expect(rows[i].fir, isNull,
            reason: 'hole ${i + 1} is par 3 — FIR not applicable');
      }
    });

    test('all par-4+ holes have FIR true (hit fairway on tee)', () {
      final par4PlusIndices = [0, 2, 3, 4, 5, 7, 8, 9, 11, 12, 13, 14, 16, 17];
      for (final i in par4PlusIndices) {
        expect(rows[i].fir, isTrue,
            reason: 'hole ${i + 1} is par 4+ — should have FIR true');
      }
    });

    // ── Summary totals ───────────────────────────────────────────────────────

    test('total score is $_expectedTotalScore', () {
      expect(summary.totalScore, _expectedTotalScore);
    });

    test('total par is $_expectedTotalPar', () {
      expect(summary.totalPar, _expectedTotalPar);
    });

    test('total relToPar is +$_expectedRelToPar', () {
      expect(summary.totalRelToPar, _expectedRelToPar);
      expect(ScorecardViewModel.relDisplay(summary.totalRelToPar), '+2');
    });

    test('total putts is $_expectedTotalPutts (2 putts × 18 holes)', () {
      expect(summary.totalPutts, _expectedTotalPutts);
    });

    test('GIR: $_expectedGirHit/$_expectedGirTotal → 89%', () {
      expect(summary.girHit, _expectedGirHit);
      expect(summary.girTotal, _expectedGirTotal);
      expect(summary.girPct, '89%');
    });

    test('FIR: $_expectedFirHit/$_expectedFirTotal → 100%', () {
      expect(summary.firHit, _expectedFirHit);
      expect(summary.firTotal, _expectedFirTotal);
      expect(summary.firPct, '100%');
    });
  });
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Snapshot of what the stroke display bar shows at a given moment.
class HoleStrokeDisplaySnapshot {
  final int holeNumber;
  final int par;
  final int strokes;
  int get relToPar => strokes - par;

  const HoleStrokeDisplaySnapshot({
    required this.holeNumber,
    required this.par,
    required this.strokes,
  });
}
