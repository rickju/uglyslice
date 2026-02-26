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

/// Helper class for converting geographic data to JTS (Java Topology Suite) geometries
/// Used for geometric calculations on golf course features like greens, fairways, and boundaries
class JtsHelper {
  // Create geometry factory with default parameters
  static final jts.GeometryFactory _factory = jts.GeometryFactory(
    jts.PrecisionModel(),
    0,
    jts.CoordinateArraySequenceFactory(),
  );

  /// Converts a list of coordinate nodes to a JTS Polygon
  ///
  /// [nodes] - List of coordinate objects with 'lat' and 'lon' properties
  /// Returns a JTS Polygon that can be used for geometric operations
  ///
  /// Throws [ArgumentError] if nodes list is empty or contains invalid data
  /// Throws [FormatException] if coordinate parsing fails
  static jts.Polygon calcPolygon(List<dynamic> nodes) {
    if (nodes.isEmpty) {
      throw ArgumentError("Nodes list cannot be empty");
    }

    if (nodes.length < 3) {
      throw ArgumentError("Polygon requires at least 3 nodes, got ${nodes.length}");
    }

    try {
      // Convert JSON coordinates to JTS Coordinates
      // Note: JTS uses (x, y) format, which is (longitude, latitude)
      final List<jts.Coordinate> coords = nodes.map((node) {
        if (node is! Map<String, dynamic>) {
          throw FormatException("Expected Map<String, dynamic>, got ${node.runtimeType}");
        }

        final lat = parseCoordinate(node['lat'], 'lat');
        final lon = parseCoordinate(node['lon'], 'lon');

        return jts.Coordinate(lon, lat);
      }).toList();

      // Ensure polygon is closed (first and last points must be identical)
      if (!coordinatesEqual(coords.first, coords.last)) {
        coords.add(coords.first);
      }

      // Create linear ring for polygon shell
      final jts.LinearRing shell = _factory.createLinearRing(coords);

      // Create polygon (no holes for now)
      return _factory.createPolygon(shell, null);
    } catch (e) {
      throw FormatException("Failed to create polygon: $e");
    }
  }

  /// Converts LatLng points to a JTS Polygon
  ///
  /// [points] - List of LatLng coordinates
  /// Returns a JTS Polygon for geometric operations
  static jts.Polygon fromLatLngPoints(List<LatLng> points) {
    if (points.isEmpty) {
      throw ArgumentError("Points list cannot be empty");
    }

    if (points.length < 3) {
      throw ArgumentError("Polygon requires at least 3 points, got ${points.length}");
    }

    final coords = points.map((point) =>
      jts.Coordinate(point.longitude, point.latitude)
    ).toList();

    // Ensure closure
    if (!coordinatesEqual(coords.first, coords.last)) {
      coords.add(coords.first);
    }

    final shell = _factory.createLinearRing(coords);
    return _factory.createPolygon(shell, null);
  }

  /// Creates a JTS Point from latitude and longitude
  ///
  /// [lat] - Latitude coordinate
  /// [lon] - Longitude coordinate
  /// Returns a JTS Point geometry
  static jts.Point createPoint(double lat, double lon) {
    return _factory.createPoint(jts.Coordinate(lon, lat));
  }

  /// Creates a JTS Point from LatLng
  ///
  /// [latLng] - LatLng coordinate
  /// Returns a JTS Point geometry
  static jts.Point fromLatLng(LatLng latLng) {
    return createPoint(latLng.latitude, latLng.longitude);
  }

  /// Checks if a point is inside a polygon
  ///
  /// [point] - The point to test
  /// [polygon] - The polygon boundary
  /// Returns true if point is inside the polygon
  static bool pointInPolygon(LatLng point, jts.Polygon polygon) {
    final jtsPoint = fromLatLng(point);
    return polygon.contains(jtsPoint);
  }

  /// Calculates the area of a polygon in square degrees (not square meters)
  /// Note: For actual area calculations in meters, additional conversion would be needed
  ///
  /// [polygon] - The polygon to calculate area for
  /// Returns area in square degrees
  static double calculateArea(jts.Polygon polygon) {
    // Get the geometry area - this is in coordinate units (degrees)
    return polygon.getArea();
  }

  /// Helper method to parse coordinate values with validation - made public for testing
  static double parseCoordinate(dynamic value, String coordinateName) {
    if (value == null) {
      throw FormatException("$coordinateName coordinate cannot be null");
    }

    if (value is num) {
      final doubleValue = value.toDouble();
      if (!doubleValue.isFinite) {
        throw FormatException("$coordinateName coordinate must be finite, got $doubleValue");
      }

      // Basic range validation for lat/lon
      if (coordinateName == 'lat' && (doubleValue < -90 || doubleValue > 90)) {
        throw FormatException("Latitude must be between -90 and 90, got $doubleValue");
      }
      if (coordinateName == 'lon' && (doubleValue < -180 || doubleValue > 180)) {
        throw FormatException("Longitude must be between -180 and 180, got $doubleValue");
      }

      return doubleValue;
    }

    throw FormatException("$coordinateName coordinate must be a number, got ${value.runtimeType}");
  }

  /// Converts an Overpass Way JSON to a JTS Polygon
  ///
  /// [wayJson] - The way JSON object from Overpass API response
  /// [nodeCoordinates] - Optional map of node IDs to coordinates (for ways without geometry)
  /// Returns a JTS Polygon created from the way's geometry or node references
  ///
  /// Supports both formats:
  /// - Ways with 'geometry' array (from "out geom" queries)
  /// - Ways with 'nodes' array requiring coordinate lookup
  ///
  /// Throws [ArgumentError] if way has insufficient points or invalid structure
  /// Throws [FormatException] if coordinate data is malformed
  static jts.Polygon fromOverpassWay(
    Map<String, dynamic> wayJson,
    [Map<int, LatLng>? nodeCoordinates]
  ) {
    if (wayJson['type'] != 'way') {
      throw ArgumentError("Expected way type, got ${wayJson['type']}");
    }

    List<Map<String, dynamic>> coordinatePoints = [];

    // Case 1: Way has geometry array (from "out geom" query)
    if (wayJson.containsKey('geometry') && wayJson['geometry'] is List) {
      final geometry = wayJson['geometry'] as List;

      if (geometry.isEmpty) {
        throw ArgumentError("Way geometry cannot be empty");
      }

      coordinatePoints = geometry.map((point) {
        if (point is! Map<String, dynamic>) {
          throw FormatException("Expected geometry point as Map, got ${point.runtimeType}");
        }
        return point;
      }).toList();
    }
    // Case 2: Way has nodes array (requires coordinate lookup)
    else if (wayJson.containsKey('nodes') && wayJson['nodes'] is List) {
      if (nodeCoordinates == null) {
        throw ArgumentError("Node coordinates map required for ways without geometry");
      }

      final nodes = wayJson['nodes'] as List;

      if (nodes.isEmpty) {
        throw ArgumentError("Way nodes cannot be empty");
      }

      coordinatePoints = nodes.map((nodeId) {
        if (nodeId is! int) {
          throw FormatException("Expected node ID as int, got ${nodeId.runtimeType}");
        }

        if (!nodeCoordinates.containsKey(nodeId)) {
          throw ArgumentError("Node coordinate not found for ID: $nodeId");
        }

        final latLng = nodeCoordinates[nodeId]!;
        return {'lat': latLng.latitude, 'lon': latLng.longitude};
      }).toList();
    }
    else {
      throw FormatException("Way must contain either 'geometry' or 'nodes' array");
    }

    // Convert coordinate points to polygon using existing method
    return calcPolygon(coordinatePoints);
  }

  /// Converts a Way object to a JTS Polygon
  ///
  /// [way] - The Way object containing points
  /// Returns a JTS Polygon created from the way's points
  ///
  /// Throws [ArgumentError] if way has insufficient points
  static jts.Polygon fromWay(Way way) {
    if (way.points.isEmpty) {
      throw ArgumentError("Way points cannot be empty");
    }

    return fromLatLngPoints(way.points);
  }

  /// Batch converts multiple Overpass way JSONs to polygons
  ///
  /// [waysJson] - List of way JSON objects from Overpass API
  /// [nodeCoordinates] - Optional map of node IDs to coordinates
  /// [filterTags] - Optional map to filter ways by specific tag values
  /// Returns a list of JTS Polygons
  ///
  /// Only processes ways that can form valid polygons (3+ points)
  static List<jts.Polygon> fromOverpassWays(
    List<dynamic> waysJson,
    [Map<int, LatLng>? nodeCoordinates,
    Map<String, String>? filterTags]
  ) {
    final List<jts.Polygon> polygons = [];

    for (final wayJson in waysJson) {
      if (wayJson is! Map<String, dynamic> || wayJson['type'] != 'way') {
        continue;
      }

      // Apply tag filters if provided
      if (filterTags != null) {
        final tags = wayJson['tags'] as Map<String, dynamic>? ?? {};
        bool matchesFilter = true;

        for (final entry in filterTags.entries) {
          if (tags[entry.key] != entry.value) {
            matchesFilter = false;
            break;
          }
        }

        if (!matchesFilter) continue;
      }

      try {
        final polygon = fromOverpassWay(wayJson, nodeCoordinates);
        polygons.add(polygon);
      } catch (e) {
        // Skip ways that can't be converted to valid polygons
        continue;
      }
    }

    return polygons;
  }

  /// Helper method to check if two coordinates are equal - made public for testing
  static bool coordinatesEqual(jts.Coordinate a, jts.Coordinate b) {
    const double tolerance = 1e-10;
    return (a.x - b.x).abs() < tolerance && (a.y - b.y).abs() < tolerance;
  }
}
