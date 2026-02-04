import 'package:flutter/material.dart';
import 'course_selection_page.dart';
import 'models/round.dart';

class PlayPage extends StatelessWidget {
  final Function(Round) onRoundStarted;

  const PlayPage({super.key, required this.onRoundStarted});

  @override
  Widget build(BuildContext context) {
    return CourseSelectionPage(onRoundStarted: onRoundStarted);
  }
}
