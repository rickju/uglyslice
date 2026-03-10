import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import '../lib/models/course.dart';

void main() {
  group('Course', () {
    group('Hole.playLine()', () {
      // Layout:
      //   tee  (-41.290, 174.770)  — south
      //   fairway centroid (-41.280, 174.770) — due north of tee  (dogleg corner)
      //   pin  (-41.280, 174.790)  — due east of fairway          (dogleg target)
      //
      // Straight tee→pin bearing ≈ 27° (NNE).
      // Correct dogleg bearing   ≈  0° (N) toward fairway first.
      final tee = LatLng(-41.290, 174.770);
      final pin = LatLng(-41.280, 174.790);

      // Square fairway polygon whose centroid is (-41.280, 174.770)
      final fairwayPoints = [
        LatLng(-41.279, 174.769), LatLng(-41.279, 174.771),
        LatLng(-41.281, 174.771), LatLng(-41.281, 174.769),
        LatLng(-41.279, 174.769), // closed ring
      ];

      Hole makeHole({List<Fairway> fairways = const []}) => Hole(
            holeNumber: 1,
            par: 4,
            pin: pin,
            teeBoxes: [TeeBox(position: tee)],
            fairways: fairways,
          );

      test('straight hole — 2 waypoints, ends at pin', () {
        final line = makeHole().playLine();
        expect(line, hasLength(2));
        expect(line.first.latitude, closeTo(tee.latitude, 1e-6));
        expect(line.last, equals(pin));
      });

      test('dogleg hole — 3 waypoints, first bearing toward fairway not pin', () {
        final fairway = Fairway(
          id: 99,
          points: fairwayPoints,
          tags: {'golf': 'fairway'},
        );
        final line = makeHole(fairways: [fairway]).playLine();
        expect(line, hasLength(3));
        expect(line.first.latitude, closeTo(tee.latitude, 1e-6));
        expect(line.last, equals(pin));

        // Fairway centroid longitude ≈ 174.770 (same as tee, due north).
        // Pin longitude = 174.790 (east). Middle waypoint must be near 174.770.
        expect(line[1].longitude, closeTo(174.770, 0.001));

        // First bearing should be ~0° (north), not ~27° (toward pin).
        final bearing = const Distance().bearing(line[0], line[1]);
        expect(bearing, closeTo(0.0, 5.0)); // within 5° of due north
      });
    });
  });
}
