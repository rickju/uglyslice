import 'package:test/test.dart';
import 'package:ugly_slice_backend/course_integrity.dart';
import 'package:ugly_slice_backend/course_parser.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Karori-ish reference coordinates.
const double _baseLat = -41.288;
const double _baseLon = 174.689;

/// Build a point map near the base.
Map<String, double> _pt(double dLat, double dLon) =>
    {'lat': _baseLat + dLat, 'lng': _baseLon + dLon};

/// A minimal valid green polygon (~20 m half-width).
List<Map<String, double>> _greenPoly(double lat, double lng) => [
      {'lat': lat - 0.0001, 'lng': lng - 0.0001},
      {'lat': lat - 0.0001, 'lng': lng + 0.0001},
      {'lat': lat + 0.0001, 'lng': lng + 0.0001},
      {'lat': lat + 0.0001, 'lng': lng - 0.0001},
    ];

/// Builds a minimal valid hole doc for [holeNumber] and [par].
/// All geometry is self-consistent: tee→pin routing ~300 m, pin inside green.
Map<String, dynamic> _validHole(int holeNumber, int par) {
  final tLat = _baseLat + holeNumber * 0.005;
  final tLon = _baseLon;
  // Pin ~250 m north of tee (≈ 0.0023 deg lat).
  final pLat = tLat + 0.0023;
  final pLon = tLon;

  return {
    'holeNumber': holeNumber,
    'par': par,
    'pin': {'lat': pLat, 'lng': pLon},
    'greens': [
      {
        'id': holeNumber,
        'points': _greenPoly(pLat, pLon),
        'tags': {'golf': 'green'},
      }
    ],
    'teePlatforms': [
      {
        'id': holeNumber,
        'points': [
          {'lat': tLat - 0.00005, 'lng': tLon - 0.00005},
          {'lat': tLat - 0.00005, 'lng': tLon + 0.00005},
          {'lat': tLat + 0.00005, 'lng': tLon + 0.00005},
          {'lat': tLat + 0.00005, 'lng': tLon - 0.00005},
        ],
        'tags': {'golf': 'tee'},
      }
    ],
    'fairways': par >= 4
        ? [
            {
              'id': holeNumber,
              'points': [
                {'lat': tLat + 0.001, 'lng': tLon - 0.0003},
                {'lat': tLat + 0.001, 'lng': tLon + 0.0003},
                {'lat': tLat + 0.002, 'lng': tLon + 0.0003},
                {'lat': tLat + 0.002, 'lng': tLon - 0.0003},
              ],
              'tags': {'golf': 'fairway'},
            }
          ]
        : [],
    // Routing: tee → pin (~0.0023 deg = ~256 m — valid for par 3/4/5).
    'routingLine': [
      {'lat': tLat, 'lng': tLon},
      {'lat': tLat + 0.001, 'lng': tLon},
      {'lat': pLat, 'lng': pLon},
    ],
    'teeBoxes': [],
  };
}

/// Build a 18-hole valid course.
ParsedCourse _validCourse18() {
  final pars = [4, 3, 4, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5];
  return ParsedCourse(
    courseId: 'course_test',
    courseDoc: {
      'id': 'course_test',
      'name': 'Test GC',
      'holeCount': 18,
      'boundaryPoints': [_pt(0, 0), _pt(0.1, 0), _pt(0.1, 0.1), _pt(0, 0.1)],
    },
    holeDocs: List.generate(18, (i) => _validHole(i + 1, pars[i])),
  );
}

List<CourseIssue> _errors(List<CourseIssue> issues) =>
    issues.where((i) => i.severity == IssueSeverity.error).toList();

List<CourseIssue> _warnings(List<CourseIssue> issues) =>
    issues.where((i) => i.severity == IssueSeverity.warning).toList();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('checkIntegrity — valid course', () {
    test('perfect 18-hole course has no issues', () {
      final issues = checkIntegrity(_validCourse18());
      expect(issues, isEmpty);
    });

    test('perfect 9-hole course has no issues', () {
      final pars9 = [4, 3, 4, 5, 4, 4, 3, 4, 5];
      final course = ParsedCourse(
        courseId: 'course_9',
        courseDoc: {
          'id': 'course_9',
          'name': 'Test 9-Hole GC',
          'holeCount': 9,
          'boundaryPoints': [_pt(0, 0), _pt(0.1, 0), _pt(0.1, 0.1), _pt(0, 0.1)],
        },
        holeDocs: List.generate(9, (i) => _validHole(i + 1, pars9[i])),
      );
      expect(checkIntegrity(course), isEmpty);
    });
  });

  group('checkIntegrity — course-level errors', () {
    test('no holes → error, returns early', () {
      final course = ParsedCourse(
        courseId: 'c',
        courseDoc: {'id': 'c', 'name': 'Empty', 'holeCount': 0, 'boundaryPoints': []},
        holeDocs: [],
      );
      final issues = checkIntegrity(course);
      expect(_errors(issues).length, equals(1));
      expect(_errors(issues).first.message, contains('No holes'));
    });

    test('27 holes → unusual-hole-count warning', () {
      // Build 27 valid holes.
      final holes = List.generate(27, (i) => _validHole(i + 1, 4));
      final course = ParsedCourse(
        courseId: 'c',
        courseDoc: {'id': 'c', 'name': 'Big GC', 'holeCount': 27, 'boundaryPoints': [_pt(0, 0)]},
        holeDocs: holes,
      );
      final issues = checkIntegrity(course);
      final warn = _warnings(issues).where((i) => i.message.contains('Unusual hole count')).toList();
      expect(warn, isNotEmpty);
      expect(warn.first.message, contains('27'));
    });

    test('missing boundary → warning', () {
      final course = _validCourse18();
      final docNoBoundary = Map<String, dynamic>.from(course.courseDoc)
        ..['boundaryPoints'] = <Map>[];
      final noBoundary = ParsedCourse(
        courseId: course.courseId,
        courseDoc: docNoBoundary,
        holeDocs: course.holeDocs,
      );
      final warnings = _warnings(checkIntegrity(noBoundary));
      expect(warnings.any((i) => i.message.contains('boundary')), isTrue);
    });

    test('duplicate hole numbers → error', () {
      final holes = List.generate(18, (i) => _validHole(i + 1, 4));
      // Make holes 1 and 2 both holeNumber=1.
      holes[1] = Map<String, dynamic>.from(holes[1])..['holeNumber'] = 1;
      final course = ParsedCourse(
        courseId: 'c',
        courseDoc: {'id': 'c', 'name': 'GC', 'holeCount': 18, 'boundaryPoints': [_pt(0, 0)]},
        holeDocs: holes,
      );
      final err = _errors(checkIntegrity(course));
      expect(err.any((i) => i.message.contains('Duplicate')), isTrue);
    });

    test('missing hole number (gap) → error', () {
      final holes = List.generate(18, (i) => _validHole(i + 1, 4));
      // Remove hole 5 and renumber 6..18 → gap at 5.
      holes.removeAt(4);
      for (int i = 4; i < holes.length; i++) {
        holes[i] = Map<String, dynamic>.from(holes[i])..['holeNumber'] = i + 2;
      }
      final course = ParsedCourse(
        courseId: 'c',
        courseDoc: {'id': 'c', 'name': 'GC', 'holeCount': 17, 'boundaryPoints': [_pt(0, 0)]},
        holeDocs: holes,
      );
      final err = _errors(checkIntegrity(course));
      expect(err.any((i) => i.message.contains('Missing')), isTrue);
    });

    test('total par out of range for 18 holes → warning', () {
      // Use all par 3 → total 54 (below 68).
      final course = ParsedCourse(
        courseId: 'c',
        courseDoc: {'id': 'c', 'name': 'GC', 'holeCount': 18, 'boundaryPoints': [_pt(0, 0)]},
        holeDocs: List.generate(18, (i) => _validHole(i + 1, 3)),
      );
      final warn = _warnings(checkIntegrity(course));
      expect(warn.any((i) => i.message.contains('total par')), isTrue);
    });

    test('total par out of range for 9 holes → warning', () {
      // All par 5 → total 45 (above 38).
      final course = ParsedCourse(
        courseId: 'c',
        courseDoc: {'id': 'c', 'name': 'GC', 'holeCount': 9, 'boundaryPoints': [_pt(0, 0)]},
        holeDocs: List.generate(9, (i) => _validHole(i + 1, 5)),
      );
      final warn = _warnings(checkIntegrity(course));
      expect(warn.any((i) => i.message.contains('total par')), isTrue);
    });
  });

  group('checkIntegrity — per-hole errors', () {
    Map<String, dynamic> _patchHole(
        ParsedCourse course, int number, Map<String, dynamic> patch) {
      final h = Map<String, dynamic>.from(
          course.holeDocs.firstWhere((h) => h['holeNumber'] == number));
      patch.forEach((k, v) => h[k] = v);
      return h;
    }

    ParsedCourse _patchedCourse(
        ParsedCourse base, int holeNumber, Map<String, dynamic> patch) {
      final docs = base.holeDocs
          .map((h) => h['holeNumber'] == holeNumber ? _patchHole(base, holeNumber, patch) : h)
          .toList();
      return ParsedCourse(
          courseId: base.courseId, courseDoc: base.courseDoc, holeDocs: docs);
    }

    test('missing par → error', () {
      final course = _patchedCourse(_validCourse18(), 1, {'par': 0});
      final err = _errors(checkIntegrity(course));
      expect(err.any((i) => i.holeNumber == 1 && i.message.contains('par')), isTrue);
    });

    test('invalid par (2) → error', () {
      final course = _patchedCourse(_validCourse18(), 1, {'par': 2});
      final err = _errors(checkIntegrity(course));
      expect(err.any((i) => i.holeNumber == 1 && i.message.contains('Invalid par')), isTrue);
    });

    test('invalid par (6) → error', () {
      final course = _patchedCourse(_validCourse18(), 3, {'par': 6});
      final err = _errors(checkIntegrity(course));
      expect(err.any((i) => i.holeNumber == 3 && i.message.contains('Invalid par')), isTrue);
    });

    test('no green polygon → error', () {
      final course = _patchedCourse(_validCourse18(), 2, {'greens': <dynamic>[]});
      final err = _errors(checkIntegrity(course));
      expect(err.any((i) => i.holeNumber == 2 && i.message.contains('green')), isTrue);
    });

    test('no tee platform and no tee box → error', () {
      final course =
          _patchedCourse(_validCourse18(), 3, {'teePlatforms': <dynamic>[], 'teeBoxes': <dynamic>[]});
      final err = _errors(checkIntegrity(course));
      expect(err.any((i) => i.holeNumber == 3 && i.message.contains('tee')), isTrue);
    });

    test('no tee platform but has tee box node → warning (not error)', () {
      final course = _patchedCourse(_validCourse18(), 4, {
        'teePlatforms': <dynamic>[],
        'teeBoxes': [
          {'lat': -41.288, 'lng': 174.689}
        ],
      });
      final issues = checkIntegrity(course);
      final h4Errors = _errors(issues).where((i) => i.holeNumber == 4).toList();
      final h4Warnings = _warnings(issues).where((i) => i.holeNumber == 4).toList();
      expect(h4Errors.where((i) => i.message.contains('tee')), isEmpty);
      expect(h4Warnings.any((i) => i.message.contains('tee')), isTrue);
    });

    test('par 4 with no fairway → warning', () {
      final hole = Map<String, dynamic>.from(_validHole(5, 4))..['fairways'] = <dynamic>[];
      final docs = [
        ...List.generate(18, (i) => i == 4 ? hole : _validHole(i + 1, [4,3,4,5,4,4,3,4,5,4,3,4,5,4,4,3,4,5][i])),
      ];
      final course = ParsedCourse(
        courseId: 'c',
        courseDoc: _validCourse18().courseDoc,
        holeDocs: docs,
      );
      final warn = _warnings(checkIntegrity(course));
      expect(warn.any((i) => i.holeNumber == 5 && i.message.contains('fairway')), isTrue);
    });

    test('routing line with < 2 points → error', () {
      final course = _patchedCourse(_validCourse18(), 6, {
        'routingLine': [
          {'lat': _baseLat, 'lng': _baseLon}
        ],
      });
      final err = _errors(checkIntegrity(course));
      expect(err.any((i) => i.holeNumber == 6 && i.message.contains('Routing line')), isTrue);
    });

    test('routing line too short for par 3 → warning', () {
      final h = Map<String, dynamic>.from(_validHole(7, 3));
      // Replace routing with 2 points only 5 m apart (<40 m min).
      h['routingLine'] = [
        {'lat': _baseLat + 7 * 0.005, 'lng': _baseLon},
        {'lat': _baseLat + 7 * 0.005 + 0.00005, 'lng': _baseLon},
      ];
      final docs = _validCourse18()
          .holeDocs
          .map((d) => d['holeNumber'] == 7 ? h : d)
          .toList();
      final course = ParsedCourse(
          courseId: 'c', courseDoc: _validCourse18().courseDoc, holeDocs: docs);
      final warn = _warnings(checkIntegrity(course));
      expect(warn.any((i) => i.holeNumber == 7 && i.message.contains('short')), isTrue);
    });

    test('routing line too long for par 3 → warning', () {
      final h = Map<String, dynamic>.from(_validHole(7, 3));
      // Replace routing with 2 points 4 km apart (> 280 m max).
      h['routingLine'] = [
        {'lat': _baseLat + 7 * 0.005, 'lng': _baseLon},
        {'lat': _baseLat + 7 * 0.005 + 0.04, 'lng': _baseLon},
      ];
      final docs = _validCourse18()
          .holeDocs
          .map((d) => d['holeNumber'] == 7 ? h : d)
          .toList();
      final course = ParsedCourse(
          courseId: 'c', courseDoc: _validCourse18().courseDoc, holeDocs: docs);
      final warn = _warnings(checkIntegrity(course));
      expect(warn.any((i) => i.holeNumber == 7 && i.message.contains('long')), isTrue);
    });

    test('pin far outside any green → error', () {
      // Green at base coords, pin 500 m away.
      final tLat = _baseLat + 1 * 0.005;
      final tLon = _baseLon;
      final h = {
        'holeNumber': 1,
        'par': 4,
        'pin': {'lat': tLat + 0.01, 'lng': tLon}, // ~1 km from tee, 500+ m from green
        'greens': [
          {
            'id': 1,
            'points': _greenPoly(tLat + 0.0023, tLon),
            'tags': {'golf': 'green'},
          }
        ],
        'teePlatforms': [
          {
            'id': 1,
            'points': [
              {'lat': tLat - 0.00005, 'lng': tLon - 0.00005},
              {'lat': tLat - 0.00005, 'lng': tLon + 0.00005},
              {'lat': tLat + 0.00005, 'lng': tLon + 0.00005},
              {'lat': tLat + 0.00005, 'lng': tLon - 0.00005},
            ],
            'tags': {},
          }
        ],
        'fairways': <dynamic>[],
        'routingLine': [
          {'lat': tLat, 'lng': tLon},
          {'lat': tLat + 0.0023, 'lng': tLon},
        ],
        'teeBoxes': <dynamic>[],
      };
      final docs = _validCourse18()
          .holeDocs
          .map((d) => d['holeNumber'] == 1 ? h : d)
          .toList();
      final course = ParsedCourse(
          courseId: 'c', courseDoc: _validCourse18().courseDoc, holeDocs: docs);
      final err = _errors(checkIntegrity(course));
      expect(err.any((i) => i.holeNumber == 1 && i.message.contains('Pin')), isTrue);
    });

    test('routing start far from tee → warning', () {
      final base = _validCourse18();
      final h = Map<String, dynamic>.from(base.holeDocs.first);
      // Routing starts 500 m from the tee platform centroid.
      final routingLine = (h['routingLine'] as List).cast<Map<String, dynamic>>();
      final farStart = {'lat': routingLine[0]['lat']! + 0.005, 'lng': routingLine[0]['lng']!};
      h['routingLine'] = [farStart, ...routingLine.skip(1)];
      final docs = base.holeDocs.map((d) => d['holeNumber'] == 1 ? h : d).toList();
      final course = ParsedCourse(courseId: 'c', courseDoc: base.courseDoc, holeDocs: docs);
      final warn = _warnings(checkIntegrity(course));
      expect(warn.any((i) => i.holeNumber == 1 && i.message.contains('start')), isTrue);
    });

    test('routing end far from pin → warning', () {
      final base = _validCourse18();
      final h = Map<String, dynamic>.from(base.holeDocs.first);
      // Routing ends 500 m from pin.
      final routingLine = (h['routingLine'] as List).cast<Map<String, dynamic>>();
      final farEnd = {'lat': routingLine.last['lat']! + 0.005, 'lng': routingLine.last['lng']!};
      h['routingLine'] = [...routingLine.take(routingLine.length - 1), farEnd];
      final docs = base.holeDocs.map((d) => d['holeNumber'] == 1 ? h : d).toList();
      final course = ParsedCourse(courseId: 'c', courseDoc: base.courseDoc, holeDocs: docs);
      final warn = _warnings(checkIntegrity(course));
      expect(warn.any((i) => i.holeNumber == 1 && i.message.contains('end')), isTrue);
    });
  });

  group('CourseIssue.toString', () {
    test('error without holeNumber', () {
      const issue = CourseIssue(severity: IssueSeverity.error, message: 'No holes');
      expect(issue.toString(), contains('[ERROR]'));
      expect(issue.toString(), contains('No holes'));
    });

    test('warning with holeNumber', () {
      const issue = CourseIssue(
          severity: IssueSeverity.warning, message: 'No fairway', holeNumber: 5);
      expect(issue.toString(), contains('[WARN]'));
      expect(issue.toString(), contains('Hole  5'));
    });
  });
}
