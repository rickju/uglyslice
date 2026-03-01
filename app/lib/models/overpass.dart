import 'package:latlong2/latlong.dart';

// overpass node: a point
class Node {
  final int id;
  final double lat;
  final double lon;
  final Map<String, dynamic> tags;

  Node({
    required this.id,
    required this.lat,
    required this.lon,
    required this.tags,
  });

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

  @override
  String toString() {
    return 'overpass Node: id: $id, tags: ${tags.toString()}\n';
  }
}

// 线/面: nodes list, point list
class Way {
  final int id;
  final List<int> nodeIds;
  final List<LatLng> points;
  final Map<String, dynamic> tags;

  Way({
    required this.id,
    required this.nodeIds,
    required this.points,
    required this.tags,
  });

  factory Way.fromJson(
    Map<String, dynamic> json,
    Map<int, LatLng> nodeCoordinates,
  ) {
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

  @override
  String toString() {
    return 'overpass Way(name: $id, node id list: ${nodeIds.toString()}, tags: ${tags.toString()}';
  }
}

class Relation {
  final int id;
  final List<int> nodeIds;
  final List<LatLng> points;
  final Map<String, dynamic> tags;

  Relation({
    required this.id,
    required this.nodeIds,
    required this.points,
    required this.tags,
  });

  factory Relation.fromJson(
    Map<String, dynamic> json,
    Map<int, LatLng> nodeCoordinates,
  ) {
    final List<int> originalNodeIds = List<int>.from(json['nodes']);
    final List<LatLng> points = [];
    final List<int> validNodeIds = [];

    for (var id in originalNodeIds) {
      if (nodeCoordinates.containsKey(id)) {
        points.add(nodeCoordinates[id]!);
        validNodeIds.add(id);
      }
    }

    return Relation(
      id: json['id'],
      nodeIds: validNodeIds,
      points: points,
      tags: json['tags'] ?? {},
    );
  }

  @override
  String toString() {
    return 'overpass Relation(name: $id, node id list: ${nodeIds.toString()}, tags: ${tags.toString()}';
  }
}