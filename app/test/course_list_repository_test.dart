/// Unit tests for [CourseListRepository].
///
/// Run with:
///   flutter test test/course_list_repository_test.dart
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/database/app_database.dart';
import '../lib/services/course_list_repository.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _inMemoryDb() => AppDatabase.forTesting(NativeDatabase.memory());

Future<void> _seedCourses(
    AppDatabase db, List<Map<String, dynamic>> courses) async {
  await db.batch((batch) {
    batch.insertAll(
      db.courseListTable,
      courses.map((c) => CourseListTableCompanion.insert(
            id: Value(c['id'] as int),
            name: c['name'] as String,
            type: c['type'] as String,
            lat: c['lat'] as double,
            lon: c['lon'] as double,
          )),
      mode: InsertMode.insertOrReplace,
    );
  });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;

  setUp(() => db = _inMemoryDb());
  tearDown(() => db.close());

  // ── isEmpty ────────────────────────────────────────────────────────────────

  group('isEmpty', () {
    test('true on fresh DB', () async {
      final repo = CourseListRepository(db);
      expect(await repo.isEmpty, isTrue);
    });

    test('false after inserting a course', () async {
      await _seedCourses(db, [
        {'id': 1, 'type': 'way', 'name': 'Alpha GC', 'lat': -41.0, 'lon': 174.0},
      ]);
      final repo = CourseListRepository(db);
      expect(await repo.isEmpty, isFalse);
    });
  });

  // ── listCourses ────────────────────────────────────────────────────────────

  group('listCourses', () {
    test('returns empty list on fresh DB', () async {
      final repo = CourseListRepository(db);
      expect(await repo.listCourses(), isEmpty);
    });

    test('results are sorted alphabetically by name', () async {
      await _seedCourses(db, [
        {'id': 1, 'type': 'way', 'name': 'Zebra GC',  'lat': -41.0, 'lon': 174.0},
        {'id': 2, 'type': 'way', 'name': 'Alpha GC',  'lat': -41.1, 'lon': 174.1},
        {'id': 3, 'type': 'way', 'name': 'Middle GC', 'lat': -41.2, 'lon': 174.2},
      ]);
      final repo = CourseListRepository(db);
      final names = (await repo.listCourses()).map((c) => c.name).toList();
      expect(names, equals(['Alpha GC', 'Middle GC', 'Zebra GC']));
    });

    test('lat/lon are stored and retrieved correctly', () async {
      await _seedCourses(db, [
        {'id': 7, 'type': 'way', 'name': 'Karori GC',
         'lat': -41.2865, 'lon': 174.7421},
      ]);
      final repo = CourseListRepository(db);
      final c = (await repo.listCourses()).first;
      expect(c.lat, closeTo(-41.2865, 1e-4));
      expect(c.lon, closeTo(174.7421, 1e-4));
    });

    test('upsert on re-insert does not duplicate rows', () async {
      final courses = [
        {'id': 1, 'type': 'way', 'name': 'Alpha GC', 'lat': -41.0, 'lon': 174.0},
      ];
      await _seedCourses(db, courses);
      await _seedCourses(db, courses);
      final repo = CourseListRepository(db);
      expect(await repo.listCourses(), hasLength(1));
    });
  });

  // ── search ─────────────────────────────────────────────────────────────────

  group('search', () {
    late CourseListRepository repo;

    setUp(() async {
      await _seedCourses(db, [
        {'id': 1, 'type': 'way', 'name': 'Karori Golf Club',    'lat': -41.0, 'lon': 174.0},
        {'id': 2, 'type': 'way', 'name': 'Royal Wellington GC', 'lat': -41.1, 'lon': 174.1},
        {'id': 3, 'type': 'way', 'name': 'Paraparaumu Beach',   'lat': -40.9, 'lon': 175.0},
      ]);
      repo = CourseListRepository(db);
    });

    test('empty query returns all courses', () async {
      expect(await repo.search(''), hasLength(3));
    });

    test('filters by substring case-insensitively', () async {
      final results = await repo.search('wellington');
      expect(results, hasLength(1));
      expect(results.first.name, equals('Royal Wellington GC'));
    });

    test('returns empty list when no match', () async {
      expect(await repo.search('zzzzz'), isEmpty);
    });

    test('matches partial name', () async {
      final results = await repo.search('para');
      expect(results.first.name, contains('Paraparaumu'));
    });
  });
}
