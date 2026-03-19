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

    case 'reparse-course':
      if (args.length < 2) {
        print('Error: reparse-course requires a course name.');
        print('  Usage: dart run bin/cli.dart reparse-course "Course Name"');
        exit(1);
      }
      await reparseCourse(args[1]);

    case 'ingest-all':
      final limitArg = args.indexOf('--limit');
      final limit = limitArg != -1 ? int.tryParse(args[limitArg + 1]) : null;
      await ingestAllNzCourses(limit: limit);

    case 'ingest-region':
      if (args.length < 2) {
        print('Error: ingest-region requires a region name.');
        print(
            '  Usage: dart run bin/cli.dart ingest-region "New Zealand" [--limit N]');
        exit(1);
      }
      final limitArg = args.indexOf('--limit');
      final limit = limitArg != -1 ? int.tryParse(args[limitArg + 1]) : null;
      await ingestRegion(args[1], limit: limit);

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
      await checkCourseIntegrity(args[1]);

    case 'check-course':
      if (args.length < 2) {
        print('Error: check-course requires a course name.');
        print('  Usage: dart run bin/cli.dart check-course "Course Name"');
        exit(1);
      }
      final bbox = args.length > 2 ? args[2] : null;
      await checkCourse(args[1], bbox: bbox);

    case 'check-cache':
      if (args.length < 2) {
        print('Error: check-cache requires a course name.');
        print('  Usage: dart run bin/cli.dart check-cache "Course Name"');
        exit(1);
      }
      await checkCourseFromCache(args[1]);

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
  print('  ingest-course <name> [bbox]  Fetch, parse, and upsert a single course');
  print('  reparse-course <name>        Re-parse from local cache, upsert (no Overpass)');
  print('  ingest-all [--limit N]        Fetch and upsert all NZ courses');
  print('  ingest-region <name> [--limit N]  Fetch and upsert courses in a named region');
  print('  check-course  <name> [bbox]   Fetch and parse a course, print details (no upsert)');
  print('  check-cache   <name>          Parse from local cache, print details (no Overpass/Supabase)');
  print('  query-course  <name>          Query Supabase for a stored course and print details');
  print('  check-integrity <name>        Query Supabase and report integrity issues');
}
