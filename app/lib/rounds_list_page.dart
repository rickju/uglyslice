import 'package:flutter/material.dart';

import 'main.dart' show db;
import 'models/round.dart';
import 'round_scorecard_page.dart';
import 'services/round_repository.dart';

class RoundsListPage extends StatelessWidget {
  const RoundsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scorecards')),
      body: StreamBuilder<List<Round>>(
        stream: RoundRepository(db).watchRoundsForPlayer('Rick'),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rounds = snap.data ?? [];
          if (rounds.isEmpty) {
            return const Center(
              child: Text(
                'No rounds yet.\nPlay a round or seed test data in Settings.',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.separated(
            itemCount: rounds.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => _RoundTile(round: rounds[i]),
          );
        },
      ),
    );
  }
}

class _RoundTile extends StatelessWidget {
  final Round round;

  const _RoundTile({required this.round});

  @override
  Widget build(BuildContext context) {
    final total = round.totalScore;
    final date = round.date;
    final dateStr =
        '${date.day} ${_month(date.month)} ${date.year}';

    return ListTile(
      title: Text(round.course.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(dateStr),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$total',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(
            '${round.holePlays.length} holes',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoundScorecardPage(round: round),
        ),
      ),
    );
  }

  String _month(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}
