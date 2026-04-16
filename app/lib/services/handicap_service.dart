import 'dart:convert';
import 'dart:io';

import '_docs_dir_stub.dart'
    if (dart.library.ui) '_docs_dir_flutter.dart';

// ── Result ────────────────────────────────────────────────────────────────────

class HandicapResult {
  final double index;
  final bool isEstimated; // true when any round used fallback par/slope
  final int roundsUsed;
  final int totalRounds;

  const HandicapResult({
    required this.index,
    required this.isEstimated,
    required this.roundsUsed,
    required this.totalRounds,
  });

  static const none = HandicapResult(
      index: 0, isEstimated: true, roundsUsed: 0, totalRounds: 0);

  String get display {
    if (totalRounds == 0) return '--';
    final s = index.toStringAsFixed(1);
    return isEstimated ? '~$s' : s;
  }
}

// ── Manual course-rating overrides ───────────────────────────────────────────

class CourseRating {
  final double courseRating;
  final double slopeRating;

  const CourseRating({required this.courseRating, required this.slopeRating});

  Map<String, dynamic> toJson() =>
      {'courseRating': courseRating, 'slopeRating': slopeRating};

  factory CourseRating.fromJson(Map<String, dynamic> j) => CourseRating(
        courseRating: (j['courseRating'] as num).toDouble(),
        slopeRating: (j['slopeRating'] as num).toDouble(),
      );
}

/// Persists user-entered course ratings to a JSON file.
class CourseRatingStore {
  static Map<String, CourseRating> _cache = {};

  static Map<String, CourseRating> get all => Map.unmodifiable(_cache);

  static CourseRating? get(String courseId) => _cache[courseId];

  static Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _cache = raw.map((k, v) =>
          MapEntry(k, CourseRating.fromJson(v as Map<String, dynamic>)));
    } catch (_) {}
  }

  static Future<void> save(String courseId, CourseRating rating) async {
    _cache[courseId] = rating;
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(
          _cache.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (_) {}
  }

  static Future<File> _file() async {
    final dir = await getDocsDir();
    return File('${dir.path}/course_ratings.json');
  }
}

// ── WHS calculation ───────────────────────────────────────────────────────────

class HandicapService {
  /// Calculates WHS Handicap Index from [rounds] (newest first).
  ///
  /// [coursePars] maps courseId → total par (from loaded course data).
  /// Falls back to 72 (18-hole) or 36 (9-hole) when not available.
  /// Uses [CourseRatingStore] for manual slope/course-rating overrides.
  static HandicapResult calculate({
    required List<({int score, int holes, String courseId})> rounds,
    Map<String, double> coursePars = const {},
  }) {
    if (rounds.isEmpty) return HandicapResult.none;

    final recent = rounds.take(20).toList();
    var anyEstimated = false;

    final diffs = <double>[];
    for (final r in recent) {
      if (r.score == 0) continue;
      final override = CourseRatingStore.get(r.courseId);
      final double cr;
      final double slope;
      if (override != null && override.slopeRating > 0) {
        cr = override.courseRating;
        slope = override.slopeRating;
      } else {
        cr = coursePars[r.courseId] ??
            (r.holes >= 14 ? 72.0 : 36.0);
        slope = 113.0;
        anyEstimated = true;
      }
      diffs.add((113.0 / slope) * (r.score - cr));
    }

    if (diffs.isEmpty) return HandicapResult.none;

    diffs.sort();
    final take = _diffCount(diffs.length);
    final best = diffs.sublist(0, take);
    final avg = best.reduce((a, b) => a + b) / best.length;
    final idx = (avg * 0.96).clamp(-10.0, 54.0);

    return HandicapResult(
      index: idx,
      isEstimated: anyEstimated,
      roundsUsed: take,
      totalRounds: diffs.length,
    );
  }

  /// WHS table: how many differentials to use for N rounds.
  static int _diffCount(int n) {
    if (n >= 20) return 8;
    if (n >= 19) return 7;
    if (n >= 17) return 6;
    if (n >= 15) return 5;
    if (n >= 12) return 4;
    if (n >= 9)  return 3;
    if (n >= 6)  return 2;
    return 1;
  }
}
