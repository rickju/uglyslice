/// Fetches all golf courses from Overpass, writes a compact JSON file,
/// and saves to a local SQLite database (course_list table).
///
/// Output format matches assets/golf_courses_nz.json:
/// [{ "id": 747473941, "type": "way", "lat": -41.28, "lon": 174.73,
///    "tags": { "name": "Karori Golf Club", "leisure": "golf_course" } }, ...]
///
/// Usage:
///   dart run bin/fetch_course_list.dart                           # worldwide
///   dart run bin/fetch_course_list.dart --bbox -47.5,166,-34,179  # NZ only
///   dart run bin/fetch_course_list.dart --bbox 24,-125,50,-66     # USA
///   dart run bin/fetch_course_list.dart --out my_courses.json
///   dart run bin/fetch_course_list.dart --db /tmp/courses.db
///   dart run bin/fetch_course_list.dart --timeout 600
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _overpassUrl = 'https://overpass-api.de/api/interpreter';
const _typePriority = {'relation': 0, 'way': 1, 'node': 2};

void main(List<String> args) async {
  // ---- Parse args ----
  String? bbox;
  var outPath = 'courses_world.json';
  var dbPath = '/tmp/ugly_slice_courses.db';
  var timeoutSecs = 300;

  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--bbox' && i + 1 < args.length) bbox = args[++i];
    if (args[i] == '--out' && i + 1 < args.length) outPath = args[++i];
    if (args[i] == '--db' && i + 1 < args.length) dbPath = args[++i];
    if (args[i] == '--timeout' && i + 1 < args.length) {
      timeoutSecs = int.parse(args[++i]);
    }
  }

  // ---- Build query ----
  final bboxClause = bbox != null ? '($bbox)' : '';
  final query = '''
[out:json][timeout:$timeoutSecs];
(
  node["leisure"="golf_course"]$bboxClause;
  way["leisure"="golf_course"]$bboxClause;
  relation["leisure"="golf_course"]$bboxClause;
);
out center tags;
''';

  print('Fetching golf courses from Overpass'
      '${bbox != null ? ' (bbox: $bbox)' : ' (worldwide)'}...');
  print('This may take 30–120 seconds.');

  // ---- Fetch ----
  final response = await http
      .post(Uri.parse(_overpassUrl), body: query)
      .timeout(Duration(seconds: timeoutSecs + 30));

  if (response.statusCode != 200) {
    stderr.writeln('Overpass returned ${response.statusCode}');
    exit(1);
  }

  // ---- Parse ----
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final elements = data['elements'] as List<dynamic>;
  print('Received ${elements.length} elements.');

  // ---- Deduplicate by name ----
  // Same golf course often appears as node + way + relation in OSM.
  // Keep highest-priority type (relation > way > node).
  // Courses without a name tag are skipped.
  final Map<String, Map<String, dynamic>> byName = {};

  for (final el in elements) {
    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    final name = tags['name'] as String?;
    if (name == null || name.trim().isEmpty) continue;

    final type = el['type'] as String;
    final center = el['center'] as Map<String, dynamic>?;

    final lat = type == 'node'
        ? (el['lat'] as num).toDouble()
        : center != null
            ? (center['lat'] as num).toDouble()
            : null;
    final lon = type == 'node'
        ? (el['lon'] as num).toDouble()
        : center != null
            ? (center['lon'] as num).toDouble()
            : null;

    if (lat == null || lon == null) continue;

    final existing = byName[name];
    final existingPriority =
        existing != null ? (_typePriority[existing['type']] ?? 9) : 9;
    final thisPriority = _typePriority[type] ?? 9;

    if (existing == null || thisPriority < existingPriority) {
      byName[name] = {
        'id': el['id'],
        'type': type,
        'lat': double.parse(lat.toStringAsFixed(6)),
        'lon': double.parse(lon.toStringAsFixed(6)),
        'tags': tags,
      };
    }
  }

  // ---- Sort by name ----
  final courses = byName.values.toList()
    ..sort((a, b) =>
        (a['tags']['name'] as String).compareTo(b['tags']['name'] as String));

  print('Unique named courses: ${courses.length}');

  // ---- Write JSON ----
  final encoder = JsonEncoder.withIndent('  ');
  await File(outPath).writeAsString(encoder.convert(courses));
  print('JSON written to $outPath');

  // ---- Save to SQLite ----
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE course_list (
          id      INTEGER PRIMARY KEY,
          name    TEXT NOT NULL,
          type    TEXT NOT NULL,
          lat     REAL NOT NULL,
          lon     REAL NOT NULL,
          tags    TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX idx_course_list_name ON course_list(name)');
    },
  );

  final batch = db.batch();
  for (final c in courses) {
    batch.insert(
      'course_list',
      {
        'id': c['id'],
        'name': (c['tags'] as Map)['name'] as String,
        'type': c['type'],
        'lat': c['lat'],
        'lon': c['lon'],
        'tags': jsonEncode(c['tags']),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
  await db.close();

  print('Saved to SQLite: $dbPath  (${courses.length} rows in course_list)');
}
