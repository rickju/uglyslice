import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/course.dart';

class CourseRepository {
  static Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'ugly_slice.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE courses (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            course_doc TEXT NOT NULL,
            holes_doc TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// Returns null if not in local cache.
  Future<Course?> fetchCourse(String courseId) async {
    final db = await _database;
    final rows = await db.query(
      'courses',
      where: 'id = ?',
      whereArgs: [courseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final courseDoc =
        jsonDecode(row['course_doc'] as String) as Map<String, dynamic>;
    final holeDocs = (jsonDecode(row['holes_doc'] as String) as List)
        .map((h) => h as Map<String, dynamic>)
        .toList();

    return Course.fromFirestore(courseDoc, holeDocs);
  }

  /// Cache course data returned from the backend.
  Future<void> saveCourse(
    String courseId,
    Map<String, dynamic> courseDoc,
    List<Map<String, dynamic>> holeDocs,
  ) async {
    final db = await _database;
    await db.insert(
      'courses',
      {
        'id': courseId,
        'name': courseDoc['name'] as String? ?? '',
        'course_doc': jsonEncode(courseDoc),
        'holes_doc': jsonEncode(holeDocs),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
