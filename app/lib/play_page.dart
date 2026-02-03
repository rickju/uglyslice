import 'package:flutter/material.dart';
import 'course_selection_page.dart';
import 'models/golf_course.dart';

class PlayPage extends StatefulWidget {
  final Function(GolfCourse) onCourseSelected;

  const PlayPage({super.key, required this.onCourseSelected});

  @override
  State<PlayPage> createState() => _PlayPageState();
}

class _PlayPageState extends State<PlayPage> {
  @override
  Widget build(BuildContext context) {
    // This is not ideal, but for now we will pass the callback down.
    // A better solution would be to use a state management library.
    return CourseSelectionPage(onCourseSelected: widget.onCourseSelected);
  }
}
