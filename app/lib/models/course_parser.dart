import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'golf_course.dart';

class CourseParser {
  static GolfCourse fromJson(String jsonString) {
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> elements = data['elements'];

    final List<Node> nodes = [];
    final Map<int, LatLng> nodeCoordinates = {};
    final Map<int, Map<String, dynamic>> nodeTags = {};

    for (var element in elements) {
      if (element['type'] == 'node') {
        final node = Node.fromJson(element);
        nodes.add(node);
        nodeCoordinates[node.id] = node.toLatLng();
        nodeTags[node.id] = node.tags;
      }
    }

    final List<Way> features = [];
    final List<Hole> holes = [];

    // Create a dummy GolfCourse to pass to Hole.fromWay initially
    // This allows Hole.fromWay to access all nodes via golfCourse.nodes
    final GolfCourse dummyGolfCourse = GolfCourse(
      id: '',
      name: '',
      location: LatLng(0, 0),
      holes: [],
      nodes: nodes,
    );

    int holeWays = 0;
    for (var element in elements) {
      if (element['type'] == 'way') {
        final way = Way.fromJson(element, nodeCoordinates);
        features.add(way);
        if (way.tags['golf'] == 'hole') {
          holeWays++;
          final hole = Hole.fromWay(way, nodeTags, dummyGolfCourse);
          if (hole != null) {
            holes.add(hole);
          }
        }
      }
    }

    holes.sort((a, b) => a.holeNumber.compareTo(b.holeNumber));

    // Extract course name and other details from the data
    String courseName = "Unknown Course";
    if (data['elements'] != null && data['elements'].isNotEmpty) {
      var courseElement = data['elements'].firstWhere(
        (e) => e['tags'] != null && e['tags']['golf'] == 'course',
        orElse: () => null,
      );
      if (courseElement != null) {
        courseName = courseElement['tags']['name'] ?? "Unknown Course";
      }
    }

    return GolfCourse(
      id: "course_${DateTime.now().millisecondsSinceEpoch}",
      name: courseName,
      location: LatLng(0, 0), // Placeholder
      holes: holes,
      features: features,
      nodes: nodes,
    );
  }
}
