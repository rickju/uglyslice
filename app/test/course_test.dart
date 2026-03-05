import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import '../lib/models/course.dart';

void main() {
  group('Course', () {
    test('parses basic JSON with hole, pin, tee', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "node", "id": 1001,
            "lat": -41.2866, "lon": 174.7772,
            "tags": {"golf": "pin"}
          },
          {
            "type": "node", "id": 1002,
            "lat": -41.2867, "lon": 174.7773,
            "tags": {"golf": "tee", "tee": "white"}
          },
          {
            "type": "way", "id": 2001,
            "nodes": [1001, 1002],
            "tags": {"golf": "hole", "ref": "1", "par": "4", "handicap": "5"}
          },
          {
            "type": "way", "id": 2002,
            "geometry": [
              {"lat": -41.2867, "lon": 174.7773},
              {"lat": -41.2868, "lon": 174.7774},
              {"lat": -41.2869, "lon": 174.7775},
              {"lat": -41.2867, "lon": 174.7773}
            ],
            "tags": {"golf": "tee", "tee": "white"}
          },
          {
            "type": "way", "id": 3001,
            "geometry": [
              {"lat": -41.2840, "lon": 174.7750},
              {"lat": -41.2880, "lon": 174.7750},
              {"lat": -41.2880, "lon": 174.7800},
              {"lat": -41.2840, "lon": 174.7800},
              {"lat": -41.2840, "lon": 174.7750}
            ],
            "tags": {"leisure": "golf_course", "name": "Test Golf Club"},
            "bounds": {
              "minlat": -41.2880, "minlon": 174.7750,
              "maxlat": -41.2840, "maxlon": 174.7800
            }
          }
        ]
      }
      ''';

      final course = Course.fromJson(jsonString);

      expect(course.name, equals('Test Golf Club'));
      expect(course.id, equals('course_3001'));
      expect(course.boundary.getArea(), greaterThan(0));
      expect(course.holes, hasLength(1));
      expect(course.teeInfos, hasLength(1));
      expect(course.teeInfos[0].color, equals('white'));

      final hole = course.holes[0];
      expect(hole.holeNumber, equals(1));
      expect(hole.par, equals(4));
      expect(hole.handicapIndex, equals(5));
      expect(hole.pin.latitude, equals(-41.2866));
      expect(hole.pin.longitude, equals(174.7772));
    });

    test('throws when no golf_course way in JSON', () {
      const jsonString = '''
      {
        "version": 0.6, "generator": "Overpass API",
        "elements": [
          {"type": "node", "id": 1001, "lat": -41.2866, "lon": 174.7772, "tags": {"golf": "pin"}}
        ]
      }
      ''';
      expect(() => Course.fromJson(jsonString), throwsA(isA<Exception>()));
    });

    test('hole without pin is skipped', () {
      const jsonString = '''
      {
        "version": 0.6, "generator": "Overpass API",
        "elements": [
          {
            "type": "way", "id": 2001,
            "geometry": [
              {"lat": -41.2866, "lon": 174.7772}, {"lat": -41.2867, "lon": 174.7773},
              {"lat": -41.2868, "lon": 174.7774}, {"lat": -41.2866, "lon": 174.7772}
            ],
            "tags": {"golf": "hole", "ref": "1", "par": "4"}
          },
          {
            "type": "way", "id": 3001,
            "geometry": [
              {"lat": -41.2840, "lon": 174.7750}, {"lat": -41.2880, "lon": 174.7750},
              {"lat": -41.2880, "lon": 174.7800}, {"lat": -41.2840, "lon": 174.7800},
              {"lat": -41.2840, "lon": 174.7750}
            ],
            "tags": {"leisure": "golf_course", "name": "Test Golf Club"}
          }
        ]
      }
      ''';
      final course = Course.fromJson(jsonString);
      expect(course.holes, isEmpty);
    });

    test('green assigned to hole via spatial containment', () {
      // Pin is at a geometry corner so position-based lookup finds it.
      // Green centroid sits inside the hole's bounding box.
      const jsonString = '''
      {
        "version": 0.6, "generator": "Overpass API",
        "elements": [
          {
            "type": "node", "id": 1001,
            "lat": -41.2870, "lon": 174.7780,
            "tags": {"golf": "pin"}
          },
          {
            "type": "way", "id": 2001,
            "geometry": [
              {"lat": -41.2860, "lon": 174.7760}, {"lat": -41.2870, "lon": 174.7760},
              {"lat": -41.2870, "lon": 174.7780}, {"lat": -41.2860, "lon": 174.7780},
              {"lat": -41.2860, "lon": 174.7760}
            ],
            "tags": {"golf": "hole", "ref": "1", "par": "4"}
          },
          {
            "type": "way", "id": 2002,
            "geometry": [
              {"lat": -41.2863, "lon": 174.7767}, {"lat": -41.2865, "lon": 174.7767},
              {"lat": -41.2865, "lon": 174.7770}, {"lat": -41.2863, "lon": 174.7770},
              {"lat": -41.2863, "lon": 174.7767}
            ],
            "tags": {"golf": "green"}
          },
          {
            "type": "way", "id": 3001,
            "geometry": [
              {"lat": -41.2840, "lon": 174.7750}, {"lat": -41.2880, "lon": 174.7750},
              {"lat": -41.2880, "lon": 174.7800}, {"lat": -41.2840, "lon": 174.7800},
              {"lat": -41.2840, "lon": 174.7750}
            ],
            "tags": {"leisure": "golf_course", "name": "Test Golf Club"}
          }
        ]
      }
      ''';

      final course = Course.fromJson(jsonString);
      expect(course.holes, hasLength(1));
      expect(course.holes[0].greens, hasLength(1));
      expect(course.holes[0].greens[0].id, equals(2002));
    });

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

    test('Karori Golf Course — 18 holes with fairways, greens, tee platforms', () async {
      final file = File('karori.json');
      if (!await file.exists()) {
        markTestSkipped('karori.json file not found');
        return;
      }

      final jsonString = await file.readAsString();
      final course = Course.fromJson(jsonString);

      expect(course.name, equals('Karori Golf Club'));
      expect(course.id, equals('course_747473941'));
      expect(course.boundary.getArea(), greaterThan(0));
      expect(course.teeInfos, isNotEmpty);
      expect(course.holes, hasLength(18));

      final byNum = {for (final h in course.holes) h.holeNumber: h};

      for (final h in course.holes) {
        print('Hole ${h.holeNumber}: '
            '${h.fairways.length} fairway(s), '
            '${h.greens.length} green(s), '
            '${h.teePlatforms.length} tee platform(s)');
      }

      // Par-3 holes 2/4/6 have no fairway way in OSM
      for (final n in [2, 4, 6]) {
        expect(byNum[n]!.fairways, isEmpty, reason: 'Hole $n (par-3) has no fairway in OSM');
      }
      // All other holes get exactly 1 fairway except 7 and 18 which get 2
      for (final n in [7, 18]) {
        expect(byNum[n]!.fairways, hasLength(2), reason: 'Hole $n should have 2 fairways');
      }
      for (final h in course.holes.where((h) => ![2, 4, 6, 7, 18].contains(h.holeNumber))) {
        expect(h.fairways, hasLength(1), reason: 'Hole ${h.holeNumber} should have 1 fairway');
      }

      // Every hole gets at least 1 green
      for (final h in course.holes) {
        expect(h.greens, isNotEmpty, reason: 'Hole ${h.holeNumber} should have at least 1 green');
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
