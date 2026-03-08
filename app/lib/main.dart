import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'main_screen.dart';
// Run `flutterfire configure` once to generate this file.
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MaterialApp(home: MainScreen()));
}
