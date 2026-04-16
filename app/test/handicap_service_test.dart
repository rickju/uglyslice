import 'package:test/test.dart';
import 'package:ugly_slice/services/handicap_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a round record with the given score and holes.
/// courseId defaults to 'course_x' which has no entry in CourseRatingStore,
/// so the path_provider-free code path (no override) is exercised.
({int score, int holes, String courseId}) r(int score,
        {int holes = 18, String courseId = 'course_x'}) =>
    (score: score, holes: holes, courseId: courseId);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('HandicapResult.display', () {
    test('returns -- when totalRounds is 0', () {
      expect(HandicapResult.none.display, equals('--'));
    });

    test('shows ~ prefix when estimated', () {
      const result = HandicapResult(
          index: 12.3, isEstimated: true, roundsUsed: 1, totalRounds: 1);
      expect(result.display, equals('~12.3'));
    });

    test('no ~ prefix when not estimated', () {
      const result = HandicapResult(
          index: 12.3, isEstimated: false, roundsUsed: 1, totalRounds: 1);
      expect(result.display, equals('12.3'));
    });

    test('one decimal place', () {
      const result = HandicapResult(
          index: 5.0, isEstimated: false, roundsUsed: 1, totalRounds: 1);
      expect(result.display, equals('5.0'));
    });
  });

  group('HandicapService.calculate — basic', () {
    test('empty rounds returns none', () {
      final result = HandicapService.calculate(rounds: []);
      expect(result.totalRounds, equals(0));
      expect(result.display, equals('--'));
    });

    test('rounds with score=0 are skipped', () {
      final result = HandicapService.calculate(rounds: [r(0)]);
      expect(result.totalRounds, equals(0));
      expect(result.display, equals('--'));
    });

    test('single round produces index', () {
      // diff = (113/113) * (85 - 72) = 13.0; idx = 13.0 * 0.96 = 12.48
      final result = HandicapService.calculate(rounds: [r(85)]);
      expect(result.totalRounds, equals(1));
      expect(result.roundsUsed, equals(1));
      expect(result.index, closeTo(12.48, 0.01));
      expect(result.isEstimated, isTrue); // no coursePars supplied
    });

    test('index is estimated when no coursePars', () {
      final result = HandicapService.calculate(rounds: [r(80)]);
      expect(result.isEstimated, isTrue);
    });

    test('index is still estimated with coursePars (slope always falls back to 113)', () {
      // coursePars provides the par value but not a real slope rating,
      // so the differential is still "estimated" per WHS terms.
      final result = HandicapService.calculate(
        rounds: [r(80, courseId: 'c1')],
        coursePars: {'c1': 72.0},
      );
      expect(result.isEstimated, isTrue);
    });

    test('estimated is always true when no CourseRatingStore override exists', () {
      // isEstimated is true whenever we fall back to slope=113 (no override).
      // coursePars helps with par value but doesn't affect the estimated flag.
      final result = HandicapService.calculate(
        rounds: [r(80, courseId: 'c1'), r(82, courseId: 'c2')],
        coursePars: {'c1': 72.0, 'c2': 72.0},
      );
      expect(result.isEstimated, isTrue);
    });
  });

  group('HandicapService.calculate — par fallbacks', () {
    test('18-hole round falls back to par 72 when no coursePars', () {
      // diff = (113/113) * (80 - 72) = 8.0; idx = 8.0 * 0.96 = 7.68
      final result = HandicapService.calculate(rounds: [r(80, holes: 18)]);
      expect(result.index, closeTo(7.68, 0.01));
    });

    test('9-hole round (holes < 14) falls back to par 36', () {
      // diff = (113/113) * (42 - 36) = 6.0; idx = 6.0 * 0.96 = 5.76
      final result = HandicapService.calculate(rounds: [r(42, holes: 9)]);
      expect(result.index, closeTo(5.76, 0.01));
    });

    test('holes=14 treated as 18-hole (threshold)', () {
      // holes >= 14 → par 72
      final result = HandicapService.calculate(rounds: [r(80, holes: 14)]);
      expect(result.index, closeTo(7.68, 0.01));
    });

    test('holes=13 treated as 9-hole', () {
      // holes < 14 → par 36
      final result = HandicapService.calculate(rounds: [r(42, holes: 13)]);
      expect(result.index, closeTo(5.76, 0.01));
    });
  });

  group('HandicapService.calculate — WHS differential count table', () {
    List<({int score, int holes, String courseId})> nRounds(int n) =>
        List.generate(n, (_) => r(80));

    test('1..5 rounds: use 1 best', () {
      for (int n = 1; n <= 5; n++) {
        final res = HandicapService.calculate(rounds: nRounds(n));
        expect(res.roundsUsed, equals(1), reason: 'n=$n');
      }
    });

    test('6..8 rounds: use 2 best', () {
      for (int n = 6; n <= 8; n++) {
        final res = HandicapService.calculate(rounds: nRounds(n));
        expect(res.roundsUsed, equals(2), reason: 'n=$n');
      }
    });

    test('9..11 rounds: use 3 best', () {
      for (int n = 9; n <= 11; n++) {
        final res = HandicapService.calculate(rounds: nRounds(n));
        expect(res.roundsUsed, equals(3), reason: 'n=$n');
      }
    });

    test('12..14 rounds: use 4 best', () {
      for (int n = 12; n <= 14; n++) {
        final res = HandicapService.calculate(rounds: nRounds(n));
        expect(res.roundsUsed, equals(4), reason: 'n=$n');
      }
    });

    test('15..16 rounds: use 5 best', () {
      for (int n = 15; n <= 16; n++) {
        final res = HandicapService.calculate(rounds: nRounds(n));
        expect(res.roundsUsed, equals(5), reason: 'n=$n');
      }
    });

    test('17..18 rounds: use 6 best', () {
      for (int n = 17; n <= 18; n++) {
        final res = HandicapService.calculate(rounds: nRounds(n));
        expect(res.roundsUsed, equals(6), reason: 'n=$n');
      }
    });

    test('19 rounds: use 7 best', () {
      final res = HandicapService.calculate(rounds: nRounds(19));
      expect(res.roundsUsed, equals(7));
    });

    test('20+ rounds: use 8 best (cap)', () {
      final res = HandicapService.calculate(rounds: nRounds(20));
      expect(res.roundsUsed, equals(8));
      // Additional rounds beyond 20 are ignored.
      final res25 = HandicapService.calculate(rounds: nRounds(25));
      expect(res25.roundsUsed, equals(8));
      expect(res25.totalRounds, equals(20)); // only 20 considered
    });
  });

  group('HandicapService.calculate — sorting and best selection', () {
    test('uses best (lowest) differentials', () {
      // 3 rounds: 72 (diff 0), 80 (diff 8), 90 (diff 18).
      // 3 rounds → use 1 best → diff for 72 = 0. idx = 0 * 0.96 = 0.0
      final result = HandicapService.calculate(
        rounds: [r(90), r(72), r(80)], // deliberately disordered
      );
      expect(result.index, closeTo(0.0, 0.01));
    });

    test('negative differential when score below par', () {
      // Score 68, par 72 → diff = -4.0, idx = -4.0 * 0.96 = -3.84
      final result = HandicapService.calculate(
        rounds: [r(68)],
        coursePars: {'course_x': 72.0},
      );
      expect(result.index, closeTo(-3.84, 0.01));
    });
  });

  group('HandicapService.calculate — clamp', () {
    test('clamps maximum at 54.0', () {
      // Score 200, par 72 → diff = 128 → avg * 0.96 >> 54
      final result = HandicapService.calculate(rounds: [r(200)]);
      expect(result.index, equals(54.0));
    });

    test('clamps minimum at -10.0', () {
      // Score 30, par 72 → diff very negative
      final result = HandicapService.calculate(
        rounds: [r(30)],
        coursePars: {'course_x': 72.0},
      );
      expect(result.index, equals(-10.0));
    });
  });

  group('HandicapService.calculate — takes only 20 most recent', () {
    test('only first 20 rounds are considered', () {
      // Build 25 rounds: first 20 have score 80 (diff ~7.68), last 5 score 60 (diff very negative).
      // If last 5 were included they'd be the best → index would be much lower.
      final rounds = [
        ...List.generate(20, (_) => r(80)),
        ...List.generate(5, (_) => r(60)),
      ];
      final result = HandicapService.calculate(rounds: rounds);
      expect(result.totalRounds, equals(20));
      // The best diff from 20 × score-80 rounds should be ~7.68.
      expect(result.index, greaterThan(0.0));
    });
  });
}
