import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class CourseSelectionPage extends StatefulWidget {
  const CourseSelectionPage({super.key});

  @override
  _CourseSelectionPageState createState() => _CourseSelectionPageState();
}

class _CourseSelectionPageState extends State<CourseSelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _allCourses = [];
  List<dynamic> _filteredCourses = [];
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
      final String data = await DefaultAssetBundle.of(context).loadString('assets/golf_courses_nz.json');
      final List<dynamic> jsonResult = json.decode(data);
      setState(() {
        _allCourses = jsonResult;
        _filteredCourses = _allCourses;
      });
    } catch (e) {
      print('Error loading local courses: $e');
      if (!mounted) return; // Crucial check before showing SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load local courses: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _filterCourses(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredCourses = _allCourses;
      });
      return;
    }
    setState(() {
      _filteredCourses = _allCourses.where((course) {
        final courseName = course['tags']['name']?.toString().toLowerCase() ?? '';
        return courseName.contains(query.toLowerCase());
      }).toList();
    });
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
              onSubmitted: (value) => _filterCourses(value),
            ),
          ),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Expanded(
                  child: ListView.builder(
                    itemCount: _filteredCourses.length,
                    itemBuilder: (context, index) {
                      final course = _filteredCourses[index];
                      final tags = course['tags'];
                      final courseName = tags['name'] ?? 'Unknown Course';

                      return ListTile(
                        title: Text(courseName),
                        onTap: () async {
                          setState(() {
                            _isLoading = true;
                          });

                          final courseId = course['id'];
                          final downloadQuery = """
[out:json];
(
  way($courseId);
  node(w);
  rel(bw);
);
out body;
node(w);
out skel qt;
                          """;

                          try {
                            final response = await http.post(
                              Uri.parse('https://overpass-api.de/api/interpreter'),
                              body: downloadQuery,
                            );

                            if (response.statusCode == 200) {
                              final directory = await getApplicationDocumentsDirectory();
                              final path = '${directory.path}/selected_course.json';
                              final file = File(path);
                              await file.writeAsString(response.body);

                              if (mounted) {
                                Navigator.pushNamed(context, '/map');
                              }
                            } else {
                              throw Exception('Failed to download course data. Status code: ${response.statusCode}');
                            }
                          } catch (e) {
                            print('Error downloading course: $e');
                            if (!mounted) return; // Crucial check before showing SnackBar
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Download failed: $e')),
                            );
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isLoading = false;
                              });
                            }
                          }
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
