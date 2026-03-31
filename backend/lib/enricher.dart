import 'dart:convert';
import 'claude_client.dart';
import 'gemini_client.dart';
import 'supabase_client.dart';
import 'web_search.dart';

/// Processes the `enrich_queue` table: for each pending course, searches the
/// web for scorecard data, extracts it with Claude, validates it, and patches
/// the course in Supabase.
class Enricher {
  final WebSearch _search;
  final ClaudeClient _claude;
  final GeminiClient? _gemini;
  final SupabaseRestClient _supabase;

  Enricher({
    WebSearch? search,
    ClaudeClient? claude,
    GeminiClient? gemini,
    SupabaseRestClient? supabase,
  })  : _search = search ?? WebSearch(),
        _claude = claude ?? ClaudeClient(),
        _gemini = gemini,
        _supabase = supabase ?? SupabaseRestClient();

  /// Enrich a single course directly by courseId + name, bypassing the queue.
  Future<void> enrichOne(String courseId, String courseName) async {
    print('Enriching: $courseName ($courseId)');
    await _enrichCourse(courseId, courseName, []);
    print('  → Done ✓');
  }

  /// Run the Gemini hole-estimate pass on a single course, bypassing the queue.
  /// Only writes to Supabase if the course currently has no holes.
  Future<void> geminiEstimateOne(String courseId, String courseName,
      {bool dryRun = false}) async {
    print('Gemini estimate: $courseName ($courseId)');
    final gemini = _gemini ?? GeminiClient();

    final courseRows = await _supabase.select(
      'courses',
      filters: 'id=eq.$courseId',
      columns: 'course_doc,holes_doc',
    );
    if (courseRows.isEmpty) throw Exception('Course not found in Supabase');

    final courseDoc = courseRows.first['course_doc'] is String
        ? jsonDecode(courseRows.first['course_doc'] as String)
            as Map<String, dynamic>
        : courseRows.first['course_doc'] as Map<String, dynamic>;
    final holeDocs = courseRows.first['holes_doc'] is String
        ? (jsonDecode(courseRows.first['holes_doc'] as String) as List<dynamic>)
            .cast<Map<String, dynamic>>()
        : (courseRows.first['holes_doc'] as List<dynamic>)
            .cast<Map<String, dynamic>>();

    if (holeDocs.isNotEmpty) {
      print('  → Already has ${holeDocs.length} holes — skipping');
      return;
    }

    final estimated =
        await _geminiHoleEstimatePass(courseName, courseDoc, gemini: gemini);
    if (estimated == null) throw Exception('Gemini returned no valid estimate');

    print('  → Estimated ${estimated.length} holes');
    if (dryRun) {
      print('  → dry run — not writing to Supabase');
      return;
    }
    await _supabase.patch('courses', 'id=eq.$courseId', {
      'holes_doc': estimated,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    print('  → Done ✓');
  }

  /// Run Gemini hole estimates for all courses with no holes in Supabase.
  Future<void> geminiEstimateAll({bool dryRun = false}) async {
    final rows = await _supabase.select(
      'courses',
      filters: 'holes_doc=eq.[]',
      columns: 'id,course_doc',
    );
    if (rows.isEmpty) {
      print('Gemini pass: no courses with empty holes_doc');
      return;
    }
    print('Gemini pass: ${rows.length} course(s) with no holes');
    for (final row in rows) {
      final courseId = row['id'] as String;
      final courseDoc = row['course_doc'] is String
          ? jsonDecode(row['course_doc'] as String) as Map<String, dynamic>
          : row['course_doc'] as Map<String, dynamic>;
      final courseName = courseDoc['name'] as String? ?? courseId;
      try {
        await geminiEstimateOne(courseId, courseName, dryRun: dryRun);
      } catch (e) {
        print('  → $courseName FAILED: $e');
      }
    }
  }

  /// Process up to [batchSize] pending items from `enrich_queue`.
  Future<void> processQueue({int batchSize = 10, bool dryRun = false}) async {
    final rows = await _supabase.select(
      'enrich_queue',
      filters: 'status=eq.pending&order=id.asc',
      columns: 'id,course_id,course_name,fields',
    );

    final toProcess = rows.take(batchSize).toList();
    if (toProcess.isEmpty) {
      print('Enrich queue: nothing to do');
      return;
    }
    print('Enrich queue: processing ${toProcess.length} course(s)');

    for (final row in toProcess) {
      final queueId = row['id'] as int;
      final courseId = row['course_id'] as String;
      final courseName = row['course_name'] as String;
      final fields = (row['fields'] as List<dynamic>).cast<String>();

      print('\n  [$queueId] $courseName');

      if (dryRun) {
        print('  → dry run — skipping');
        continue;
      }

      // Mark in_progress
      await _supabase.patch(
        'enrich_queue',
        'id=eq.$queueId',
        {
          'status': 'in_progress',
          'attempts': 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      try {
        await _enrichCourse(courseId, courseName, fields);
        await _supabase.patch(
          'enrich_queue',
          'id=eq.$queueId',
          {
            'status': 'done',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
        print('  → Done ✓');
      } catch (e) {
        print('  → Failed: $e');
        await _supabase.patch(
          'enrich_queue',
          'id=eq.$queueId',
          {
            'status': 'failed',
            'last_error': e.toString(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
        );
      }
    }
  }

  Future<void> _enrichCourse(
      String courseId, String courseName, List<String> fields) async {
    // 1. Load current course data from Supabase (needed to know holeCount).
    final courseRows = await _supabase.select(
      'courses',
      filters: 'id=eq.$courseId',
      columns: 'course_doc,holes_doc',
    );
    if (courseRows.isEmpty) throw Exception('Course not found in Supabase');

    final courseDoc = courseRows.first['course_doc'] is String
        ? jsonDecode(courseRows.first['course_doc'] as String)
            as Map<String, dynamic>
        : courseRows.first['course_doc'] as Map<String, dynamic>;
    var holeDocs = courseRows.first['holes_doc'] is String
        ? (jsonDecode(courseRows.first['holes_doc'] as String) as List<dynamic>)
            .cast<Map<String, dynamic>>()
        : (courseRows.first['holes_doc'] as List<dynamic>)
            .cast<Map<String, dynamic>>();

    // 1b. Gemini hole-skeleton pass — only when OSM produced no holes at all
    //     and a GeminiClient was provided.
    if (holeDocs.isEmpty && _gemini != null) {
      print('  → No holes in OSM data — running Gemini hole-estimate pass');
      final estimated = await _geminiHoleEstimatePass(courseName, courseDoc);
      if (estimated != null) {
        holeDocs = estimated;
        final now = DateTime.now().toUtc().toIso8601String();
        await _supabase.patch(
          'courses',
          'id=eq.$courseId',
          {'holes_doc': holeDocs, 'updated_at': now},
        );
        print('  → Gemini estimated ${holeDocs.length} holes (marked estimated)');
      } else {
        print('  → Gemini hole estimate failed — skipping enrichment');
        return;
      }
    }

    final holeCount = holeDocs.length;

    // 2. Web search — primary query + fallback query if needed.
    final queries = [
      '$courseName golf course scorecard ratings handicaps par yardage',
      '"$courseName" scorecard hole par handicap',
    ];

    // Aggregator domains deprioritised — we prefer official club sites.
    const aggregators = {
      'bluegolf.com', 'golfshake.com', '18birdies.com',
      'golfify.io', 'offcourse.co', 'mscorecard.com',
    };

    Map? extracted;

    for (final query in queries) {
      if (extracted != null) break;

      print('  → Searching: $query');
      final results = await _search.search(query, count: 10);
      if (results.isEmpty) continue;

      // Sort: official club sites first, aggregators last.
      final sorted = [...results]..sort((a, b) {
          final aAgg = aggregators.any((d) => a.url.contains(d)) ? 1 : 0;
          final bAgg = aggregators.any((d) => b.url.contains(d)) ? 1 : 0;
          return aAgg.compareTo(bAgg);
        });

      // Fetch up to 5 pages in parallel.
      final candidates = sorted.take(5).toList();
      print('  → Fetching ${candidates.length} page(s) in parallel ...');
      final texts = await Future.wait(
        candidates.map((r) async {
          print('     ${r.url}');
          return _search.fetchText(r.url, maxChars: 6000);
        }),
      );

      final pageParts = texts
          .where((t) => t != null && t.length > 200)
          .cast<String>()
          .toList();
      if (pageParts.isEmpty) continue;

      // Ask Claude once with all pages combined.
      final combined = pageParts.join('\n\n---\n\n');
      final prompt = _buildPrompt(courseName, combined, holeCount);
      print('  → Asking Claude (${pageParts.length} page(s)) ...');
      final result = await _claude.completeJson(prompt);
      if (result is! Map) continue;

      extracted = result;
      if (_isComplete(extracted, holeCount)) {
        print('  → Complete data found');
      }
    }

    if (extracted == null) throw Exception('No valid data extracted');

    // 5. Validate and apply all extracted fields.
    final holesPatch = List<Map<String, dynamic>>.from(holeDocs);
    final coursePatch = Map<String, dynamic>.from(courseDoc);
    bool holesChanged = false;
    bool courseChanged = false;

    // --- hole_handicaps ---
    final handicaps = extracted['hole_handicaps'];
    if (handicaps is List && handicaps.length == holeCount) {
      final values = handicaps.map((h) => (h as num).toInt()).toList();
      if (_validHandicaps(values, holeCount)) {
        for (int i = 0; i < holesPatch.length; i++) {
          holesPatch[i]['handicapIndex'] = values[i];
        }
        holesChanged = true;
        print('  → Applied hole handicaps: $values');
      } else {
        print('  → Handicap validation failed — skipping');
      }
    }

    // --- hole_pars ---
    final pars = extracted['hole_pars'];
    if (pars is List && pars.length == holeCount) {
      final values = pars.map((p) => (p as num).toInt()).toList();
      if (values.every((p) => p >= 3 && p <= 6)) {
        for (int i = 0; i < holesPatch.length; i++) {
          holesPatch[i]['par'] = values[i];
        }
        holesChanged = true;
        print('  → Applied hole pars: $values');
      }
    }

    // --- hole_yardages (store per-hole yardage for primary/longest tee) ---
    final yardages = extracted['hole_yardages'];
    if (yardages is List && yardages.length == holeCount) {
      final values = yardages.map((y) => (y as num).toInt()).toList();
      if (values.every((y) => y >= 50 && y <= 700)) {
        for (int i = 0; i < holesPatch.length; i++) {
          holesPatch[i]['yardage'] = values[i];
        }
        holesChanged = true;
        print('  → Applied hole yardages: $values');
      }
    }

    // --- tee_ratings ---
    final teeRatings = extracted['tee_ratings'];
    if (teeRatings is List && teeRatings.isNotEmpty) {
      final teeInfos = (coursePatch['teeInfos'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final updated = _applyTeeRatings(teeInfos, teeRatings);
      if (updated != null) {
        coursePatch['teeInfos'] = updated;
        courseChanged = true;
        print('  → Applied tee ratings for ${updated.length} tee(s)');
      }
    }

    // --- course_par (total) ---
    final totalPar = extracted['course_par'];
    if (totalPar is num && totalPar >= 54 && totalPar <= 78) {
      coursePatch['par'] = totalPar.toInt();
      courseChanged = true;
      print('  → Applied course par: $totalPar');
    }

    // --- total_holes + course_layouts ---
    final totalHoles = extracted['total_holes'];
    if (totalHoles is num && totalHoles >= 9) {
      coursePatch['totalHoles'] = totalHoles.toInt();
      courseChanged = true;
      print('  → Applied total holes: $totalHoles');
    }
    final layouts = extracted['course_layouts'];
    if (layouts is List && layouts.isNotEmpty) {
      coursePatch['courseLayouts'] = layouts;
      courseChanged = true;
      final names = (layouts).map((l) => '${l['name']} (${l['holes']}h)').join(', ');
      print('  → Applied course layouts: $names');
    }

    if (!holesChanged && !courseChanged) {
      throw Exception('No valid data extracted');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    if (holesChanged) {
      await _supabase.patch(
          'courses', 'id=eq.$courseId', {'holes_doc': holesPatch, 'updated_at': now});
    }
    if (courseChanged) {
      await _supabase.patch(
          'courses', 'id=eq.$courseId', {'course_doc': coursePatch, 'updated_at': now});
    }
  }

  String _buildPrompt(String courseName, String pageText, int holeCount) {
    return '''
You are extracting golf course data from a club website for "$courseName" ($holeCount holes).

From the text below, extract as much as you can find and return a JSON object with these fields (omit any you cannot find — do NOT guess):

- "total_holes": integer — total number of holes across all courses/loops at this venue (e.g. 18, 27, 36)
- "course_layouts": array of objects, one per distinct course/loop, each with:
    "name" (string e.g. "Championship", "President's Course", "East", "West"),
    "holes" (integer — number of holes in this layout)
- "hole_handicaps": array of $holeCount integers — stroke index / handicap index per hole (1 = hardest)
- "hole_pars": array of $holeCount integers — par value per hole (3, 4, or 5)
- "hole_yardages": array of $holeCount integers — yardage per hole from the longest/championship tee
- "course_par": integer — total par for the main/championship course (e.g. 70, 71, 72)
- "tee_ratings": array of objects, one per tee, each with:
    "name" (string e.g. "White", "Yellow", "Red"),
    "yardage" (total yards, integer),
    "course_rating" (decimal e.g. 71.4),
    "slope_rating" (integer e.g. 128)

Return ONLY a valid JSON object. Do not guess any values.

--- PAGE TEXT ---
$pageText''';
  }

  /// Returns true if extracted data has handicaps, pars, yardages and tee ratings.
  bool _isComplete(Map extracted, int holeCount) {
    bool hasHandicaps = extracted['hole_handicaps'] is List &&
        (extracted['hole_handicaps'] as List).length == holeCount;
    bool hasPars = extracted['hole_pars'] is List &&
        (extracted['hole_pars'] as List).length == holeCount;
    bool hasYardages = extracted['hole_yardages'] is List &&
        (extracted['hole_yardages'] as List).length == holeCount &&
        (extracted['hole_yardages'] as List).any((y) => (y as num) > 100);
    bool hasTeeRatings = extracted['tee_ratings'] is List &&
        (extracted['tee_ratings'] as List).isNotEmpty;
    return hasHandicaps && hasPars && hasYardages && hasTeeRatings;
  }

  /// Validate hole handicap list: right length, values 1–holeCount unique.
  bool _validHandicaps(List<int> values, int holeCount) {
    if (values.length != holeCount) return false;
    final sorted = [...values]..sort();
    for (int i = 0; i < sorted.length; i++) {
      if (sorted[i] != i + 1) return false;
    }
    return true;
  }

  /// Merge extracted tee ratings into existing teeInfos by name match.
  /// If OSM had no named tees (all "unknown"), replace with extracted tees.
  /// Returns updated list or null if nothing applied.
  List<Map<String, dynamic>>? _applyTeeRatings(
      List<Map<String, dynamic>> teeInfos, List teeRatings) {
    final allUnknown = teeInfos.every(
        (t) => (t['name'] as String?)?.toLowerCase() == 'unknown');

    // If all tees are "unknown", replace the list entirely with extracted data.
    if (allUnknown) {
      final built = <Map<String, dynamic>>[];
      for (final extracted in teeRatings) {
        if (extracted is! Map) continue;
        final name = extracted['name'] as String?;
        if (name == null) continue;
        final yardage = (extracted['yardage'] as num?)?.toDouble() ?? 0.0;
        final rating = (extracted['course_rating'] as num?)?.toDouble() ?? 0.0;
        final slope = (extracted['slope_rating'] as num?)?.toDouble() ?? 0.0;
        if (yardage < 1000 || yardage > 8000) continue;
        built.add({
          'name': name,
          'color': _guessColor(name),
          'yardage': yardage,
          'courseRating': rating >= 55 && rating <= 85 ? rating : 0.0,
          'slopeRating': slope >= 55 && slope <= 155 ? slope : 0.0,
        });
      }
      return built.isNotEmpty ? built : null;
    }

    // Otherwise merge by name.
    int applied = 0;
    for (final extracted in teeRatings) {
      if (extracted is! Map) continue;
      final name = (extracted['name'] as String?)?.toLowerCase();
      if (name == null) continue;

      final idx = teeInfos
          .indexWhere((t) => (t['name'] as String?)?.toLowerCase() == name);
      if (idx == -1) continue;

      final yardage = (extracted['yardage'] as num?)?.toDouble();
      final rating = (extracted['course_rating'] as num?)?.toDouble();
      final slope = (extracted['slope_rating'] as num?)?.toInt();

      if (yardage != null && yardage >= 1000 && yardage <= 8000) {
        teeInfos[idx]['yardage'] = yardage;
        applied++;
      }
      if (rating != null && rating >= 55 && rating <= 85) {
        teeInfos[idx]['courseRating'] = rating;
        applied++;
      }
      if (slope != null && slope >= 55 && slope <= 155) {
        teeInfos[idx]['slopeRating'] = slope.toDouble();
        applied++;
      }
    }
    return applied > 0 ? teeInfos : null;
  }

  /// Best-effort color guess from tee name.
  String _guessColor(String name) {
    final n = name.toLowerCase();
    for (final color in ['white', 'yellow', 'red', 'blue', 'black', 'gold', 'green', 'silver']) {
      if (n.contains(color)) return color;
    }
    return n; // fallback: use name as color
  }

  /// Ask Gemini to estimate a hole skeleton for a course with no OSM hole data.
  /// Returns a list of holeDocs (each marked `estimated: true`) or null on failure.
  Future<List<Map<String, dynamic>>?> _geminiHoleEstimatePass(
      String courseName, Map<String, dynamic> courseDoc,
      {GeminiClient? gemini}) async {
    gemini ??= _gemini;
    if (gemini == null) return null;
    final centre = _boundaryCentre(courseDoc);
    final locationHint = centre != null
        ? 'The course boundary centre is approximately ${centre.$1.toStringAsFixed(5)}, ${centre.$2.toStringAsFixed(5)} (lat, lng).'
        : 'The course is in New Zealand.';

    final prompt = '''
You are a golf course data assistant. The course "$courseName" in New Zealand has no hole geometry in OpenStreetMap.
$locationHint

Estimate the layout and return a JSON array with one object per hole. Use 9 holes if this is likely a 9-hole course, otherwise 18.

Each hole object must have:
- "holeNumber": integer (1-based)
- "par": integer (3, 4, or 5)
- "handicapIndex": integer (1 to holeCount, each unique)
- "tee": {"lat": float, "lng": float} — estimated tee position
- "pin": {"lat": float, "lng": float} — estimated green/pin position
- "estimated": true

Place tee and pin coordinates near the boundary centre. Space holes plausibly within ~500m of the centre.
Return ONLY a valid JSON array. Do not add explanations.
''';

    try {
      final result = await gemini.completeJson(prompt, maxTokens: 3000);
      if (result is! List) return null;

      final holes = result.cast<Map<String, dynamic>>();
      final holeCount = holes.length;
      if (holeCount != 9 && holeCount != 18) return null;

      // Validate structure and handicap uniqueness.
      final handicaps = <int>{};
      for (final h in holes) {
        final par = h['par'];
        final hi = h['handicapIndex'];
        final tee = h['tee'];
        final pin = h['pin'];
        if (par is! num || par < 3 || par > 5) return null;
        if (hi is! num || hi < 1 || hi > holeCount) return null;
        if (!handicaps.add(hi.toInt())) return null; // duplicate
        if (tee is! Map || pin is! Map) return null;
        if (tee['lat'] == null || tee['lng'] == null) return null;
        if (pin['lat'] == null || pin['lng'] == null) return null;
      }

      // Normalise into the standard holeDoc shape.
      return holes.map((h) {
        final tee = h['tee'] as Map;
        final pin = h['pin'] as Map;
        return {
          'holeNumber': (h['holeNumber'] as num).toInt(),
          'par': (h['par'] as num).toInt(),
          'handicapIndex': (h['handicapIndex'] as num).toInt(),
          'pin': {
            'lat': (pin['lat'] as num).toDouble(),
            'lng': (pin['lng'] as num).toDouble(),
          },
          'teeBoxes': [
            {
              'lat': (tee['lat'] as num).toDouble(),
              'lng': (tee['lng'] as num).toDouble(),
            }
          ],
          'routingLine': [],
          'teePlatforms': [],
          'fairways': [],
          'greens': [],
          'estimated': true,
        };
      }).toList();
    } catch (e) {
      print('  → Gemini hole estimate error: $e');
      return null;
    }
  }

  /// Returns the (lat, lng) centroid of the course boundary polygon, or null.
  (double, double)? _boundaryCentre(Map<String, dynamic> courseDoc) {
    final points = courseDoc['boundaryPoints'];
    if (points is! List || points.isEmpty) return null;
    double sumLat = 0, sumLng = 0;
    int count = 0;
    for (final p in points) {
      if (p is! Map) continue;
      final lat = p['lat'];
      final lng = p['lng'];
      if (lat is num && lng is num) {
        sumLat += lat.toDouble();
        sumLng += lng.toDouble();
        count++;
      }
    }
    if (count == 0) return null;
    return (sumLat / count, sumLng / count);
  }

}
