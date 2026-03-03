import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import 'dart:convert';
import '../lib/models/course.dart';

void main() {
  group('Golf Features Shared Parsing', () {
    // Common test data template
    const baseWayJson = {
      'type': 'way',
      'id': 12345,
      'geometry': [
        {'lat': -41.2866, 'lon': 174.7772},
        {'lat': -41.2866, 'lon': 174.7775},
        {'lat': -41.2869, 'lon': 174.7775},
        {'lat': -41.2869, 'lon': 174.7772},
        {'lat': -41.2866, 'lon': 174.7772}, // Closed polygon
      ],
      'bounds': {
        'minlat': -41.2869,
        'minlon': 174.7772,
        'maxlat': -41.2866,
        'maxlon': 174.7775,
      }
    };

    test('Green.fromJson should use Way.fromJson shared logic', () {
      final greenJson = Map<String, dynamic>.from(baseWayJson);
      greenJson['tags'] = {'golf': 'green', 'surface': 'grass'};

      final green = Green.fromJson(greenJson);

      expect(green, isNotNull);
      expect(green!.id, equals(12345));
      expect(green.points, hasLength(5));
      expect(green.tags['golf'], equals('green'));
      expect(green.bounds, isNotNull);
      expect(green.polygon, isNotNull);
      expect(green.getArea(), greaterThan(0));
      expect(green.containsPoint(LatLng(-41.28675, 174.77735)), isTrue);
    });

    test('Fairway.fromJson should use Way.fromJson shared logic', () {
      final fairwayJson = Map<String, dynamic>.from(baseWayJson);
      fairwayJson['tags'] = {'golf': 'fairway', 'surface': 'grass'};

      final fairway = Fairway.fromJson(fairwayJson);

      expect(fairway, isNotNull);
      expect(fairway!.id, equals(12345));
      expect(fairway.points, hasLength(5));
      expect(fairway.tags['golf'], equals('fairway'));
      expect(fairway.bounds, isNotNull);
      expect(fairway.polygon, isNotNull);
      expect(fairway.getArea(), greaterThan(0));
      expect(fairway.containsPoint(LatLng(-41.28675, 174.77735)), isTrue);
    });

    test('Bunker.fromJson should use Way.fromJson shared logic', () {
      final bunkerJson = Map<String, dynamic>.from(baseWayJson);
      bunkerJson['tags'] = {'golf': 'bunker', 'surface': 'sand'};

      final bunker = Bunker.fromJson(bunkerJson);

      expect(bunker, isNotNull);
      expect(bunker!.id, equals(12345));
      expect(bunker.points, hasLength(5));
      expect(bunker.tags['golf'], equals('bunker'));
      expect(bunker.bounds, isNotNull);
      expect(bunker.polygon, isNotNull);
      expect(bunker.getArea(), greaterThan(0));
      expect(bunker.containsPoint(LatLng(-41.28675, 174.77735)), isTrue);
    });

    test('Hazard.fromJson should use Way.fromJson shared logic', () {
      final hazardJson = Map<String, dynamic>.from(baseWayJson);
      hazardJson['tags'] = {'golf': 'water_hazard', 'natural': 'water'};

      final hazard = Hazard.fromJson(hazardJson);

      expect(hazard, isNotNull);
      expect(hazard!.id, equals(12345));
      expect(hazard.points, hasLength(5));
      expect(hazard.tags['golf'], equals('water_hazard'));
      expect(hazard.getHazardType(), equals('water_hazard'));
      expect(hazard.bounds, isNotNull);
      expect(hazard.polygon, isNotNull);
      expect(hazard.getArea(), greaterThan(0));
      expect(hazard.containsPoint(LatLng(-41.28675, 174.77735)), isTrue);
    });

    test('should handle different hazard types', () {
      final lateralWaterJson = Map<String, dynamic>.from(baseWayJson);
      lateralWaterJson['tags'] = {'golf': 'lateral_water_hazard'};

      final lateralHazard = Hazard.fromJson(lateralWaterJson);
      expect(lateralHazard, isNotNull);
      expect(lateralHazard!.getHazardType(), equals('lateral_water_hazard'));

      final generalHazardJson = Map<String, dynamic>.from(baseWayJson);
      generalHazardJson['tags'] = {'golf': 'hazard'};

      final generalHazard = Hazard.fromJson(generalHazardJson);
      expect(generalHazard, isNotNull);
      expect(generalHazard!.getHazardType(), equals('hazard'));
    });

    test('all classes should reject invalid golf tags', () {
      final invalidJson = Map<String, dynamic>.from(baseWayJson);
      invalidJson['tags'] = {'golf': 'invalid_type'};

      expect(Green.fromJson(invalidJson), isNull);
      expect(Fairway.fromJson(invalidJson), isNull);
      expect(Bunker.fromJson(invalidJson), isNull);
      expect(Hazard.fromJson(invalidJson), isNull);
    });

    test('all classes should reject insufficient points', () {
      final insufficientJson = {
        'type': 'way',
        'id': 12345,
        'geometry': [
          {'lat': -41.2866, 'lon': 174.7772},
          {'lat': -41.2867, 'lon': 174.7773},
        ],
        'tags': {'golf': 'green'}
      };

      expect(Green.fromJson(insufficientJson), isNull);

      insufficientJson['tags'] = {'golf': 'fairway'};
      expect(Fairway.fromJson(insufficientJson), isNull);

      insufficientJson['tags'] = {'golf': 'bunker'};
      expect(Bunker.fromJson(insufficientJson), isNull);

      insufficientJson['tags'] = {'golf': 'water_hazard'};
      expect(Hazard.fromJson(insufficientJson), isNull);
    });

    test('should have consistent shared behavior across all classes', () {
      final testJson = Map<String, dynamic>.from(baseWayJson);

      // Test each class with their appropriate golf tag
      testJson['tags'] = {'golf': 'green'};
      final green = Green.fromJson(testJson);

      testJson['tags'] = {'golf': 'fairway'};
      final fairway = Fairway.fromJson(testJson);

      testJson['tags'] = {'golf': 'bunker'};
      final bunker = Bunker.fromJson(testJson);

      testJson['tags'] = {'golf': 'water_hazard'};
      final hazard = Hazard.fromJson(testJson);

      // All should have same geometry data since they use shared parsing
      expect(green!.points.length, equals(fairway!.points.length));
      expect(fairway.points.length, equals(bunker!.points.length));
      expect(bunker.points.length, equals(hazard!.points.length));

      // All should have same bounds since they use shared parsing
      expect(green.bounds?.southWest.latitude, equals(fairway.bounds?.southWest.latitude));
      expect(fairway.bounds?.southWest.latitude, equals(bunker.bounds?.southWest.latitude));
      expect(bunker.bounds?.southWest.latitude, equals(hazard.bounds?.southWest.latitude));

      // All should have same area calculation since they use shared polygons
      final expectedArea = green.getArea();
      expect(fairway.getArea(), equals(expectedArea));
      expect(bunker.getArea(), equals(expectedArea));
      expect(hazard.getArea(), equals(expectedArea));
    });

    test('should parse real Karori golf features if available', () async {
      final file = File('karori.json');
      if (!await file.exists()) {
        markTestSkipped('karori.json file not found');
        return;
      }

      final jsonString = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(jsonString);
      final List<dynamic> elements = data['elements'];

      // Find different golf features
      final greenWays = elements.where((e) =>
        e['type'] == 'way' && e['tags']?['golf'] == 'green'
      ).toList();

      final fairwayWays = elements.where((e) =>
        e['type'] == 'way' && e['tags']?['golf'] == 'fairway'
      ).toList();

      print('Found in Karori data:');
      print('  - Greens: ${greenWays.length}');
      print('  - Fairways: ${fairwayWays.length}');

      // Test parsing real greens
      if (greenWays.isNotEmpty) {
        final green = Green.fromJson(greenWays.first);
        expect(green, isNotNull);
        print('  - Sample green: ${green}');
      }

      // Test parsing real fairways
      if (fairwayWays.isNotEmpty) {
        final fairway = Fairway.fromJson(fairwayWays.first);
        expect(fairway, isNotNull);
        print('  - Sample fairway: ${fairway}');
      }
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}