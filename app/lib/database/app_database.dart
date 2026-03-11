import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:syncable/syncable.dart';
import 'package:uuid/uuid.dart'; // needed by app_database.g.dart (clientDefault)

import '../models/round.dart'; // needed by app_database.g.dart (@UseRowClass)
import 'tables/rounds_table.dart';
import 'tables/courses_table.dart';

export 'tables/rounds_table.dart';
export 'tables/courses_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [Rounds, Courses])
class AppDatabase extends _$AppDatabase with SyncableDatabase {
  AppDatabase() : super(driftDatabase(name: 'ugly_slice'));

  @override
  int get schemaVersion => 1;
}
