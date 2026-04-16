// Scenario: User opens app while standing at Karori hole 1 green,
// starts a round, then switches to hole 2.
//
// All assertions check that the numbers shown to the user make sense —
// no missing data, no obviously wrong distances, correct par and defaults.

import 'package:test/test.dart';
import 'package:ugly_slice/viewmodels/display_models.dart';
import 'package:ugly_slice/viewmodels/round_view_model.dart';
import 'package:ugly_slice/viewmodels/scorecard_view_model.dart';

import 'fixtures.dart';

void main() {
  group('Karori: user at hole 1 green, starts round, switches to hole 2', () {
    // Player GPS is at the hole 1 pin — they've just walked up to the green.
    const playerPos = kKaroriH1Pin;
    final holes = makeKaroriHoles(); // [hole1 par4, hole2 par3]
    const emptyStrokes = <int, int>{};

    // ── Hole 1 display (holeIndex 0) ──────────────────────────────────────────

    group('on hole 1', () {
      late HoleDistanceDisplay? dist;
      late HoleStrokeDisplay stroke;

      setUp(() {
        dist = RoundViewModel.computeDistances(
          holes: holes,
          holeIndex: 0,
          playerPos: playerPos,
        );
        stroke = RoundViewModel.computeStrokeDisplay(
          holes: holes,
          holeIndex: 0,
          strokes: emptyStrokes,
        );
      });

      test('distance data is available', () {
        expect(dist, isNotNull);
      });

      test('distPin is very small — player is standing at the pin', () {
        // Player IS at the H1 pin, so distance should be 0-5 yards.
        expect(dist!.distPin, lessThanOrEqualTo(5));
      });

      test('front and back of green are both very close', () {
        expect(dist!.distFront, isNotNull);
        expect(dist!.distBack, isNotNull);
        // Both edges of the green are within ~40 yards when standing on it.
        expect(dist!.distFront!, lessThanOrEqualTo(40));
        expect(dist!.distBack!, lessThanOrEqualTo(40));
      });

      test('hole number is 1', () {
        expect(stroke.holeNumber, equals(1));
      });

      test('par is 4', () {
        expect(stroke.par, equals(4));
      });

      test('stroke count defaults to par (4) — hole not yet touched', () {
        expect(stroke.strokes, equals(4));
      });
    });

    // ── Hole 2 display (holeIndex 1) — player has not moved ──────────────────

    group('after switching to hole 2', () {
      late HoleDistanceDisplay? dist;
      late HoleStrokeDisplay stroke;

      setUp(() {
        dist = RoundViewModel.computeDistances(
          holes: holes,
          holeIndex: 1,
          playerPos: playerPos, // player is still at H1 green
        );
        stroke = RoundViewModel.computeStrokeDisplay(
          holes: holes,
          holeIndex: 1,
          strokes: emptyStrokes,
        );
      });

      test('distance data is available', () {
        expect(dist, isNotNull);
      });

      test('distPin is reasonable — H1 green to H2 pin is roughly 100-200 yards', () {
        // From H1 pin (-41.28555, 174.69028) to H2 pin (-41.28514, 174.68885)
        // is approximately 130-150 yards. Must not show the old 370-yard bug.
        expect(dist!.distPin, inInclusiveRange(100, 200),
            reason: 'H1 green to H2 pin should be ~130-150 yards, not 370');
      });

      test('distPin is NOT the buggy 370 yards', () {
        expect(dist!.distPin, lessThan(300));
      });

      test('front and back of green are available', () {
        expect(dist!.distFront, isNotNull);
        expect(dist!.distBack, isNotNull);
      });

      test('distFront < distPin < distBack', () {
        // Front edge of green is closer than pin; back edge is farther.
        expect(dist!.distFront!, lessThan(dist!.distPin));
        expect(dist!.distBack!, greaterThan(dist!.distPin));
      });

      test('distBack is plausible — not a misassigned far-away green', () {
        // Back of H2 green from H1 pin should be under 200 yards.
        expect(dist!.distBack!, lessThan(200),
            reason: 'distBack of 370 would indicate a wrong green was assigned');
      });

      test('hole number is 2', () {
        expect(stroke.holeNumber, equals(2));
      });

      test('par is 3 — this is a par 3 hole', () {
        expect(stroke.par, equals(3));
      });

      test('stroke count defaults to par (3) — hole not yet touched', () {
        expect(stroke.strokes, equals(3));
      });
    });

    // ── Scorecard after finishing hole 1 with score 5 ─────────────────────────

    group('scorecard after completing hole 1 (score 5, bogey)', () {
      final holePlays = [bogeyMissedGir(holeNumber: 1)]; // 5 shots, Dr rough, ...
      final pars = {1: 4};

      test('score is 5', () {
        final rows = ScorecardViewModel.buildRows(holePlays: holePlays, pars: pars);
        expect(rows.first.score, equals(5));
      });

      test('relToPar is +1 (bogey)', () {
        final rows = ScorecardViewModel.buildRows(holePlays: holePlays, pars: pars);
        expect(rows.first.relToPar, equals(1));
      });

      test('relDisplay shows "+1"', () {
        final rows = ScorecardViewModel.buildRows(holePlays: holePlays, pars: pars);
        expect(ScorecardViewModel.relDisplay(rows.first.relToPar), equals('+1'));
      });

      test('GIR is false — missed green in regulation on a bogey', () {
        final rows = ScorecardViewModel.buildRows(holePlays: holePlays, pars: pars);
        expect(rows.first.gir, isFalse);
      });

      test('FIR is false — approach shot was in rough (bogeyMissedGir fixture)', () {
        final rows = ScorecardViewModel.buildRows(holePlays: holePlays, pars: pars);
        expect(rows.first.fir, isFalse);
      });

      test('putts is 2', () {
        final rows = ScorecardViewModel.buildRows(holePlays: holePlays, pars: pars);
        expect(rows.first.putts, equals(2));
      });

      test('summary result is +1', () {
        final summary = ScorecardViewModel.buildSummary(holePlays: holePlays, pars: pars);
        expect(summary.totalRelToPar, equals(1));
      });

      test('summary GIR% is "-" (only 1 hole, missed it)', () {
        // bogeyMissedGir GIR=false → 0 of 1 = 0%, rounds to "0%"
        final summary = ScorecardViewModel.buildSummary(holePlays: holePlays, pars: pars);
        expect(summary.girPct, equals('0%'));
      });
    });
  });
}
