import 'package:flutter_test/flutter_test.dart';
import 'package:ugly_slice_shared/round_data.dart';
import 'package:ugly_slice/viewmodels/scorecard_view_model.dart';

import 'fixtures.dart';

void main() {
  group('ScorecardViewModel.putts', () {
    test('counts putter shots', () {
      expect(ScorecardViewModel.putts(parGir4()), equals(2));
    });

    test('counts green lieType shots even without a club assigned', () {
      final hp = makeHolePlay(shots: [
        makeShot(lieType: LieType.fairway),
        makeShot(lieType: LieType.green), // chip from fringe, no club
      ]);
      expect(ScorecardViewModel.putts(hp), equals(1));
    });

    test('returns 0 for empty hole', () {
      expect(ScorecardViewModel.putts(emptyHole()), equals(0));
    });

    test('counts 3 putts correctly', () {
      expect(ScorecardViewModel.putts(doubleBogeyMissedFir()), equals(3));
    });
  });

  group('ScorecardViewModel.gir', () {
    test('true when first green shot is at index == par-2 (par 4, index 2)', () {
      expect(ScorecardViewModel.gir(parGir4(), 4), isTrue);
    });

    test('false when green reached after par-2 index', () {
      // bogeyMissedGir: green at index 3, par-2 = 2 → missed
      expect(ScorecardViewModel.gir(bogeyMissedGir(), 4), isFalse);
    });

    test('true for par 3 birdie (green at index 0, par-2 = 1)', () {
      expect(ScorecardViewModel.gir(par3Birdie(), 3), isTrue);
    });

    test('null when par is 0 (unknown)', () {
      expect(ScorecardViewModel.gir(parGir4(), 0), isNull);
    });

    test('false when no putt/green shot found', () {
      final hp = makeHolePlay(shots: [
        makeShot(lieType: LieType.fairway),
        makeShot(lieType: LieType.rough),
      ]);
      expect(ScorecardViewModel.gir(hp, 4), isFalse);
    });

    test('false for empty hole', () {
      expect(ScorecardViewModel.gir(emptyHole(), 4), isFalse);
    });
  });

  group('ScorecardViewModel.fir', () {
    test('true when shot[1] is in fairway (par 4)', () {
      expect(ScorecardViewModel.fir(parGir4(), 4), isTrue);
    });

    test('false when shot[1] is in rough', () {
      expect(ScorecardViewModel.fir(bogeyMissedGir(), 4), isFalse);
    });

    test('false when shot[1] is in rough (double bogey)', () {
      expect(ScorecardViewModel.fir(doubleBogeyMissedFir(), 4), isFalse);
    });

    test('null for par 3', () {
      expect(ScorecardViewModel.fir(par3Birdie(), 3), isNull);
    });

    test('null for par 0 (unknown)', () {
      expect(ScorecardViewModel.fir(parGir4(), 0), isNull);
    });

    test('null when fewer than 2 shots', () {
      final hp = makeHolePlay(shots: [makeShot(isTeeShot: true)]);
      expect(ScorecardViewModel.fir(hp, 4), isNull);
    });
  });

  group('ScorecardViewModel.relDisplay', () {
    test('"E" for 0', () => expect(ScorecardViewModel.relDisplay(0), equals('E')));
    test('"+3" for 3', () => expect(ScorecardViewModel.relDisplay(3), equals('+3')));
    test('"-1" for -1', () => expect(ScorecardViewModel.relDisplay(-1), equals('-1')));
    test('"-" for null', () => expect(ScorecardViewModel.relDisplay(null), equals('-')));
  });

  group('ScorecardViewModel.clubs', () {
    test('formats Dr·7i·2Pu for standard par 4', () {
      expect(ScorecardViewModel.clubs(parGir4()), equals('Dr·7i·2Pu'));
    });

    test('collapses 3 consecutive putts', () {
      final hp = makeHolePlay(shots: [
        makeShot(club: makeDriver(), lieType: LieType.fairway),
        makeShot(club: makePutter(), lieType: LieType.green),
        makeShot(club: makePutter(), lieType: LieType.green),
        makeShot(club: makePutter(), lieType: LieType.green),
      ]);
      expect(ScorecardViewModel.clubs(hp), equals('Dr·3Pu'));
    });

    test('shows "?" for shots with no club', () {
      final hp = makeHolePlay(shots: [makeShot(lieType: LieType.rough)]);
      expect(ScorecardViewModel.clubs(hp), equals('?'));
    });

    test('empty hole returns empty string', () {
      expect(ScorecardViewModel.clubs(emptyHole()), equals(''));
    });
  });

  group('ScorecardViewModel.buildSummary', () {
    test('50% GIR for 1 hit out of 2 par-4 holes', () {
      final holePlays = [parGir4(holeNumber: 1), bogeyMissedGir(holeNumber: 2)];
      final summary = ScorecardViewModel.buildSummary(
        holePlays: holePlays,
        pars: {1: 4, 2: 4},
      );
      expect(summary.girHit, equals(1));
      expect(summary.girTotal, equals(2));
      expect(summary.girPct, equals('50%'));
    });

    test('50% FIR for 1 hit out of 2 par-4 holes', () {
      final holePlays = [parGir4(holeNumber: 1), doubleBogeyMissedFir(holeNumber: 2)];
      final summary = ScorecardViewModel.buildSummary(
        holePlays: holePlays,
        pars: {1: 4, 2: 4},
      );
      expect(summary.firHit, equals(1));
      expect(summary.firTotal, equals(2));
      expect(summary.firPct, equals('50%'));
    });

    test('par 3 holes do not count toward FIR total', () {
      final holePlays = [par3Birdie(holeNumber: 1), parGir4(holeNumber: 2)];
      final summary = ScorecardViewModel.buildSummary(
        holePlays: holePlays,
        pars: {1: 3, 2: 4},
      );
      // Only hole 2 (par 4) is measurable for FIR.
      expect(summary.firTotal, equals(1));
    });

    test('totalRelToPar is null when pars map is empty', () {
      final summary = ScorecardViewModel.buildSummary(
        holePlays: [parGir4()],
        pars: {},
      );
      expect(summary.totalRelToPar, isNull);
    });

    test('GIR% is "-" when no holes have known par', () {
      final summary = ScorecardViewModel.buildSummary(
        holePlays: [parGir4()],
        pars: {},
      );
      expect(summary.girPct, equals('-'));
    });

    test('totalScore sums all shot counts', () {
      // parGir4 = 4 shots, bogeyMissedGir = 5 shots → total 9
      final summary = ScorecardViewModel.buildSummary(
        holePlays: [parGir4(holeNumber: 1), bogeyMissedGir(holeNumber: 2)],
        pars: {1: 4, 2: 4},
      );
      expect(summary.totalScore, equals(9));
      expect(summary.totalPar, equals(8));
      expect(summary.totalRelToPar, equals(1));
    });

    test('totalPutts sums across all holes', () {
      // parGir4 = 2 putts, bogeyMissedGir = 2 putts → 4
      final summary = ScorecardViewModel.buildSummary(
        holePlays: [parGir4(holeNumber: 1), bogeyMissedGir(holeNumber: 2)],
        pars: {1: 4, 2: 4},
      );
      expect(summary.totalPutts, equals(4));
    });
  });

  group('ScorecardViewModel.buildRows', () {
    test('returns one row per HolePlay', () {
      final rows = ScorecardViewModel.buildRows(
        holePlays: [parGir4(holeNumber: 1), bogeyMissedGir(holeNumber: 2)],
        pars: {1: 4, 2: 4},
      );
      expect(rows, hasLength(2));
    });

    test('row has correct relToPar for even score', () {
      final rows = ScorecardViewModel.buildRows(
        holePlays: [parGir4(holeNumber: 1)], // 4 shots, par 4 → E
        pars: {1: 4},
      );
      expect(rows.first.relToPar, equals(0));
    });

    test('row relToPar is null when par not in map', () {
      final rows = ScorecardViewModel.buildRows(
        holePlays: [parGir4(holeNumber: 7)],
        pars: {}, // no par for hole 7
      );
      expect(rows.first.relToPar, isNull);
      expect(rows.first.par, isNull);
    });
  });
}
