import 'package:drift/drift.dart';

@DataClassName('CourseListRow')
class CourseListTable extends Table {
  IntColumn get id => integer()(); // OSM element id
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'node' | 'way' | 'relation'
  RealColumn get lat => real()();
  RealColumn get lon => real()();

  @override
  Set<Column> get primaryKey => {id};
}
