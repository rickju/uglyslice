import 'package:flutter/material.dart';
import 'package:ugly_slice/models/course.dart';
import 'package:ugly_slice/models/scorecard.dart';

class ScorecardPage extends StatefulWidget {
  final GolfCourse golfCourse;
  final Scorecard scorecard;
  final Function(int, int) onScoreChanged;

  const ScorecardPage({
    super.key,
    required this.golfCourse,
    required this.scorecard,
    required this.onScoreChanged,
  });

  @override
  State<ScorecardPage> createState() => _ScorecardPageState();
}

class _ScorecardPageState extends State<ScorecardPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scorecard')),
      body: ListView.builder(
        itemCount: widget.golfCourse.holes.length,
        itemBuilder: (context, index) {
          final hole = widget.golfCourse.holes[index];
          final score = widget.scorecard.getScore(index);

          return ListTile(
            title: Text('Hole ${hole.holeNumber} - Par ${hole.par}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    if (score > 0) {
                      widget.onScoreChanged(index, score - 1);
                    }
                  },
                ),
                Text('$score', style: const TextStyle(fontSize: 20)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    widget.onScoreChanged(index, score + 1);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
