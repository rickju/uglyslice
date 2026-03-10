import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'dart:convert';
import 'jts_helper.dart';

/// Axis-aligned bounding box — replaces flutter_map's LatLngBounds.
typedef BBox = ({double minLat, double minLon, double maxLat, double maxLon});

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

// line/area: nodes list, point list
class Way {
  final int id;
  final List<int> nodeIds;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final BBox? bounds;
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
    BBox? bounds;
    if (json.containsKey('bounds') && json['bounds'] is Map<String, dynamic>) {
      final boundsData = json['bounds'] as Map<String, dynamic>;
      if (boundsData.containsKey('minlat') &&
          boundsData.containsKey('minlon') &&
          boundsData.containsKey('maxlat') &&
          boundsData.containsKey('maxlon')) {
        bounds = (
          minLat: (boundsData['minlat'] as num).toDouble(),
          minLon: (boundsData['minlon'] as num).toDouble(),
          maxLat: (boundsData['maxlat'] as num).toDouble(),
          maxLon: (boundsData['maxlon'] as num).toDouble(),
        );
      }
    }

    // Create JTS polygon from points if there are enough points
    jts.Polygon? polygon;
    if (points.length >= 3) {
      try {
        polygon = JtsHelper.fromLatLngPoints(points);
      } catch (e) {
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
    return 'overpass Way(id: $id, nodeIds: ${nodeIds.toString()}, tags: ${tags.toString()}';
  }
}

class Relation {
  final int id;
  final List<int> nodeIds;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final BBox? bounds;
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

    if (json.containsKey('geometry') && json['geometry'] is List) {
      final geometry = json['geometry'] as List;
      for (var point in geometry) {
        if (point is Map<String, dynamic> &&
            point.containsKey('lat') &&
            point.containsKey('lon')) {
          points.add(LatLng(point['lat'], point['lon']));
        }
      }
      validNodeIds.clear();
    } else if (json.containsKey('nodes') && json['nodes'] is List) {
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

    BBox? bounds;
    if (json.containsKey('bounds') && json['bounds'] is Map<String, dynamic>) {
      final boundsData = json['bounds'] as Map<String, dynamic>;
      if (boundsData.containsKey('minlat') &&
          boundsData.containsKey('minlon') &&
          boundsData.containsKey('maxlat') &&
          boundsData.containsKey('maxlon')) {
        bounds = (
          minLat: (boundsData['minlat'] as num).toDouble(),
          minLon: (boundsData['minlon'] as num).toDouble(),
          maxLat: (boundsData['maxlat'] as num).toDouble(),
          maxLon: (boundsData['maxlon'] as num).toDouble(),
        );
      }
    }

    jts.Polygon? polygon;
    if (points.length >= 3) {
      try {
        polygon = JtsHelper.fromLatLngPoints(points);
      } catch (e) {
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
    return 'overpass Relation(id: $id, nodeIds: ${nodeIds.toString()}, tags: ${tags.toString()}';
  }
}

class Overpass {
  final List<Node> nodes;
  final List<Way> ways;
  final List<Relation> relations;

  Overpass({
    this.nodes = const <Node>[],
    this.ways = const <Way>[],
    this.relations = const <Relation>[],
  });

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
        ways.add(Way.fromJson(element, nodeCoordinates));
      } else if (element['type'] == 'relation') {
        relations.add(Relation.fromJson(element, nodeCoordinates));
      }
    }

    return Overpass(nodes: nodes, ways: ways, relations: relations);
  }
}
