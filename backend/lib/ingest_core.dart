import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'course_integrity.dart';
import 'course_parser.dart';
import 'raw_json_store.dart';
import 'supabase_client.dart';

String _md5(String data) => md5.convert(utf8.encode(data)).toString();

const overpassUrl = 'https://overpass-api.de/api/interpreter';
const nzBbox = '-47.5,166.0,-34.0,179.0';

/// Fetch, parse, and upsert a single course. Returns the courseId.
/// Throws on any failure.
Future<String> ingestOneCourse(String courseName, {String? bbox}) async {
  final effectiveBbox = bbox ?? nzBbox;

  print('Fetching: $courseName ...');

  final store = RawJsonStore();
  String rawBody;

  final cached = await store.loadIfFresh(courseName);
  if (cached != null) {
    print('  → Using cached Overpass JSON (< 23h old)');
    rawBody = cached;
  } else {
    final query = buildDetailQuery(courseName, effectiveBbox);
    final fetchStart = DateTime.now();
    final overpassResponse =
        await http.post(Uri.parse(overpassUrl), body: query);
    final fetchMs = DateTime.now().difference(fetchStart).inMilliseconds;

    if (overpassResponse.statusCode != 200) {
      print('  → Overpass: ${overpassResponse.statusCode} (error)');
      throw Exception('Overpass returned ${overpassResponse.statusCode}');
    }

    rawBody = overpassResponse.body;
    final overpassData = jsonDecode(rawBody) as Map<String, dynamic>;
    final elementCount =
        (overpassData['elements'] as List<dynamic>? ?? []).length;
    print('  → Overpass: 200 OK, $elementCount elements (${fetchMs}ms)');

    await store.save(courseName, rawBody, elementCount);
    print('  → Cached raw JSON to ${store.dbPath}');
  }

  print('  → Parsing ...');
  final ParsedCourse parsed;
  try {
    parsed = parseCourse(rawBody);
  } catch (e) {
    print('  → Parse FAILED: $e');
    throw Exception('Parse failed: $e');
  }
  print('  → Parsed: ${parsed.courseId}, ${parsed.holeDocs.length} holes');

  final newHash = _md5(rawBody);
  final supabase = SupabaseRestClient();

  // Change detection: skip if Overpass data unchanged (best-effort —
  // requires migration 009; silently bypassed if column not yet applied).
  try {
    final existingRows = await supabase.select(
      'courses',
      filters: 'name=eq.$courseName',
      columns: 'id,overpass_hash',
    );
    if (existingRows.isNotEmpty &&
        existingRows.first['overpass_hash'] == newHash) {
      print('  → Overpass data unchanged (hash match) — skipping upsert');
      return existingRows.first['id'] as String;
    }
  } catch (_) {
    // overpass_hash column not yet in DB — skip change detection.
  }

  // Upsert: include overpass_hash if the column exists, fall back without it.
  Future<void> doUpsert(bool withHash) => supabase.upsert('courses', [
        {
          'id': parsed.courseId,
          'name': parsed.courseDoc['name'] as String? ?? courseName,
          'course_doc': parsed.courseDoc,
          'holes_doc': parsed.holeDocs,
          if (withHash) 'overpass_hash': newHash,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }
      ]);

  try {
    await doUpsert(true);
  } catch (e) {
    if (e.toString().contains('overpass_hash')) {
      await doUpsert(false); // column not yet migrated
    } else {
      rethrow;
    }
  }
  print('  → Upserted to Supabase ✓');

  await _persistIntegrityIssues(supabase, parsed);
  await _enqueueEnrichmentIfNeeded(supabase, parsed);

  return parsed.courseId;
}

/// Re-parse a course from the local SQLite cache and upsert to Supabase.
/// No Overpass request — useful when Overpass is rate-limiting.
Future<String> reparseCourse(String courseName) async {
  final store = RawJsonStore();
  final rawBody = await store.load(courseName);
  await store.close();

  if (rawBody == null) {
    await store.close();
    await _suggestFromCache(courseName);
    throw Exception('No cached JSON for "$courseName".');
  }

  print('  → Parsing from cache ...');
  final ParsedCourse parsed;
  try {
    parsed = parseCourse(rawBody);
  } catch (e) {
    print('  → Parse FAILED: $e');
    throw Exception('Parse failed: $e');
  }
  print('  → Parsed: ${parsed.courseId}, ${parsed.holeDocs.length} holes');

  final supabase = SupabaseRestClient();
  await supabase.upsert('courses', [
    {
      'id': parsed.courseId,
      'name': parsed.courseDoc['name'] as String? ?? courseName,
      'course_doc': parsed.courseDoc,
      'holes_doc': parsed.holeDocs,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }
  ]);
  print('  → Upserted to Supabase ✓');
  await _persistIntegrityIssues(supabase, parsed);
  await _enqueueEnrichmentIfNeeded(supabase, parsed);

  return parsed.courseId;
}

/// Print raw OSM elements for a specific hole from the cached JSON.
Future<void> inspectCachedHole(String courseName, int holeRef) async {
  final store = RawJsonStore();
  final rawBody = await store.load(courseName);
  await store.close();

  if (rawBody == null) {
    print('No cached JSON for "$courseName". Run ingest-course first.');
    return;
  }

  final data = jsonDecode(rawBody) as Map<String, dynamic>;
  final elements = data['elements'] as List<dynamic>;

  final holeElements = elements.where((e) {
    final tags = (e['tags'] as Map<String, dynamic>?) ?? {};
    return tags['golf'] == 'hole' && tags['ref'] == '$holeRef';
  }).toList();

  if (holeElements.isEmpty) {
    print('No hole ref=$holeRef found in cached data for "$courseName".');
    return;
  }

  for (final el in holeElements) {
    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    final geom = (el['geometry'] as List<dynamic>?) ?? [];
    print('type    : ${el['type']}');
    print('id      : ${el['id']}');
    print('tags    : $tags');
    print('geometry: ${geom.length} points');
    if (geom.isNotEmpty) {
      print('  first : ${geom.first}');
      print('  last  : ${geom.last}');
    }
    print('');
  }
}

typedef IngestAllResult = ({int total, int succeeded, int failed});

/// Shared ingest logic: runs list+detail Overpass queries, upserts course_list,
/// parses and upserts each course. [cacheKey] is the name used in the raw JSON
/// cache. Returns summary counts.
Future<IngestAllResult> _ingestFromQueries({
  required String listQuery,
  required String detailQuery,
  required String cacheKey,
  int? limit,
}) async {
  final supabase = SupabaseRestClient();

  final listResponse = await http
      .post(Uri.parse(overpassUrl), body: listQuery)
      .timeout(const Duration(seconds: 150));

  if (listResponse.statusCode != 200) {
    throw Exception('Overpass list query failed: ${listResponse.statusCode}');
  }

  final data = jsonDecode(listResponse.body) as Map<String, dynamic>;
  final elements = data['elements'] as List<dynamic>;

  const typePriority = {'relation': 0, 'way': 1, 'node': 2};

  // OSM golf subtypes that are not real courses.
  const nonCourseGolfTags = {
    'driving_range', 'miniature', 'pitch_and_putt', 'practice', 'academy',
  };

  // Name keywords that indicate non-playable venues.
  const junkNameKeywords = [
    'driving range', 'mini golf', 'mini-golf', 'miniature golf',
    'pitch & putt', 'pitch and putt', 'putting course', 'putting green',
    'golf academy', 'practice center', 'practice centre',
  ];

  bool _isJunkElement(Map<String, dynamic> tags, String name) {
    final golfTag = tags['golf'] as String?;
    if (golfTag != null && nonCourseGolfTags.contains(golfTag)) return true;
    final lower = name.toLowerCase();
    return junkNameKeywords.any((k) => lower.contains(k));
  }

  final Map<String, Map<String, dynamic>> byName = {};
  for (final el in elements) {
    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    final name = (tags['name'] as String?)?.trim();
    if (name == null || name.isEmpty) continue;
    if (_isJunkElement(tags, name)) {
      print('  Skipping non-course: "$name"');
      continue;
    }

    final type = el['type'] as String;
    final center = el['center'] as Map<String, dynamic>?;
    final lat = type == 'node'
        ? (el['lat'] as num).toDouble()
        : (center?['lat'] as num?)?.toDouble();
    final lon = type == 'node'
        ? (el['lon'] as num).toDouble()
        : (center?['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) continue;

    final existing = byName[name];
    final existingPri =
        existing != null ? (typePriority[existing['type']] ?? 9) : 9;
    if (existing == null || (typePriority[type] ?? 9) < existingPri) {
      byName[name] = {
        'id': el['id'] as int,
        'type': type,
        'name': name,
        'lat': lat,
        'lon': lon,
      };
    }
  }

  final now = DateTime.now().toUtc().toIso8601String();
  final courseListRows =
      byName.values.map((c) => {...c, 'updated_at': now}).toList();
  await supabase.upsert('course_list', courseListRows);
  print('Upserted ${courseListRows.length} courses to course_list');

  print('Fetching all course details (single query) ...');
  final store = RawJsonStore();
  String rawBody;

  final cached = await store.loadIfFresh(cacheKey);
  if (cached != null) {
    print('Using cached Overpass JSON (< 23h old)');
    rawBody = cached;
  } else {
    final fetchStart = DateTime.now();
    final detailResponse = await http
        .post(Uri.parse(overpassUrl), body: detailQuery)
        .timeout(const Duration(seconds: 330));
    final fetchMs = DateTime.now().difference(fetchStart).inMilliseconds;

    if (detailResponse.statusCode != 200) {
      throw Exception(
          'Overpass detail query failed: ${detailResponse.statusCode}');
    }

    rawBody = detailResponse.body;
    final detailData = jsonDecode(rawBody) as Map<String, dynamic>;
    final elementCount =
        (detailData['elements'] as List<dynamic>? ?? []).length;
    print('Overpass: 200 OK, $elementCount elements (${fetchMs}ms)');

    await store.save(cacheKey, rawBody, elementCount);
    print('Cached raw JSON to ${store.dbPath}');
  }

  print('\nParsing all courses ...');
  final allParsed = parseAllCourses(rawBody);
  print('Found ${allParsed.length} parseable courses (way/relation geometry)\n');

  final total =
      limit != null && limit < allParsed.length ? limit : allParsed.length;
  if (limit != null) {
    print('(limiting to $total of ${allParsed.length} parsed courses)');
  }

  int succeeded = 0;
  int failed = 0;

  // Load existing hashes for change detection.
  final existingHashes = <String, String>{}; // courseId → hash
  try {
    final hashRows = await supabase.select('courses', columns: 'id,overpass_hash');
    for (final r in hashRows) {
      final id = r['id'] as String?;
      final hash = r['overpass_hash'] as String?;
      if (id != null && hash != null) existingHashes[id] = hash;
    }
  } catch (_) {} // Non-fatal: proceed without change detection

  // Per-course hash derived from the bulk raw body + courseId (stable proxy).
  final bulkHash = _md5(rawBody);

  for (int i = 0; i < total; i++) {
    final parsed = allParsed[i];
    final name = parsed.courseDoc['name'] as String;
    print(
        '[${i + 1}/$total] ${parsed.courseId}  "$name"  ${parsed.holeDocs.length} holes');
    try {
      // Use per-course hash: MD5(bulkHash + courseId) — stable if the bulk
      // Overpass response is the same, changes when OSM data changes.
      final courseHash = _md5('$bulkHash:${parsed.courseId}');
      if (existingHashes[parsed.courseId] == courseHash) {
        print('  → Unchanged (hash match) — skipping');
        succeeded++;
        continue;
      }
      await supabase.upsert('courses', [
        {
          'id': parsed.courseId,
          'name': name,
          'course_doc': parsed.courseDoc,
          'holes_doc': parsed.holeDocs,
          'overpass_hash': courseHash,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }
      ]);
      print('  → Upserted to Supabase ✓');
      await _persistIntegrityIssues(supabase, parsed);
      await _enqueueEnrichmentIfNeeded(supabase, parsed);
      succeeded++;
    } catch (e) {
      print('  → Supabase upsert FAILED: $e');
      failed++;
    }
  }

  await store.close();
  print('\nDone. parsed=$total  succeeded=$succeeded  failed=$failed');
  return (total: total, succeeded: succeeded, failed: failed);
}

/// Fetch all NZ courses from Overpass, upsert course_list, then parse and
/// upsert each course. Returns summary counts.
Future<IngestAllResult> ingestAllNzCourses({int? limit}) {
  final listQuery = '''
[out:json][timeout:120];
(
  node["leisure"="golf_course"]($nzBbox);
  way["leisure"="golf_course"]($nzBbox);
  relation["leisure"="golf_course"]($nzBbox);
);
out center tags;
''';

  final detailQuery = '''
[out:json][timeout:300];
(
  way["leisure"="golf_course"]($nzBbox);
  relation["leisure"="golf_course"]($nzBbox);
)->.courses;
.courses out geom;
(
  node(area.courses)["golf"];
  way(area.courses)["golf"];
  relation(area.courses)["golf"];
);
out geom;
''';

  return _ingestFromQueries(
    listQuery: listQuery,
    detailQuery: detailQuery,
    cacheKey: '__all_nz__',
    limit: limit,
  );
}

/// Fetch all courses in a named region (country, state, or county) from
/// Overpass, upsert course_list, parse and upsert each course.
Future<IngestAllResult> ingestRegion(String regionName, {int? limit}) {
  final escaped = regionName.replaceAll('"', '\\"');

  final listQuery = '''
[out:json][timeout:120];
area["name"="$escaped"]->.searchArea;
(
  node["leisure"="golf_course"](area.searchArea);
  way["leisure"="golf_course"](area.searchArea);
  relation["leisure"="golf_course"](area.searchArea);
);
out center tags;
''';

  final detailQuery = '''
[out:json][timeout:300];
area["name"="$escaped"]->.searchArea;
(
  way["leisure"="golf_course"](area.searchArea);
  relation["leisure"="golf_course"](area.searchArea);
)->.courses;
.courses out geom;
(
  node(area.courses)["golf"];
  way(area.courses)["golf"];
  relation(area.courses)["golf"];
);
out geom;
''';

  final cacheKey =
      '__region_${regionName.replaceAll(' ', '_').toLowerCase()}__';
  print('Ingesting region: $regionName');
  return _ingestFromQueries(
    listQuery: listQuery,
    detailQuery: detailQuery,
    cacheKey: cacheKey,
    limit: limit,
  );
}

/// Query Supabase for a stored course and print its details.
Future<void> queryCourse(String courseName) async {
  final supabase = SupabaseRestClient();
  print('Querying Supabase for: $courseName ...\n');

  final rows = await supabase.select(
    'courses',
    filters: 'name=eq.$courseName',
    columns: 'id,name,course_doc,holes_doc,updated_at',
  );

  if (rows.isEmpty) {
    print('Not found in Supabase.');
    return;
  }

  final row = rows.first;
  final courseDoc = row['course_doc'] is String
      ? jsonDecode(row['course_doc'] as String) as Map<String, dynamic>
      : row['course_doc'] as Map<String, dynamic>;
  final holeDocs = row['holes_doc'] is String
      ? (jsonDecode(row['holes_doc'] as String) as List<dynamic>)
          .cast<Map<String, dynamic>>()
      : (row['holes_doc'] as List<dynamic>).cast<Map<String, dynamic>>();

  print('=== ${row['name']} ===');
  print('ID         : ${row['id']}');
  print('Updated at : ${row['updated_at']}');
  print('Holes      : ${holeDocs.length}');
  print('Boundary pts: ${(courseDoc['boundaryPoints'] as List?)?.length ?? 0}');
  print('');

  for (final h in holeDocs) {
    final num = (h['holeNumber'] as int).toString().padLeft(2);
    final par = h['par'];
    final hcp = h['handicapIndex'];
    final fairways = (h['fairways'] as List).length;
    final greens = (h['greens'] as List).length;
    final tees = (h['teePlatforms'] as List).length;
    final routingPts = (h['routingLine'] as List).length;
    print('  Hole $num  par $par  hcp ${hcp.toString().padLeft(2)}'
        '  fairways=$fairways  greens=$greens'
        '  tee_platforms=$tees  routing_pts=$routingPts');
  }
}

/// Query Supabase for a stored course and run integrity checks on it.
Future<void> checkCourseIntegrity(String courseName) async {
  final supabase = SupabaseRestClient();
  print('Querying Supabase for: $courseName ...\n');

  final rows = await supabase.select(
    'courses',
    filters: 'name=eq.$courseName',
    columns: 'id,name,course_doc,holes_doc',
  );

  if (rows.isEmpty) {
    print('Not found in Supabase. Run ingest-course or ingest-region first.');
    return;
  }

  final row = rows.first;
  final courseDoc = row['course_doc'] is String
      ? jsonDecode(row['course_doc'] as String) as Map<String, dynamic>
      : row['course_doc'] as Map<String, dynamic>;
  final holeDocs = row['holes_doc'] is String
      ? (jsonDecode(row['holes_doc'] as String) as List<dynamic>)
          .cast<Map<String, dynamic>>()
      : (row['holes_doc'] as List<dynamic>).cast<Map<String, dynamic>>();

  final parsed = ParsedCourse(
    courseId: row['id'] as String,
    courseDoc: courseDoc,
    holeDocs: holeDocs,
  );

  print('=== ${row['name']}  (${holeDocs.length} holes) ===\n');

  final issues = checkIntegrity(parsed);
  if (issues.isEmpty) {
    print('No issues found — looks good!');
    return;
  }

  final errors = issues.where((i) => i.severity == IssueSeverity.error).length;
  final warnings =
      issues.where((i) => i.severity == IssueSeverity.warning).length;

  for (final issue in issues) {
    print(issue);
  }
  print('\n$errors error(s)  $warnings warning(s)');
}

/// Fetch and parse a course, print detailed breakdown. No Supabase upsert.
Future<void> checkCourse(String courseName, {String? bbox}) async {
  final effectiveBbox = bbox ?? nzBbox;

  print('Fetching: $courseName ...');

  final query = buildDetailQuery(courseName, effectiveBbox);
  final fetchStart = DateTime.now();
  final overpassResponse =
      await http.post(Uri.parse(overpassUrl), body: query);
  final fetchMs = DateTime.now().difference(fetchStart).inMilliseconds;

  if (overpassResponse.statusCode != 200) {
    print('Overpass error: ${overpassResponse.statusCode}');
    return;
  }

  final rawBody = overpassResponse.body;
  final overpassData = jsonDecode(rawBody) as Map<String, dynamic>;
  final elementCount =
      (overpassData['elements'] as List<dynamic>? ?? []).length;
  print('Overpass: 200 OK, $elementCount elements (${fetchMs}ms)\n');

  final ParsedCourse parsed;
  try {
    parsed = parseCourse(rawBody);
  } catch (e) {
    print('Parse FAILED: $e');
    return;
  }

  print('=== ${parsed.courseDoc['name']} ===');
  print('ID    : ${parsed.courseId}');
  print('Holes : ${parsed.holeDocs.length}');
  print('');

  for (final h in parsed.holeDocs) {
    final num = (h['holeNumber'] as int).toString().padLeft(2);
    final par = h['par'];
    final fairways = (h['fairways'] as List).length;
    final greens = (h['greens'] as List).length;
    final tees = (h['teePlatforms'] as List).length;
    final routingPts = (h['routingLine'] as List).length;
    print('  Hole $num  par $par'
        '  fairways=$fairways  greens=$greens'
        '  tee_platforms=$tees  routing_pts=$routingPts');
  }
}

/// Print cached courses whose names contain any word from [query].
Future<void> _suggestFromCache(String query) async {
  final store = RawJsonStore();
  // Try full query first, then each word individually.
  var matches = await store.search(query);
  if (matches.isEmpty) {
    final words = query.split(RegExp(r'\s+')).where((w) => w.length > 2);
    for (final word in words) {
      final m = await store.search(word);
      for (final name in m) {
        if (!matches.contains(name)) matches.add(name);
      }
    }
  }
  await store.close();

  if (matches.isEmpty) {
    print('No cached courses match "$query". Run ingest-course or ingest-all first.');
  } else {
    print('No exact match for "$query". Did you mean:');
    for (final name in matches) {
      print('  $name');
    }
  }
}

/// Search the local cache for course names matching [query] and print them.
Future<void> searchCachedCourses(String query) async {
  final store = RawJsonStore();
  final matches = await store.search(query);
  await store.close();

  if (matches.isEmpty) {
    print('No cached courses match "$query".');
    return;
  }
  print('${matches.length} match(es) for "$query":');
  for (final name in matches) {
    print('  $name');
  }
}

/// Print all distinct course names in the local cache.
Future<void> listCachedCourses() async {
  final store = RawJsonStore();
  final names = await store.listNames();
  await store.close();

  if (names.isEmpty) {
    print('Cache is empty. Run ingest-course or ingest-all first.');
    return;
  }
  print('${names.length} course(s) in cache:');
  for (final name in names) {
    print('  $name');
  }
}

/// Parse a course from the local SQLite cache and print hole details.
/// No Overpass or Supabase required — useful for verifying parser output.
Future<void> checkCourseFromCache(String courseName) async {
  final store = RawJsonStore();
  final rawBody = await store.load(courseName);
  await store.close();

  if (rawBody == null) {
    await _suggestFromCache(courseName);
    return;
  }

  print('Parsing from cache ...\n');
  final ParsedCourse parsed;
  try {
    parsed = parseCourse(rawBody);
  } catch (e) {
    print('Parse FAILED: $e');
    return;
  }

  print('=== ${parsed.courseDoc['name']} ===');
  print('ID    : ${parsed.courseId}');
  print('Holes : ${parsed.holeDocs.length}');
  print('');

  for (final h in parsed.holeDocs) {
    final num = (h['holeNumber'] as int).toString().padLeft(2);
    final par = h['par'];
    final fairways = (h['fairways'] as List).length;
    final greens = (h['greens'] as List).length;
    final tees = (h['teePlatforms'] as List).length;
    final routingPts = (h['routingLine'] as List).length;
    print('  Hole $num  par $par'
        '  fairways=$fairways  greens=$greens'
        '  tee_platforms=$tees  routing_pts=$routingPts');
  }
}

// ---------------------------------------------------------------------------
// Integrity + enrichment helpers
// ---------------------------------------------------------------------------

/// Write integrity issues for [parsed] to the `course_issues` table.
/// Clears existing open issues first so stale issues are removed on re-ingest.
Future<void> _persistIntegrityIssues(
    SupabaseRestClient supabase, ParsedCourse parsed) async {
  try {
    // Clear existing open issues for this course.
    await supabase.delete(
        'course_issues',
        'course_id=eq.${parsed.courseId}&resolved_at=is.null');

    final issues = checkIntegrity(parsed);
    if (issues.isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    await supabase.insert('course_issues', issues.map((issue) {
      return {
        'course_id': parsed.courseId,
        'severity': issue.severity.name,
        'message': issue.message,
        'hole_number': issue.holeNumber,
        'detected_at': now,
      };
    }).toList());

    final errors = issues.where((i) => i.severity == IssueSeverity.error).length;
    final warnings = issues.where((i) => i.severity == IssueSeverity.warning).length;
    print('  → Integrity: $errors error(s)  $warnings warning(s) written to course_issues');
  } catch (e) {
    print('  → Integrity persist FAILED: $e');
  }
}

/// Add this course to `enrich_queue` if it is missing ratings or handicaps.
Future<void> _enqueueEnrichmentIfNeeded(
    SupabaseRestClient supabase, ParsedCourse parsed) async {
  try {
    final fields = <String>[];

    // Check for missing hole handicaps (all zero = likely not set).
    final handicaps = parsed.holeDocs
        .map((h) => (h['handicapIndex'] as int?) ?? 0)
        .toList();
    if (handicaps.every((h) => h == 0)) fields.add('hole_handicaps');

    // Check for missing par (all zero = not set).
    final pars = parsed.holeDocs.map((h) => (h['par'] as int?) ?? 0).toList();
    if (pars.every((p) => p == 0)) fields.add('hole_pars');

    // Check for missing tee ratings.
    final teeInfos =
        (parsed.courseDoc['teeInfos'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    final hasRatings = teeInfos.any(
        (t) => ((t['courseRating'] as num?)?.toDouble() ?? 0.0) > 0);
    if (teeInfos.isNotEmpty && !hasRatings) fields.add('tee_ratings');

    if (fields.isEmpty) return;

    final name = parsed.courseDoc['name'] as String? ?? parsed.courseId;
    // Skip if already pending or in_progress for this course.
    final existing = await supabase.select('enrich_queue',
        filters:
            'course_id=eq.${parsed.courseId}&status=in.(pending,in_progress)',
        columns: 'id');
    if (existing.isNotEmpty) {
      print('  → Enrich queue: already queued, skipping');
      return;
    }
    await supabase.insert('enrich_queue', [
      {
        'course_id': parsed.courseId,
        'course_name': name,
        'fields': fields,
        'status': 'pending',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }
    ]);
    print('  → Enrich queue: added fields=$fields');
  } catch (e) {
    print('  → Enrich queue FAILED: $e');
  }
}

/// Query all courses from Supabase, run integrity checks, and persist issues.
/// Useful for a standalone audit pass without re-ingesting from Overpass.
Future<void> auditAllCourses({bool dryRun = false}) async {
  final supabase = SupabaseRestClient();
  print('Auditing all courses in Supabase ...');

  final rows = await supabase.select(
    'courses',
    columns: 'id,name,course_doc,holes_doc',
  );

  print('Found ${rows.length} courses\n');

  int totalErrors = 0;
  int totalWarnings = 0;
  int cleanCount = 0;

  for (final row in rows) {
    final courseDoc = row['course_doc'] is String
        ? jsonDecode(row['course_doc'] as String) as Map<String, dynamic>
        : row['course_doc'] as Map<String, dynamic>;
    final holeDocs = row['holes_doc'] is String
        ? (jsonDecode(row['holes_doc'] as String) as List<dynamic>)
            .cast<Map<String, dynamic>>()
        : (row['holes_doc'] as List<dynamic>).cast<Map<String, dynamic>>();

    final parsed = ParsedCourse(
      courseId: row['id'] as String,
      courseDoc: courseDoc,
      holeDocs: holeDocs,
    );

    final issues = checkIntegrity(parsed);
    if (issues.isEmpty) {
      cleanCount++;
      continue;
    }

    final errors = issues.where((i) => i.severity == IssueSeverity.error).length;
    final warnings = issues.where((i) => i.severity == IssueSeverity.warning).length;
    totalErrors += errors;
    totalWarnings += warnings;

    print('${row['name']}  ($errors err  $warnings warn)');
    for (final issue in issues) {
      print('  $issue');
    }

    if (!dryRun) {
      await _persistIntegrityIssues(supabase, parsed);
      await _enqueueEnrichmentIfNeeded(supabase, parsed);
    }
  }

  print('\nAudit complete: ${rows.length} courses  '
      'clean=$cleanCount  errors=$totalErrors  warnings=$totalWarnings');
  if (dryRun) print('(dry run — no writes)');
}

String buildDetailQuery(String courseName, String bbox) => '''
[out:json][timeout:25];
(
  node["leisure"="golf_course"]["name"="$courseName"]($bbox);
  way["leisure"="golf_course"]["name"="$courseName"]($bbox);
  relation["leisure"="golf_course"]["name"="$courseName"]($bbox);
)->.course;
.course out geom;
(
  node(area.course)["golf"];
  way(area.course)["golf"];
  relation(area.course)["golf"];
);
out geom;
''';
