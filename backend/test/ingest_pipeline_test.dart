/// Integration test: course name → Overpass query → parseCourse → SQLite → integrity check.
///
/// Hits the real Overpass API — requires network access.
///
/// Run with defaults (Karori Golf Club):
///   dart test test/ingest_pipeline_test.dart
///
/// Override course name / bbox:
///   dart test test/ingest_pipeline_test.dart -DCOURSE_NAME="Royal Wellington Golf Club"
///   dart test test/ingest_pipeline_test.dart -DCOURSE_NAME="..." -DBBOX="-47.5,166.0,-34.0,179.0"
@Tags(['integration'])
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';
import 'package:ugly_slice_backend/course_parser.dart';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const _courseName =
    String.fromEnvironment('COURSE_NAME', defaultValue: 'Karori Golf Club');
const _bbox =
    String.fromEnvironment('BBOX', defaultValue: '-47.5,166.0,-34.0,179.0');
const _overpassUrl = 'https://overpass-api.de/api/interpreter';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _buildQuery(String courseName, String bbox) => '''
[out:json][timeout:25];
(
  node["leisure"="golf_course"]["name"="$courseName"]($bbox);
  way["leisure"="golf_course"]["name"="$courseName"]($bbox);
  relation["leisure"="golf_course"]["name"="$courseName"]($bbox);
)->.course;
.course out geom;
(
  node(area.course)["golf"];
  way(area.course)["golf"];
  relation(area.course)["golf"];
);
out geom;
''';

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

Future<void> _saveToDb(Database db, ParsedCourse parsed) async {
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
  expect(rows, isNotEmpty, reason: 'Course $courseId not found in DB after save');
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

  setUpAll(() async {
    // 1. Fetch from Overpass
    final response = await http
        .post(Uri.parse(_overpassUrl), body: _buildQuery(_courseName, _bbox))
        .timeout(const Duration(seconds: 40));

    if (response.statusCode != 200) {
      throw StateError('Overpass returned ${response.statusCode}');
    }

    // 2. Parse
    final parsed = parseCourse(response.body);

    // 3. Save to in-memory SQLite
    db = await _openDb();
    await _saveToDb(db, parsed);

    // 4. Load back
    (courseDoc, holeDocs) = await _loadFromDb(db, parsed.courseId);

    print('Loaded: ${courseDoc['name']}  '
        '(${holeDocs.length} holes, id: ${courseDoc['id']})');
  });

  tearDownAll(() async => db.close());

  // ---- Course document ----

  group('course document', () {
    test('id starts with "course_"', () {
      expect(courseDoc['id'], startsWith('course_'));
    });

    test('name matches requested course', () {
      expect(courseDoc['name'], equals(_courseName));
    });

    test('holeCount is 9 or 18', () {
      expect(courseDoc['holeCount'], anyOf(equals(9), equals(18)));
    });

    test('boundary has points', () {
      expect((courseDoc['boundaryPoints'] as List), isNotEmpty);
    });

    test('cartPaths is a list', () {
      expect(courseDoc['cartPaths'], isA<List>());
    });

    test('updatedAt is present', () {
      expect(courseDoc['updatedAt'], isNotNull);
    });
  });

  // ---- Hole list ----

  group('hole list', () {
    test('has at least one hole', () {
      expect(holeDocs, isNotEmpty);
    });

    test('hole count matches courseDoc.holeCount', () {
      expect(holeDocs.length, equals(courseDoc['holeCount']));
    });

    test('holes numbered sequentially from 1', () {
      final nums = holeDocs.map((h) => h['holeNumber'] as int).toList()..sort();
      expect(nums, equals(List.generate(holeDocs.length, (i) => i + 1)));
    });
  });

  // ---- Greens ----

  group('greens', () {
    test('every hole has at least 1 green', () {
      for (final h in holeDocs) {
        expect((h['greens'] as List), isNotEmpty,
            reason: 'Hole ${h['holeNumber']} has no green');
      }
    });

    test('every green has a valid numeric id', () {
      for (final h in holeDocs) {
        for (final gr in (h['greens'] as List).cast<Map<String, dynamic>>()) {
          expect(gr['id'], isA<int>(),
              reason: 'Green on hole ${h['holeNumber']} has bad id');
        }
      }
    });

    test('every green has polygon points', () {
      for (final h in holeDocs) {
        for (final gr in (h['greens'] as List).cast<Map<String, dynamic>>()) {
          expect((gr['points'] as List), isNotEmpty,
              reason: 'Green ${gr['id']} on hole ${h['holeNumber']} has no points');
        }
      }
    });
  });

  // ---- Pins ----

  group('pins', () {
    test('every hole has a pin with valid lat/lng', () {
      for (final h in holeDocs) {
        final pin = h['pin'] as Map?;
        expect(pin, isNotNull,
            reason: 'Hole ${h['holeNumber']} has no pin');
        expect(pin!['lat'], isA<double>(),
            reason: 'Hole ${h['holeNumber']} pin lat is not a double');
        expect(pin['lng'], isA<double>(),
            reason: 'Hole ${h['holeNumber']} pin lng is not a double');
        expect((pin['lat'] as double).abs(), lessThanOrEqualTo(90.0));
        expect((pin['lng'] as double).abs(), lessThanOrEqualTo(180.0));
      }
    });
  });

  // ---- Fairways ----

  group('fairways', () {
    test('fairways list is present on every hole', () {
      for (final h in holeDocs) {
        expect(h['fairways'], isA<List>(),
            reason: 'Hole ${h['holeNumber']} missing fairways field');
      }
    });

    test('every fairway has polygon points', () {
      for (final h in holeDocs) {
        for (final fw in (h['fairways'] as List).cast<Map<String, dynamic>>()) {
          expect((fw['points'] as List), isNotEmpty,
              reason: 'Fairway on hole ${h['holeNumber']} has no points');
        }
      }
    });
  });

  // ---- Tee platforms ----

  group('tee platforms', () {
    test('tee platforms list is present on every hole', () {
      for (final h in holeDocs) {
        expect(h['teePlatforms'], isA<List>(),
            reason: 'Hole ${h['holeNumber']} missing teePlatforms field');
      }
    });

    test('every tee platform has polygon points', () {
      for (final h in holeDocs) {
        for (final tp
            in (h['teePlatforms'] as List).cast<Map<String, dynamic>>()) {
          expect((tp['points'] as List), isNotEmpty,
              reason: 'TeePlatform on hole ${h['holeNumber']} has no points');
        }
      }
    });
  });

  // ---- Routing lines ----

  group('routing lines', () {
    test('every hole has a routing line with at least 2 points', () {
      for (final h in holeDocs) {
        expect((h['routingLine'] as List).length, greaterThanOrEqualTo(2),
            reason: 'Hole ${h['holeNumber']} routing line too short');
      }
    });
  });

  // ---- Par values ----

  group('par values', () {
    test('all par values are 0, 3, 4, or 5', () {
      for (final h in holeDocs) {
        expect(h['par'], anyOf(equals(0), equals(3), equals(4), equals(5)),
            reason:
                'Hole ${h['holeNumber']} has unexpected par value ${h['par']}');
      }
    });
  });
}
