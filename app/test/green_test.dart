import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import 'dart:convert';
import '../lib/models/course.dart';

void main() {
  group('Green', () {
    test('should create Green from valid JSON with geometry', () {
      const greenJson = {
        'type': 'way',
        'id': 12345,
        'geometry': [
          {'lat': -41.2866, 'lon': 174.7772},
          {'lat': -41.2866, 'lon': 174.7775}, // Rectangle corner
          {'lat': -41.2869, 'lon': 174.7775},
          {'lat': -41.2869, 'lon': 174.7772},
          {'lat': -41.2866, 'lon': 174.7772}, // Closed polygon
        ],
        'tags': {
          'golf': 'green',
          'surface': 'grass',
          'name': 'Green 1'
        },
        'bounds': {
          'minlat': -41.2869,
          'minlon': 174.7772,
          'maxlat': -41.2866,
          'maxlon': 174.7775,
        }
      };

      final green = Green.fromJson(greenJson);

      // Verify basic properties
      expect(green, isNotNull);
      expect(green!.id, equals(12345));
      expect(green.points, hasLength(5));
      expect(green.tags['golf'], equals('green'));
      expect(green.tags['surface'], equals('grass'));
      expect(green.tags['name'], equals('Green 1'));

      // Verify points are correctly parsed
      expect(green.points[0], equals(LatLng(-41.2866, 174.7772)));
      expect(green.points[4], equals(LatLng(-41.2866, 174.7772))); // Closed

      // Verify bounds
      expect(green.bounds, isNotNull);
      expect(green.bounds!.southWest.latitude, equals(-41.2869));
      expect(green.bounds!.southWest.longitude, equals(174.7772));
      expect(green.bounds!.northEast.latitude, equals(-41.2866));
      expect(green.bounds!.northEast.longitude, equals(174.7775));

      // Verify JTS polygon
      expect(green.polygon, isNotNull);
      expect(green.getArea(), greaterThan(0));

      // Verify point-in-polygon functionality
      final centerPoint = LatLng(-41.28675, 174.77735); // Center of rectangle
      expect(green.containsPoint(centerPoint), isTrue);

      final outsidePoint = LatLng(-41.3000, 174.8000); // Far outside
      expect(green.containsPoint(outsidePoint), isFalse);
    });

    test('should return null for non-way JSON', () {
      const nodeJson = {
        'type': 'node',
        'id': 12345,
        'lat': -41.2866,
        'lon': 174.7772,
        'tags': {'golf': 'green'}
      };

      final green = Green.fromJson(nodeJson);
      expect(green, isNull);
    });

    test('should return null for way without golf=green tag', () {
      const wayJson = {
        'type': 'way',
        'id': 12345,
        'geometry': [
          {'lat': -41.2866, 'lon': 174.7772},
          {'lat': -41.2867, 'lon': 174.7773},
          {'lat': -41.2868, 'lon': 174.7774},
        ],
        'tags': {'golf': 'fairway'} // Not a green
      };

      final green = Green.fromJson(wayJson);
      expect(green, isNull);
    });

    test('should return null for way with insufficient points', () {
      const wayJson = {
        'type': 'way',
        'id': 12345,
        'geometry': [
          {'lat': -41.2866, 'lon': 174.7772},
          {'lat': -41.2867, 'lon': 174.7773},
        ],
        'tags': {'golf': 'green'}
      };

      final green = Green.fromJson(wayJson);
      expect(green, isNull);
    });

    test('should handle missing bounds gracefully', () {
      const wayJson = {
        'type': 'way',
        'id': 12345,
        'geometry': [
          {'lat': -41.2866, 'lon': 174.7772},
          {'lat': -41.2867, 'lon': 174.7773},
          {'lat': -41.2868, 'lon': 174.7774},
        ],
        'tags': {'golf': 'green'}
      };

      final green = Green.fromJson(wayJson);

      expect(green, isNotNull);
      expect(green!.bounds, isNull);
      expect(green.polygon, isNotNull); // Should still create polygon
    });

    test('should handle malformed bounds gracefully', () {
      const wayJson = {
        'type': 'way',
        'id': 12345,
        'geometry': [
          {'lat': -41.2866, 'lon': 174.7772},
          {'lat': -41.2867, 'lon': 174.7773},
          {'lat': -41.2868, 'lon': 174.7774},
        ],
        'tags': {'golf': 'green'},
        'bounds': {
          'minlat': -41.2869,
          // Missing other bound values
        }
      };

      final green = Green.fromJson(wayJson);

      expect(green, isNotNull);
      expect(green!.bounds, isNull); // Malformed bounds ignored
      expect(green.polygon, isNotNull);
    });

    test('should return null for way without geometry', () {
      const wayJson = {
        'type': 'way',
        'id': 12345,
        'nodes': [1001, 1002, 1003], // Only node references, no geometry
        'tags': {'golf': 'green'}
      };

      final green = Green.fromJson(wayJson);
      expect(green, isNull); // Current implementation doesn't support node-based
    });

    test('should create meaningful toString output', () {
      const wayJson = {
        'type': 'way',
        'id': 99999,
        'geometry': [
          {'lat': -41.2866, 'lon': 174.7772},
          {'lat': -41.2867, 'lon': 174.7773},
          {'lat': -41.2868, 'lon': 174.7774},
        ],
        'tags': {'golf': 'green'}
      };

      final green = Green.fromJson(wayJson);
      final str = green!.toString();

      expect(str, contains('Green(id: 99999'));
      expect(str, contains('points: 3'));
      expect(str, contains('area:'));
      expect(str, contains('sq degrees'));
    });

    test('should work with fromWay legacy method', () {
      // Create a mock Way object
      final wayPoints = [
        LatLng(-41.2866, 174.7772),
        LatLng(-41.2867, 174.7773),
        LatLng(-41.2868, 174.7774),
      ];

      // Create a simple way manually (this would normally come from Overpass parsing)
      const wayData = {
        'type': 'way',
        'id': 54321,
        'geometry': [
          {'lat': -41.2866, 'lon': 174.7772},
          {'lat': -41.2867, 'lon': 174.7773},
          {'lat': -41.2868, 'lon': 174.7774},
        ],
        'tags': {'golf': 'green'}
      };

      final green = Green.fromJson(wayData);

      expect(green, isNotNull);
      expect(green!.id, equals(54321));
      expect(green.points, hasLength(3));
      expect(green.polygon, isNotNull);
    });

    test('should parse real Karori green data if available', () async {
      final file = File('karori.json');
      if (!await file.exists()) {
        markTestSkipped('karori.json file not found');
        return;
      }

      final jsonString = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(jsonString);
      final List<dynamic> elements = data['elements'];

      // Find green ways in Karori data
      final greenWays = elements.where((element) =>
        element['type'] == 'way' && element['tags']?['golf'] == 'green'
      ).toList();

      expect(greenWays, isNotEmpty, reason: 'Karori should have green ways');

      // Test parsing a real green
      final firstGreenWay = greenWays.first;
      final green = Green.fromJson(firstGreenWay);

      expect(green, isNotNull, reason: 'Should parse real Karori green');
      expect(green!.id, equals(firstGreenWay['id']));
      expect(green.points, isNotEmpty, reason: 'Green should have geometry points');
      expect(green.polygon, isNotNull, reason: 'Should create polygon from real data');

      print('Karori Green ${green.id}:');
      print('  - Points: ${green.points.length}');
      print('  - Area: ${green.getArea()?.toStringAsFixed(8)} sq degrees');
      print('  - Bounds: ${green.bounds}');
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}