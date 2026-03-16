import 'dart:convert';
import 'package:functions_framework/functions_framework.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'course_parser.dart';
import 'supabase_client.dart';

const _overpassUrl = 'https://overpass-api.de/api/interpreter';
const _nzBbox = '-47.5,166.0,-34.0,179.0';

/// Cloud Function handler: receives {courseName, bbox?}, fetches Overpass data,
/// parses it, and upserts both course_list and courses rows in Supabase.
///
/// Kept for single-course dev/testing.
@CloudFunction()
Future<Response> ingestCourse(Request request) async {
  final body = await request.readAsString();
  final Map<String, dynamic> params = jsonDecode(body) as Map<String, dynamic>;

  final courseName = params['courseName'] as String?;
  if (courseName == null || courseName.isEmpty) {
    return Response.badRequest(
        body: jsonEncode({'error': 'courseName is required'}),
        headers: {'content-type': 'application/json'});
  }

  final bbox = params['bbox'] as String? ?? _nzBbox;

  // 1. Fetch from Overpass
  final query = _buildDetailQuery(courseName, bbox);
  final overpassResponse = await http.post(
    Uri.parse(_overpassUrl),
    body: query,
  );

  if (overpassResponse.statusCode != 200) {
    return Response.internalServerError(
        body: jsonEncode(
            {'error': 'Overpass returned ${overpassResponse.statusCode}'}),
        headers: {'content-type': 'application/json'});
  }

  // 2. Parse
  final ParsedCourse parsed;
  try {
    parsed = parseCourse(overpassResponse.body);
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Parse failed: $e'}),
        headers: {'content-type': 'application/json'});
  }

  // 3. Upsert to Supabase
  try {
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
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': 'Supabase upsert failed: $e'}),
        headers: {'content-type': 'application/json'});
  }

  return Response.ok(
    jsonEncode({'courseId': parsed.courseId}),
    headers: {'content-type': 'application/json'},
  );
}

/// Batch ingestion handler: fetches all NZ golf courses from Overpass,
/// upserts course_list rows, then parses each course and upserts courses rows.
@CloudFunction()
Future<Response> ingestAllNzCourses(Request request) async {
  final supabase = SupabaseRestClient();

  // 1. Fetch course list from Overpass
  final listQuery = '''
[out:json][timeout:120];
(
  node["leisure"="golf_course"]($_nzBbox);
  way["leisure"="golf_course"]($_nzBbox);
  relation["leisure"="golf_course"]($_nzBbox);
);
out center tags;
''';

  final listResponse = await http
      .post(Uri.parse(_overpassUrl), body: listQuery)
      .timeout(const Duration(seconds: 150));

  if (listResponse.statusCode != 200) {
    return Response.internalServerError(
        body: jsonEncode(
            {'error': 'Overpass list query failed: ${listResponse.statusCode}'}),
        headers: {'content-type': 'application/json'});
  }

  final data = jsonDecode(listResponse.body) as Map<String, dynamic>;
  final elements = data['elements'] as List<dynamic>;

  // Deduplicate by name — keep highest-priority OSM type
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

  // 2. Upsert course_list rows
  await supabase.upsert('course_list', byName.values.toList());

  // 3. For each course: fetch details from Overpass, parse, upsert courses
  int succeeded = 0;
  int failed = 0;
  for (final course in byName.values) {
    final name = course['name'] as String;
    try {
      final detailQuery = _buildDetailQuery(name, _nzBbox);
      final detailResponse = await http
          .post(Uri.parse(_overpassUrl), body: detailQuery)
          .timeout(const Duration(seconds: 60));

      if (detailResponse.statusCode != 200) {
        failed++;
        continue;
      }

      final ParsedCourse parsed;
      try {
        parsed = parseCourse(detailResponse.body);
      } catch (_) {
        failed++;
        continue;
      }

      await supabase.upsert('courses', [
        {
          'id': parsed.courseId,
          'name': parsed.courseDoc['name'] as String? ?? name,
          'course_doc': parsed.courseDoc,
          'holes_doc': parsed.holeDocs,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }
      ]);
      succeeded++;
    } catch (_) {
      failed++;
    }
  }

  return Response.ok(
    jsonEncode({
      'courseListCount': byName.length,
      'coursesSucceeded': succeeded,
      'coursesFailed': failed,
    }),
    headers: {'content-type': 'application/json'},
  );
}

String _buildDetailQuery(String courseName, String bbox) => '''
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
