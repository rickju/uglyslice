import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/course.dart';

class CourseRepository {
  final AppDatabase _db;

  CourseRepository(this._db);

  /// Returns the cached course or null if not in local DB.
  Future<Course?> fetchCourse(String courseId) async {
    final row = await (_db.select(_db.courses)
          ..where((t) => t.id.equals(courseId)))
        .getSingleOrNull();
    if (row == null) return null;

    final courseDoc =
        jsonDecode(row.courseDoc) as Map<String, dynamic>;
    final holeDocs = (jsonDecode(row.holesDoc) as List)
        .cast<Map<String, dynamic>>();
    return Course.fromMap(courseDoc, holeDocs);
  }

  /// Upsert course data returned from the backend.
  Future<void> saveCourse(
    String courseId,
    Map<String, dynamic> courseDoc,
    List<Map<String, dynamic>> holeDocs,
  ) async {
    await _db.into(_db.courses).insertOnConflictUpdate(CoursesCompanion(
          id: Value(courseId),
          name: Value(courseDoc['name'] as String? ?? ''),
          courseDoc: Value(jsonEncode(courseDoc)),
          holesDoc: Value(jsonEncode(holeDocs)),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ));
  }
}
