import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'database/app_database.dart';
import 'services/sync_service.dart';
import 'services/course_sync_service.dart';
import 'main_screen.dart';

// App-wide singletons — injected into repositories via constructor.
late final AppDatabase db;
late final SyncService syncService;
late final CourseSyncService courseSyncService;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  db = AppDatabase();
  syncService = SyncService(
    db: db,
    supabase: Supabase.instance.client,
  );
  courseSyncService = CourseSyncService(
    db: db,
    supabase: Supabase.instance.client,
  );

  // Sign in anonymously if no existing session.
  // Requires "Allow anonymous sign-ins" enabled in Supabase Auth settings.
  try {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      await Supabase.instance.client.auth.signInAnonymously();
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await syncService.setUser(userId);
      // Fire course sync in background — app is usable immediately from local SQLite.
      courseSyncService.syncAll().catchError(
          (e) => debugPrint('Course sync failed: $e'));
    }
  } catch (e) {
    // Sync disabled — app works fully offline without auth.
    debugPrint('Supabase auth failed, running offline: $e');
  }

  runApp(const MaterialApp(home: MainScreen()));
}
