import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:ugly_slice/database/app_database.dart';
import 'package:ugly_slice/models/course.dart';
import 'package:ugly_slice/models/round.dart';
import 'package:ugly_slice/services/round_repository.dart';
import 'package:ugly_slice_shared/player.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Round makeRound({
  String? id,
  String playerName = 'Rick',
  String courseId = 'course_karori',
  String courseName = 'Karori GC',
  DateTime? date,
  bool deleted = false,
}) =>
    Round(
      id: id,
      deleted: deleted,
      player: Player(name: playerName, handicap: 10.0),
      course: Course.stub(id: courseId, name: courseName),
      date: date ?? DateTime.utc(2024, 6, 1),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late RoundRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RoundRepository(db);
  });

  tearDown(() async => db.close());

  // ── saveRound ───────────────────────────────────────────────────────────────

  group('saveRound', () {
    test('returns the round id', () async {
      final round = makeRound(id: 'round-001');
      final id = await repo.saveRound(round);
      expect(id, equals('round-001'));
    });

    test('round is retrievable after save', () async {
      final round = makeRound(id: 'round-002');
      await repo.saveRound(round);
      final loaded = await repo.loadRound('round-002');
      expect(loaded, isNotNull);
      expect(loaded!.player.name, equals('Rick'));
      expect(loaded.course.name, equals('Karori GC'));
    });

    test('insertOrIgnore: second save of same id does not overwrite', () async {
      final original = makeRound(id: 'round-003', playerName: 'Rick');
      await repo.saveRound(original);

      final duplicate = makeRound(id: 'round-003', playerName: 'Other');
      await repo.saveRound(duplicate);

      final loaded = await repo.loadRound('round-003');
      // Original player name is preserved.
      expect(loaded!.player.name, equals('Rick'));
    });
  });

  // ── updateRound ─────────────────────────────────────────────────────────────

  group('updateRound', () {
    test('overwrites course name', () async {
      final round = makeRound(id: 'round-010', courseName: 'Old Course');
      await repo.saveRound(round);

      final updated = round.copyWith(
        course: Course.stub(id: 'course_karori', name: 'New Course'),
      );
      await repo.updateRound('round-010', updated);

      final loaded = await repo.loadRound('round-010');
      expect(loaded!.course.name, equals('New Course'));
    });

    test('bumps updatedAt relative to a clearly older timestamp', () async {
      // Give the round a fixed old updatedAt so we can compare reliably.
      final oldTime = DateTime.utc(2020, 1, 1);
      final round = Round(
        id: 'round-011b',
        updatedAt: oldTime,
        player: Player(name: 'Rick', handicap: 10.0),
        course: Course.stub(id: 'course_karori', name: 'Karori GC'),
        date: DateTime.utc(2024, 6, 1),
      );
      await repo.saveRound(round);
      await repo.updateRound('round-011b', round);

      final loaded = await repo.loadRound('round-011b');
      // updateRound always sets updatedAt = DateTime.now(), clearly after 2020.
      expect(loaded!.updatedAt.millisecondsSinceEpoch,
          greaterThan(oldTime.millisecondsSinceEpoch));
    });

    test('player handicap update is persisted', () async {
      final round = makeRound(id: 'round-011');
      await repo.saveRound(round);

      final updated = round.copyWith(
        player: Player(name: 'Rick', handicap: 7.5),
      );
      await repo.updateRound('round-011', updated);

      final loaded = await repo.loadRound('round-011');
      expect(loaded!.player.handicap, closeTo(7.5, 0.01));
    });
  });

  // ── deleteRound ─────────────────────────────────────────────────────────────

  group('deleteRound', () {
    test('soft-deletes: loadRound returns null after delete', () async {
      final round = makeRound(id: 'round-020');
      await repo.saveRound(round);

      await repo.deleteRound('round-020');

      final loaded = await repo.loadRound('round-020');
      expect(loaded, isNull);
    });

    test('deleted round excluded from listRoundsForPlayer', () async {
      await repo.saveRound(makeRound(id: 'round-021'));
      await repo.deleteRound('round-021');

      final rounds = await repo.listRoundsForPlayer('Rick');
      expect(rounds.any((r) => r.id == 'round-021'), isFalse);
    });

    test('row still exists in DB after soft-delete (not hard-deleted)', () async {
      final round = makeRound(id: 'round-022');
      await repo.saveRound(round);
      await repo.deleteRound('round-022');

      // Query directly including deleted rows.
      final all = await (db.select(db.rounds)).get();
      final row = all.firstWhere((r) => r.id == 'round-022');
      expect(row.deleted, isTrue);
    });
  });

  // ── listRoundsForPlayer ──────────────────────────────────────────────────────

  group('listRoundsForPlayer', () {
    test('returns rounds for correct player only', () async {
      await repo.saveRound(makeRound(id: 'r1', playerName: 'Rick'));
      await repo.saveRound(makeRound(id: 'r2', playerName: 'Alice'));
      await repo.saveRound(makeRound(id: 'r3', playerName: 'Rick'));

      final rounds = await repo.listRoundsForPlayer('Rick');
      expect(rounds.length, equals(2));
      expect(rounds.every((r) => r.player.name == 'Rick'), isTrue);
    });

    test('returns newest first by date', () async {
      await repo.saveRound(makeRound(id: 'r-old', date: DateTime.utc(2023, 1, 1)));
      await repo.saveRound(makeRound(id: 'r-new', date: DateTime.utc(2024, 6, 1)));
      await repo.saveRound(makeRound(id: 'r-mid', date: DateTime.utc(2024, 1, 1)));

      final rounds = await repo.listRoundsForPlayer('Rick');
      expect(rounds[0].id, equals('r-new'));
      expect(rounds[1].id, equals('r-mid'));
      expect(rounds[2].id, equals('r-old'));
    });

    test('excludes deleted rounds', () async {
      await repo.saveRound(makeRound(id: 'r-live'));
      await repo.saveRound(makeRound(id: 'r-dead'));
      await repo.deleteRound('r-dead');

      final rounds = await repo.listRoundsForPlayer('Rick');
      expect(rounds.length, equals(1));
      expect(rounds.first.id, equals('r-live'));
    });

    test('returns empty list when no rounds exist', () async {
      final rounds = await repo.listRoundsForPlayer('Nobody');
      expect(rounds, isEmpty);
    });
  });

  // ── loadRound ───────────────────────────────────────────────────────────────

  group('loadRound', () {
    test('returns null for unknown id', () async {
      final loaded = await repo.loadRound('does-not-exist');
      expect(loaded, isNull);
    });

    test('returns null for deleted round', () async {
      await repo.saveRound(makeRound(id: 'r-del'));
      await repo.deleteRound('r-del');
      expect(await repo.loadRound('r-del'), isNull);
    });

    test('round-trips course name and date', () async {
      final date = DateTime.utc(2024, 7, 4);
      final round = makeRound(
        id: 'r-rt',
        courseName: 'Miramar Links',
        date: date,
      );
      await repo.saveRound(round);
      final loaded = await repo.loadRound('r-rt');
      expect(loaded!.course.name, equals('Miramar Links'));
      expect(loaded.date.toUtc(), equals(date));
    });
  });

  // ── watchRoundsForPlayer ─────────────────────────────────────────────────────

  group('watchRoundsForPlayer', () {
    test('emits current list immediately', () async {
      await repo.saveRound(makeRound(id: 'w-1'));
      final list = await repo.watchRoundsForPlayer('Rick').first;
      expect(list.length, equals(1));
    });

    test('emits updated list after save', () async {
      final stream = repo.watchRoundsForPlayer('Rick');

      // First emission: empty.
      final empty = await stream.first;
      expect(empty, isEmpty);

      await repo.saveRound(makeRound(id: 'w-2'));

      // Second emission: one round.
      final withOne = await stream.first;
      expect(withOne.length, equals(1));
    });

    test('emits updated list after delete', () async {
      await repo.saveRound(makeRound(id: 'w-3'));
      final stream = repo.watchRoundsForPlayer('Rick');

      await stream.first; // consume initial
      await repo.deleteRound('w-3');

      final afterDelete = await stream.first;
      expect(afterDelete, isEmpty);
    });
  });
}
