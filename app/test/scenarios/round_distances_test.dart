import 'package:test/test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ugly_slice/viewmodels/round_view_model.dart';

import 'fixtures.dart';

void main() {
  group('RoundViewModel.computeDistances', () {
    test('returns null when playerPos is null', () {
      final hole = makeHole(pin: kGenericPin, greenPoints: kGenericGreenPoints);
      final result = RoundViewModel.computeDistances(
        holes: [hole],
        holeIndex: 0,
        playerPos: null,
      );
      expect(result, isNull);
    });

    test('returns null when holes list is empty', () {
      final result = RoundViewModel.computeDistances(
        holes: [],
        holeIndex: 0,
        playerPos: kGenericFairway,
      );
      expect(result, isNull);
    });

    test('returns null when holeIndex is out of range', () {
      final hole = makeHole();
      final result = RoundViewModel.computeDistances(
        holes: [hole],
        holeIndex: 5,
        playerPos: kGenericFairway,
      );
      expect(result, isNull);
    });

    test('distPin is non-zero when player is on fairway', () {
      final hole = makeHole(pin: kGenericPin);
      final result = RoundViewModel.computeDistances(
        holes: [hole],
        holeIndex: 0,
        playerPos: kGenericFairway,
      )!;
      expect(result.distPin, greaterThan(0));
    });

    test('distFront and distBack are null when hole has no green polygon', () {
      final hole = makeHole(pin: kGenericPin); // no greenPoints
      final result = RoundViewModel.computeDistances(
        holes: [hole],
        holeIndex: 0,
        playerPos: kGenericFairway,
      )!;
      expect(result.distFront, isNull);
      expect(result.distBack, isNull);
    });

    test('distFront < distPin < distBack when player is off green', () {
      final hole = makeHole(pin: kGenericPin, greenPoints: kGenericGreenPoints);
      final result = RoundViewModel.computeDistances(
        holes: [hole],
        holeIndex: 0,
        playerPos: kGenericFairway,
      )!;
      expect(result.distFront, isNotNull);
      expect(result.distBack, isNotNull);
      expect(result.distFront!, lessThan(result.distPin));
      expect(result.distBack!, greaterThan(result.distPin));
    });

    test('green polygon points >60m from pin are excluded (outlier filter)', () {
      // Add a far-outlier point that should be filtered out.
      final farOutlier = makeHole(
        pin: kGenericPin,
        greenPoints: [
          LatLng(-41.350, 174.700), // ~7 km away — well outside 60 m
          ...kGenericGreenPoints,
        ],
      );
      final result = RoundViewModel.computeDistances(
        holes: [farOutlier],
        holeIndex: 0,
        playerPos: kGenericFairway,
      )!;
      // If the outlier were included, distBack would be thousands of yards.
      expect(result.distBack!, lessThan(500));
    });

    test('Karori hole 2 regression — ~200 yards from tee, not 370', () {
      // Real-world regression: hole 2 was showing 370/343 instead of ~200y.
      // GPS tee-to-pin distance is ~200 yards (scorecard says ~170 from front tees).
      // This test pins the expected distance range so a misassigned green is caught.
      final hole = makeHole(
        number: 2,
        par: 3,
        pin: kKaroriH2Pin,
        greenPoints: kKaroriH2GreenPoints,
      );
      final result = RoundViewModel.computeDistances(
        holes: [hole],
        holeIndex: 0,
        playerPos: kKaroriH2Tee,
      )!;
      expect(result.distPin, inInclusiveRange(170, 230),
          reason: 'Karori hole 2 GPS distance is ~200 yards from tee');
      expect(result.distBack!, lessThan(250),
          reason: 'Back of green should not exceed ~250 yards from tee');
    });
  });

  group('RoundViewModel.computeStrokeDisplay', () {
    test('defaults to par when hole not in strokes map', () {
      final hole = makeHole(number: 3, par: 4);
      final display = RoundViewModel.computeStrokeDisplay(
        holes: [hole],
        holeIndex: 0,
        strokes: {},
      );
      expect(display.strokes, equals(4));
      expect(display.par, equals(4));
      expect(display.holeNumber, equals(3));
    });

    test('reflects manual stroke override', () {
      final hole = makeHole(par: 4);
      final display = RoundViewModel.computeStrokeDisplay(
        holes: [hole],
        holeIndex: 0,
        strokes: {0: 7},
      );
      expect(display.strokes, equals(7));
    });

    test('zero strokes allowed (not yet played, manually zeroed)', () {
      final hole = makeHole(par: 5);
      final display = RoundViewModel.computeStrokeDisplay(
        holes: [hole],
        holeIndex: 0,
        strokes: {0: 0},
      );
      expect(display.strokes, equals(0));
    });
  });

  group('RoundViewModel.shotDistanceYards', () {
    test('returns positive yards for two distinct points', () {
      final d = RoundViewModel.shotDistanceYards(kGenericFairway, kGenericPin);
      expect(d, greaterThan(0));
    });

    test('returns 0 for identical points', () {
      final d = RoundViewModel.shotDistanceYards(kGenericPin, kGenericPin);
      expect(d, equals(0));
    });

    test('is symmetric', () {
      final a = RoundViewModel.shotDistanceYards(kGenericFairway, kGenericPin);
      final b = RoundViewModel.shotDistanceYards(kGenericPin, kGenericFairway);
      expect(a, equals(b));
    });
  });
}
