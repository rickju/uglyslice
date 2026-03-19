import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'course_repository.dart';

class CourseSyncService {
  final AppDatabase _db;
  final SupabaseClient _supabase;

  CourseSyncService({required AppDatabase db, required SupabaseClient supabase})
      : _db = db,
        _supabase = supabase;

  /// Pull course_list + courses from Supabase → upsert local SQLite.
  Future<void> syncAll() async {
    await _syncCourseList();
    await _syncCourses();
  }

  /// Fetch a single course by name from Supabase, save it locally, and return
  /// its id.
  Future<String> syncCourse(String courseName) async {
    final rows = await _supabase
        .from('courses')
        .select()
        .eq('name', courseName)
        .limit(1);
    if (rows.isEmpty) throw Exception('$courseName not found in Supabase');

    final r = rows.first;
    final courseId = r['id'] as String;
    final courseDoc = r['course_doc'] as Map<String, dynamic>;
    final holeDocs = (r['holes_doc'] as List)
        .map((h) => h as Map<String, dynamic>)
        .toList();
    final repo = CourseRepository(_db);
    await repo.saveCourse(courseId, courseDoc, holeDocs);
    return courseId;
  }

  Future<void> _syncCourseList() async {
    final rows = await _supabase.from('course_list').select();
    if (rows.isEmpty) return;

    await _db.batch((batch) {
      batch.insertAll(
        _db.courseListTable,
        rows.map((r) => CourseListTableCompanion.insert(
              id: Value(r['id'] as int),
              name: r['name'] as String,
              type: r['type'] as String,
              lat: r['lat'] as double,
              lon: r['lon'] as double,
            )),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> _syncCourses() async {
    final rows = await _supabase.from('courses').select();
    if (rows.isEmpty) return;

    final repo = CourseRepository(_db);
    for (final r in rows) {
      try {
        final courseDoc = r['course_doc'] as Map<String, dynamic>;
        final holeDocs = (r['holes_doc'] as List)
            .map((h) => h as Map<String, dynamic>)
            .toList();
        await repo.saveCourse(r['id'] as String, courseDoc, holeDocs);
      } catch (e) {
        debugPrint('CourseSyncService: failed to save course ${r['id']}: $e');
      }
    }
  }
}
