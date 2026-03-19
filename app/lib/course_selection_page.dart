import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'database/app_database.dart';
import 'main.dart' show db, courseSyncService;
import 'round_page.dart';
import 'services/course_list_repository.dart';
import 'services/course_repository.dart';

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
    await _fetchLocation();
    await _loadAll();
  }

  Future<void> _fetchLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(const Duration(seconds: 5));
      _lat = pos.latitude;
      _lon = pos.longitude;
    } catch (_) {}
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Golf Course'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sync courses',
            onPressed: _isLoading ? null : _sync,
          ),
        ],
      ),
      body: Column(
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
            const Expanded(child: Center(child: CircularProgressIndicator()))
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
                  return ListTile(
                    leading: recent
                        ? const Icon(Icons.history, size: 18,
                            color: Colors.amber)
                        : null,
                    title: Text(course.name),
                    onTap: () => _openCourse(course),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
