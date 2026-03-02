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

    test('should parse Karori Golf Course real data', () async {
      final file = File('karori.json');
      if (!await file.exists()) {
        markTestSkipped('karori.json file not found');
        return;
      }

      final jsonString = await file.readAsString();
      final course = Course.fromJson(jsonString);

      // Verify basic course info
      expect(course.name, equals('Karori Golf Club'));
      expect(course.id, equals('course_747473941'));

      // Verify boundary polygon exists
      expect(course.boundary, isNotNull);
      expect(course.boundary.getArea(), greaterThan(0));

      // Should have some tee info from the tee ways
      expect(course.teeInfos, isNotEmpty);
      print('Karori tee info count: ${course.teeInfos.length}');

      // Note: Karori doesn't have hole ways with ref tags, so holes will be empty
      // This is expected for this dataset
      print('Karori holes count: ${course.holes.length}');

      // Verify overpass data is preserved
      expect(course.overpass.nodes, isNotEmpty);
      expect(course.overpass.ways, isNotEmpty);

      print('Karori Course parsed successfully:');
      print('  - Name: ${course.name}');
      print('  - ID: ${course.id}');
      print('  - Boundary area: ${course.boundary.getArea()} sq degrees');
      print('  - Tee info types: ${course.teeInfos.length}');
      print('  - Holes: ${course.holes.length}');
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}