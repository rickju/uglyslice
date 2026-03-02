import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'dart:convert';
import 'jts.dart';

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
  final LatLngBounds? bounds;
  final jts.Polygon? polygon;

  Way({
    required this.id,
    required this.nodeIds,
    required this.points,
    required this.tags,
    this.bounds,
    this.polygon,
  });

  factory Way.fromJson(
    Map<String, dynamic> json,
    Map<int, LatLng>? nodeCoordinates,
  ) {
    final List<LatLng> points = [];
    final List<int> validNodeIds = [];

    // Case 1: Way has geometry array (from "out geom" queries)
    if (json.containsKey('geometry') && json['geometry'] is List) {
      final geometry = json['geometry'] as List;
      for (var point in geometry) {
        if (point is Map<String, dynamic> &&
            point.containsKey('lat') &&
            point.containsKey('lon')) {
          points.add(LatLng(point['lat'], point['lon']));
        }
      }
      // No node IDs available for geometry-based ways
      validNodeIds.clear();
    }
    // Case 2: Way has nodes array (requires coordinate lookup)
    else if (json.containsKey('nodes') && json['nodes'] is List) {
      if (nodeCoordinates != null) {
        final List<int> originalNodeIds = List<int>.from(json['nodes']);

        for (var id in originalNodeIds) {
          if (nodeCoordinates.containsKey(id)) {
            points.add(nodeCoordinates[id]!);
            validNodeIds.add(id);
          }
        }
      }
    }

    // Parse bounds if available
    LatLngBounds? bounds;
    if (json.containsKey('bounds') && json['bounds'] is Map<String, dynamic>) {
      final boundsData = json['bounds'] as Map<String, dynamic>;
      if (boundsData.containsKey('minlat') &&
          boundsData.containsKey('minlon') &&
          boundsData.containsKey('maxlat') &&
          boundsData.containsKey('maxlon')) {
        bounds = LatLngBounds(
          LatLng(boundsData['minlat'], boundsData['minlon']), // southWest
          LatLng(boundsData['maxlat'], boundsData['maxlon']), // northEast
        );
      }
    }

    // Create JTS polygon from points if there are enough points
    jts.Polygon? polygon;
    if (points.length >= 3) {
      try {
        polygon = JtsHelper.fromLatLngPoints(points);
      } catch (e) {
        // If polygon creation fails, leave it as null
        polygon = null;
      }
    }

    return Way(
      id: json['id'],
      nodeIds: validNodeIds,
      points: points,
      tags: json['tags'] ?? {},
      bounds: bounds,
      polygon: polygon,
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
  final LatLngBounds? bounds;
  final jts.Polygon? polygon;

  Relation({
    required this.id,
    required this.nodeIds,
    required this.points,
    required this.tags,
    this.bounds,
    this.polygon,
  });

  factory Relation.fromJson(
    Map<String, dynamic> json,
    Map<int, LatLng>? nodeCoordinates,
  ) {
    final List<LatLng> points = [];
    final List<int> validNodeIds = [];

    // Case 1: Relation has geometry array (from "out geom" queries)
    if (json.containsKey('geometry') && json['geometry'] is List) {
      final geometry = json['geometry'] as List;
      for (var point in geometry) {
        if (point is Map<String, dynamic> &&
            point.containsKey('lat') &&
            point.containsKey('lon')) {
          points.add(LatLng(point['lat'], point['lon']));
        }
      }
      // No node IDs available for geometry-based relations
      validNodeIds.clear();
    }
    // Case 2: Relation has nodes array (requires coordinate lookup)
    else if (json.containsKey('nodes') && json['nodes'] is List) {
      if (nodeCoordinates != null) {
        final List<int> originalNodeIds = List<int>.from(json['nodes']);

        for (var id in originalNodeIds) {
          if (nodeCoordinates.containsKey(id)) {
            points.add(nodeCoordinates[id]!);
            validNodeIds.add(id);
          }
        }
      }
    }

    // Parse bounds if available
    LatLngBounds? bounds;
    if (json.containsKey('bounds') && json['bounds'] is Map<String, dynamic>) {
      final boundsData = json['bounds'] as Map<String, dynamic>;
      if (boundsData.containsKey('minlat') &&
          boundsData.containsKey('minlon') &&
          boundsData.containsKey('maxlat') &&
          boundsData.containsKey('maxlon')) {
        bounds = LatLngBounds(
          LatLng(boundsData['minlat'], boundsData['minlon']), // southWest
          LatLng(boundsData['maxlat'], boundsData['maxlon']), // northEast
        );
      }
    }

    // Create JTS polygon from points if there are enough points
    jts.Polygon? polygon;
    if (points.length >= 3) {
      try {
        polygon = JtsHelper.fromLatLngPoints(points);
      } catch (e) {
        // If polygon creation fails, leave it as null
        polygon = null;
      }
    }

    return Relation(
      id: json['id'],
      nodeIds: validNodeIds,
      points: points,
      tags: json['tags'] ?? {},
      bounds: bounds,
      polygon: polygon,
    );
  }

  @override
  String toString() {
    return 'overpass Relation(name: $id, node id list: ${nodeIds.toString()}, tags: ${tags.toString()}';
  }
}

class Overpass {
  final List<Node> nodes;
  final List<Way> ways;
  final List<Relation> relations;

 Overpass( {this.nodes = const <Node>[],
            this.ways = const <Way> [],
            this.relations = const <Relation> []} );

  static Overpass fromJson(String json) {
    final Map<String, dynamic> data = jsonDecode(json);
    final List<dynamic> elements = data['elements'];
    print('json parsed: elements num: ${elements.length}');

    final List<Node> nodes = [];
    final List<Way> ways = [];
    final List<Relation> relations = [];
    final Map<int, LatLng> nodeCoordinates = {};

    // First pass: collect all nodes and build coordinate map
    for (var element in elements) {
      if (element['type'] == 'node') {
        final node = Node.fromJson(element);
        nodes.add(node);
        nodeCoordinates[node.id] = node.toLatLng();
      }
    }

    // Second pass: process ways and relations with coordinate map
    for (var element in elements) {
      if (element['type'] == 'way') {
        final way = Way.fromJson(element, nodeCoordinates);
        ways.add(way);
      } else if (element['type'] == 'relation') {
        final relation = Relation.fromJson(element, nodeCoordinates);
        relations.add(relation);
      }
    }

    return Overpass(
      nodes: nodes,
      ways: ways,
      relations: relations,
    );
  } // fromJson
}

