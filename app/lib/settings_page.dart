import 'package:flutter/material.dart';

import 'main.dart' show db;
import 'seed_data.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
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
        ],
      ),
    );
  }
}
