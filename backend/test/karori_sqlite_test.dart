/// Integration test: parse karori.json → save to SQLite → load back → verify.
import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ugly_slice_backend/course_parser.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE courses (
          id         TEXT PRIMARY KEY,
          name       TEXT NOT NULL,
          course_doc TEXT NOT NULL,
          holes_doc  TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    },
  );
}

Future<void> _saveToDb(
  Database db,
  ParsedCourse parsed,
) async {
  await db.insert(
    'courses',
    {
      'id': parsed.courseId,
      'name': parsed.courseDoc['name'] as String,
      'course_doc': jsonEncode(parsed.courseDoc),
      'holes_doc': jsonEncode(parsed.holeDocs),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> _loadFromDb(
  Database db,
  String courseId,
) async {
  final rows = await db.query(
    'courses',
    where: 'id = ?',
    whereArgs: [courseId],
    limit: 1,
  );
  expect(rows, isNotEmpty, reason: 'Course $courseId not found in DB');
  final courseDoc =
      jsonDecode(rows[0]['course_doc'] as String) as Map<String, dynamic>;
  final holeDocs = (jsonDecode(rows[0]['holes_doc'] as String) as List)
      .cast<Map<String, dynamic>>();
  return (courseDoc, holeDocs);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Database db;
  late Map<String, dynamic> courseDoc;
  late List<Map<String, dynamic>> holeDocs;
  late Map<int, Map<String, dynamic>> byNum;

  setUpAll(() async {
    final file = File('../app/karori.json');
    if (!await file.exists()) {
      throw StateError('karori.json not found — run tests from backend/ dir');
    }
    final jsonString = await file.readAsString();

    final parsed = parseCourse(jsonString);

    db = await _openDb();
    await _saveToDb(db, parsed);

    (courseDoc, holeDocs) = await _loadFromDb(db, 'course_747473941');
    byNum = {for (final h in holeDocs) h['holeNumber'] as int: h};
  });

  tearDownAll(() => db.close());

  // ---- Course-level ----

  group('course document', () {
    test('id is course_747473941', () {
      expect(courseDoc['id'], equals('course_747473941'));
    });

    test('name is Karori Golf Club', () {
      expect(courseDoc['name'], equals('Karori Golf Club'));
    });

    test('holeCount is 18', () {
      expect(courseDoc['holeCount'], equals(18));
    });

    test('boundary has points in Wellington area', () {
      final pts = (courseDoc['boundaryPoints'] as List).cast<Map>();
      expect(pts, isNotEmpty);
      for (final p in pts.take(5)) {
        expect((p['lat'] as double), lessThan(-41.0));
        expect((p['lng'] as double), greaterThan(174.0));
      }
    });

    test('teeInfos has at least one entry', () {
      expect((courseDoc['teeInfos'] as List), isNotEmpty);
    });

    test('cartPaths is a list (may be empty)', () {
      expect(courseDoc['cartPaths'], isA<List>());
    });

    test('updatedAt is present', () {
      expect(courseDoc['updatedAt'], isNotNull);
    });
  });

  // ---- Hole collection ----

  group('hole list', () {
    test('exactly 18 holes', () {
      expect(holeDocs, hasLength(18));
    });

    test('holes numbered 1–18 with no gaps', () {
      final nums = holeDocs.map((h) => h['holeNumber'] as int).toList()..sort();
      expect(nums, equals(List.generate(18, (i) => i + 1)));
    });
  });

  // ---- Per-hole checks ----

  group('pins', () {
    test('every hole has a pin in Wellington area', () {
      for (final h in holeDocs) {
        final pin = h['pin'] as Map;
        final lat = pin['lat'] as double;
        final lng = pin['lng'] as double;
        expect(lat, lessThan(-41.0),
            reason: 'Hole ${h['holeNumber']} pin lat out of range');
        expect(lat, greaterThan(-42.0),
            reason: 'Hole ${h['holeNumber']} pin lat out of range');
        expect(lng, greaterThan(174.0),
            reason: 'Hole ${h['holeNumber']} pin lng out of range');
        expect(lng, lessThan(175.0),
            reason: 'Hole ${h['holeNumber']} pin lng out of range');
      }
    });
  });

  group('par values', () {
    // Karori layout: par-3 = 2,4,6,13 | par-5 = 7,14 | par-0 = 12 (missing OSM tag)
    test('par-3 holes are 2, 4, 6, 13', () {
      for (final n in [2, 4, 6, 13]) {
        expect(byNum[n]!['par'], equals(3), reason: 'Hole $n should be par-3');
      }
    });

    test('par-5 holes are 7 and 14', () {
      expect(byNum[7]!['par'], equals(5));
      expect(byNum[14]!['par'], equals(5));
    });

    test('remaining holes are par-4 (hole 12 has missing OSM tag → par 0)', () {
      for (final h in holeDocs) {
        final n = h['holeNumber'] as int;
        if ([2, 4, 6, 7, 13, 14, 12].contains(n)) continue;
        expect(h['par'], equals(4), reason: 'Hole $n should be par-4');
      }
    });

    test('hole 12 has par 0 (missing OSM tag — known data gap)', () {
      expect(byNum[12]!['par'], equals(0));
    });
  });

  group('fairways', () {
    test('par-3 holes 2, 4, 6 have no fairway', () {
      for (final n in [2, 4, 6]) {
        expect((byNum[n]!['fairways'] as List), isEmpty,
            reason: 'Hole $n (par-3) should have no fairway');
      }
    });

    test('holes 7 and 18 have 2 fairways each', () {
      expect((byNum[7]!['fairways'] as List), hasLength(2));
      expect((byNum[18]!['fairways'] as List), hasLength(2));
    });

    test('all other holes have exactly 1 fairway', () {
      for (final h in holeDocs) {
        final n = h['holeNumber'] as int;
        if ([2, 4, 6, 7, 18].contains(n)) continue;
        expect((h['fairways'] as List), hasLength(1),
            reason: 'Hole $n should have 1 fairway');
      }
    });

    test('every fairway has polygon points', () {
      for (final h in holeDocs) {
        for (final fw
            in (h['fairways'] as List).cast<Map<String, dynamic>>()) {
          expect((fw['points'] as List), isNotEmpty,
              reason: 'Fairway ${fw['id']} on hole ${h['holeNumber']} has no points');
        }
      }
    });
  });

  group('greens', () {
    test('every hole has at least 1 green', () {
      for (final h in holeDocs) {
        expect((h['greens'] as List), isNotEmpty,
            reason: 'Hole ${h['holeNumber']} has no green');
      }
    });

    test('every green has polygon points', () {
      for (final h in holeDocs) {
        for (final gr
            in (h['greens'] as List).cast<Map<String, dynamic>>()) {
          expect((gr['points'] as List), isNotEmpty,
              reason: 'Green ${gr['id']} on hole ${h['holeNumber']} has no points');
        }
      }
    });

    test('every green has a valid numeric id', () {
      for (final h in holeDocs) {
        for (final gr
            in (h['greens'] as List).cast<Map<String, dynamic>>()) {
          expect(gr['id'], isA<int>());
        }
      }
    });
  });

  group('tee platforms', () {
    test('hole 1 has 3 tee platforms', () {
      expect((byNum[1]!['teePlatforms'] as List), hasLength(3));
    });

    test('every tee platform has polygon points', () {
      for (final h in holeDocs) {
        for (final tp
            in (h['teePlatforms'] as List).cast<Map<String, dynamic>>()) {
          expect((tp['points'] as List), isNotEmpty,
              reason:
                  'TeePlatform ${tp['id']} on hole ${h['holeNumber']} has no points');
        }
      }
    });
  });

  group('routing lines', () {
    test('every hole has a routing line with at least 2 points', () {
      for (final h in holeDocs) {
        expect((h['routingLine'] as List).length, greaterThanOrEqualTo(2),
            reason: 'Hole ${h['holeNumber']} routing line too short');
      }
    });
  });
}
