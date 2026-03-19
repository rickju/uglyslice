/// CLI wrapper for ingest operations.
///
/// Usage:
///   dart run bin/cli.dart ingest-course "Karori Golf Club"
///   dart run bin/cli.dart ingest-course          ← interactive picker
///   dart run bin/cli.dart ingest-all
import 'dart:io';
import 'package:ugly_slice_backend/ingest_core.dart';
import 'package:ugly_slice_backend/raw_json_store.dart';
import 'package:ugly_slice_backend/supabase_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(1);
  }

  switch (args[0]) {
    case 'ingest-course':
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      final bbox = args.length > 2 ? args[2] : null;
      await ingestOneCourse(name, bbox: bbox);

    case 'reparse-course':
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await reparseCourse(name);

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
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await queryCourse(name);

    case 'check-integrity':
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await checkCourseIntegrity(name);

    case 'check-course':
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      final bbox = args.length > 2 ? args[2] : null;
      await checkCourse(name, bbox: bbox);

    case 'check-cache':
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await checkCourseFromCache(name);

    case 'search-courses':
      if (args.length < 2) {
        print('Error: search-courses requires a query.');
        print('  Usage: dart run bin/cli.dart search-courses "karori"');
        exit(1);
      }
      await searchCachedCourses(args[1]);

    case 'list-courses':
      await listCachedCourses();

    default:
      print('Unknown command: ${args[0]}');
      _usage();
      exit(1);
  }
}

/// Interactive fuzzy picker. Reads course names from the local cache, lets
/// the user type to filter, and arrow-keys to select. Returns the chosen name
/// or null if cancelled / no terminal.
Future<String?> _pickCourseName() async {
  if (!stdin.hasTerminal) return null;

  // Prefer Supabase course_list (full list); fall back to local SQLite cache.
  List<String> allNames = [];
  try {
    final supabase = SupabaseRestClient();
    final rows = await supabase.select('course_list', columns: 'name');
    allNames = rows
        .map((r) => r['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort();
    stdout.write('(${allNames.length} courses from Supabase)\n');
  } catch (_) {
    final store = RawJsonStore();
    allNames = await store.listNames();
    await store.close();
    if (allNames.isNotEmpty) {
      stdout.write('(${allNames.length} courses from local cache)\n');
    }
  }

  if (allNames.isEmpty) {
    print('No courses found. Run ingest-all or set SUPABASE env vars.');
    return null;
  }

  stdin.echoMode = false;
  stdin.lineMode = false;

  var query = '';
  var selectedIdx = 0;
  var printedLines = 0;
  const maxShow = 10;

  List<String> _filter(String q) {
    if (q.isEmpty) return allNames.take(maxShow).toList();
    final lower = q.toLowerCase();
    return allNames
        .where((n) => n.toLowerCase().contains(lower))
        .take(maxShow)
        .toList();
  }

  void clearPrinted() {
    for (var i = 0; i < printedLines; i++) {
      stdout.write('\x1b[1A\x1b[2K'); // move up + clear line
    }
    printedLines = 0;
  }

  void render(List<String> matches) {
    clearPrinted();
    stdout.write('Search: $query\n');
    for (var i = 0; i < matches.length; i++) {
      if (i == selectedIdx) {
        stdout.write('\x1b[32m> ${matches[i]}\x1b[0m\n'); // green highlight
      } else {
        stdout.write('  ${matches[i]}\n');
      }
    }
    if (matches.isEmpty) {
      stdout.write('  (no matches)\n');
      printedLines = 2;
    } else {
      printedLines = 1 + matches.length;
    }
  }

  var matches = _filter(query);
  render(matches);

  String? result;

  while (true) {
    final byte = stdin.readByteSync();
    if (byte == -1) break;

    if (byte == 0x1b) {
      // Escape sequence — read two more bytes for arrow keys.
      final b2 = stdin.readByteSync();
      if (b2 == 0x5b) {
        final b3 = stdin.readByteSync();
        if (b3 == 0x41 && selectedIdx > 0) selectedIdx--;          // ↑
        if (b3 == 0x42 && selectedIdx < matches.length - 1) selectedIdx++; // ↓
      }
    } else if (byte == 0x0d || byte == 0x0a) {
      // Enter — confirm selection.
      if (matches.isNotEmpty) result = matches[selectedIdx];
      break;
    } else if (byte == 0x7f || byte == 0x08) {
      // Backspace.
      if (query.isNotEmpty) {
        query = query.substring(0, query.length - 1);
        selectedIdx = 0;
      }
    } else if (byte == 0x03) {
      // Ctrl+C — cancel.
      break;
    } else if (byte >= 0x20 && byte < 0x7f) {
      // Printable ASCII.
      query += String.fromCharCode(byte);
      selectedIdx = 0;
    }

    matches = _filter(query);
    if (selectedIdx >= matches.length) {
      selectedIdx = matches.isEmpty ? 0 : matches.length - 1;
    }
    render(matches);
  }

  stdin.echoMode = true;
  stdin.lineMode = true;
  clearPrinted();

  if (result != null) {
    print('Selected: $result');
  }
  return result;
}

void _usage() {
  print('Usage: dart run bin/cli.dart <command> [args]');
  print('');
  print('Commands:');
  print('  ingest-course [name] [bbox]   Fetch, parse, and upsert a single course');
  print('  reparse-course [name]         Re-parse from local cache, upsert (no Overpass)');
  print('  ingest-all [--limit N]        Fetch and upsert all NZ courses');
  print('  ingest-region <name> [--limit N]  Fetch and upsert courses in a named region');
  print('  check-course  [name] [bbox]   Fetch and parse a course, print details (no upsert)');
  print('  check-cache   [name]          Parse from local cache, print details (no Overpass/Supabase)');
  print('  search-courses <query>        Search cached course names for a partial match');
  print('  list-courses                  List all course names in the local cache');
  print('  query-course  [name]          Query Supabase for a stored course and print details');
  print('  check-integrity [name]        Query Supabase and report integrity issues');
  print('');
  print('Tip: omit [name] to get an interactive picker (type to filter, ↑↓ to select).');
}
