/// Unit tests for [Course.fromMap] round-trip serialisation.
///
/// Run with:
///   flutter test test/course_from_map_test.dart
library;

import 'package:test/test.dart';
import 'package:latlong2/latlong.dart';

import '../lib/models/course.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _courseDoc({int holeCount = 9}) => {
      'id': 'course_123',
      'name': 'Test Golf Club',
      'holeCount': holeCount,
      'boundaryPoints': [
        {'lat': -41.290, 'lng': 174.770},
        {'lat': -41.280, 'lng': 174.780},
        {'lat': -41.270, 'lng': 174.770},
        {'lat': -41.290, 'lng': 174.770},
      ],
      'teeInfos': [
        {'name': 'Blue', 'color': 'blue', 'yardage': 5500.0,
         'courseRating': 68.5, 'slopeRating': 120.0},
        {'name': 'Red', 'color': 'red', 'yardage': 4800.0,
         'courseRating': 65.0, 'slopeRating': 110.0},
      ],
      'cartPaths': [],
      'updatedAt': '2024-01-01T00:00:00.000Z',
    };

Map<String, dynamic> _holeDoc(int number) => {
      'holeNumber': number,
      'par': 4,
      'handicapIndex': number,
      'pin': {'lat': -41.280, 'lng': 174.770},
      'routingLine': [
        {'lat': -41.290, 'lng': 174.770},
        {'lat': -41.280, 'lng': 174.770},
      ],
      'teeBoxes': [
        {'lat': -41.290, 'lng': 174.770}
      ],
      'teePlatforms': [
        {
          'id': number * 10,
          'points': [
            {'lat': -41.291, 'lng': 174.769},
            {'lat': -41.291, 'lng': 174.771},
            {'lat': -41.289, 'lng': 174.771},
            {'lat': -41.289, 'lng': 174.769},
            {'lat': -41.291, 'lng': 174.769},
          ],
          'tags': {'golf': 'tee', 'color': 'blue'},
        }
      ],
      'fairways': [
        {
          'id': number * 10 + 1,
          'points': [
            {'lat': -41.286, 'lng': 174.769},
            {'lat': -41.286, 'lng': 174.771},
            {'lat': -41.283, 'lng': 174.771},
            {'lat': -41.283, 'lng': 174.769},
            {'lat': -41.286, 'lng': 174.769},
          ],
          'tags': {'golf': 'fairway'},
        }
      ],
      'greens': [
        {
          'id': number * 10 + 2,
          'points': [
            {'lat': -41.281, 'lng': 174.769},
            {'lat': -41.281, 'lng': 174.771},
            {'lat': -41.279, 'lng': 174.771},
            {'lat': -41.279, 'lng': 174.769},
            {'lat': -41.281, 'lng': 174.769},
          ],
          'tags': {'golf': 'green'},
        }
      ],
    };

List<Map<String, dynamic>> _holeDocs(int count) =>
    List.generate(count, (i) => _holeDoc(i + 1));

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Course.fromMap', () {
    // ── Basic reconstruction ─────────────────────────────────────────────────

    test('id and name are preserved', () {
      final course = Course.fromMap(_courseDoc(), _holeDocs(9));
      expect(course.id, equals('course_123'));
      expect(course.name, equals('Test Golf Club'));
    });

    test('correct number of holes', () {
      final course = Course.fromMap(_courseDoc(holeCount: 9), _holeDocs(9));
      expect(course.holes.length, equals(9));
    });

    test('holes numbered 1..N', () {
      final course = Course.fromMap(_courseDoc(holeCount: 9), _holeDocs(9));
      final nums = course.holes.map((h) => h.holeNumber).toList()..sort();
      expect(nums, equals(List.generate(9, (i) => i + 1)));
    });

    // ── TeeInfos ─────────────────────────────────────────────────────────────

    test('teeInfos are loaded', () {
      final course = Course.fromMap(_courseDoc(), _holeDocs(9));
      expect(course.teeInfos.length, equals(2));
    });

    test('teeInfo fields are preserved', () {
      final course = Course.fromMap(_courseDoc(), _holeDocs(9));
      final blue = course.teeInfos.firstWhere((t) => t.color == 'blue');
      expect(blue.yardage, closeTo(5500.0, 0.01));
      expect(blue.courseRating, closeTo(68.5, 0.01));
      expect(blue.slopeRating, closeTo(120.0, 0.01));
    });

    // ── Boundary ─────────────────────────────────────────────────────────────

    test('boundary polygon is non-null', () {
      final course = Course.fromMap(_courseDoc(), _holeDocs(9));
      expect(course.boundary, isNotNull);
    });

    // ── Per-hole geometry ────────────────────────────────────────────────────

    test('pin coordinates are preserved', () {
      final course = Course.fromMap(_courseDoc(holeCount: 1), _holeDocs(1));
      final pin = course.holes.first.pin;
      expect(pin.latitude, closeTo(-41.280, 1e-6));
      expect(pin.longitude, closeTo(174.770, 1e-6));
    });

    test('par value is preserved', () {
      final course = Course.fromMap(_courseDoc(holeCount: 1), _holeDocs(1));
      expect(course.holes.first.par, equals(4));
    });

    test('teeBoxes are loaded', () {
      final course = Course.fromMap(_courseDoc(holeCount: 1), _holeDocs(1));
      expect(course.holes.first.teeBoxes, isNotEmpty);
    });

    test('teePlatforms are loaded with polygon points', () {
      final course = Course.fromMap(_courseDoc(holeCount: 1), _holeDocs(1));
      final tp = course.holes.first.teePlatforms.first;
      expect(tp.points, hasLength(5));
    });

    test('fairways are loaded with polygon points', () {
      final course = Course.fromMap(_courseDoc(holeCount: 1), _holeDocs(1));
      expect(course.holes.first.fairways, isNotEmpty);
      expect(course.holes.first.fairways.first.points, hasLength(5));
    });

    test('greens are loaded with polygon points', () {
      final course = Course.fromMap(_courseDoc(holeCount: 1), _holeDocs(1));
      expect(course.holes.first.greens, isNotEmpty);
      expect(course.holes.first.greens.first.points, hasLength(5));
    });

    test('routing line is loaded', () {
      final course = Course.fromMap(_courseDoc(holeCount: 1), _holeDocs(1));
      expect(course.holes.first.routingLine, hasLength(2));
    });

    // ── playLine smoke test ──────────────────────────────────────────────────

    test('playLine returns at least 2 points', () {
      final course = Course.fromMap(_courseDoc(holeCount: 1), _holeDocs(1));
      final line = course.holes.first.playLine();
      expect(line.length, greaterThanOrEqualTo(2));
    });

    test('playLine ends at the pin', () {
      final course = Course.fromMap(_courseDoc(holeCount: 1), _holeDocs(1));
      final line = course.holes.first.playLine();
      expect(line.last, equals(const LatLng(-41.280, 174.770)));
    });

    // ── 18-hole ──────────────────────────────────────────────────────────────

    test('18-hole course loads all holes', () {
      final course = Course.fromMap(_courseDoc(holeCount: 18), _holeDocs(18));
      expect(course.holes.length, equals(18));
    });
  });
}
