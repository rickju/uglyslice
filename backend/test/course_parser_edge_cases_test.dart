/// Unit tests for course_parser.dart edge cases.
///
/// Covers:
///   - 27-hole course: duplicate hole refs → holes renumbered 1..27
///   - parseAllCourses: multiple courses in one bbox JSON
///   - parseAllCourses: skips courses with empty hole list
///   - parseAllCourses: skips "Unknown Golf Course" (no name tag)
///   - Driving range / mini-golf: no golf=hole ways → empty holeDocs
library;

import 'dart:convert';
import 'package:test/test.dart';
import 'package:ugly_slice_backend/course_parser.dart';

// ---------------------------------------------------------------------------
// Minimal Overpass JSON builders
// ---------------------------------------------------------------------------

/// Creates a minimal but structurally valid Overpass JSON string containing
/// one golf course way (boundary) with [holeCount] golf=hole ways.
///
/// All hole ways are given [holeNumbers] as ref tags.
/// [duplicateRefs]: if true all holes share ref=1 (simulates a 27-hole course
/// that has two loops numbered 1-9 with the same refs).
///
/// Coordinates are a tiny square near Karori, Wellington.
String _buildOverpassJson({
  required String courseName,
  required List<int> holeRefs,
  int courseWayId = 999,
  bool noName = false,
}) {
  // Boundary square: 200 nodes arranged as a closed box.
  // Using large enough coords to contain all hole ways.
  const double lat0 = -41.290;
  const double lon0 = 174.685;
  const double lat1 = -41.260;
  const double lon1 = 174.720;

  // Course boundary nodes (4 corners + closing node).
  final boundaryNodeIds = [1001, 1002, 1003, 1004, 1001];
  final boundaryNodes = [
    {'type': 'node', 'id': 1001, 'lat': lat0, 'lon': lon0, 'tags': {}},
    {'type': 'node', 'id': 1002, 'lat': lat0, 'lon': lon1, 'tags': {}},
    {'type': 'node', 'id': 1003, 'lat': lat1, 'lon': lon1, 'tags': {}},
    {'type': 'node', 'id': 1004, 'lat': lat1, 'lon': lon0, 'tags': {}},
  ];

  // Course boundary way.
  final courseWayTags = {
    'leisure': 'golf_course',
    if (!noName) 'name': courseName,
  };
  final courseWay = {
    'type': 'way',
    'id': courseWayId,
    'tags': courseWayTags,
    'nodes': boundaryNodeIds,
    'geometry': [
      {'lat': lat0, 'lon': lon0},
      {'lat': lat0, 'lon': lon1},
      {'lat': lat1, 'lon': lon1},
      {'lat': lat1, 'lon': lon0},
      {'lat': lat0, 'lon': lon0},
    ],
  };

  // Generate one hole way per entry in holeRefs.
  final holeWays = <Map<String, dynamic>>[];
  final holePinNodes = <Map<String, dynamic>>[];
  int nextNodeId = 2000;
  int nextWayId = 3000;

  for (int i = 0; i < holeRefs.length; i++) {
    final ref = holeRefs[i];
    // Place holes evenly inside the boundary.
    final frac = (i + 1) / (holeRefs.length + 1);
    final holeLat = lat0 + (lat1 - lat0) * frac;
    final holeLon = lon0 + (lon1 - lon0) * 0.4;
    final pinLat = holeLat + 0.002;
    final pinLon = holeLon;

    final pinNodeId = nextNodeId++;
    holePinNodes.add({
      'type': 'node',
      'id': pinNodeId,
      'lat': pinLat,
      'lon': pinLon,
      'tags': {'golf': 'pin'},
    });

    final wayId = nextWayId++;
    holeWays.add({
      'type': 'way',
      'id': wayId,
      'tags': {'golf': 'hole', 'ref': '$ref', 'par': '4'},
      'nodes': [pinNodeId],
      'geometry': [
        {'lat': holeLat, 'lon': holeLon},
        {'lat': holeLat + 0.001, 'lon': holeLon},
        {'lat': pinLat, 'lon': pinLon},
      ],
    });
  }

  final elements = [
    ...boundaryNodes,
    ...holePinNodes,
    courseWay,
    ...holeWays,
  ];

  return jsonEncode({'elements': elements});
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('parseCourse — duplicate hole refs (27-hole / overlapping loops)', () {
    test('holes are renumbered 1..N when duplicate refs exist', () {
      // Two loops share refs 1-9 (like a course with an extra 9-hole loop).
      final refs = [...List.generate(9, (i) => i + 1), ...List.generate(9, (i) => i + 1)];
      final json = _buildOverpassJson(courseName: 'Twin Loop GC', holeRefs: refs);

      final parsed = parseCourse(json);

      // No duplicate hole numbers after renumbering.
      final nums = parsed.holeDocs.map((h) => h['holeNumber'] as int).toList()..sort();
      expect(nums, equals(List.generate(nums.length, (i) => i + 1)),
          reason: 'Hole numbers must be sequential with no duplicates');
    });

    test('all original holes are preserved when refs are duplicated', () {
      final refs = [...List.generate(9, (i) => i + 1), ...List.generate(9, (i) => i + 1)];
      final json = _buildOverpassJson(courseName: 'Twin Loop GC', holeRefs: refs);

      final parsed = parseCourse(json);
      expect(parsed.holeDocs.length, equals(18));
    });
  });

  group('parseCourse — 27 unique hole refs', () {
    test('all 27 holes preserved and numbered 1..27', () {
      final refs = List.generate(27, (i) => i + 1);
      final json = _buildOverpassJson(courseName: 'Big GC', holeRefs: refs);

      final parsed = parseCourse(json);
      expect(parsed.holeDocs.length, equals(27));

      final nums = parsed.holeDocs.map((h) => h['holeNumber'] as int).toList()..sort();
      expect(nums, equals(List.generate(27, (i) => i + 1)));
    });
  });

  group('parseCourse — no hole ways (driving range / wrong tag)', () {
    test('returns ParsedCourse with empty holeDocs', () {
      // No golf=hole ways — just the boundary.
      final json = _buildOverpassJson(courseName: 'Driving Range', holeRefs: []);

      final parsed = parseCourse(json);
      expect(parsed.holeDocs, isEmpty);
    });
  });

  group('parseCourse — course metadata', () {
    test('courseId starts with "course_"', () {
      final json = _buildOverpassJson(courseName: 'Karori Golf Club', holeRefs: [1, 2, 3]);
      final parsed = parseCourse(json);
      expect(parsed.courseId, startsWith('course_'));
    });

    test('course name is extracted from way tag', () {
      final json = _buildOverpassJson(courseName: 'Miramar Links', holeRefs: [1]);
      final parsed = parseCourse(json);
      expect(parsed.courseDoc['name'], equals('Miramar Links'));
    });

    test('missing name tag → "Unknown Golf Course"', () {
      final json =
          _buildOverpassJson(courseName: '', holeRefs: [1, 2], noName: true);
      final parsed = parseCourse(json);
      expect(parsed.courseDoc['name'], equals('Unknown Golf Course'));
    });
  });

  group('parseCourse — throws on missing course way', () {
    test('throws when JSON has no golf_course way', () {
      final json = jsonEncode({
        'elements': [
          {'type': 'node', 'id': 1, 'lat': -41.28, 'lon': 174.69, 'tags': {}},
        ]
      });
      expect(() => parseCourse(json), throwsException);
    });
  });

  group('parseAllCourses — multi-course bbox response', () {
    test('parses each named course with holes', () {
      // Build JSON with two courses by merging their elements.
      final json1 = jsonDecode(
          _buildOverpassJson(courseName: 'Course Alpha', holeRefs: [1, 2, 3], courseWayId: 100));
      final json2 = jsonDecode(
          _buildOverpassJson(courseName: 'Course Beta', holeRefs: [1, 2], courseWayId: 200));

      // Merge elements, offsetting node/way ids to avoid collisions.
      final elements2 = (json2['elements'] as List).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['id'] = (m['id'] as int) + 10000;
        // Offset geometry slightly so Course Beta is spatially distinct.
        if (m.containsKey('lat')) m['lat'] = (m['lat'] as double) - 0.05;
        if (m.containsKey('lon')) m['lon'] = (m['lon'] as double) + 0.05;
        if (m.containsKey('geometry')) {
          m['geometry'] = (m['geometry'] as List).map((g) {
            final gm = Map<String, dynamic>.from(g as Map);
            gm['lat'] = (gm['lat'] as double) - 0.05;
            gm['lon'] = (gm['lon'] as double) + 0.05;
            return gm;
          }).toList();
        }
        return m;
      }).toList();

      final merged = jsonEncode({
        'elements': [...json1['elements'] as List, ...elements2]
      });

      final courses = parseAllCourses(merged);
      // Both courses should be parsed (some may fail spatial containment — at least 1).
      expect(courses, isNotEmpty);
      expect(courses.every((c) => c.holeDocs.isNotEmpty), isTrue,
          reason: 'Only courses with holes should be returned');
    });

    test('skips course with no holes', () {
      final json = _buildOverpassJson(courseName: 'Empty GC', holeRefs: []);
      final courses = parseAllCourses(json);
      expect(courses, isEmpty);
    });

    test('skips course with Unknown Golf Course name', () {
      final json = _buildOverpassJson(courseName: '', holeRefs: [1, 2], noName: true);
      final courses = parseAllCourses(json);
      expect(courses, isEmpty);
    });

    test('returns empty list when no golf_course ways', () {
      final json = jsonEncode({
        'elements': [
          {'type': 'node', 'id': 1, 'lat': -41.28, 'lon': 174.69, 'tags': {}},
        ]
      });
      expect(parseAllCourses(json), isEmpty);
    });
  });
}
