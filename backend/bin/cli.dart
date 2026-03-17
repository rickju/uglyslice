/// CLI wrapper for ingest operations.
///
/// Usage:
///   dart run bin/cli.dart ingest-course "Karori Golf Club"
///   dart run bin/cli.dart ingest-all
import 'dart:io';
import 'package:ugly_slice_backend/ingest_core.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(1);
  }

  switch (args[0]) {
    case 'ingest-course':
      if (args.length < 2) {
        print('Error: ingest-course requires a course name.');
        print('  Usage: dart run bin/cli.dart ingest-course "Course Name"');
        exit(1);
      }
      final bbox = args.length > 2 ? args[2] : null;
      await ingestOneCourse(args[1], bbox: bbox);

    case 'ingest-all':
      await ingestAllNzCourses();

    default:
      print('Unknown command: ${args[0]}');
      _usage();
      exit(1);
  }
}

void _usage() {
  print('Usage: dart run bin/cli.dart <command> [args]');
  print('');
  print('Commands:');
  print('  ingest-course <name> [bbox]   Fetch, parse, and upsert a single course');
  print('  ingest-all                    Fetch and upsert all NZ courses');
}
