import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' as jts;

/// Helper class for converting geographic data to JTS (Java Topology Suite) geometries.
/// Used for geometric calculations on golf course features like greens, fairways, and boundaries.
class JtsHelper {
  static final jts.GeometryFactory _factory = jts.GeometryFactory(
    jts.PrecisionModel(),
    0,
    jts.CoordinateArraySequenceFactory(),
  );

  /// Converts a list of coordinate nodes to a JTS Polygon.
  static jts.Polygon calcPolygon(List<dynamic> nodes) {
    if (nodes.isEmpty) {
      throw ArgumentError('Nodes list cannot be empty');
    }
    if (nodes.length < 3) {
      throw ArgumentError('Polygon requires at least 3 nodes, got ${nodes.length}');
    }
    try {
      final List<jts.Coordinate> coords = nodes.map((node) {
        if (node is! Map<String, dynamic>) {
          throw FormatException('Expected Map<String, dynamic>, got ${node.runtimeType}');
        }
        final lat = parseCoordinate(node['lat'], 'lat');
        final lon = parseCoordinate(node['lon'], 'lon');
        return jts.Coordinate(lon, lat);
      }).toList();
      if (!coordinatesEqual(coords.first, coords.last)) coords.add(coords.first);
      final jts.LinearRing shell = _factory.createLinearRing(coords);
      return _factory.createPolygon(shell, null);
    } catch (e) {
      throw FormatException('Failed to create polygon: $e');
    }
  }

  /// Converts LatLng points to a JTS Polygon.
  static jts.Polygon fromLatLngPoints(List<LatLng> points) {
    if (points.isEmpty) {
      throw ArgumentError('Points list cannot be empty');
    }
    if (points.length < 3) {
      throw ArgumentError('Polygon requires at least 3 points, got ${points.length}');
    }
    final coords = points
        .map((point) => jts.Coordinate(point.longitude, point.latitude))
        .toList();
    if (!coordinatesEqual(coords.first, coords.last)) coords.add(coords.first);
    final shell = _factory.createLinearRing(coords);
    return _factory.createPolygon(shell, null);
  }

  static jts.Point createPoint(double lat, double lon) {
    return _factory.createPoint(jts.Coordinate(lon, lat));
  }

  static jts.Point fromLatLng(LatLng latLng) {
    return createPoint(latLng.latitude, latLng.longitude);
  }

  /// Checks if a point is inside a polygon.
  static bool pointInPolygon(LatLng point, jts.Polygon polygon) {
    final jtsPoint = fromLatLng(point);
    return polygon.contains(jtsPoint);
  }

  static double calculateArea(jts.Polygon polygon) {
    return polygon.getArea();
  }

  static double parseCoordinate(dynamic value, String coordinateName) {
    if (value == null) {
      throw FormatException('$coordinateName coordinate cannot be null');
    }
    if (value is num) {
      final doubleValue = value.toDouble();
      if (!doubleValue.isFinite) {
        throw FormatException('$coordinateName coordinate must be finite, got $doubleValue');
      }
      if (coordinateName == 'lat' && (doubleValue < -90 || doubleValue > 90)) {
        throw FormatException('Latitude must be between -90 and 90, got $doubleValue');
      }
      if (coordinateName == 'lon' && (doubleValue < -180 || doubleValue > 180)) {
        throw FormatException('Longitude must be between -180 and 180, got $doubleValue');
      }
      return doubleValue;
    }
    throw FormatException('$coordinateName coordinate must be a number, got ${value.runtimeType}');
  }

  static bool coordinatesEqual(jts.Coordinate a, jts.Coordinate b) {
    const double tolerance = 1e-10;
    return (a.x - b.x).abs() < tolerance && (a.y - b.y).abs() < tolerance;
  }
}
