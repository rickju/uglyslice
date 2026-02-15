import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for rootBundle
import 'dart:convert';
import 'round_page.dart';

// A simple class to hold the compact course data
class CompactCourse {
  final String name;
  final double lat;
  final double lon;

  CompactCourse({required this.name, required this.lat, required this.lon});

  factory CompactCourse.fromJson(Map<String, dynamic> json) {
    return CompactCourse(
      name: json['name'],
      lat: json['lat'],
      lon: json['lon'],
    );
  }
}

class CourseSelectionPage extends StatefulWidget {
  const CourseSelectionPage({super.key});

  @override
  _CourseSelectionPageState createState() => _CourseSelectionPageState();
}

class _CourseSelectionPageState extends State<CourseSelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  List<CompactCourse> _allCourses = []; // Store all courses from the local file
  List<CompactCourse> _searchResults = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLocalCourses();
  }

  Future<void> _loadLocalCourses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Corrected to load from the root asset path
      final String jsonString = await rootBundle.loadString(
        'nz-course-compact.json',
      );
      final List<dynamic> data = json.decode(jsonString);
      setState(() {
        _allCourses = data
            .map((courseJson) => CompactCourse.fromJson(courseJson))
            .toList();
        _searchResults = _allCourses; // Initially, show all courses
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load local courses: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterCourses(String query) {
    setState(() {
      if (query.isEmpty) {
        _searchResults = _allCourses;
      } else {
        _searchResults = _allCourses.where((course) {
          return course.name.toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select a Golf Course')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search for a course',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _filterCourses(_searchController.text),
                ),
              ),
              onChanged: (value) => _filterCourses(value),
            ),
          ),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Expanded(
                  child: ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final course = _searchResults[index];

                      return ListTile(
                        title: Text(course.name),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              // XXX builder: (context) => RoundPage(courseName: course.name),
                              builder: (context) =>
                                  RoundPage(courseName: 'Karori Golf Club'),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
