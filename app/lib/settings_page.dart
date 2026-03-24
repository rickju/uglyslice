import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_page.dart';
import 'main.dart' show db;
import 'seed_data.dart';
import 'services/course_repository.dart';
import 'services/handicap_service.dart';
import 'services/round_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  HandicapResult _handicap = HandicapResult.none;
  // courseId → (name, par)
  Map<String, (String, double)> _courseMeta = {};
  bool _loadingHandicap = true;

  @override
  void initState() {
    super.initState();
    _loadHandicap();
  }

  Future<void> _loadHandicap() async {
    await CourseRatingStore.load();
    final rounds = await RoundRepository(db).listRoundsForPlayer('Rick');
    if (!mounted) return;

    // Fetch par for each unique course.
    final repo = CourseRepository(db);
    final Map<String, double> coursePars = {};
    final Map<String, (String, double)> meta = {};
    for (final r in rounds) {
      if (meta.containsKey(r.course.id)) continue;
      final c = await repo.fetchCourse(r.course.id);
      if (c != null && c.holes.isNotEmpty) {
        final par = c.holes.fold(0, (s, h) => s + h.par).toDouble();
        coursePars[r.course.id] = par;
        meta[r.course.id] = (r.course.name, par);
      } else {
        meta[r.course.id] = (r.course.name, 0.0);
      }
    }

    final input = rounds.map((r) => (
          score: r.totalScore,
          holes: r.holePlays.length,
          courseId: r.course.id,
        )).toList();

    setState(() {
      _handicap = HandicapService.calculate(rounds: input, coursePars: coursePars);
      _courseMeta = meta;
      _loadingHandicap = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email;
    final isAnon = user?.isAnonymous ?? true;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── Account ────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(isAnon ? 'Not signed in' : (email ?? 'Signed in')),
            subtitle: isAnon ? const Text('Anonymous session') : null,
          ),
          const Divider(),

          // ── Handicap ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Handicap',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
          ),
          if (_loadingHandicap)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _HandicapCard(
              result: _handicap,
              courseMeta: _courseMeta,
              onRatingChanged: () => _loadHandicap(),
            ),
          const Divider(),

          // ── Dev tools ──────────────────────────────────────────────
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
              _loadHandicap();
            },
          ),
          const Divider(),

          // ── Sign out ───────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Sign out',
                style: TextStyle(color: Colors.redAccent)),
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

// ── Handicap card ─────────────────────────────────────────────────────────────

class _HandicapCard extends StatelessWidget {
  final HandicapResult result;
  final Map<String, (String, double)> courseMeta;
  final VoidCallback onRatingChanged;

  const _HandicapCard({
    required this.result,
    required this.courseMeta,
    required this.onRatingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Index display
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(result.display,
                  style: theme.textTheme.displaySmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.isEstimated
                        ? 'Estimated index'
                        : 'Handicap Index (WHS)',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (result.totalRounds > 0)
                    Text(
                      'Best ${result.roundsUsed} of ${result.totalRounds} rounds',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (result.isEstimated)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Add course ratings below for an official WHS index.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
        // Per-course rating rows
        ...courseMeta.entries.map((e) {
          final courseId = e.key;
          final (name, par) = e.value;
          final override = CourseRatingStore.get(courseId);
          return ListTile(
            dense: true,
            title: Text(name, style: const TextStyle(fontSize: 14)),
            subtitle: override != null
                ? Text(
                    'CR ${override.courseRating.toStringAsFixed(1)}  '
                    'Slope ${override.slopeRating.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12))
                : Text('Par ${par > 0 ? par.toInt() : '?'} · no ratings',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: TextButton(
              child:
                  Text(override != null ? 'Edit' : 'Add rating'),
              onPressed: () async {
                await _showRatingDialog(context, courseId, name, par, override);
                onRatingChanged();
              },
            ),
          );
        }),
      ],
    );
  }

  Future<void> _showRatingDialog(BuildContext context, String courseId,
      String name, double par, CourseRating? existing) async {
    final crCtrl = TextEditingController(
        text: existing?.courseRating.toStringAsFixed(1) ??
            (par > 0 ? par.toStringAsFixed(1) : ''));
    final srCtrl = TextEditingController(
        text: existing?.slopeRating.toStringAsFixed(0) ?? '113');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name, style: const TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: crCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Course Rating', hintText: 'e.g. 70.4'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: srCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Slope Rating', hintText: 'e.g. 125'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final cr = double.tryParse(crCtrl.text);
              final sr = double.tryParse(srCtrl.text);
              if (cr != null && sr != null) {
                await CourseRatingStore.save(
                    courseId, CourseRating(courseRating: cr, slopeRating: sr));
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
