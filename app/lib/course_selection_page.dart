import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CourseSelectionPage extends StatefulWidget {
  const CourseSelectionPage({super.key});

  @override
  _CourseSelectionPageState createState() => _CourseSelectionPageState();
}

class _CourseSelectionPageState extends State<CourseSelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;

  Future<void> _searchCourses(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final overpassQuery = """
[out:json];
area[name="New Zealand"]->.searchArea;
(
  way["leisure"="golf_course"]["name"~"(?i)$query"](area.searchArea);
);
out center;
    """;

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: overpassQuery,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _searchResults = data['elements'];
        });
      } else {
        throw Exception('Failed to load course data');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search failed: $e')),
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
                  onPressed: () => _searchCourses(_searchController.text),
                ),
              ),
              onSubmitted: (value) => _searchCourses(value),
            ),
          ),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Expanded(
                  child: ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final course = _searchResults[index];
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
                              // Navigate to the map page with the downloaded data
                              Navigator.pushNamed(context, '/map', arguments: response.body);
                            } else {
                              throw Exception('Failed to download course data');
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
