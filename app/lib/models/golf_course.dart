import 'package:latlong2/latlong.dart';
import 'dart:convert';

class GolfCourse {
  final List<Way> features;
  final List<Node> nodes;
  final List<Hole> holes;

  GolfCourse({required this.features, required this.nodes, required this.holes});

    factory GolfCourse.fromJson(String jsonString) {

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

      print('Node tags: $nodeTags');

  

      final List<Way> features = [];

      final List<Hole> holes = []; // Temporary list for holes

  

      // Create a dummy GolfCourse to pass to Hole.fromWay initially

      // This allows Hole.fromWay to access all nodes via golfCourse.nodes

      final GolfCourse dummyGolfCourse = GolfCourse(features: [], nodes: nodes, holes: []);

  

      int holeWays = 0;

      for (var element in elements) {

        if (element['type'] == 'way') {

          final way = Way.fromJson(element, nodeCoordinates);

          features.add(way);

          if (way.tags['golf'] == 'hole') {

            holeWays++;

            print('Found hole way with ref: ${way.tags["ref"]}');

            final hole = Hole.fromWay(way, nodeTags, dummyGolfCourse);

            if (hole != null) {

              holes.add(hole);

              print('  - Hole created with pin at ${hole.pin}');

            } else {

              print('  - Hole creation failed.');

            }

          }

        }

      }

      print('Found $holeWays hole ways.');

  

      holes.sort((a, b) => a.holeNumber.compareTo(b.holeNumber));

  

      return GolfCourse(features: features, nodes: nodes, holes: holes);

    }
}

class Hole {
  final int holeNumber;
  final int par;
  final LatLng pin;
  final List<LatLng> tees;

  Hole({required this.holeNumber, required this.par, required this.pin, required this.tees});

  static Hole? fromWay(Way way, Map<int, Map<String, dynamic>> nodeTags, GolfCourse golfCourse) {
    if (!way.tags.containsKey('ref')) {
      return null;
    }
    final holeNumber = int.parse(way.tags['ref']);
    final par = int.parse(way.tags['par'] ?? '0');

    LatLng? pin;
    List<LatLng> tees = [];

    print('  - Processing hole ${way.tags["ref"]} with ${way.nodeIds.length} nodes.');
    for (var i = 0; i < way.nodeIds.length; i++) {
      final nodeId = way.nodeIds[i];
      // Find the corresponding node in the golfCourse.nodes list
      final node = golfCourse.nodes.firstWhere((n) => n.id == nodeId, orElse: () => throw Exception('Node not found'));
      print('    - Node ${node.id} tags: ${node.tags}');
      if (node.tags['golf'] == 'pin') {
        pin = node.toLatLng();
        print('      - Found pin at ${pin}');
      } else {
        tees.add(node.toLatLng());
      }
    }

    if (pin == null) {
      print('  - Pin not found for hole ${way.tags["ref"]}');
      return null;
    }

    return Hole(
      holeNumber: holeNumber,
      par: par,
      pin: pin,
      tees: tees,
    );
  }
}


class Node {
  final int id;
  final double lat;
  final double lon;
  final Map<String, dynamic> tags;

  Node({required this.id, required this.lat, required this.lon, required this.tags});

  factory Node.fromJson(Map<String, dynamic> json) {
    return Node(
      id: json['id'],
      lat: json['lat'],
      lon: json['lon'],
      tags: json['tags'] ?? {},
    );
  }

  LatLng toLatLng() {
    return LatLng(lat, lon);
  }
}

class Way {
  final int id;
  final List<int> nodeIds;
  final List<LatLng> points;
  final Map<String, dynamic> tags;

  Way({required this.id, required this.nodeIds, required this.points, required this.tags});

  factory Way.fromJson(Map<String, dynamic> json, Map<int, LatLng> nodeCoordinates) {
    final List<int> originalNodeIds = List<int>.from(json['nodes']);
    final List<LatLng> points = [];
    final List<int> validNodeIds = [];

    for (var id in originalNodeIds) {
      if (nodeCoordinates.containsKey(id)) {
        points.add(nodeCoordinates[id]!);
        validNodeIds.add(id);
      }
    }
    
    return Way(
      id: json['id'],
      nodeIds: validNodeIds,
      points: points,
      tags: json['tags'] ?? {},
    );
  }
}
