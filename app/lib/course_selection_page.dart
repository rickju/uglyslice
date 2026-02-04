import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for rootBundle
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'models/golf_course.dart';
import 'models/course_parser.dart';
import 'models/round.dart';
import 'models/player.dart';
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
  final Function(Round) onRoundStarted;

  const CourseSelectionPage({super.key, required this.onRoundStarted});

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
      final String jsonString = await rootBundle.loadString('nz-course-compact.json');
      final List<dynamic> data = json.decode(jsonString);
      setState(() {
        _allCourses = data.map((courseJson) => CompactCourse.fromJson(courseJson)).toList();
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
  
  Future<void> _fetchAndStartRound(String courseName) async {
    setState(() {
      _isLoading = true;
    });

    // Use the course name to query Overpass API for full data
    final downloadQuery = """
[out:json];
area[name="New Zealand"]->.searchArea;
(
  way["leisure"="golf_course"]["name"="$courseName"](area.searchArea);
  node(w);
  rel(bw);
);
out body;
>;
out skel qt;
    """;

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: downloadQuery,
      );

      if (response.statusCode == 200) {
        final golfCourse = CourseParser.fromJson(response.body, courseName);
        final player = Player(name: 'Rick');
        final round = Round(player: player, course: golfCourse, date: DateTime.now());
        widget.onRoundStarted(round);

      } else {
        throw Exception('Failed to download full course data');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Golf Course'),
      ),
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
                        onTap: () => _fetchAndStartRound(course.name),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
