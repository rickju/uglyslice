/// CLI wrapper for ingest operations.
///
/// Usage:
///   dart run bin/cli.dart ingest-course "Karori Golf Club"
///   dart run bin/cli.dart ingest-course          ← interactive picker
///   dart run bin/cli.dart ingest-all
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:ugly_slice_backend/enricher.dart';
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

    case 'enrich-course':
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await _enrichOneCourse(name);

    case 'delete-course':
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await _deleteCourse(name, dryRun: args.contains('--dry-run'));

    case 'cleanup-junk':
      await _cleanupJunk(dryRun: args.contains('--dry-run'));

    case 'reingest-incomplete':
      final limitArg = args.indexOf('--limit');
      final limit = limitArg != -1 ? int.tryParse(args[limitArg + 1]) : null;
      final threshArg = args.indexOf('--min-holes');
      final minHoles = threshArg != -1 ? int.tryParse(args[threshArg + 1]) ?? 9 : 9;
      final region = args.contains('--region')
          ? args[args.indexOf('--region') + 1]
          : 'New Zealand';
      await _reingestIncomplete(region: region, minHoles: minHoles, limit: limit);

    default:
      print('Unknown command: ${args[0]}');
      _usage();
      exit(1);
  }
}

// ── Enrich one course by name ─────────────────────────────────────────────────

Future<void> _enrichOneCourse(String name) async {
  final supabase = SupabaseRestClient();

  // Look up course_id from Supabase.
  final rows = await supabase.select('courses', filters: 'name=eq.$name', columns: 'id');
  if (rows.isEmpty) {
    print('Course "$name" not found in Supabase. Run ingest-course first.');
    exit(1);
  }
  final courseId = rows.first['id'] as String;

  // Ensure there's a pending queue entry (upsert if missing).
  final existing = await supabase.select('enrich_queue',
      filters: 'course_id=eq.$courseId', columns: 'id,status');
  if (existing.isEmpty) {
    await supabase.insert('enrich_queue', [
      {
        'course_id': courseId,
        'course_name': name,
        'fields': ['hole_handicaps', 'hole_pars', 'tee_ratings'],
        'status': 'pending',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }
    ]);
    print('Added "$name" to enrich queue.');
  } else {
    await supabase.patch('enrich_queue', 'course_id=eq.$courseId', {
      'status': 'pending',
      'last_error': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    print('Reset "$name" to pending.');
  }

  // Enrich directly — no queue ordering issues.
  final enricher = Enricher();
  await enricher.enrichOne(courseId, name);
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

// ── Delete / cleanup ──────────────────────────────────────────────────────────

// ── Reingest incomplete courses ───────────────────────────────────────────────

/// Re-ingests courses that have fewer than [minHoles] holes parsed.
/// Fetches fresh Overpass data (ignores TTL cache) and reports progress.
Future<void> _reingestIncomplete({
  String region = 'New Zealand',
  int minHoles = 9,
  int? limit,
}) async {
  final supabase = SupabaseRestClient();

  // Determine bbox for the region to filter course_list.
  const nzBbox = 'lat=gte.-47.5&lat=lte.-34.0&lon=gte.166.0&lon=lte.179.0';
  final bboxFilter = region == 'New Zealand' ? nzBbox : null;
  if (bboxFilter == null) {
    print('Error: only "New Zealand" region supported currently.');
    exit(1);
  }

  // Get regional course names.
  final listRows = await supabase.select(
    'course_list',
    filters: bboxFilter,
    columns: 'name',
  );
  final regionalNames = {for (final r in listRows) r['name'] as String};
  print('Region "$region": ${regionalNames.length} courses in course_list');

  // Get all courses and find incomplete ones in this region.
  final allRows = await supabase.select(
    'courses',
    columns: 'id,name,course_doc',
  );

  int getHoles(Map r) {
    var doc = r['course_doc'];
    if (doc is String) doc = jsonDecode(doc);
    return (doc as Map?)?['holeCount'] as int? ?? 0;
  }

  final incomplete = allRows
      .where((r) =>
          regionalNames.contains(r['name'] as String) &&
          getHoles(r) < minHoles)
      .toList();

  var toProcess = incomplete;
  if (limit != null) toProcess = toProcess.take(limit).toList();

  print('Incomplete (<$minHoles holes): ${incomplete.length}  processing: ${toProcess.length}');
  print('');

  int improved = 0, unchanged = 0, failed = 0;

  for (int i = 0; i < toProcess.length; i++) {
    final name = toProcess[i]['name'] as String;
    final before = getHoles(toProcess[i]);
    stdout.write('[${i + 1}/${toProcess.length}] $name ($before h) ... ');

    try {
      await ingestOneCourse(name);

      // Check new hole count.
      final updated = await supabase.select(
        'courses',
        filters: 'name=eq.${Uri.encodeComponent(name)}',
        columns: 'course_doc',
      );
      final after = updated.isEmpty ? 0 : (() {
        var doc = updated.first['course_doc'];
        if (doc is String) doc = jsonDecode(doc);
        return (doc as Map?)?['holeCount'] as int? ?? 0;
      })();

      if (after > before) {
        print('$before → $after h ✓');
        improved++;
      } else {
        print('still ${after}h (OSM unmapped)');
        unchanged++;
      }
    } catch (e) {
      print('FAILED: $e');
      failed++;
    }

    // Polite delay to avoid hammering Overpass.
    if (i < toProcess.length - 1) {
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  print('');
  print('Done — improved: $improved  unchanged: $unchanged  failed: $failed');
}

// ── Keywords that unambiguously identify non-playable venues ─────────────────

/// Keywords that unambiguously identify non-playable venues.
const _junkKeywords = [
  'driving range',
  'mini golf',
  'mini-golf',
  'pitch & putt',
  'pitch and putt',
  'putting course',
  'putting green',
  'golf academy',
  'practice center',
  'practice centre',
];

/// Exact names that are clearly not real golf courses (manual list).
const _junkExact = [
  'Golf Driving Range',
  'Driving Range',
  'Lilliput Mini Golf',
  'Mini Golf NZ with Bunnies',
  'Mini Golf',
  'Shooters Golf Driving Range',
  'Canterbury International Golf Academy',
  'Golf Warehouse Driving Range',
  '18 Hole Groomed Putting Course',
  'Lake Taupō Hole in One Challenge',
  'Whanga Putter',
  'prodrive Golf',
  'Ringa Ringa Heights',
  'Golflands',
  'Callum Brae Family Golf',
  "Maxwell's Golf Retreat",
  'Hole 11',
];

bool _isJunk(String name) {
  final lower = name.toLowerCase();
  if (_junkExact.any((e) => e.toLowerCase() == lower)) return true;
  return _junkKeywords.any((k) => lower.contains(k));
}

Future<void> _deleteCourse(String name, {bool dryRun = false}) async {
  final supabase = SupabaseRestClient();
  final encoded = Uri.encodeComponent(name);

  // Look up id first.
  final rows = await supabase.select('courses', filters: 'name=eq.$encoded', columns: 'id');
  if (rows.isEmpty) {
    print('Course "$name" not found in courses table.');
  } else {
    final id = rows.first['id'] as String;
    if (dryRun) {
      print('[dry-run] Would delete courses/$id "$name"');
    } else {
      await supabase.delete('courses', 'id=eq.$id');
      print('Deleted from courses: "$name" ($id)');
    }
  }

  // Remove from course_list too.
  final listRows = await supabase.select('course_list', filters: 'name=eq.$encoded', columns: 'id');
  if (listRows.isEmpty) {
    print('  (not in course_list)');
  } else {
    final listId = listRows.first['id'];
    if (dryRun) {
      print('[dry-run] Would delete course_list/$listId "$name"');
    } else {
      await supabase.delete('course_list', 'name=eq.$encoded');
      print('Deleted from course_list: "$name"');
    }
  }
}

Future<void> _cleanupJunk({bool dryRun = false}) async {
  final supabase = SupabaseRestClient();

  // Fetch all course names.
  final rows = await supabase.select('courses', columns: 'id,name');
  final junk = rows.where((r) => _isJunk(r['name'] as String)).toList();

  if (junk.isEmpty) {
    print('No junk courses found.');
    return;
  }

  print('Found ${junk.length} junk course(s):');
  for (final r in junk) {
    print('  ${r['id']}  ${r['name']}');
  }
  print('');

  if (dryRun) {
    print('[dry-run] No changes made. Re-run without --dry-run to delete.');
    return;
  }

  // Confirm.
  stdout.write('Delete all ${junk.length} course(s)? [y/N] ');
  final input = stdin.readLineSync()?.trim().toLowerCase();
  if (input != 'y') {
    print('Aborted.');
    return;
  }

  int deleted = 0;
  for (final r in junk) {
    final name = r['name'] as String;
    final id = r['id'] as String;
    final encoded = Uri.encodeComponent(name);
    await supabase.delete('courses', 'id=eq.$id');
    await supabase.delete('course_list', 'name=eq.$encoded');
    print('  Deleted: "$name"');
    deleted++;
  }
  print('\nDone — $deleted course(s) removed.');
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
  print('  enrich-course [name]          Web search + Claude extract → patch course in Supabase');
  print('  delete-course [name] [--dry-run]  Remove a course from courses + course_list');
  print('  cleanup-junk  [--dry-run]     Remove driving ranges, mini golf, etc.');
  print('  reingest-incomplete           Re-fetch courses with <9 holes from Overpass');
  print('    [--region <name>]           Region to filter (default: New Zealand)');
  print('    [--min-holes N]             Hole threshold (default: 9)');
  print('    [--limit N]                 Max courses to process');
  print('');
  print('Tip: omit [name] for an interactive picker (★ recent · sorted nearby · type to filter).');
}
