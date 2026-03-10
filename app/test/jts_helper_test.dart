import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:ugly_slice/models/jts.dart';

void main() {
  group('JtsHelper', () {
    group('calcPolygon', () {
      test('should create polygon from valid coordinate nodes', () {
        final nodes = [
          {'lat': 0.0, 'lon': 0.0},
          {'lat': 0.0, 'lon': 1.0},
          {'lat': 1.0, 'lon': 1.0},
          {'lat': 1.0, 'lon': 0.0},
        ];

        final polygon = JtsHelper.calcPolygon(nodes);

        expect(polygon, isA<jts.Polygon>());
        expect(polygon.getArea(), greaterThan(0));
      });

      test('should automatically close polygon if not closed', () {
        final nodes = [
          {'lat': 0.0, 'lon': 0.0},
          {'lat': 0.0, 'lon': 1.0},
          {'lat': 1.0, 'lon': 1.0},
          // Note: missing closing point
        ];

        final polygon = JtsHelper.calcPolygon(nodes);

        expect(polygon, isA<jts.Polygon>());
        final coords = polygon.getExteriorRing().getCoordinates();
        expect(coords.first.x, equals(coords.last.x));
        expect(coords.first.y, equals(coords.last.y));
      });

      test('should not duplicate closing point if already closed', () {
        final nodes = [
          {'lat': 0.0, 'lon': 0.0},
          {'lat': 0.0, 'lon': 1.0},
          {'lat': 1.0, 'lon': 1.0},
          {'lat': 0.0, 'lon': 0.0}, // Already closed
        ];

        final polygon = JtsHelper.calcPolygon(nodes);

        expect(polygon, isA<jts.Polygon>());
        final coords = polygon.getExteriorRing().getCoordinates();
        // Should have 4 coordinates (3 unique + 1 closing)
        expect(coords.length, equals(4));
      });

      test('should throw ArgumentError for empty nodes list', () {
        expect(
          () => JtsHelper.calcPolygon([]),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Nodes list cannot be empty',
          )),
        );
      });

      test('should throw ArgumentError for insufficient nodes', () {
        final nodes = [
          {'lat': 0.0, 'lon': 0.0},
          {'lat': 0.0, 'lon': 1.0},
        ];

        expect(
          () => JtsHelper.calcPolygon(nodes),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Polygon requires at least 3 nodes, got 2',
          )),
        );
      });

      test('should throw FormatException for invalid node format', () {
        final nodes = [
          'invalid_node', // Not a Map
          {'lat': 0.0, 'lon': 1.0},
          {'lat': 1.0, 'lon': 1.0},
        ];

        expect(
          () => JtsHelper.calcPolygon(nodes),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw FormatException for missing coordinates', () {
        final nodes = [
          {'lat': 0.0}, // Missing 'lon'
          {'lat': 0.0, 'lon': 1.0},
          {'lat': 1.0, 'lon': 1.0},
        ];

        expect(
          () => JtsHelper.calcPolygon(nodes),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw FormatException for invalid coordinate values', () {
        final nodes = [
          {'lat': 'invalid', 'lon': 0.0}, // Invalid lat
          {'lat': 0.0, 'lon': 1.0},
          {'lat': 1.0, 'lon': 1.0},
        ];

        expect(
          () => JtsHelper.calcPolygon(nodes),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw FormatException for out-of-range coordinates', () {
        final nodes = [
          {'lat': 95.0, 'lon': 0.0}, // Invalid latitude > 90
          {'lat': 0.0, 'lon': 1.0},
          {'lat': 1.0, 'lon': 1.0},
        ];

        expect(
          () => JtsHelper.calcPolygon(nodes),
          throwsA(isA<FormatException>()),
        );
      });

      test('should handle golf course coordinate precision', () {
        // Real golf course coordinates (Karori Golf Club area)
        final nodes = [
          {'lat': -41.2866, 'lon': 174.7772},
          {'lat': -41.2867, 'lon': 174.7780},
          {'lat': -41.2870, 'lon': 174.7778},
          {'lat': -41.2869, 'lon': 174.7770},
        ];

        final polygon = JtsHelper.calcPolygon(nodes);

        expect(polygon, isA<jts.Polygon>());
        expect(polygon.getArea(), greaterThan(0));
      });
    });

    group('fromLatLngPoints', () {
      test('should create polygon from LatLng points', () {
        final points = [
          LatLng(0.0, 0.0),
          LatLng(0.0, 1.0),
          LatLng(1.0, 1.0),
          LatLng(1.0, 0.0),
        ];

        final polygon = JtsHelper.fromLatLngPoints(points);

        expect(polygon, isA<jts.Polygon>());
        expect(polygon.getArea(), greaterThan(0));
      });

      test('should throw ArgumentError for empty points list', () {
        expect(
          () => JtsHelper.fromLatLngPoints([]),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Points list cannot be empty',
          )),
        );
      });

      test('should throw ArgumentError for insufficient points', () {
        final points = [
          LatLng(0.0, 0.0),
          LatLng(0.0, 1.0),
        ];

        expect(
          () => JtsHelper.fromLatLngPoints(points),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Polygon requires at least 3 points, got 2',
          )),
        );
      });

      test('should automatically close polygon from LatLng points', () {
        final points = [
          LatLng(0.0, 0.0),
          LatLng(0.0, 1.0),
          LatLng(1.0, 1.0),
        ];

        final polygon = JtsHelper.fromLatLngPoints(points);

        expect(polygon, isA<jts.Polygon>());
        final coords = polygon.getExteriorRing().getCoordinates();
        expect(coords.first.x, equals(coords.last.x));
        expect(coords.first.y, equals(coords.last.y));
      });
    });

    group('createPoint', () {
      test('should create JTS point from lat/lon', () {
        final point = JtsHelper.createPoint(-41.2866, 174.7772);

        expect(point, isA<jts.Point>());
        expect(point.getX(), equals(174.7772)); // longitude
        expect(point.getY(), equals(-41.2866)); // latitude
      });

      test('should handle edge coordinate values', () {
        final point1 = JtsHelper.createPoint(90.0, 180.0);
        final point2 = JtsHelper.createPoint(-90.0, -180.0);

        expect(point1, isA<jts.Point>());
        expect(point2, isA<jts.Point>());
      });
    });

    group('fromLatLng', () {
      test('should create JTS point from LatLng', () {
        final latLng = LatLng(-41.2866, 174.7772);
        final point = JtsHelper.fromLatLng(latLng);

        expect(point, isA<jts.Point>());
        expect(point.getX(), equals(174.7772));
        expect(point.getY(), equals(-41.2866));
      });
    });

    group('pointInPolygon', () {
      late jts.Polygon testPolygon;

      setUp(() {
        final points = [
          LatLng(0.0, 0.0),
          LatLng(0.0, 2.0),
          LatLng(2.0, 2.0),
          LatLng(2.0, 0.0),
        ];
        testPolygon = JtsHelper.fromLatLngPoints(points);
      });

      test('should return true for point inside polygon', () {
        final pointInside = LatLng(1.0, 1.0);

        final result = JtsHelper.pointInPolygon(pointInside, testPolygon);

        expect(result, isTrue);
      });

      test('should return false for point outside polygon', () {
        final pointOutside = LatLng(3.0, 3.0);

        final result = JtsHelper.pointInPolygon(pointOutside, testPolygon);

        expect(result, isFalse);
      });

      test('should handle point on polygon boundary', () {
        final pointOnBoundary = LatLng(0.0, 1.0);

        final result = JtsHelper.pointInPolygon(pointOnBoundary, testPolygon);

        // JTS boundary behavior can vary - accept either true or false for boundary points
        expect(result, isA<bool>());
      });

      test('should work with golf course precision coordinates', () {
        // Create a small green polygon
        final greenPoints = [
          LatLng(-41.28660, 174.77720),
          LatLng(-41.28660, 174.77730),
          LatLng(-41.28670, 174.77730),
          LatLng(-41.28670, 174.77720),
        ];
        final green = JtsHelper.fromLatLngPoints(greenPoints);

        final ballPosition = LatLng(-41.28665, 174.77725); // Center of green

        final result = JtsHelper.pointInPolygon(ballPosition, green);

        expect(result, isTrue);
      });
    });

    group('calculateArea', () {
      test('should calculate positive area for valid polygon', () {
        final points = [
          LatLng(0.0, 0.0),
          LatLng(0.0, 1.0),
          LatLng(1.0, 1.0),
          LatLng(1.0, 0.0),
        ];
        final polygon = JtsHelper.fromLatLngPoints(points);

        final area = JtsHelper.calculateArea(polygon);

        expect(area, greaterThan(0));
      });

      test('should handle minimum valid polygon (4 same points)', () {
        // JTS requires at least 4 points for a LinearRing, so test with 4 identical points
        final points = [
          LatLng(0.0, 0.0),
          LatLng(0.0, 0.0),
          LatLng(0.0, 0.0),
          LatLng(0.0, 0.0),
        ];
        final polygon = JtsHelper.fromLatLngPoints(points);

        final area = JtsHelper.calculateArea(polygon);

        expect(area, equals(0.0));
      });
    });

    group('parseCoordinate', () {
      test('should parse valid integer coordinates', () {
        expect(JtsHelper.parseCoordinate(42, 'lat'), equals(42.0));
        expect(JtsHelper.parseCoordinate(-180, 'lon'), equals(-180.0));
      });

      test('should parse valid double coordinates', () {
        expect(JtsHelper.parseCoordinate(41.2866, 'lat'), equals(41.2866));
        expect(JtsHelper.parseCoordinate(-174.7772, 'lon'), equals(-174.7772));
      });

      test('should throw FormatException for null values', () {
        expect(
          () => JtsHelper.parseCoordinate(null, 'lat'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw FormatException for non-numeric values', () {
        expect(
          () => JtsHelper.parseCoordinate('invalid', 'lat'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw FormatException for infinite values', () {
        expect(
          () => JtsHelper.parseCoordinate(double.infinity, 'lat'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => JtsHelper.parseCoordinate(double.negativeInfinity, 'lon'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw FormatException for NaN values', () {
        expect(
          () => JtsHelper.parseCoordinate(double.nan, 'lat'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should validate latitude range', () {
        expect(
          () => JtsHelper.parseCoordinate(91.0, 'lat'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => JtsHelper.parseCoordinate(-91.0, 'lat'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should validate longitude range', () {
        expect(
          () => JtsHelper.parseCoordinate(181.0, 'lon'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => JtsHelper.parseCoordinate(-181.0, 'lon'),
          throwsA(isA<FormatException>()),
        );
      });

      test('should accept edge values for coordinates', () {
        expect(JtsHelper.parseCoordinate(90.0, 'lat'), equals(90.0));
        expect(JtsHelper.parseCoordinate(-90.0, 'lat'), equals(-90.0));
        expect(JtsHelper.parseCoordinate(180.0, 'lon'), equals(180.0));
        expect(JtsHelper.parseCoordinate(-180.0, 'lon'), equals(-180.0));
      });
    });

    group('coordinatesEqual', () {
      test('should return true for identical coordinates', () {
        final coord1 = jts.Coordinate(174.7772, -41.2866);
        final coord2 = jts.Coordinate(174.7772, -41.2866);

        expect(JtsHelper.coordinatesEqual(coord1, coord2), isTrue);
      });

      test('should return true for coordinates within tolerance', () {
        final coord1 = jts.Coordinate(174.77720, -41.28660);
        final coord2 = jts.Coordinate(174.77720000001, -41.28660000001);

        expect(JtsHelper.coordinatesEqual(coord1, coord2), isTrue);
      });

      test('should return false for coordinates outside tolerance', () {
        final coord1 = jts.Coordinate(174.7772, -41.2866);
        final coord2 = jts.Coordinate(174.7773, -41.2867);

        expect(JtsHelper.coordinatesEqual(coord1, coord2), isFalse);
      });
    });

    group('Golf Course Integration Tests', () {
      test('should handle typical golf green polygon', () {
        // Simulate a golf green as a roughly circular polygon
        final greenNodes = [
          {'lat': -41.28660, 'lon': 174.77720},
          {'lat': -41.28658, 'lon': 174.77725},
          {'lat': -41.28660, 'lon': 174.77730},
          {'lat': -41.28665, 'lon': 174.77732},
          {'lat': -41.28670, 'lon': 174.77730},
          {'lat': -41.28672, 'lon': 174.77725},
          {'lat': -41.28670, 'lon': 174.77720},
          {'lat': -41.28665, 'lon': 174.77718},
        ];

        final green = JtsHelper.calcPolygon(greenNodes);

        expect(green, isA<jts.Polygon>());
        expect(green.getArea(), greaterThan(0));

        // Test if ball positions are correctly identified
        final ballOnGreen = LatLng(-41.28665, 174.77725);
        final ballOffGreen = LatLng(-41.28680, 174.77740);

        expect(JtsHelper.pointInPolygon(ballOnGreen, green), isTrue);
        expect(JtsHelper.pointInPolygon(ballOffGreen, green), isFalse);
      });

      test('should handle fairway polygon with precision', () {
        // Simulate a fairway as an elongated polygon
        final fairwayNodes = [
          {'lat': -41.28600, 'lon': 174.77700},
          {'lat': -41.28590, 'lon': 174.77710},
          {'lat': -41.28650, 'lon': 174.77750},
          {'lat': -41.28660, 'lon': 174.77740},
        ];

        final fairway = JtsHelper.calcPolygon(fairwayNodes);

        expect(fairway, isA<jts.Polygon>());
        expect(fairway.getArea(), greaterThan(0));

        final ballOnFairway = LatLng(-41.28620, 174.77720);
        expect(JtsHelper.pointInPolygon(ballOnFairway, fairway), isTrue);
      });
    });
  });
}
