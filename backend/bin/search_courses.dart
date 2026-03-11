/// Interactive course search — type to filter, results update live from SQLite.
/// On selection: checks for full parsed data, fetches from Overpass if missing.
///
/// Usage:
///   dart run bin/search_courses.dart
///   dart run bin/search_courses.dart --db /tmp/ugly_slice_courses.db
///   dart run bin/search_courses.dart --limit 15
///
/// Keys:
///   Any char  — append to query
///   Backspace — delete last char
///   Enter     — select course (fetch + parse if not cached)
///   Escape    — exit
///   ↑ / ↓    — move selection up / down
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ugly_slice_backend/course_parser.dart';

// ANSI helpers
const _reset = '\x1B[0m';
const _bold = '\x1B[1m';
const _cyan = '\x1B[36m';
const _yellow = '\x1B[33m';
const _green = '\x1B[32m';
const _red = '\x1B[31m';
const _clearLine = '\x1B[2K\r';
const _clearDown = '\x1B[J';

void _up(int n) { if (n > 0) stdout.write('\x1B[${n}A'); }

const _overpassUrl = 'https://overpass-api.de/api/interpreter';

// ---------------------------------------------------------------------------

void main(List<String> args) async {
  var dbPath = '/tmp/ugly_slice_courses.db';
  var limit = 10;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--db' && i + 1 < args.length) dbPath = args[++i];
    if (args[i] == '--limit' && i + 1 < args.length) limit = int.parse(args[++i]);
  }

  if (!File(dbPath).existsSync()) {
    stderr.writeln('DB not found: $dbPath');
    stderr.writeln('Run: dart run bin/fetch_course_list.dart --db $dbPath');
    exit(1);
  }

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Open read-write so we can create the courses table and save parsed data
  final db = await openDatabase(
    dbPath,
    version: 1,
    onOpen: (db) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS courses (
          id         TEXT PRIMARY KEY,
          name       TEXT NOT NULL,
          course_doc TEXT NOT NULL,
          holes_doc  TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    },
  );

  stdin.echoMode = false;
  stdin.lineMode = false;

  var query = '';
  var selected = 0;
  var results = <Map<String, Object?>>[];

  Future<void> refresh() async {
    if (query.isEmpty) {
      results = [];
    } else {
      results = await db.query(
        'course_list',
        columns: ['name', 'lat', 'lon'],
        where: 'name LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'name ASC',
        limit: limit,
      );
    }
    selected = selected.clamp(0, results.isEmpty ? 0 : results.length - 1);
  }

  void render(int prevLines) {
    _up(prevLines);
    stdout.write('$_clearLine$_bold${_cyan}Search:$_reset  $query█\n');

    if (query.isEmpty) {
      stdout.write('$_clearLine${_yellow}Start typing a course name...$_reset$_clearDown\n');
    } else if (results.isEmpty) {
      stdout.write('$_clearLine${_yellow}No matches$_reset$_clearDown\n');
    } else {
      for (var i = 0; i < results.length; i++) {
        final name = results[i]['name'] as String;
        final lat = (results[i]['lat'] as double).toStringAsFixed(4);
        final lon = (results[i]['lon'] as double).toStringAsFixed(4);
        final prefix = i == selected ? '$_bold$_cyan ▶ ' : '   ';
        stdout.write('$_clearLine$prefix$name$_reset  $_yellow($lat, $lon)$_reset\n');
      }
      stdout.write(_clearDown);
    }
  }

  // Initial blank render
  stdout.write('\n\n');
  var prevLines = 2;
  render(prevLines);
  prevLines = 2;

  // Key loop
  await for (final bytes in stdin) {
    for (var i = 0; i < bytes.length;) {
      // Arrow keys: ESC [ A/B
      if (bytes[i] == 0x1B && i + 2 < bytes.length && bytes[i + 1] == 0x5B) {
        if (bytes[i + 2] == 0x41 && selected > 0) selected--;
        if (bytes[i + 2] == 0x42 && selected < results.length - 1) selected++;
        i += 3;
        render(prevLines);
        prevLines = query.isEmpty ? 2 : results.length + 1;
        continue;
      }

      final byte = bytes[i++];

      if (byte == 0x1B) { // Escape
        _restoreTerminal();
        await db.close();
        return;
      } else if (byte == 0x0D || byte == 0x0A) { // Enter
        if (results.isNotEmpty) {
          final chosen = results[selected];
          _restoreTerminal();
          stdout.write('\n');
          await _handleSelection(db, chosen);
        } else {
          _restoreTerminal();
        }
        await db.close();
        return;
      } else if (byte == 0x7F || byte == 0x08) { // Backspace
        if (query.isNotEmpty) {
          query = query.substring(0, query.length - 1);
          selected = 0;
          await refresh();
        }
      } else if (byte >= 0x20) { // Printable
        query += utf8.decode([byte]);
        selected = 0;
        await refresh();
      }

      render(prevLines);
      prevLines = query.isEmpty ? 2 : results.length + 1;
    }
  }
}

// ---------------------------------------------------------------------------
// Selection handler: cache check → Overpass fetch → parse → save
// ---------------------------------------------------------------------------

Future<void> _handleSelection(
  Database db,
  Map<String, Object?> course,
) async {
  final name = course['name'] as String;
  final lat = course['lat'] as double;
  final lon = course['lon'] as double;

  print('$_bold$_cyan$name$_reset  ($lat, $lon)');

  // 1. Check courses table for cached full data
  final cached = await db.query(
    'courses',
    columns: ['id', 'name', 'updated_at'],
    where: 'name = ?',
    whereArgs: [name],
    limit: 1,
  );

  if (cached.isNotEmpty) {
    final ts = DateTime.fromMillisecondsSinceEpoch(
        cached[0]['updated_at'] as int);
    print('${_green}✓ Already parsed$_reset — cached on '
        '${ts.toLocal().toString().substring(0, 16)}');
    _printCachedSummary(db, cached[0]['id'] as String);
    return;
  }

  // 2. Not cached — fetch from Overpass using a tight bbox around center
  print('${_yellow}Not in cache. Fetching from Overpass...$_reset');

  const pad = 0.08; // ~8 km padding
  final bbox = '${lat - pad},${lon - pad},${lat + pad},${lon + pad}';
  final overpassQuery = '''
[out:json][timeout:25];
(
  node["leisure"="golf_course"]["name"="$name"]($bbox);
  way["leisure"="golf_course"]["name"="$name"]($bbox);
  relation["leisure"="golf_course"]["name"="$name"]($bbox);
)->.course;
.course out geom;
(
  node(area.course)["golf"];
  way(area.course)["golf"];
  relation(area.course)["golf"];
);
out geom;
''';

  final http.Response response;
  try {
    response = await http
        .post(Uri.parse(_overpassUrl), body: overpassQuery)
        .timeout(const Duration(seconds: 40));
  } catch (e) {
    print('${_red}Network error: $e$_reset');
    return;
  }

  if (response.statusCode != 200) {
    print('${_red}Overpass returned ${response.statusCode}$_reset');
    return;
  }

  // 3. Parse
  final ParsedCourse parsed;
  try {
    parsed = parseCourse(response.body);
  } catch (e) {
    print('${_red}Parse error: $e$_reset');
    return;
  }

  // 4. Save to courses table
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

  // 5. Print summary
  print('${_green}✓ Parsed and saved$_reset  id: ${parsed.courseId}');
  _printHoleSummary(parsed.holeDocs);
}

void _printHoleSummary(List<Map<String, dynamic>> holeDocs) {
  print('  Holes: ${holeDocs.length}');
  for (final h in holeDocs) {
    final n = h['holeNumber'].toString().padLeft(2);
    final par = h['par'];
    final fairways = (h['fairways'] as List).length;
    final greens = (h['greens'] as List).length;
    final tees = (h['teePlatforms'] as List).length;
    print('  Hole $n: par $par  '
        '$fairways fairway(s)  $greens green(s)  $tees tee(s)');
  }
}

Future<void> _printCachedSummary(Database db, String courseId) async {
  final rows = await db.query(
    'courses',
    columns: ['holes_doc'],
    where: 'id = ?',
    whereArgs: [courseId],
    limit: 1,
  );
  if (rows.isEmpty) return;
  final holeDocs = (jsonDecode(rows[0]['holes_doc'] as String) as List)
      .cast<Map<String, dynamic>>();
  _printHoleSummary(holeDocs);
}

void _restoreTerminal() {
  stdin.echoMode = true;
  stdin.lineMode = true;
}
