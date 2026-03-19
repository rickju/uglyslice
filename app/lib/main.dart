import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
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

  // If there's an existing session (real or anonymous), resume it and go straight
  // to the main screen. Otherwise show the auth page.
  Widget home;
  final session = Supabase.instance.client.auth.currentSession;
  if (session != null) {
    final userId = session.user.id;
    try {
      await syncService.setUser(userId);
      courseSyncService.syncAll().catchError(
          (e) => debugPrint('Course sync failed: $e'));
    } catch (e) {
      debugPrint('Sync setup failed, running offline: $e');
    }
    home = const MainScreen();
  } else {
    home = const AuthPage();
  }

  runApp(MaterialApp(home: home));
}
