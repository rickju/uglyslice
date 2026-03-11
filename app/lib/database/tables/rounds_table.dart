import 'package:drift/drift.dart';
import 'package:syncable/syncable.dart';
import 'package:uuid/uuid.dart';

import '../../models/round.dart';

@UseRowClass(Round, constructor: 'fromRow')
class Rounds extends Table implements SyncableTable {
  @override
  TextColumn get id =>
      text().clientDefault(() => const Uuid().v4()).withLength(max: 36)();
  @override
  TextColumn get userId => text().nullable().withLength(max: 36)();
  @override
  DateTimeColumn get updatedAt => dateTime()();
  @override
  BoolColumn get deleted =>
      boolean().withDefault(const Constant(false))();

  TextColumn get playerName => text()();
  RealColumn get playerHandicap =>
      real().withDefault(const Constant(0.0))();
  TextColumn get courseId => text()();
  TextColumn get courseName => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get status =>
      text().withDefault(const Constant('in_progress'))();
  TextColumn get data =>
      text().withDefault(const Constant('{}'))(); // JSON holePlays

  @override
  Set<Column> get primaryKey => {id};
}
