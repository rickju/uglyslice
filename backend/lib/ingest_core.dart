import 'dart:convert';
import 'package:http/http.dart' as http;
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

typedef IngestAllResult = ({int total, int succeeded, int failed});

/// Fetch all NZ courses from Overpass, upsert course_list, then parse and
/// upsert each course. Returns summary counts.
Future<IngestAllResult> ingestAllNzCourses() async {
  final supabase = SupabaseRestClient();

  final listQuery = '''
[out:json][timeout:120];
(
  node["leisure"="golf_course"]($nzBbox);
  way["leisure"="golf_course"]($nzBbox);
  relation["leisure"="golf_course"]($nzBbox);
);
out center tags;
''';

  final listResponse = await http
      .post(Uri.parse(overpassUrl), body: listQuery)
      .timeout(const Duration(seconds: 150));

  if (listResponse.statusCode != 200) {
    throw Exception(
        'Overpass list query failed: ${listResponse.statusCode}');
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

  await supabase.upsert('course_list', byName.values.toList());

  int succeeded = 0;
  int failed = 0;
  final courseList = byName.values.toList();
  final total = courseList.length;
  final store = RawJsonStore();

  for (int i = 0; i < total; i++) {
    final course = courseList[i];
    final name = course['name'] as String;
    print('\n[${i + 1}/$total] Fetching: $name ...');
    try {
      final detailQuery = buildDetailQuery(name, nzBbox);
      final fetchStart = DateTime.now();
      final detailResponse = await http
          .post(Uri.parse(overpassUrl), body: detailQuery)
          .timeout(const Duration(seconds: 60));
      final fetchMs = DateTime.now().difference(fetchStart).inMilliseconds;

      if (detailResponse.statusCode != 200) {
        print('  → Overpass: ${detailResponse.statusCode} (error)');
        failed++;
        continue;
      }

      final rawBody = detailResponse.body;
      final overpassData = jsonDecode(rawBody) as Map<String, dynamic>;
      final elementCount =
          (overpassData['elements'] as List<dynamic>? ?? []).length;
      print('  → Overpass: 200 OK, $elementCount elements (${fetchMs}ms)');

      await store.save(name, rawBody, elementCount);
      print('  → Cached raw JSON to ${store.dbPath}');

      print('  → Parsing ...');
      final ParsedCourse parsed;
      try {
        parsed = parseCourse(rawBody);
      } catch (e) {
        print('  → Parse FAILED: $e');
        print('  → Skipping Supabase upsert');
        failed++;
        continue;
      }
      print(
          '  → Parsed: ${parsed.courseId}, ${parsed.holeDocs.length} holes');

      await supabase.upsert('courses', [
        {
          'id': parsed.courseId,
          'name': parsed.courseDoc['name'] as String? ?? name,
          'course_doc': parsed.courseDoc,
          'holes_doc': parsed.holeDocs,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }
      ]);
      print('  → Upserted to Supabase ✓');
      succeeded++;
    } catch (e) {
      print('  → ERROR: $e');
      failed++;
    }
  }

  print('\nDone. courseList=$total  succeeded=$succeeded  failed=$failed');
  return (total: total, succeeded: succeeded, failed: failed);
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
