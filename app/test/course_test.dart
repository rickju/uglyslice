import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import '../lib/models/course.dart';

void main() {
  group('Course', () {
    test('should parse Course from simple JSON with golf course and holes', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "node",
            "id": 1001,
            "lat": -41.2866,
            "lon": 174.7772,
            "tags": {"golf": "pin"}
          },
          {
            "type": "node",
            "id": 1002,
            "lat": -41.2867,
            "lon": 174.7773,
            "tags": {"golf": "tee", "tee": "white"}
          },
          {
            "type": "way",
            "id": 2001,
            "nodes": [1001, 1002],
            "tags": {"golf": "hole", "ref": "1", "par": "4", "handicap": "5"}
          },
          {
            "type": "way",
            "id": 2002,
            "geometry": [
              {"lat": -41.2867, "lon": 174.7773},
              {"lat": -41.2868, "lon": 174.7774},
              {"lat": -41.2869, "lon": 174.7775},
              {"lat": -41.2867, "lon": 174.7773}
            ],
            "tags": {"golf": "tee", "tee": "white"}
          },
          {
            "type": "way",
            "id": 3001,
            "geometry": [
              {"lat": -41.2840, "lon": 174.7750},
              {"lat": -41.2880, "lon": 174.7750},
              {"lat": -41.2880, "lon": 174.7800},
              {"lat": -41.2840, "lon": 174.7800},
              {"lat": -41.2840, "lon": 174.7750}
            ],
            "tags": {"leisure": "golf_course", "name": "Test Golf Club"},
            "bounds": {
              "minlat": -41.2880,
              "minlon": 174.7750,
              "maxlat": -41.2840,
              "maxlon": 174.7800
            }
          }
        ]
      }
      ''';

      final course = Course.fromJson(jsonString);

      // Verify course basic info
      expect(course.name, equals('Test Golf Club'));
      expect(course.id, equals('course_3001'));

      // Verify overpass data is stored
      expect(course.overpass.nodes, hasLength(2));
      expect(course.overpass.ways, hasLength(3)); // hole way, tee way, golf course way

      // Verify boundary polygon
      expect(course.boundary, isNotNull);
      expect(course.boundary.getArea(), greaterThan(0));

      // Verify holes are extracted
      print('Course holes found: ${course.holes.length}');
      for (final hole in course.holes) {
        print('  - Hole ${hole.holeNumber}: par ${hole.par}');
      }
      expect(course.holes, hasLength(1));
      final hole = course.holes[0];
      expect(hole.holeNumber, equals(1));
      expect(hole.par, equals(4));
      expect(hole.handicapIndex, equals(5));
      expect(hole.pin.latitude, equals(-41.2866));
      expect(hole.pin.longitude, equals(174.7772));

      // Verify tee info is extracted
      expect(course.teeInfos, hasLength(1));
      expect(course.teeInfos[0].color, equals('white'));
    });

    test('should handle missing golf course way', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "node",
            "id": 1001,
            "lat": -41.2866,
            "lon": 174.7772,
            "tags": {"golf": "pin"}
          }
        ]
      }
      ''';

      expect(
        () => Course.fromJson(jsonString),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle holes without pins gracefully', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "way",
            "id": 2001,
            "geometry": [
              {"lat": -41.2866, "lon": 174.7772},
              {"lat": -41.2867, "lon": 174.7773},
              {"lat": -41.2868, "lon": 174.7774},
              {"lat": -41.2866, "lon": 174.7772}
            ],
            "tags": {"golf": "hole", "ref": "1", "par": "4"},
            "bounds": {
              "minlat": -41.2868,
              "minlon": 174.7772,
              "maxlat": -41.2866,
              "maxlon": 174.7774
            }
          },
          {
            "type": "way",
            "id": 3001,
            "geometry": [
              {"lat": -41.2840, "lon": 174.7750},
              {"lat": -41.2880, "lon": 174.7750},
              {"lat": -41.2880, "lon": 174.7800},
              {"lat": -41.2840, "lon": 174.7800},
              {"lat": -41.2840, "lon": 174.7750}
            ],
            "tags": {"leisure": "golf_course", "name": "Test Golf Club"}
          }
        ]
      }
      ''';

      final course = Course.fromJson(jsonString);

      // Should have no holes since hole without pin is filtered out
      expect(course.holes, hasLength(0));
      expect(course.name, equals('Test Golf Club'));
    });

    test('assigns putting_green to correct hole via spatial containment', () {
      // Pin is at (-41.2870, 174.7780) — a corner of the hole polygon,
      // so the geometry-based pin lookup finds it. Green centroid sits
      // well inside the rectangle, triggering spatial containment assignment.
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "node", "id": 1001,
            "lat": -41.2870, "lon": 174.7780,
            "tags": {"golf": "pin"}
          },
          {
            "type": "way", "id": 2001,
            "geometry": [
              {"lat": -41.2860, "lon": 174.7760},
              {"lat": -41.2870, "lon": 174.7760},
              {"lat": -41.2870, "lon": 174.7780},
              {"lat": -41.2860, "lon": 174.7780},
              {"lat": -41.2860, "lon": 174.7760}
            ],
            "tags": {"golf": "hole", "ref": "1", "par": "4"}
          },
          {
            "type": "way", "id": 2002,
            "geometry": [
              {"lat": -41.2863, "lon": 174.7767},
              {"lat": -41.2865, "lon": 174.7767},
              {"lat": -41.2865, "lon": 174.7770},
              {"lat": -41.2863, "lon": 174.7770},
              {"lat": -41.2863, "lon": 174.7767}
            ],
            "tags": {"golf": "green"}
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
            "tags": {"leisure": "golf_course", "name": "Test Golf Club"}
          }
        ]
      }
      ''';

      final course = Course.fromJson(jsonString);

      for (final h in course.holes) {
        print('Hole ${h.holeNumber}: ${h.greens.length} green(s)');
      }

      expect(course.holes, hasLength(1));
      final hole = course.holes[0];
      expect(hole.holeNumber, equals(1));
      expect(hole.greens, hasLength(1));
      expect(hole.greens[0].id, equals(2002));
    });

    test('should parse Karori Golf Course real data', () async {
      final file = File('karori.json');
      if (!await file.exists()) {
        markTestSkipped('karori.json file not found');
        return;
      }

      final jsonString = await file.readAsString();
      final course = Course.fromJson(jsonString);

      expect(course.name, equals('Karori Golf Club'));
      expect(course.id, equals('course_747473941'));
      expect(course.boundary, isNotNull);
      expect(course.boundary.getArea(), greaterThan(0));
      expect(course.teeInfos, isNotEmpty);
      expect(course.overpass.nodes, isNotEmpty);
      expect(course.overpass.ways, isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('Karori holes have correct fairways assigned', () async {
      final file = File('karori.json');
      if (!await file.exists()) {
        markTestSkipped('karori.json file not found');
        return;
      }

      final jsonString = await file.readAsString();
      final course = Course.fromJson(jsonString);

      expect(course.holes, hasLength(18));

      final byNum = {for (final h in course.holes) h.holeNumber: h};

      // Print for diagnostics
      for (final h in course.holes) {
        print('Hole ${h.holeNumber}: ${h.fairways.length} fairway(s), ${h.greens.length} green(s), ${h.teePlatforms.length} tee platform(s)');
      }

      // Par-3 holes with no fairway way in OSM
      for (final n in [2, 4, 6]) {
        expect(byNum[n]!.fairways, isEmpty, reason: 'Hole $n (par-3) has no fairway in OSM');
      }

      // All other holes get at least 1 fairway (bounding box or nearest fallback)
      for (final h in course.holes.where((h) => ![2, 4, 6].contains(h.holeNumber))) {
        expect(h.fairways, isNotEmpty, reason: 'Hole ${h.holeNumber} should have at least 1 fairway');
      }

      // Holes with 2 fairways (bounding boxes overlap adjacent hole)
      for (final n in [5, 18]) {
        expect(byNum[n]!.fairways, hasLength(2), reason: 'Hole $n should have 2 fairways');
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('Karori holes have correct greens assigned', () async {
      final file = File('karori.json');
      if (!await file.exists()) {
        markTestSkipped('karori.json file not found');
        return;
      }

      final jsonString = await file.readAsString();
      final course = Course.fromJson(jsonString);

      expect(course.holes, hasLength(18));

      final byNum = {for (final h in course.holes) h.holeNumber: h};

      for (final h in course.holes) {
        print('Hole ${h.holeNumber}: ${h.greens.length} green(s)');
      }

      // Holes with no green way in OSM near enough to assign
      for (final n in [7, 16]) {
        expect(byNum[n]!.greens, isEmpty, reason: 'Hole $n has no green in OSM');
      }

      // All other holes get at least 1 green
      for (final h in course.holes.where((h) => ![7, 16].contains(h.holeNumber))) {
        expect(h.greens, isNotEmpty, reason: 'Hole ${h.holeNumber} should have at least 1 green');
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}