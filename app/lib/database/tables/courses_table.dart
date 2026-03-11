import 'package:drift/drift.dart';

@DataClassName('CourseRow')
class Courses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get courseDoc => text()(); // JSON blob
  TextColumn get holesDoc => text()();  // JSON blob
  IntColumn get updatedAt => integer()(); // millisecondsSinceEpoch

  @override
  Set<Column> get primaryKey => {id};
}
