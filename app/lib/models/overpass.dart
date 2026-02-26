import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' as jts;

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

// hleper/converter:  json/[{ "lat": 1.1, "lon": 2.2 }, ...] => polygon
class JtsHelper {
  static final _factory = jts.GeometryFactory();

  static jts.Polygon calcPolygon(List<dynamic> json) {
    if (json.isEmpty) throw ArgumentError("Nodes cannot be empty");

    // json/Map => Coordinate. note: JTS构造函数通常是(x, y), 即(lon, lat)
    List<jts.Coordinate> coords = json.map((node) {
      return jts.Coordinate(node['lon'] as double, node['lat'] as double);
    }).toList();

    // 多边形必须闭合
    if (coords.first != coords.last) {
      coords.add(coords.first);
    }

    // shell/外壳 coord -> LinearRing
    jts.LinearRing shell = _factory.createLinearRing(coords);
    // hole/内孔
    // List<LinearRing>? holeRings = holes?.map((h) => factory.createLinearRing(h)).toList();

    //  linearring => Polygon
    return _factory.createPolygon(shell, null);
  }
}
