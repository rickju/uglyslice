import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'main.dart' show db;
import 'seed_data.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email;
    final isAnon = user?.isAnonymous ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(isAnon ? 'Not signed in' : (email ?? 'Signed in')),
            subtitle: isAnon ? const Text('Anonymous session') : null,
          ),
          const Divider(),
          ListTile(
            title: const Text('Seed test data'),
            subtitle: const Text('Add 3 fake Karori rounds'),
            trailing: const Icon(Icons.add_circle_outline),
            onTap: () async {
              await seedKaroriRounds(db);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Seeded 3 Karori rounds')),
                );
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Sign out', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthPage()),
                  (_) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
