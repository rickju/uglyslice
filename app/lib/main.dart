import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'database/app_database.dart';
import 'services/sync_service.dart';
import 'main_screen.dart';

// App-wide singletons — injected into repositories via constructor.
late final AppDatabase db;
late final SyncService syncService;

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

  // Sign in anonymously if no existing session.
  // Enable "Allow anonymous sign-ins" in your Supabase project settings.
  final session = Supabase.instance.client.auth.currentSession;
  if (session == null) {
    await Supabase.instance.client.auth.signInAnonymously();
  }

  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId != null) {
    await syncService.setUser(userId);
  }

  runApp(const MaterialApp(home: MainScreen()));
}
