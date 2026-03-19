/// CLI wrapper for ingest operations.
///
/// Usage:
///   dart run bin/cli.dart ingest-course "Karori Golf Club"
///   dart run bin/cli.dart ingest-course          ← interactive picker
///   dart run bin/cli.dart ingest-all
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
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

// ── Picker ────────────────────────────────────────────────────────────────────

typedef _CourseEntry = ({String name, double lat, double lon});

/// Interactive fuzzy picker with recently-used and nearby priority.
/// Omit the course name on any command to invoke it.
Future<String?> _pickCourseName() async {
  if (!stdin.hasTerminal) return null;

  // Load recently used names (most recent first).
  final recent = _loadRecent();
  final recentSet = recent.toSet();

  // Load all courses from Supabase (with lat/lon); fall back to local cache.
  List<_CourseEntry> allCourses = [];
  String sourceLabel = '';
  try {
    final supabase = SupabaseRestClient();
    final rows = await supabase.select('course_list', columns: 'name,lat,lon');
    allCourses = rows
        .where((r) => (r['name'] as String?)?.isNotEmpty == true)
        .map((r) => (
              name: r['name'] as String,
              lat: (r['lat'] as num).toDouble(),
              lon: (r['lon'] as num).toDouble(),
            ))
        .toList();
    sourceLabel = '${allCourses.length} courses';
  } catch (_) {
    final store = RawJsonStore();
    final names = await store.listNames();
    await store.close();
    allCourses = names.map((n) => (name: n, lat: 0.0, lon: 0.0)).toList();
    sourceLabel = '${allCourses.length} cached';
  }

  if (allCourses.isEmpty) {
    print('No courses found. Run ingest-all or set SUPABASE env vars.');
    return null;
  }

  // Get approximate location via IP for nearby sort (best-effort, 3s timeout).
  final loc = await _approxLocation();

  // Build priority list: recent first, then nearby (or alpha if no location).
  final recentEntries =
      recent.where((r) => allCourses.any((c) => c.name == r)).toList();
  var others =
      allCourses.where((c) => !recentSet.contains(c.name)).toList();
  if (loc != null) {
    others.sort((a, b) => _distSq(loc.$1, loc.$2, a.lat, a.lon)
        .compareTo(_distSq(loc.$1, loc.$2, b.lat, b.lon)));
  } else {
    others.sort((a, b) => a.name.compareTo(b.name));
  }
  final prioritized = [...recentEntries, ...others.map((c) => c.name)];

  // ── UI ────────────────────────────────────────────────────────────────────
  stdin.echoMode = false;
  stdin.lineMode = false;

  var query = '';
  var selectedIdx = 0;
  var printedLines = 0;
  const maxShow = 10;

  List<String> filter(String q) {
    if (q.isEmpty) return prioritized.take(maxShow).toList();
    final lower = q.toLowerCase();
    return prioritized
        .where((n) => n.toLowerCase().contains(lower))
        .take(maxShow)
        .toList();
  }

  void clearPrinted() {
    for (var i = 0; i < printedLines; i++) stdout.write('\x1b[1A\x1b[2K');
    printedLines = 0;
  }

  void render(List<String> matches) {
    clearPrinted();
    final hint = loc != null ? 'nearby' : 'alpha';
    stdout.write('Search: $query  \x1b[2m[$sourceLabel · $hint]\x1b[0m\n');
    var lines = 1;
    if (matches.isEmpty) {
      stdout.write('  \x1b[2m(no matches)\x1b[0m\n');
      lines++;
    }
    for (var i = 0; i < matches.length; i++) {
      // ★ for recently-used when not filtering
      final star =
          (query.isEmpty && recentSet.contains(matches[i])) ? '★ ' : '  ';
      if (i == selectedIdx) {
        stdout.write('\x1b[32m>$star${matches[i]}\x1b[0m\n');
      } else {
        stdout.write(' $star${matches[i]}\n');
      }
      lines++;
    }
    printedLines = lines;
  }

  var matches = filter(query);
  render(matches);

  String? result;
  while (true) {
    final byte = stdin.readByteSync();
    if (byte == -1) break;

    if (byte == 0x1b) {
      final b2 = stdin.readByteSync();
      if (b2 == 0x5b) {
        final b3 = stdin.readByteSync();
        if (b3 == 0x41 && selectedIdx > 0) selectedIdx--;
        if (b3 == 0x42 && selectedIdx < matches.length - 1) selectedIdx++;
      }
    } else if (byte == 0x0d || byte == 0x0a) {
      if (matches.isNotEmpty) result = matches[selectedIdx];
      break;
    } else if (byte == 0x7f || byte == 0x08) {
      if (query.isNotEmpty) {
        query = query.substring(0, query.length - 1);
        selectedIdx = 0;
      }
    } else if (byte == 0x03) {
      break;
    } else if (byte >= 0x20 && byte < 0x7f) {
      query += String.fromCharCode(byte);
      selectedIdx = 0;
    }

    matches = filter(query);
    if (selectedIdx >= matches.length) {
      selectedIdx = matches.isEmpty ? 0 : matches.length - 1;
    }
    render(matches);
  }

  stdin.echoMode = true;
  stdin.lineMode = true;
  clearPrinted();

  if (result != null) {
    _saveRecent(result);
    print('Selected: $result');
  }
  return result;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// IP-based approximate location. Returns (lat, lon) or null on failure.
Future<(double, double)?> _approxLocation() async {
  try {
    final resp = await http
        .get(Uri.parse('https://ipinfo.io/json'))
        .timeout(const Duration(seconds: 3));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final loc = data['loc'] as String?;
    if (loc == null) return null;
    final parts = loc.split(',');
    return (double.parse(parts[0]), double.parse(parts[1]));
  } catch (_) {
    return null;
  }
}

/// Squared degree distance (cheap proxy for sorting — no trig needed).
double _distSq(double lat1, double lon1, double lat2, double lon2) {
  final dlat = lat2 - lat1;
  final dlon = (lon2 - lon1) * 0.75; // rough cos(lat) correction
  return dlat * dlat + dlon * dlon;
}

File get _recentFile =>
    File('${Platform.environment['HOME'] ?? '/tmp'}/.ugly_slice_recent.json');

List<String> _loadRecent() {
  try {
    return (jsonDecode(_recentFile.readAsStringSync()) as List).cast<String>();
  } catch (_) {
    return [];
  }
}

void _saveRecent(String name) {
  var recent = _loadRecent()..remove(name);
  recent.insert(0, name);
  if (recent.length > 20) recent = recent.sublist(0, 20);
  _recentFile.writeAsStringSync(jsonEncode(recent));
}

// ── Usage ─────────────────────────────────────────────────────────────────────

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
  print('Tip: omit [name] for an interactive picker (★ recent · sorted nearby · type to filter).');
}
