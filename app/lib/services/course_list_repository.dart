import 'package:drift/drift.dart';

import '../database/app_database.dart';

class CourseListRepository {
  final AppDatabase _db;

  CourseListRepository(this._db);

  /// All courses in the local DB, sorted by name.
  Future<List<CourseListRow>> listCourses() =>
      (_db.select(_db.courseListTable)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  /// Filtered by name substring, case-insensitive.
  Future<List<CourseListRow>> search(String query) =>
      (_db.select(_db.courseListTable)
            ..where((t) => t.name.lower().like('%${query.toLowerCase()}%'))
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  /// True if the course list has never been synced.
  Future<bool> get isEmpty async =>
      (await _db.select(_db.courseListTable).get()).isEmpty;
}
