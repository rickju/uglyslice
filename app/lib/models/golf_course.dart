import 'package:latlong2/latlong.dart';
import 'dart:convert';

class Tee {
  final String color;
  final double distance;
  final double courseRating;
  final double slopeRating;

  Tee({
    required this.color,
    this.distance = 0.0,
    this.courseRating = 0.0,
    this.slopeRating = 0.0,
  });
}

class Hole {
  final int holeNumber;
  final int par;
  final int handicapIndex;
  final LatLng pin;
  final List<Tee> tees;

  Hole({
    required this.holeNumber,
    required this.par,
    this.handicapIndex = 0,
    required this.pin,
    this.tees = const [],
  });

  static Hole? fromWay(Way way, Map<int, Map<String, dynamic>> nodeTags, GolfCourse golfCourse) {
    if (!way.tags.containsKey('ref')) {
      return null;
    }
    final holeNumber = int.parse(way.tags['ref']);
    final par = int.parse(way.tags['par'] ?? '0');
    final handicapIndex = int.parse(way.tags['handicap'] ?? '0');

    LatLng? pin;
    List<Tee> tees = [];

    print('  - Processing hole ${way.tags["ref"]} with ${way.nodeIds.length} nodes.');
    for (var i = 0; i < way.nodeIds.length; i++) {
      final nodeId = way.nodeIds[i];
      // Find the corresponding node in the golfCourse.nodes list
      final node = golfCourse.nodes.firstWhere((n) => n.id == nodeId, orElse: () => throw Exception('Node not found'));
      print('    - Node ${node.id} tags: ${node.tags}');
      if (node.tags['golf'] == 'pin') {
        pin = node.toLatLng();
        print('      - Found pin at ${pin}');
      } else if (node.tags['golf'] == 'tee') {
        final tee = Tee(
          color: node.tags['tee'] ?? 'white',
          distance: double.parse(node.tags['distance'] ?? '0'),
        );
        tees.add(tee);
      }
    }

    if (pin == null) {
      print('  - Pin not found for hole ${way.tags["ref"]}');
      return null;
    }

    return Hole(
      holeNumber: holeNumber,
      par: par,
      handicapIndex: handicapIndex,
      pin: pin,
      tees: tees,
    );
  }
}

class GolfCourse {
  final String id;
  final String name;
  final LatLng location;
  final int holesCount;
  final List<Hole> holes;

  // These are for parsing from OpenStreetMap data
  final List<Way> features;
  final List<Node> nodes;

  GolfCourse({
    required this.id,
    required this.name,
    required this.location,
    this.holesCount = 18,
    required this.holes,
    this.features = const [],
    this.nodes = const [],
  });
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
