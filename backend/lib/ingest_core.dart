import 'dart:convert';
import 'package:http/http.dart' as http;
import 'course_integrity.dart';
import 'course_parser.dart';
import 'raw_json_store.dart';
import 'supabase_client.dart';

const overpassUrl = 'https://overpass-api.de/api/interpreter';
const nzBbox = '-47.5,166.0,-34.0,179.0';

/// Fetch, parse, and upsert a single course. Returns the courseId.
/// Throws on any failure.
Future<String> ingestOneCourse(String courseName, {String? bbox}) async {
  final effectiveBbox = bbox ?? nzBbox;

  print('Fetching: $courseName ...');

  final query = buildDetailQuery(courseName, effectiveBbox);
  final fetchStart = DateTime.now();
  final overpassResponse = await http.post(Uri.parse(overpassUrl), body: query);
  final fetchMs = DateTime.now().difference(fetchStart).inMilliseconds;

  if (overpassResponse.statusCode != 200) {
    print('  → Overpass: ${overpassResponse.statusCode} (error)');
    throw Exception('Overpass returned ${overpassResponse.statusCode}');
  }

  final rawBody = overpassResponse.body;
  final overpassData = jsonDecode(rawBody) as Map<String, dynamic>;
  final elementCount =
      (overpassData['elements'] as List<dynamic>? ?? []).length;
  print('  → Overpass: 200 OK, $elementCount elements (${fetchMs}ms)');

  final store = RawJsonStore();
  await store.save(courseName, rawBody, elementCount);
  print('  → Cached raw JSON to ${store.dbPath}');

  print('  → Parsing ...');
  final ParsedCourse parsed;
  try {
    parsed = parseCourse(rawBody);
  } catch (e) {
    print('  → Parse FAILED: $e');
    throw Exception('Parse failed: $e');
  }
  print('  → Parsed: ${parsed.courseId}, ${parsed.holeDocs.length} holes');

  final supabase = SupabaseRestClient();
  await supabase.upsert('courses', [
    {
      'id': parsed.courseId,
      'name': parsed.courseDoc['name'] as String? ?? courseName,
      'course_doc': parsed.courseDoc,
      'holes_doc': parsed.holeDocs,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }
  ]);
  print('  → Upserted to Supabase ✓');

  return parsed.courseId;
}

/// Re-parse a course from the local SQLite cache and upsert to Supabase.
/// No Overpass request — useful when Overpass is rate-limiting.
Future<String> reparseCourse(String courseName) async {
  final store = RawJsonStore();
  final rawBody = await store.load(courseName);
  await store.close();

  if (rawBody == null) {
    throw Exception(
        'No cached JSON for "$courseName". Run ingest-course first.');
  }

  print('  → Parsing from cache ...');
  final ParsedCourse parsed;
  try {
    parsed = parseCourse(rawBody);
  } catch (e) {
    print('  → Parse FAILED: $e');
    throw Exception('Parse failed: $e');
  }
  print('  → Parsed: ${parsed.courseId}, ${parsed.holeDocs.length} holes');

  final supabase = SupabaseRestClient();
  await supabase.upsert('courses', [
    {
      'id': parsed.courseId,
      'name': parsed.courseDoc['name'] as String? ?? courseName,
      'course_doc': parsed.courseDoc,
      'holes_doc': parsed.holeDocs,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }
  ]);
  print('  → Upserted to Supabase ✓');

  return parsed.courseId;
}

/// Print raw OSM elements for a specific hole from the cached JSON.
Future<void> inspectCachedHole(String courseName, int holeRef) async {
  final store = RawJsonStore();
  final rawBody = await store.load(courseName);
  await store.close();

  if (rawBody == null) {
    print('No cached JSON for "$courseName". Run ingest-course first.');
    return;
  }

  final data = jsonDecode(rawBody) as Map<String, dynamic>;
  final elements = data['elements'] as List<dynamic>;

  final holeElements = elements.where((e) {
    final tags = (e['tags'] as Map<String, dynamic>?) ?? {};
    return tags['golf'] == 'hole' && tags['ref'] == '$holeRef';
  }).toList();

  if (holeElements.isEmpty) {
    print('No hole ref=$holeRef found in cached data for "$courseName".');
    return;
  }

  for (final el in holeElements) {
    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    final geom = (el['geometry'] as List<dynamic>?) ?? [];
    print('type    : ${el['type']}');
    print('id      : ${el['id']}');
    print('tags    : $tags');
    print('geometry: ${geom.length} points');
    if (geom.isNotEmpty) {
      print('  first : ${geom.first}');
      print('  last  : ${geom.last}');
    }
    print('');
  }
}

typedef IngestAllResult = ({int total, int succeeded, int failed});

/// Shared ingest logic: runs list+detail Overpass queries, upserts course_list,
/// parses and upserts each course. [cacheKey] is the name used in the raw JSON
/// cache. Returns summary counts.
Future<IngestAllResult> _ingestFromQueries({
  required String listQuery,
  required String detailQuery,
  required String cacheKey,
  int? limit,
}) async {
  final supabase = SupabaseRestClient();

  final listResponse = await http
      .post(Uri.parse(overpassUrl), body: listQuery)
      .timeout(const Duration(seconds: 150));

  if (listResponse.statusCode != 200) {
    throw Exception('Overpass list query failed: ${listResponse.statusCode}');
  }

  final data = jsonDecode(listResponse.body) as Map<String, dynamic>;
  final elements = data['elements'] as List<dynamic>;

  const typePriority = {'relation': 0, 'way': 1, 'node': 2};
  final Map<String, Map<String, dynamic>> byName = {};
  for (final el in elements) {
    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    final name = (tags['name'] as String?)?.trim();
    if (name == null || name.isEmpty) continue;

    final type = el['type'] as String;
    final center = el['center'] as Map<String, dynamic>?;
    final lat = type == 'node'
        ? (el['lat'] as num).toDouble()
        : (center?['lat'] as num?)?.toDouble();
    final lon = type == 'node'
        ? (el['lon'] as num).toDouble()
        : (center?['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) continue;

    final existing = byName[name];
    final existingPri =
        existing != null ? (typePriority[existing['type']] ?? 9) : 9;
    if (existing == null || (typePriority[type] ?? 9) < existingPri) {
      byName[name] = {
        'id': el['id'] as int,
        'type': type,
        'name': name,
        'lat': lat,
        'lon': lon,
      };
    }
  }

  final now = DateTime.now().toUtc().toIso8601String();
  final courseListRows =
      byName.values.map((c) => {...c, 'updated_at': now}).toList();
  await supabase.upsert('course_list', courseListRows);
  print('Upserted ${courseListRows.length} courses to course_list');

  print('Fetching all course details (single query) ...');
  final fetchStart = DateTime.now();
  final detailResponse = await http
      .post(Uri.parse(overpassUrl), body: detailQuery)
      .timeout(const Duration(seconds: 330));
  final fetchMs = DateTime.now().difference(fetchStart).inMilliseconds;

  if (detailResponse.statusCode != 200) {
    throw Exception(
        'Overpass detail query failed: ${detailResponse.statusCode}');
  }

  final rawBody = detailResponse.body;
  final detailData = jsonDecode(rawBody) as Map<String, dynamic>;
  final elementCount = (detailData['elements'] as List<dynamic>? ?? []).length;
  print('Overpass: 200 OK, $elementCount elements (${fetchMs}ms)');

  final store = RawJsonStore();
  await store.save(cacheKey, rawBody, elementCount);
  print('Cached raw JSON to ${store.dbPath}');

  print('\nParsing all courses ...');
  final allParsed = parseAllCourses(rawBody);
  print('Found ${allParsed.length} parseable courses (way/relation geometry)\n');

  final total =
      limit != null && limit < allParsed.length ? limit : allParsed.length;
  if (limit != null) {
    print('(limiting to $total of ${allParsed.length} parsed courses)');
  }

  int succeeded = 0;
  int failed = 0;

  for (int i = 0; i < total; i++) {
    final parsed = allParsed[i];
    final name = parsed.courseDoc['name'] as String;
    print(
        '[${i + 1}/$total] ${parsed.courseId}  "$name"  ${parsed.holeDocs.length} holes');
    try {
      await supabase.upsert('courses', [
        {
          'id': parsed.courseId,
          'name': name,
          'course_doc': parsed.courseDoc,
          'holes_doc': parsed.holeDocs,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }
      ]);
      print('  → Upserted to Supabase ✓');
      succeeded++;
    } catch (e) {
      print('  → Supabase upsert FAILED: $e');
      failed++;
    }
  }

  await store.close();
  print('\nDone. parsed=$total  succeeded=$succeeded  failed=$failed');
  return (total: total, succeeded: succeeded, failed: failed);
}

/// Fetch all NZ courses from Overpass, upsert course_list, then parse and
/// upsert each course. Returns summary counts.
Future<IngestAllResult> ingestAllNzCourses({int? limit}) {
  final listQuery = '''
[out:json][timeout:120];
(
  node["leisure"="golf_course"]($nzBbox);
  way["leisure"="golf_course"]($nzBbox);
  relation["leisure"="golf_course"]($nzBbox);
);
out center tags;
''';

  final detailQuery = '''
[out:json][timeout:300];
(
  way["leisure"="golf_course"]($nzBbox);
  relation["leisure"="golf_course"]($nzBbox);
)->.courses;
.courses out geom;
(
  node(area.courses)["golf"];
  way(area.courses)["golf"];
  relation(area.courses)["golf"];
);
out geom;
''';

  return _ingestFromQueries(
    listQuery: listQuery,
    detailQuery: detailQuery,
    cacheKey: '__all_nz__',
    limit: limit,
  );
}

/// Fetch all courses in a named region (country, state, or county) from
/// Overpass, upsert course_list, parse and upsert each course.
Future<IngestAllResult> ingestRegion(String regionName, {int? limit}) {
  final escaped = regionName.replaceAll('"', '\\"');

  final listQuery = '''
[out:json][timeout:120];
area["name"="$escaped"]->.searchArea;
(
  node["leisure"="golf_course"](area.searchArea);
  way["leisure"="golf_course"](area.searchArea);
  relation["leisure"="golf_course"](area.searchArea);
);
out center tags;
''';

  final detailQuery = '''
[out:json][timeout:300];
area["name"="$escaped"]->.searchArea;
(
  way["leisure"="golf_course"](area.searchArea);
  relation["leisure"="golf_course"](area.searchArea);
)->.courses;
.courses out geom;
(
  node(area.courses)["golf"];
  way(area.courses)["golf"];
  relation(area.courses)["golf"];
);
out geom;
''';

  final cacheKey =
      '__region_${regionName.replaceAll(' ', '_').toLowerCase()}__';
  print('Ingesting region: $regionName');
  return _ingestFromQueries(
    listQuery: listQuery,
    detailQuery: detailQuery,
    cacheKey: cacheKey,
    limit: limit,
  );
}

/// Query Supabase for a stored course and print its details.
Future<void> queryCourse(String courseName) async {
  final supabase = SupabaseRestClient();
  print('Querying Supabase for: $courseName ...\n');

  final rows = await supabase.select(
    'courses',
    filters: 'name=eq.$courseName',
    columns: 'id,name,course_doc,holes_doc,updated_at',
  );

  if (rows.isEmpty) {
    print('Not found in Supabase.');
    return;
  }

  final row = rows.first;
  final courseDoc = row['course_doc'] is String
      ? jsonDecode(row['course_doc'] as String) as Map<String, dynamic>
      : row['course_doc'] as Map<String, dynamic>;
  final holeDocs = row['holes_doc'] is String
      ? (jsonDecode(row['holes_doc'] as String) as List<dynamic>)
          .cast<Map<String, dynamic>>()
      : (row['holes_doc'] as List<dynamic>).cast<Map<String, dynamic>>();

  print('=== ${row['name']} ===');
  print('ID         : ${row['id']}');
  print('Updated at : ${row['updated_at']}');
  print('Holes      : ${holeDocs.length}');
  print('Boundary pts: ${(courseDoc['boundaryPoints'] as List?)?.length ?? 0}');
  print('');

  for (final h in holeDocs) {
    final num = (h['holeNumber'] as int).toString().padLeft(2);
    final par = h['par'];
    final hcp = h['handicapIndex'];
    final fairways = (h['fairways'] as List).length;
    final greens = (h['greens'] as List).length;
    final tees = (h['teePlatforms'] as List).length;
    final routingPts = (h['routingLine'] as List).length;
    print('  Hole $num  par $par  hcp ${hcp.toString().padLeft(2)}'
        '  fairways=$fairways  greens=$greens'
        '  tee_platforms=$tees  routing_pts=$routingPts');
  }
}

/// Query Supabase for a stored course and run integrity checks on it.
Future<void> checkCourseIntegrity(String courseName) async {
  final supabase = SupabaseRestClient();
  print('Querying Supabase for: $courseName ...\n');

  final rows = await supabase.select(
    'courses',
    filters: 'name=eq.$courseName',
    columns: 'id,name,course_doc,holes_doc',
  );

  if (rows.isEmpty) {
    print('Not found in Supabase. Run ingest-course or ingest-region first.');
    return;
  }

  final row = rows.first;
  final courseDoc = row['course_doc'] is String
      ? jsonDecode(row['course_doc'] as String) as Map<String, dynamic>
      : row['course_doc'] as Map<String, dynamic>;
  final holeDocs = row['holes_doc'] is String
      ? (jsonDecode(row['holes_doc'] as String) as List<dynamic>)
          .cast<Map<String, dynamic>>()
      : (row['holes_doc'] as List<dynamic>).cast<Map<String, dynamic>>();

  final parsed = ParsedCourse(
    courseId: row['id'] as String,
    courseDoc: courseDoc,
    holeDocs: holeDocs,
  );

  print('=== ${row['name']}  (${holeDocs.length} holes) ===\n');

  final issues = checkIntegrity(parsed);
  if (issues.isEmpty) {
    print('No issues found — looks good!');
    return;
  }

  final errors = issues.where((i) => i.severity == IssueSeverity.error).length;
  final warnings =
      issues.where((i) => i.severity == IssueSeverity.warning).length;

  for (final issue in issues) {
    print(issue);
  }
  print('\n$errors error(s)  $warnings warning(s)');
}

/// Fetch and parse a course, print detailed breakdown. No Supabase upsert.
Future<void> checkCourse(String courseName, {String? bbox}) async {
  final effectiveBbox = bbox ?? nzBbox;

  print('Fetching: $courseName ...');

  final query = buildDetailQuery(courseName, effectiveBbox);
  final fetchStart = DateTime.now();
  final overpassResponse =
      await http.post(Uri.parse(overpassUrl), body: query);
  final fetchMs = DateTime.now().difference(fetchStart).inMilliseconds;

  if (overpassResponse.statusCode != 200) {
    print('Overpass error: ${overpassResponse.statusCode}');
    return;
  }

  final rawBody = overpassResponse.body;
  final overpassData = jsonDecode(rawBody) as Map<String, dynamic>;
  final elementCount =
      (overpassData['elements'] as List<dynamic>? ?? []).length;
  print('Overpass: 200 OK, $elementCount elements (${fetchMs}ms)\n');

  final ParsedCourse parsed;
  try {
    parsed = parseCourse(rawBody);
  } catch (e) {
    print('Parse FAILED: $e');
    return;
  }

  print('=== ${parsed.courseDoc['name']} ===');
  print('ID    : ${parsed.courseId}');
  print('Holes : ${parsed.holeDocs.length}');
  print('');

  for (final h in parsed.holeDocs) {
    final num = (h['holeNumber'] as int).toString().padLeft(2);
    final par = h['par'];
    final fairways = (h['fairways'] as List).length;
    final greens = (h['greens'] as List).length;
    final tees = (h['teePlatforms'] as List).length;
    final routingPts = (h['routingLine'] as List).length;
    print('  Hole $num  par $par'
        '  fairways=$fairways  greens=$greens'
        '  tee_platforms=$tees  routing_pts=$routingPts');
  }
}

String buildDetailQuery(String courseName, String bbox) => '''
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
