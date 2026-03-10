import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'overpass.dart';

/// Helper class for converting geographic data to JTS geometries.
class JtsHelper {
  static final jts.GeometryFactory _factory = jts.GeometryFactory(
    jts.PrecisionModel(),
    0,
    jts.CoordinateArraySequenceFactory(),
  );

  static jts.Polygon calcPolygon(List<dynamic> nodes) {
    if (nodes.isEmpty) throw ArgumentError('Nodes list cannot be empty');
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
      final shell = _factory.createLinearRing(coords);
      return _factory.createPolygon(shell, null);
    } catch (e) {
      throw FormatException('Failed to create polygon: $e');
    }
  }

  static jts.Polygon fromLatLngPoints(List<LatLng> points) {
    if (points.isEmpty) throw ArgumentError('Points list cannot be empty');
    if (points.length < 3) {
      throw ArgumentError('Polygon requires at least 3 points, got ${points.length}');
    }
    final coords = points
        .map((p) => jts.Coordinate(p.longitude, p.latitude))
        .toList();
    if (!coordinatesEqual(coords.first, coords.last)) coords.add(coords.first);
    final shell = _factory.createLinearRing(coords);
    return _factory.createPolygon(shell, null);
  }

  static jts.Point createPoint(double lat, double lon) =>
      _factory.createPoint(jts.Coordinate(lon, lat));

  static jts.Point fromLatLng(LatLng latLng) =>
      createPoint(latLng.latitude, latLng.longitude);

  static bool pointInPolygon(LatLng point, jts.Polygon polygon) =>
      polygon.contains(fromLatLng(point));

  static double calculateArea(jts.Polygon polygon) => polygon.getArea();

  static jts.Polygon fromWay(Way way) {
    if (way.points.isEmpty) throw ArgumentError('Way points cannot be empty');
    return fromLatLngPoints(way.points);
  }

  static double parseCoordinate(dynamic value, String coordinateName) {
    if (value == null) throw FormatException('$coordinateName coordinate cannot be null');
    if (value is num) {
      final v = value.toDouble();
      if (!v.isFinite) throw FormatException('$coordinateName must be finite, got $v');
      if (coordinateName == 'lat' && (v < -90 || v > 90)) {
        throw FormatException('Latitude must be between -90 and 90, got $v');
      }
      if (coordinateName == 'lon' && (v < -180 || v > 180)) {
        throw FormatException('Longitude must be between -180 and 180, got $v');
      }
      return v;
    }
    throw FormatException('$coordinateName must be a number, got ${value.runtimeType}');
  }

  static bool coordinatesEqual(jts.Coordinate a, jts.Coordinate b) {
    const double tolerance = 1e-10;
    return (a.x - b.x).abs() < tolerance && (a.y - b.y).abs() < tolerance;
  }
}
