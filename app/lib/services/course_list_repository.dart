import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../database/app_database.dart';

class CourseListRepository {
  final AppDatabase _db;

  CourseListRepository(this._db);

  /// All courses sorted by priority: recent first, then nearby, then alpha.
  Future<List<CourseListRow>> listCourses({double? lat, double? lon}) async {
    final all = await (_db.select(_db.courseListTable)).get();
    return _sorted(all, lat: lat, lon: lon);
  }

  /// Filtered by name substring, sorted by priority.
  Future<List<CourseListRow>> search(String query,
      {double? lat, double? lon}) async {
    final lower = query.toLowerCase();
    final all = await (_db.select(_db.courseListTable)
          ..where((t) => t.name.lower().like('%$lower%')))
        .get();
    return _sorted(all, lat: lat, lon: lon);
  }

  /// True if the course list has never been synced.
  Future<bool> get isEmpty async =>
      (await _db.select(_db.courseListTable).get()).isEmpty;

  // ── Sorting ────────────────────────────────────────────────────────────────

  List<CourseListRow> _sorted(List<CourseListRow> courses,
      {double? lat, double? lon}) {
    final recent = RecentCourses.cached;

    int priority(CourseListRow c) {
      final idx = recent.indexOf(c.name);
      if (idx != -1) return idx; // 0 = most recent
      return recent.length + 1;  // not recent
    }

    double dist(CourseListRow c) {
      if (lat == null || lon == null) return 0;
      final dlat = c.lat - lat;
      final dlon = (c.lon - lon) * cos(lat * pi / 180);
      return dlat * dlat + dlon * dlon;
    }

    final sorted = courses..sort((a, b) {
      final pa = priority(a);
      final pb = priority(b);
      if (pa != pb) return pa.compareTo(pb);
      // Both non-recent: sort by distance if available, else alpha.
      if (lat != null) return dist(a).compareTo(dist(b));
      return a.name.compareTo(b.name);
    });
    debugPrint('_sorted: lat=$lat lon=$lon recent=${recent.length} top3=${sorted.take(3).map((c) => c.name).join(', ')}');
    return sorted;
  }
}

// ── Recent courses ────────────────────────────────────────────────────────────

/// Tracks recently opened courses, persisted to a JSON file.
class RecentCourses {
  static const _maxRecent = 10;
  static List<String> _cache = [];

  static List<String> get cached => List.unmodifiable(_cache);

  static Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      _cache = (jsonDecode(await file.readAsString()) as List).cast<String>();
    } catch (_) {}
  }

  static Future<void> add(String courseName) async {
    _cache
      ..remove(courseName)
      ..insert(0, courseName);
    if (_cache.length > _maxRecent) _cache = _cache.sublist(0, _maxRecent);
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(_cache));
    } catch (_) {}
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/recent_courses.json');
  }
}
