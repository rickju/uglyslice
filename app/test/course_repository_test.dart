/// Unit tests for [CourseRepository] using an in-memory Drift database.
///
/// Run with:
///   flutter test test/course_repository_test.dart
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/database/app_database.dart';
import '../lib/services/course_repository.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

AppDatabase _inMemoryDb() => AppDatabase.forTesting(NativeDatabase.memory());

Map<String, dynamic> _fakeCourseDoc({
  String id = 'course_1',
  String name = 'Test Golf Club',
  int holeCount = 9,
}) =>
    {
      'id': id,
      'name': name,
      'holeCount': holeCount,
      'boundaryPoints': [
        {'lat': -41.29, 'lng': 174.77},
        {'lat': -41.28, 'lng': 174.78},
        {'lat': -41.27, 'lng': 174.77},
      ],
      'teeInfos': [],
      'cartPaths': [],
      'updatedAt': DateTime.now().toIso8601String(),
    };

List<Map<String, dynamic>> _fakeHoleDocs(int count) => List.generate(
      count,
      (i) => {
        'holeNumber': i + 1,
        'par': 4,
        'handicapIndex': i + 1,
        'pin': {'lat': -41.28 + i * 0.001, 'lng': 174.77},
        'routingLine': [
          {'lat': -41.29 + i * 0.001, 'lng': 174.77},
          {'lat': -41.28 + i * 0.001, 'lng': 174.77},
        ],
        'teeBoxes': [
          {'lat': -41.29 + i * 0.001, 'lng': 174.77}
        ],
        'teePlatforms': [],
        'fairways': [],
        'greens': [
          {
            'id': i + 1,
            'points': [
              {'lat': -41.280, 'lng': 174.770},
              {'lat': -41.280, 'lng': 174.771},
              {'lat': -41.279, 'lng': 174.771},
              {'lat': -41.279, 'lng': 174.770},
              {'lat': -41.280, 'lng': 174.770},
            ],
            'tags': {'golf': 'green'},
          }
        ],
      },
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;
  late CourseRepository repo;

  setUp(() {
    db = _inMemoryDb();
    repo = CourseRepository(db);
  });

  tearDown(() => db.close());

  // ── fetchCourse ────────────────────────────────────────────────────────────

  group('fetchCourse', () {
    test('returns null when course is not in DB', () async {
      final result = await repo.fetchCourse('course_missing');
      expect(result, isNull);
    });

    test('returns a Course after saveCourse', () async {
      final courseDoc = _fakeCourseDoc();
      final holeDocs = _fakeHoleDocs(9);
      await repo.saveCourse('course_1', courseDoc, holeDocs);

      final course = await repo.fetchCourse('course_1');
      expect(course, isNotNull);
    });

    test('course name survives round-trip', () async {
      final courseDoc = _fakeCourseDoc(name: 'Karori Golf Club');
      await repo.saveCourse('course_1', courseDoc, _fakeHoleDocs(9));

      final course = await repo.fetchCourse('course_1');
      expect(course!.name, equals('Karori Golf Club'));
    });

    test('hole count survives round-trip', () async {
      final courseDoc = _fakeCourseDoc(holeCount: 9);
      await repo.saveCourse('course_1', courseDoc, _fakeHoleDocs(9));

      final course = await repo.fetchCourse('course_1');
      expect(course!.holes.length, equals(9));
    });

    test('hole numbers are 1..N after round-trip', () async {
      await repo.saveCourse('course_1', _fakeCourseDoc(holeCount: 9),
          _fakeHoleDocs(9));

      final course = await repo.fetchCourse('course_1');
      final nums = course!.holes.map((h) => h.holeNumber).toList()..sort();
      expect(nums, equals(List.generate(9, (i) => i + 1)));
    });

    test('pin coordinates survive round-trip', () async {
      await repo.saveCourse('course_1', _fakeCourseDoc(holeCount: 1),
          _fakeHoleDocs(1));

      final course = await repo.fetchCourse('course_1');
      final pin = course!.holes.first.pin;
      expect(pin.latitude, closeTo(-41.28, 1e-6));
      expect(pin.longitude, closeTo(174.77, 1e-6));
    });

    test('green polygon survives round-trip', () async {
      await repo.saveCourse('course_1', _fakeCourseDoc(holeCount: 1),
          _fakeHoleDocs(1));

      final course = await repo.fetchCourse('course_1');
      expect(course!.holes.first.greens, isNotEmpty);
      expect(course.holes.first.greens.first.points, hasLength(5));
    });
  });

  // ── saveCourse (upsert) ────────────────────────────────────────────────────

  group('saveCourse', () {
    test('second save with same id updates the record', () async {
      await repo.saveCourse(
          'course_1', _fakeCourseDoc(name: 'Old Name'), _fakeHoleDocs(9));
      await repo.saveCourse(
          'course_1', _fakeCourseDoc(name: 'New Name'), _fakeHoleDocs(9));

      final course = await repo.fetchCourse('course_1');
      expect(course!.name, equals('New Name'));
    });

    test('can save two different courses independently', () async {
      await repo.saveCourse(
          'course_1', _fakeCourseDoc(id: 'course_1', name: 'Alpha'), _fakeHoleDocs(9));
      await repo.saveCourse(
          'course_2', _fakeCourseDoc(id: 'course_2', name: 'Beta'), _fakeHoleDocs(18));

      expect((await repo.fetchCourse('course_1'))!.name, equals('Alpha'));
      expect((await repo.fetchCourse('course_2'))!.name, equals('Beta'));
      expect((await repo.fetchCourse('course_2'))!.holes.length, equals(18));
    });
  });
}
