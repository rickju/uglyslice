import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/round.dart';

class RoundRepository {
  final AppDatabase _db;

  RoundRepository(this._db);

  // ── Writes ───────────────────────────────────────────────────────────────────

  /// Save a new round locally. Returns the round's id.
  Future<String> saveRound(Round round) async {
    await _db.into(_db.rounds).insert(
          _toCompanion(round),
          mode: InsertMode.insertOrIgnore,
        );
    return round.id;
  }

  /// Overwrite an existing round, bumping updatedAt.
  Future<void> updateRound(String roundId, Round round) async {
    final updated = round.copyWith(
      id: roundId,
      updatedAt: DateTime.now().toUtc(),
    );
    await _db.update(_db.rounds).replace(_toCompanion(updated));
  }

  /// Soft-delete a round (propagates to Supabase via sync).
  Future<void> deleteRound(String roundId) async {
    await (_db.update(_db.rounds)..where((t) => t.id.equals(roundId)))
        .write(RoundsCompanion(
      deleted: const Value(true),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  // ── Reads ────────────────────────────────────────────────────────────────────

  /// List all non-deleted rounds for a player, newest first.
  Future<List<Round>> listRoundsForPlayer(String playerName) =>
      (_db.select(_db.rounds)
            ..where((t) =>
                t.playerName.equals(playerName) & t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .get();

  /// Load a single round by id. Returns null if not found or deleted.
  Future<Round?> loadRound(String roundId) =>
      (_db.select(_db.rounds)
            ..where((t) =>
                t.id.equals(roundId) & t.deleted.equals(false)))
          .getSingleOrNull();

  /// Reactive stream of non-deleted rounds for a player, newest first.
  Stream<List<Round>> watchRoundsForPlayer(String playerName) =>
      (_db.select(_db.rounds)
            ..where((t) =>
                t.playerName.equals(playerName) & t.deleted.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  // ── Private helpers ──────────────────────────────────────────────────────────

  static RoundsCompanion _toCompanion(Round r) => RoundsCompanion(
        id: Value(r.id),
        userId: Value(r.userId),
        updatedAt: Value(r.updatedAt),
        deleted: Value(r.deleted),
        playerName: Value(r.player.name),
        playerHandicap: Value(r.player.handicap),
        courseId: Value(r.course.id),
        courseName: Value(r.course.name),
        date: Value(r.date),
        status: Value(r.status),
        data: Value(jsonEncode(
            {'holePlays': r.holePlays.map((h) => h.toMap()).toList()})),
      );
}
