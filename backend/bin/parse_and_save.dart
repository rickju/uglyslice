/// Standalone script: parse a golf course JSON file and save it to SQLite.
/// Usage: dart run bin/parse_and_save.dart [json_file] [db_path]
/// Defaults: ../app/karori.json  /tmp/ugly_slice_test.db
import 'dart:io';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ugly_slice_backend/course_parser.dart';

Future<void> main(List<String> args) async {
  final jsonFile =
      args.isNotEmpty ? args[0] : '../app/karori.json';
  final dbPath =
      args.length > 1 ? args[1] : '/tmp/ugly_slice_test.db';

  // ---------- Parse ----------
  print('Reading $jsonFile ...');
  final jsonString = await File(jsonFile).readAsString();

  print('Parsing ...');
  final parsed = parseCourse(jsonString);

  print('\n=== Parsed course ===');
  print('ID   : ${parsed.courseId}');
  print('Name : ${parsed.courseDoc['name']}');
  print('Holes: ${parsed.holeDocs.length}');
  for (final h in parsed.holeDocs) {
    final fairways = (h['fairways'] as List).length;
    final greens = (h['greens'] as List).length;
    final tees = (h['teePlatforms'] as List).length;
    final num = h['holeNumber'].toString().padLeft(2);
    print('  Hole $num: par ${h['par']}  '
        '$fairways fairway(s)  $greens green(s)  $tees tee platform(s)');
  }

  // ---------- Save to SQLite ----------
  print('\nSaving to $dbPath ...');
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = await openDatabase(
    dbPath,
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

  // ---------- Verify ----------
  final rows = await db.query(
    'courses',
    columns: ['id', 'name', 'updated_at'],
    where: 'id = ?',
    whereArgs: [parsed.courseId],
  );
  await db.close();

  if (rows.isEmpty) {
    print('ERROR: row not found after insert!');
    exit(1);
  }
  print('Saved!  id=${rows[0]['id']}  name="${rows[0]['name']}"');
  print('DB file: $dbPath');
}
