import 'dart:convert';
import 'dart:math' show cos, sqrt, pi;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'database/app_database.dart';
import 'main.dart' show db, courseSyncService;
import 'models/round.dart';
import 'round_page.dart';
import 'round_scorecard_page.dart';
import 'services/course_list_repository.dart';
import 'services/course_repository.dart';
import 'services/round_repository.dart';

class CourseSelectionPage extends StatefulWidget {
  const CourseSelectionPage({super.key});

  @override
  State<CourseSelectionPage> createState() => _CourseSelectionPageState();
}

class _CourseSelectionPageState extends State<CourseSelectionPage> {
  late final CourseListRepository _repo;
  late final CourseRepository _courseRepo;
  final TextEditingController _searchController = TextEditingController();

  List<CourseListRow> _results = [];
  List<Round> _recentRounds = [];
  bool _isLoading = true;
  String? _error;

  double? _lat;
  double? _lon;

  @override
  void initState() {
    super.initState();
    _repo = CourseListRepository(db);
    _courseRepo = CourseRepository(db);
    _init();
  }

  Future<void> _init() async {
    await RecentCourses.load();
    await Future.wait([_fetchLocation(), _loadRecentRounds()]);
    await _loadAll();
  }

  Future<void> _loadRecentRounds() async {
    final rounds = await RoundRepository(db).listRoundsForPlayer('Rick');
    if (mounted) setState(() => _recentRounds = rounds.take(5).toList());
  }

  Future<void> _fetchLocation() async {
    // Try GPS first.
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.denied &&
          permission != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 5));
        _lat = pos.latitude;
        _lon = pos.longitude;
        return;
      }
    } catch (_) {}
    // Fall back to IP geolocation (city-level, good enough for sorting).
    try {
      final res = await http
          .get(Uri.parse('https://ipinfo.io/json'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final loc = data['loc'] as String?; // "lat,lon"
        if (loc != null) {
          final parts = loc.split(',');
          if (parts.length == 2) {
            _lat = double.tryParse(parts[0]);
            _lon = double.tryParse(parts[1]);
            debugPrint('IP location: $_lat, $_lon (${data['city']})');
          }
        }
      }
    } catch (e) {
      debugPrint('IP location error: $e');
    }
  }

  Future<void> _sync() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await courseSyncService.syncAll();
      await _loadAll();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Sync failed: $e';
      });
    }
  }

  Future<void> _loadAll() async {
    final courses = await _repo.listCourses(lat: _lat, lon: _lon);
    setState(() {
      _results = courses;
      _isLoading = false;
    });
  }

  Future<void> _search(String query) async {
    final courses = query.isEmpty
        ? await _repo.listCourses(lat: _lat, lon: _lon)
        : await _repo.search(query, lat: _lat, lon: _lon);
    setState(() => _results = courses);
  }

  Future<void> _openCourse(CourseListRow course) async {
    await RecentCourses.add(course.name);

    // Cache hit → navigate immediately
    final cached = await _courseRepo.fetchCourseByName(course.name);
    if (cached != null) {
      if (!mounted) return;
      _navigate(cached.id, course.name);
      return;
    }

    // Cache miss → sync this course then navigate
    setState(() => _isLoading = true);
    try {
      final courseId = await courseSyncService.syncCourse(course.name);
      if (!mounted) return;
      _navigate(courseId, course.name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load ${course.name}: $e';
      });
    }
  }

  void _navigate(String courseId, String courseName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoundPage(courseId: courseId, courseName: courseName),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isRecent(CourseListRow course) =>
      RecentCourses.cached.contains(course.name);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Play'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Sync courses',
              onPressed: _isLoading ? null : _sync,
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(icon: Icon(Icons.golf_course), text: 'Courses'),
              Tab(
                icon: Badge(
                  isLabelVisible: _recentRounds.isNotEmpty,
                  label: Text('${_recentRounds.length}'),
                  child: const Icon(Icons.history),
                ),
                text: 'Recent Rounds',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // ── Courses tab ──────────────────────────────────────────
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _search,
                  ),
                ),
                if (_isLoading)
                  const Expanded(
                      child: Center(child: CircularProgressIndicator()))
                else if (_error != null)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton(
                              onPressed: _sync, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final course = _results[i];
                        final recent = _isRecent(course);
                        String? distLabel;
                        if (_lat != null && _lon != null) {
                          final dlat = course.lat - _lat!;
                          final dlon = (course.lon - _lon!) *
                              cos(_lat! * pi / 180);
                          final km = sqrt(dlat * dlat + dlon * dlon) * 111;
                          distLabel = km < 1 ? '<1 km' : '${km.round()} km';
                        }
                        return ListTile(
                          leading: recent
                              ? const Icon(Icons.history,
                                  size: 18, color: Colors.amber)
                              : null,
                          title: Text(course.name),
                          trailing: distLabel != null
                              ? Text(distLabel,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500))
                              : null,
                          onTap: () => _openCourse(course),
                        );
                      },
                    ),
                  ),
              ],
            ),
            // ── Recent Rounds tab ────────────────────────────────────
            _recentRounds.isEmpty
                ? const Center(child: Text('No rounds yet'))
                : ListView.builder(
                    itemCount: _recentRounds.length,
                    itemBuilder: (context, i) {
                      final round = _recentRounds[i];
                      final total = round.holePlays
                          .fold(0, (s, hp) => s + hp.score);
                      final holes = round.holePlays.length;
                      final date = round.date;
                      final dateStr =
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      return ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: Text(round.course.name),
                        subtitle: Text(dateStr),
                        trailing: holes > 0
                            ? Text('$total pts · $holes holes',
                                style: const TextStyle(fontSize: 13))
                            : null,
                        onTap: () async {
                          final repo = CourseRepository(db);
                          final course =
                              await repo.fetchCourse(round.course.id);
                          if (course == null || !mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RoundPage(
                                courseId: round.course.id,
                                courseName: round.course.name,
                                reviewRound: round.copyWith(course: course),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
