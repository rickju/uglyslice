import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncable/syncable.dart';

import '../database/app_database.dart';
import '../models/round.dart';

/// Wraps [SyncManager] and wires up all syncable types.
///
/// Call [setUser] once you have an authenticated Supabase user.
/// The manager handles bidirectional sync of [Round] data between
/// the local Drift DB and the Supabase `rounds` table.
class SyncService {
  late final SyncManager _manager;

  SyncService({required AppDatabase db, required SupabaseClient supabase}) {
    _manager = SyncManager(
      localDatabase: db,
      supabaseClient: supabase,
    );

    _manager.registerSyncable<Round>(
      backendTable: 'rounds',
      fromJson: Round.fromJson,
      companionConstructor: RoundsCompanion.new,
    );
  }

  /// Call after Supabase sign-in. Fills any local-only rounds with the
  /// userId, then enables background sync.
  Future<void> setUser(String userId) async {
    _manager.setUserId(userId);
    await _manager.fillMissingUserIdForLocalTables();
    _manager.enableSync();
  }

  void disableSync() => _manager.disableSync();

  Future<void> dispose() async => _manager.dispose();
}
