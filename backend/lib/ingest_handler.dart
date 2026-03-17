import 'dart:convert';
import 'package:functions_framework/functions_framework.dart';
import 'package:shelf/shelf.dart';
import 'ingest_core.dart';

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

  final bbox = params['bbox'] as String?;

  try {
    final courseId = await ingestOneCourse(courseName, bbox: bbox);
    return Response.ok(
      jsonEncode({'courseId': courseId}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'content-type': 'application/json'});
  }
}

/// Batch ingestion handler: fetches all NZ golf courses from Overpass,
/// upserts course_list rows, then parses each course and upserts courses rows.
@CloudFunction()
Future<Response> ingestAllNzCoursesHandler(Request request) async {
  try {
    final result = await ingestAllNzCourses();
    return Response.ok(
      jsonEncode({
        'courseListCount': result.total,
        'coursesSucceeded': result.succeeded,
        'coursesFailed': result.failed,
      }),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
        body: jsonEncode({'error': '$e'}),
        headers: {'content-type': 'application/json'});
  }
}
