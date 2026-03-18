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
      final limitArg = args.indexOf('--limit');
      final limit = limitArg != -1 ? int.tryParse(args[limitArg + 1]) : null;
      await ingestAllNzCourses(limit: limit);

    case 'query-course':
      if (args.length < 2) {
        print('Error: query-course requires a course name.');
        print('  Usage: dart run bin/cli.dart query-course "Course Name"');
        exit(1);
      }
      await queryCourse(args[1]);

    case 'check-integrity':
      if (args.length < 2) {
        print('Error: check-integrity requires a course name.');
        print('  Usage: dart run bin/cli.dart check-integrity "Course Name"');
        exit(1);
      }
      final bbox = args.length > 2 ? args[2] : null;
      await checkCourseIntegrity(args[1], bbox: bbox);

    case 'check-course':
      if (args.length < 2) {
        print('Error: check-course requires a course name.');
        print('  Usage: dart run bin/cli.dart check-course "Course Name"');
        exit(1);
      }
      final bbox = args.length > 2 ? args[2] : null;
      await checkCourse(args[1], bbox: bbox);

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
  print('  check-course  <name> [bbox]   Fetch and parse a course, print details (no upsert)');
  print('  query-course  <name>          Query Supabase for a stored course and print details');
  print('  check-integrity <name> [bbox] Fetch, parse, and report integrity issues');
}
