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

    // ── Stage 1: Overpass ──────────────────────────────────────────────────────

    case 'fetch':
    case 'ingest-course': // alias
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      final bbox = args.length > 2 ? args[2] : null;
      await ingestOneCourse(name, bbox: bbox);

    case 'fetch-nz':
    case 'ingest-nz': // alias
      final limitArg = args.indexOf('--limit');
      final limit = limitArg != -1 ? int.tryParse(args[limitArg + 1]) : null;
      await ingestAllNzCourses(limit: limit);

    case 'fetch-region':
    case 'ingest-region': // alias
      final regionName = args.length >= 2 ? args[1] : await _pickRegion();
      if (regionName == null) exit(1);
      final limitArg = args.indexOf('--limit');
      final limit = limitArg != -1 ? int.tryParse(args[limitArg + 1]) : null;
      await ingestRegion(regionName, limit: limit);

    // ── Stage 2: Cache ─────────────────────────────────────────────────────────

    case 'cache-status':
      final query = args.length >= 2 ? args[1] : null;
      await _cacheStatus(filter: query);

    case 'cache-list':
    case 'list-courses':   // alias
    case 'search-courses': // alias
      final query = args.length >= 2 ? args[1] : null;
      if (query != null) {
        await searchCachedCourses(query);
      } else {
        await listCachedCourses();
      }

    case 'cache-parse':
    case 'check-cache':  // alias
    case 'check-course': // alias (was fetch+parse; now cache-only)
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await checkCourseFromCache(name);

    case 'cache-reparse':
    case 'reparse-course': // alias
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await reparseCourse(name);

    // ── Stage 3: Supabase ──────────────────────────────────────────────────────

    case 'db-show':
    case 'query-course': // alias
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await queryCourse(name);

    case 'db-integrity':
    case 'check-integrity': // alias
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await checkCourseIntegrity(name);

    case 'db-enrich':
    case 'enrich-course': // alias
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await _enrichOneCourse(name);

    case 'db-delete':
    case 'delete-course': // alias
      final name = args.length >= 2 ? args[1] : await _pickCourseName();
      if (name == null) exit(1);
      await _deleteCourse(name, dryRun: args.contains('--dry-run'));

    case 'db-cleanup':
    case 'cleanup-junk': // alias
      await _cleanupJunk(dryRun: args.contains('--dry-run'));

    case 'db-incomplete':
    case 'reingest-incomplete': // alias
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

// ── Region picker ─────────────────────────────────────────────────────────────

/// Canonical region list for fetch-region / daemon.
/// "United States" is omitted — too large for a single Overpass query.
/// Use individual US states instead.
const kRegions = [
  // Countries / territories
  'New Zealand',
  'Australia',
  'United Kingdom',
  'Ireland',
  'Canada',
  'Germany',
  'France',
  'Spain',
  'Italy',
  'Netherlands',
  'Sweden',
  'Denmark',
  'Norway',
  'Finland',
  'Japan',
  'South Korea',
  'South Africa',
  // US states (alphabetical)
  'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California',
  'Colorado', 'Connecticut', 'Delaware', 'Florida', 'Georgia',
  'Hawaii', 'Idaho', 'Illinois', 'Indiana', 'Iowa',
  'Kansas', 'Kentucky', 'Louisiana', 'Maine', 'Maryland',
  'Massachusetts', 'Michigan', 'Minnesota', 'Mississippi', 'Missouri',
  'Montana', 'Nebraska', 'Nevada', 'New Hampshire', 'New Jersey',
  'New Mexico', 'New York', 'North Carolina', 'North Dakota', 'Ohio',
  'Oklahoma', 'Oregon', 'Pennsylvania', 'Rhode Island', 'South Carolina',
  'South Dakota', 'Tennessee', 'Texas', 'Utah', 'Vermont',
  'Virginia', 'Washington', 'West Virginia', 'Wisconsin', 'Wyoming',
];

/// Interactive fuzzy picker over [kRegions].
/// Returns the selected region name, or null if cancelled / non-terminal.
Future<String?> _pickRegion() async {
  if (!stdin.hasTerminal) return null;

  const maxShow = 12;

  List<String> filter(String q) {
    if (q.isEmpty) return kRegions.take(maxShow).toList();
    final lower = q.toLowerCase();
    return kRegions
        .where((r) => r.toLowerCase().contains(lower))
        .take(maxShow)
        .toList();
  }

  stdin.echoMode = false;
  stdin.lineMode = false;

  var query = '';
  var selectedIdx = 0;
  var printedLines = 0;

  void clearPrinted() {
    for (var i = 0; i < printedLines; i++) stdout.write('\x1b[1A\x1b[2K');
    printedLines = 0;
  }

  void render(List<String> matches) {
    clearPrinted();
    stdout.write(
        'Region: $query  \x1b[2m[${kRegions.length} regions · type to filter]\x1b[0m\n');
    var lines = 1;
    if (matches.isEmpty) {
      stdout.write('  \x1b[2m(no matches)\x1b[0m\n');
      lines++;
    }
    for (var i = 0; i < matches.length; i++) {
      if (i == selectedIdx) {
        stdout.write('\x1b[32m>  ${matches[i]}\x1b[0m\n');
      } else {
        stdout.write('   ${matches[i]}\n');
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

  if (result != null) print('Selected: $result');
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

// ── Cache status ──────────────────────────────────────────────────────────────

Future<void> _cacheStatus({String? filter}) async {
  final store = RawJsonStore();
  final allEntries = await store.cacheStatus(filter: filter, includeSystem: true);
  await store.close();

  if (allEntries.isEmpty) {
    print(filter != null ? 'No cache entries matching "$filter".' : 'Cache is empty.');
    return;
  }

  final systemEntries = allEntries.where((e) => (e['name'] as String).startsWith('_')).toList();
  final courseEntries = allEntries.where((e) => !(e['name'] as String).startsWith('_')).toList();

  final totalBytes = allEntries.fold<int>(0, (s, e) => s + (e['json_bytes'] as int? ?? 0));
  print('Overpass cache: ${courseEntries.length} course(s)  ${systemEntries.length} bulk blob(s)  ${_fmtBytes(totalBytes)} total\n');

  final header = '${'Name'.padRight(50)}  ${'Fetched'.padRight(16)}  ${'Age'.padLeft(8)}  Ver  Size';
  final divider = '-' * header.length;

  void printEntries(List<Map<String, dynamic>> entries) {
    final now = DateTime.now();
    for (final e in entries) {
      final name = (e['name'] as String).padRight(50);
      final ms = e['last_fetched'] as int;
      final fetched = DateTime.fromMillisecondsSinceEpoch(ms);
      final age = now.difference(fetched);
      final ageStr = _fmtAge(age).padLeft(8);
      final fetchedStr = fetched.toLocal().toString().substring(0, 16).padRight(16);
      final versions = (e['versions'] as int).toString().padLeft(3);
      final sizeStr = _fmtBytes(e['json_bytes'] as int? ?? 0).padLeft(6);
      print('$name  $fetchedStr  $ageStr  $versions  $sizeStr');
    }
  }

  if (systemEntries.isNotEmpty) {
    print('BULK BLOBS');
    print(header);
    print(divider);
    printEntries(systemEntries);
    print('');
  }

  if (courseEntries.isNotEmpty) {
    print('INDIVIDUAL COURSES');
    print(header);
    print(divider);
    printEntries(courseEntries);
  }
}

String _fmtAge(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inMinutes}m';
}

String _fmtBytes(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  return '${bytes}B';
}

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
  print('── Stage 1: Overpass  (fetch from OSM → local cache + Supabase) ──────────');
  print('  fetch [name] [bbox]              Fetch one course → cache + Supabase');
  print('  fetch-nz [--limit N]             Fetch all NZ courses (NI + SI)');
  print('  fetch-region <name> [--limit N]  Fetch all courses in a named region');
  print('');
  print('── Stage 2: Cache  (local SQLite, no network) ───────────────────────────');
  print('  cache-status [query]             Show cached blobs: name, age, size, versions');
  print('  cache-list   [query]             List cached course names (filter optional)');
  print('  cache-parse  [name]              Parse from cache, print details (no DB write)');
  print('  cache-reparse [name]             Parse from cache, upsert to Supabase');
  print('');
  print('── Stage 3: Supabase  (read/write DB) ───────────────────────────────────');
  print('  db-show      [name]              Print course details from Supabase');
  print('  db-integrity [name]              Run integrity checks, show issues');
  print('  db-enrich    [name]              Web search + Claude → patch course');
  print('  db-delete    [name] [--dry-run]  Remove course from courses + course_list');
  print('  db-cleanup   [--dry-run]         Remove driving ranges, mini golf, etc.');
  print('  db-incomplete [--region R] [--min-holes N] [--limit N]');
  print('                                   Re-fetch courses with too few holes');
  print('');
  print('Tip: omit [name] for an interactive picker (★ recent · sorted nearby · type to filter).');
  print('Old command names (ingest-course, reparse-course, query-course, etc.) still work as aliases.');
}
