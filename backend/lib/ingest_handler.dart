import 'dart:convert';
import 'package:functions_framework/functions_framework.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'course_parser.dart';

const _overpassUrl = 'https://overpass-api.de/api/interpreter';

/// Cloud Function handler: receives {courseName, bbox?}, fetches Overpass data,
/// parses it, and returns the full course JSON for the client to cache locally.
///
/// Expected request body (JSON):
/// ```json
/// {
///   "courseName": "Karori Golf Club",
///   "bbox": "-47.5,166.0,-34.0,179.0"   // optional, NZ default used if absent
/// }
/// ```
///
/// Response body (JSON):
/// ```json
/// {
///   "courseId": "course_747473941",
///   "courseDoc": { ...course metadata... },
///   "holeDocs": [ ...hole maps... ]
/// }
/// ```
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

  final bbox = params['bbox'] as String? ?? '-47.5,166.0,-34.0,179.0';

  // 1. Fetch from Overpass
  final query = _buildQuery(courseName, bbox);
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

  // 3. Return full course data — client is responsible for caching
  return Response.ok(
    jsonEncode({
      'courseId': parsed.courseId,
      'courseDoc': parsed.courseDoc,
      'holeDocs': parsed.holeDocs,
    }),
    headers: {'content-type': 'application/json'},
  );
}

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
