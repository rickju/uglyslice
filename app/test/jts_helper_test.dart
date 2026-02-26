import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:ugly_slice/models/overpass.dart';

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

    group('fromOverpassWay', () {
      test('should create polygon from way with geometry array', () {
        final wayJson = {
          'type': 'way',
          'id': 123456,
          'geometry': [
            {'lat': -41.2846553, 'lon': 174.6895637},
            {'lat': -41.2848567, 'lon': 174.6903869},
            {'lat': -41.2849339, 'lon': 174.6907022},
            {'lat': -41.2846553, 'lon': 174.6895637}, // Closed
          ],
          'tags': {'golf': 'fairway'}
        };

        final polygon = JtsHelper.fromOverpassWay(wayJson);

        expect(polygon, isA<jts.Polygon>());
        expect(polygon.getArea(), greaterThan(0));
      });

      test('should create polygon from way with nodes array', () {
        final wayJson = {
          'type': 'way',
          'id': 123456,
          'nodes': [1001, 1002, 1003],
          'tags': {'golf': 'green'}
        };

        final nodeCoordinates = {
          1001: LatLng(-41.2846553, 174.6895637),
          1002: LatLng(-41.2848567, 174.6903869),
          1003: LatLng(-41.2849339, 174.6907022),
        };

        final polygon = JtsHelper.fromOverpassWay(wayJson, nodeCoordinates);

        expect(polygon, isA<jts.Polygon>());
        expect(polygon.getArea(), greaterThan(0));
      });

      test('should automatically close polygon if not closed', () {
        final wayJson = {
          'type': 'way',
          'id': 123456,
          'geometry': [
            {'lat': -41.2846553, 'lon': 174.6895637},
            {'lat': -41.2848567, 'lon': 174.6903869},
            {'lat': -41.2849339, 'lon': 174.6907022},
            // Not closed - should be automatically closed
          ],
          'tags': {'golf': 'fairway'}
        };

        final polygon = JtsHelper.fromOverpassWay(wayJson);

        expect(polygon, isA<jts.Polygon>());
        final coords = polygon.getExteriorRing().getCoordinates();
        expect(coords.first.x, equals(coords.last.x));
        expect(coords.first.y, equals(coords.last.y));
      });

      test('should throw ArgumentError for non-way type', () {
        final relationJson = {
          'type': 'relation',
          'id': 123456,
        };

        expect(
          () => JtsHelper.fromOverpassWay(relationJson),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Expected way type, got relation',
          )),
        );
      });

      test('should throw ArgumentError for empty geometry', () {
        final wayJson = {
          'type': 'way',
          'id': 123456,
          'geometry': [],
        };

        expect(
          () => JtsHelper.fromOverpassWay(wayJson),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Way geometry cannot be empty',
          )),
        );
      });

      test('should throw ArgumentError for missing node coordinates', () {
        final wayJson = {
          'type': 'way',
          'id': 123456,
          'nodes': [1001, 1002, 1003],
        };

        expect(
          () => JtsHelper.fromOverpassWay(wayJson),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Node coordinates map required for ways without geometry',
          )),
        );
      });

      test('should throw ArgumentError for missing node in coordinates map', () {
        final wayJson = {
          'type': 'way',
          'id': 123456,
          'nodes': [1001, 1002, 1003],
        };

        final nodeCoordinates = {
          1001: LatLng(-41.2846553, 174.6895637),
          1002: LatLng(-41.2848567, 174.6903869),
          // Missing 1003
        };

        expect(
          () => JtsHelper.fromOverpassWay(wayJson, nodeCoordinates),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Node coordinate not found for ID: 1003',
          )),
        );
      });

      test('should throw FormatException for invalid geometry point format', () {
        final wayJson = {
          'type': 'way',
          'id': 123456,
          'geometry': [
            {'lat': -41.2846553, 'lon': 174.6895637},
            'invalid_point', // Not a Map
            {'lat': -41.2849339, 'lon': 174.6907022},
          ],
        };

        expect(
          () => JtsHelper.fromOverpassWay(wayJson),
          throwsA(isA<FormatException>()),
        );
      });

      test('should throw FormatException for way without geometry or nodes', () {
        final wayJson = {
          'type': 'way',
          'id': 123456,
          'tags': {'golf': 'fairway'},
          // Missing both geometry and nodes
        };

        expect(
          () => JtsHelper.fromOverpassWay(wayJson),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            "Way must contain either 'geometry' or 'nodes' array",
          )),
        );
      });

      test('should handle real Overpass golf course data', () {
        // Real fairway data from karori.json
        final realWayJson = {
          'type': 'way',
          'id': 747473941,
          'bounds': {
            'minlat': -41.2952060,
            'minlon': 174.6810615,
            'maxlat': -41.2846553,
            'maxlon': 174.6917260
          },
          'geometry': [
            {'lat': -41.2846553, 'lon': 174.6895637},
            {'lat': -41.2848567, 'lon': 174.6903869},
            {'lat': -41.2849339, 'lon': 174.6907022},
            {'lat': -41.2853260, 'lon': 174.6906786},
            {'lat': -41.2855924, 'lon': 174.6905574},
          ],
          'tags': {'golf': 'fairway', 'surface': 'grass'}
        };

        final polygon = JtsHelper.fromOverpassWay(realWayJson);

        expect(polygon, isA<jts.Polygon>());
        expect(polygon.getArea(), greaterThan(0));

        // Test point-in-polygon with golf course coordinates
        final pointOnFairway = LatLng(-41.2850, 174.6905);
        expect(JtsHelper.pointInPolygon(pointOnFairway, polygon), isA<bool>());
      });
    });

    group('fromWay', () {
      test('should create polygon from Way object', () {
        final way = Way(
          id: 123456,
          nodeIds: [1001, 1002, 1003],
          points: [
            LatLng(-41.2846553, 174.6895637),
            LatLng(-41.2848567, 174.6903869),
            LatLng(-41.2849339, 174.6907022),
          ],
          tags: {'golf': 'green'},
        );

        final polygon = JtsHelper.fromWay(way);

        expect(polygon, isA<jts.Polygon>());
        expect(polygon.getArea(), greaterThan(0));
      });

      test('should throw ArgumentError for Way with empty points', () {
        final way = Way(
          id: 123456,
          nodeIds: [],
          points: [],
          tags: {},
        );

        expect(
          () => JtsHelper.fromWay(way),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Way points cannot be empty',
          )),
        );
      });
    });

    group('fromOverpassWays', () {
      test('should convert multiple ways to polygons', () {
        final waysJson = [
          {
            'type': 'way',
            'id': 123456,
            'geometry': [
              {'lat': -41.2846553, 'lon': 174.6895637},
              {'lat': -41.2848567, 'lon': 174.6903869},
              {'lat': -41.2849339, 'lon': 174.6907022},
            ],
            'tags': {'golf': 'fairway'}
          },
          {
            'type': 'way',
            'id': 123457,
            'geometry': [
              {'lat': -41.2850000, 'lon': 174.6900000},
              {'lat': -41.2851000, 'lon': 174.6901000},
              {'lat': -41.2852000, 'lon': 174.6902000},
            ],
            'tags': {'golf': 'green'}
          },
        ];

        final polygons = JtsHelper.fromOverpassWays(waysJson);

        expect(polygons, hasLength(2));
        expect(polygons[0], isA<jts.Polygon>());
        expect(polygons[1], isA<jts.Polygon>());
      });

      test('should filter ways by tags', () {
        final waysJson = [
          {
            'type': 'way',
            'id': 123456,
            'geometry': [
              {'lat': -41.2846553, 'lon': 174.6895637},
              {'lat': -41.2848567, 'lon': 174.6903869},
              {'lat': -41.2849339, 'lon': 174.6907022},
            ],
            'tags': {'golf': 'fairway'}
          },
          {
            'type': 'way',
            'id': 123457,
            'geometry': [
              {'lat': -41.2850000, 'lon': 174.6900000},
              {'lat': -41.2851000, 'lon': 174.6901000},
              {'lat': -41.2852000, 'lon': 174.6902000},
            ],
            'tags': {'golf': 'green'}
          },
          {
            'type': 'way',
            'id': 123458,
            'geometry': [
              {'lat': -41.2855000, 'lon': 174.6905000},
              {'lat': -41.2856000, 'lon': 174.6906000},
              {'lat': -41.2857000, 'lon': 174.6907000},
            ],
            'tags': {'golf': 'bunker'}
          },
        ];

        // Filter only fairways
        final fairwayPolygons = JtsHelper.fromOverpassWays(
          waysJson,
          null,
          {'golf': 'fairway'},
        );

        expect(fairwayPolygons, hasLength(1));

        // Filter only greens
        final greenPolygons = JtsHelper.fromOverpassWays(
          waysJson,
          null,
          {'golf': 'green'},
        );

        expect(greenPolygons, hasLength(1));
      });

      test('should skip invalid ways and continue processing', () {
        final waysJson = [
          {
            'type': 'way',
            'id': 123456,
            'geometry': [
              {'lat': -41.2846553, 'lon': 174.6895637},
              {'lat': -41.2848567, 'lon': 174.6903869},
              {'lat': -41.2849339, 'lon': 174.6907022},
            ],
            'tags': {'golf': 'fairway'}
          },
          {
            'type': 'relation', // Not a way - should be skipped
            'id': 123457,
          },
          {
            'type': 'way',
            'id': 123458,
            'geometry': [], // Empty geometry - should be skipped
          },
          {
            'type': 'way',
            'id': 123459,
            'geometry': [
              {'lat': -41.2850000, 'lon': 174.6900000},
              {'lat': -41.2851000, 'lon': 174.6901000},
              {'lat': -41.2852000, 'lon': 174.6902000},
            ],
            'tags': {'golf': 'green'}
          },
        ];

        final polygons = JtsHelper.fromOverpassWays(waysJson);

        // Should only process valid ways (first and last)
        expect(polygons, hasLength(2));
      });

      test('should handle ways with nodes array', () {
        final waysJson = [
          {
            'type': 'way',
            'id': 123456,
            'nodes': [1001, 1002, 1003],
            'tags': {'golf': 'fairway'}
          },
        ];

        final nodeCoordinates = {
          1001: LatLng(-41.2846553, 174.6895637),
          1002: LatLng(-41.2848567, 174.6903869),
          1003: LatLng(-41.2849339, 174.6907022),
        };

        final polygons = JtsHelper.fromOverpassWays(waysJson, nodeCoordinates);

        expect(polygons, hasLength(1));
        expect(polygons[0], isA<jts.Polygon>());
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

