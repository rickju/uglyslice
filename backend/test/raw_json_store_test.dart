import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:ugly_slice_backend/raw_json_store.dart';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Use a temp file per test so tests are fully isolated.
  late RawJsonStore store;
  late File dbFile;

  setUp(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmpDir = Directory.systemTemp.createTempSync('raw_json_store_test');
    dbFile = File('${tmpDir.path}/test.db');
    store = RawJsonStore(path: dbFile.path);
  });

  tearDown(() async {
    await store.close();
    if (dbFile.parent.existsSync()) dbFile.parent.deleteSync(recursive: true);
  });

  group('save + load', () {
    test('load returns null when nothing saved', () async {
      final result = await store.load('Karori Golf Club');
      expect(result, isNull);
    });

    test('load returns saved JSON', () async {
      const json = '{"elements":[]}';
      await store.save('Karori Golf Club', json, 0);
      final loaded = await store.load('Karori Golf Club');
      expect(loaded, equals(json));
    });

    test('save is append-only: load returns most recent', () async {
      await store.save('Karori Golf Club', '{"v":1}', 10);
      await Future.delayed(const Duration(milliseconds: 5));
      await store.save('Karori Golf Club', '{"v":2}', 20);

      final loaded = await store.load('Karori Golf Club');
      expect(loaded, equals('{"v":2}'));
    });

    test('multiple courses are stored independently', () async {
      await store.save('Course A', '{"a":1}', 5);
      await store.save('Course B', '{"b":2}', 3);

      expect(await store.load('Course A'), equals('{"a":1}'));
      expect(await store.load('Course B'), equals('{"b":2}'));
    });

    test('load returns null for unknown course name', () async {
      await store.save('Course A', '{"a":1}', 5);
      expect(await store.load('Course X'), isNull);
    });
  });

  group('loadIfFresh', () {
    test('returns JSON when within maxAge', () async {
      await store.save('Fresh Course', '{"fresh":true}', 1);
      final result = await store.loadIfFresh(
        'Fresh Course',
        maxAge: const Duration(hours: 24),
      );
      expect(result, equals('{"fresh":true}'));
    });

    test('returns null when stale (maxAge very small)', () async {
      await store.save('Stale Course', '{"stale":true}', 1);
      await Future.delayed(const Duration(milliseconds: 20));
      final result = await store.loadIfFresh(
        'Stale Course',
        maxAge: const Duration(milliseconds: 1),
      );
      expect(result, isNull);
    });

    test('returns null when nothing saved', () async {
      final result = await store.loadIfFresh('Nobody');
      expect(result, isNull);
    });

    test('fresh check uses most recent version', () async {
      // Old version (will be stale), then a fresh version.
      await store.save('Course', '{"old":true}', 1);
      await Future.delayed(const Duration(milliseconds: 5));
      await store.save('Course', '{"new":true}', 1);

      final result = await store.loadIfFresh(
        'Course',
        maxAge: const Duration(hours: 1),
      );
      expect(result, equals('{"new":true}'));
    });
  });

  group('listNames', () {
    test('returns empty list when nothing saved', () async {
      expect(await store.listNames(), isEmpty);
    });

    test('returns distinct course names in alphabetical order', () async {
      await store.save('Zebra GC', '{}', 0);
      await store.save('Alpha GC', '{}', 0);
      await store.save('Alpha GC', '{}', 0); // duplicate → distinct
      await store.save('Miramar GC', '{}', 0);

      final names = await store.listNames();
      expect(names, equals(['Alpha GC', 'Miramar GC', 'Zebra GC']));
    });

    test('does not include system keys (__ prefix)', () async {
      await store.save('__all_nz__', '{}', 0);
      await store.save('Karori Golf Club', '{}', 0);

      final names = await store.listNames();
      expect(names, equals(['Karori Golf Club']));
      expect(names.any((n) => n.startsWith('__')), isFalse);
    });
  });

  group('search', () {
    setUp(() async {
      await store.save('Karori Golf Club', '{}', 0);
      await store.save('Royal Wellington Golf Club', '{}', 0);
      await store.save('Miramar Links', '{}', 0);
    });

    test('returns matching names (case-sensitive LIKE)', () async {
      final results = await store.search('Golf Club');
      expect(results, containsAll(['Karori Golf Club', 'Royal Wellington Golf Club']));
      expect(results.contains('Miramar Links'), isFalse);
    });

    test('returns all names when query matches everything', () async {
      final results = await store.search('');
      expect(results.length, equals(3));
    });

    test('returns empty when no match', () async {
      final results = await store.search('Zzz');
      expect(results, isEmpty);
    });

    test('does not include system keys', () async {
      await store.save('__all_nz__', '{}', 0);
      final results = await store.search('');
      expect(results.any((n) => n.startsWith('__')), isFalse);
    });
  });

  group('cacheStatus', () {
    test('returns empty list when nothing saved', () async {
      expect(await store.cacheStatus(), isEmpty);
    });

    test('groups by name and includes version count', () async {
      await store.save('Course A', '{"v":1}', 10);
      await Future.delayed(const Duration(milliseconds: 5));
      await store.save('Course A', '{"v":2}', 20);
      await store.save('Course B', '{"v":1}', 5);

      final status = await store.cacheStatus();
      expect(status.length, equals(2));

      final a = status.firstWhere((r) => r['name'] == 'Course A');
      expect(a['versions'], equals(2));

      final b = status.firstWhere((r) => r['name'] == 'Course B');
      expect(b['versions'], equals(1));
    });

    test('sorted by last_fetched descending', () async {
      await store.save('Earlier', '{}', 0);
      await Future.delayed(const Duration(milliseconds: 5));
      await store.save('Later', '{}', 0);

      final status = await store.cacheStatus();
      expect(status.first['name'], equals('Later'));
      expect(status.last['name'], equals('Earlier'));
    });

    test('excludes system keys by default', () async {
      await store.save('__all_nz__', '{}', 0);
      await store.save('Normal', '{}', 0);

      final status = await store.cacheStatus();
      expect(status.any((r) => (r['name'] as String).startsWith('__')), isFalse);
    });

    test('includes system keys when includeSystem=true', () async {
      await store.save('__all_nz__', '{}', 0);
      await store.save('Normal', '{}', 0);

      final status = await store.cacheStatus(includeSystem: true);
      expect(status.any((r) => r['name'] == '__all_nz__'), isTrue);
    });

    test('filter parameter narrows results', () async {
      await store.save('Karori Golf Club', '{}', 0);
      await store.save('Royal Wellington', '{}', 0);

      final status = await store.cacheStatus(filter: 'Karori');
      expect(status.length, equals(1));
      expect(status.first['name'], equals('Karori Golf Club'));
    });
  });
}
