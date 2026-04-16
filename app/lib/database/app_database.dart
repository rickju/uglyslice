import 'package:drift/drift.dart';
import 'package:syncable/syncable.dart';

import '_db_connect_stub.dart'
    if (dart.library.ui) '_db_connect_flutter.dart';
import 'package:uuid/uuid.dart'; // needed by app_database.g.dart (clientDefault)

import '../models/round.dart'; // needed by app_database.g.dart (@UseRowClass)
import 'tables/rounds_table.dart';
import 'tables/courses_table.dart';
import 'tables/course_list_table.dart';

export 'tables/rounds_table.dart';
export 'tables/courses_table.dart';
export 'tables/course_list_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Rounds, Courses, CourseListTable])
class AppDatabase extends _$AppDatabase with SyncableDatabase {
  AppDatabase() : super(openAppDatabase());

  /// For unit tests only — uses the provided executor directly.
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(courseListTable);
        },
      );
}
