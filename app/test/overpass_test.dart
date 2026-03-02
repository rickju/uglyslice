import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ugly_slice/models/overpass.dart';

void main() {
  group('Node', () {
    test('should create node from constructor', () {
      final node = Node(
        id: 12345,
        lat: -41.2866,
        lon: 174.7772,
        tags: {'golf': 'pin', 'name': 'Hole 1'},
      );

      expect(node.id, equals(12345));
      expect(node.lat, equals(-41.2866));
      expect(node.lon, equals(174.7772));
      expect(node.tags['golf'], equals('pin'));
      expect(node.tags['name'], equals('Hole 1'));
    });

    test('should create node from JSON', () {
      final json = {
        'id': 67890,
        'lat': -41.2867,
        'lon': 174.7773,
        'tags': {'golf': 'tee', 'tee': 'blue'},
      };

      final node = Node.fromJson(json);

      expect(node.id, equals(67890));
      expect(node.lat, equals(-41.2867));
      expect(node.lon, equals(174.7773));
      expect(node.tags['golf'], equals('tee'));
      expect(node.tags['tee'], equals('blue'));
    });

    test('should create node from JSON with empty tags', () {
      final json = {
        'id': 11111,
        'lat': -41.2868,
        'lon': 174.7774,
      };

      final node = Node.fromJson(json);

      expect(node.id, equals(11111));
      expect(node.lat, equals(-41.2868));
      expect(node.lon, equals(174.7774));
      expect(node.tags, isEmpty);
    });

    test('should convert to LatLng', () {
      final node = Node(
        id: 12345,
        lat: -41.2866,
        lon: 174.7772,
        tags: {},
      );

      final latLng = node.toLatLng();

      expect(latLng.latitude, equals(-41.2866));
      expect(latLng.longitude, equals(174.7772));
    });

    test('should have meaningful toString', () {
      final node = Node(
        id: 12345,
        lat: -41.2866,
        lon: 174.7772,
        tags: {'golf': 'pin'},
      );

      final str = node.toString();

      expect(str, contains('12345'));
      expect(str, contains('golf'));
      expect(str, contains('pin'));
    });
  });

  group('Way', () {
    final nodeCoordinates = {
      1001: LatLng(-41.2866, 174.7772),
      1002: LatLng(-41.2867, 174.7773),
      1003: LatLng(-41.2868, 174.7774),
      1004: LatLng(-41.2869, 174.7775),
    };

    test('should create way from constructor', () {
      final way = Way(
        id: 23456,
        nodeIds: [1001, 1002, 1003],
        points: [
          LatLng(-41.2866, 174.7772),
          LatLng(-41.2867, 174.7773),
          LatLng(-41.2868, 174.7774),
        ],
        tags: {'golf': 'fairway'},
      );

      expect(way.id, equals(23456));
      expect(way.nodeIds, equals([1001, 1002, 1003]));
      expect(way.points, hasLength(3));
      expect(way.tags['golf'], equals('fairway'));
    });

    test('should create way from JSON with all valid nodes', () {
      final json = {
        'id': 34567,
        'nodes': [1001, 1002, 1003],
        'tags': {'golf': 'green'},
      };

      final way = Way.fromJson(json, nodeCoordinates);

      expect(way.id, equals(34567));
      expect(way.nodeIds, equals([1001, 1002, 1003]));
      expect(way.points, hasLength(3));
      expect(way.points[0], equals(LatLng(-41.2866, 174.7772)));
      expect(way.points[1], equals(LatLng(-41.2867, 174.7773)));
      expect(way.points[2], equals(LatLng(-41.2868, 174.7774)));
      expect(way.tags['golf'], equals('green'));
    });

    test('should create way from JSON filtering out missing nodes', () {
      final json = {
        'id': 34567,
        'nodes': [1001, 9999, 1003, 8888], // 9999 and 8888 don't exist
        'tags': {'golf': 'bunker'},
      };

      final way = Way.fromJson(json, nodeCoordinates);

      expect(way.id, equals(34567));
      expect(way.nodeIds, equals([1001, 1003])); // Only valid nodes
      expect(way.points, hasLength(2));
      expect(way.points[0], equals(LatLng(-41.2866, 174.7772)));
      expect(way.points[1], equals(LatLng(-41.2868, 174.7774)));
      expect(way.tags['golf'], equals('bunker'));
    });

    test('should create way from JSON with empty tags', () {
      final json = {
        'id': 45678,
        'nodes': [1001, 1002],
      };

      final way = Way.fromJson(json, nodeCoordinates);

      expect(way.id, equals(45678));
      expect(way.nodeIds, equals([1001, 1002]));
      expect(way.points, hasLength(2));
      expect(way.tags, isEmpty);
    });

    test('should handle empty nodes list', () {
      final json = {
        'id': 56789,
        'nodes': <int>[],
        'tags': {'golf': 'hole'},
      };

      final way = Way.fromJson(json, nodeCoordinates);

      expect(way.id, equals(56789));
      expect(way.nodeIds, isEmpty);
      expect(way.points, isEmpty);
      expect(way.tags['golf'], equals('hole'));
    });

    test('should have meaningful toString', () {
      final way = Way(
        id: 23456,
        nodeIds: [1001, 1002],
        points: [LatLng(-41.2866, 174.7772), LatLng(-41.2867, 174.7773)],
        tags: {'golf': 'fairway'},
      );

      final str = way.toString();

      expect(str, contains('23456'));
      expect(str, contains('1001'));
      expect(str, contains('1002'));
      expect(str, contains('golf'));
      expect(str, contains('fairway'));
    });
  });

  group('Relation', () {
    final nodeCoordinates = {
      2001: LatLng(-41.2870, 174.7776),
      2002: LatLng(-41.2871, 174.7777),
      2003: LatLng(-41.2872, 174.7778),
    };

    test('should create relation from constructor', () {
      final relation = Relation(
        id: 78901,
        nodeIds: [2001, 2002, 2003],
        points: [
          LatLng(-41.2870, 174.7776),
          LatLng(-41.2871, 174.7777),
          LatLng(-41.2872, 174.7778),
        ],
        tags: {'type': 'multipolygon', 'golf': 'course'},
      );

      expect(relation.id, equals(78901));
      expect(relation.nodeIds, equals([2001, 2002, 2003]));
      expect(relation.points, hasLength(3));
      expect(relation.tags['type'], equals('multipolygon'));
      expect(relation.tags['golf'], equals('course'));
    });

    test('should create relation from JSON with all valid nodes', () {
      final json = {
        'id': 89012,
        'nodes': [2001, 2002, 2003],
        'tags': {'type': 'route', 'golf': 'hole'},
      };

      final relation = Relation.fromJson(json, nodeCoordinates);

      expect(relation.id, equals(89012));
      expect(relation.nodeIds, equals([2001, 2002, 2003]));
      expect(relation.points, hasLength(3));
      expect(relation.points[0], equals(LatLng(-41.2870, 174.7776)));
      expect(relation.points[1], equals(LatLng(-41.2871, 174.7777)));
      expect(relation.points[2], equals(LatLng(-41.2872, 174.7778)));
      expect(relation.tags['type'], equals('route'));
      expect(relation.tags['golf'], equals('hole'));
    });

    test('should create relation from JSON filtering out missing nodes', () {
      final json = {
        'id': 90123,
        'nodes': [2001, 7777, 2003], // 7777 doesn't exist
        'tags': {'golf': 'water_hazard'},
      };

      final relation = Relation.fromJson(json, nodeCoordinates);

      expect(relation.id, equals(90123));
      expect(relation.nodeIds, equals([2001, 2003])); // Only valid nodes
      expect(relation.points, hasLength(2));
      expect(relation.points[0], equals(LatLng(-41.2870, 174.7776)));
      expect(relation.points[1], equals(LatLng(-41.2872, 174.7778)));
      expect(relation.tags['golf'], equals('water_hazard'));
    });

    test('should have meaningful toString', () {
      final relation = Relation(
        id: 78901,
        nodeIds: [2001, 2002],
        points: [LatLng(-41.2870, 174.7776), LatLng(-41.2871, 174.7777)],
        tags: {'type': 'multipolygon'},
      );

      final str = relation.toString();

      expect(str, contains('78901'));
      expect(str, contains('2001'));
      expect(str, contains('2002'));
      expect(str, contains('type'));
      expect(str, contains('multipolygon'));
    });
  });

  group('Overpass', () {
    test('should create overpass from constructor', () {
      final nodes = [
        Node(id: 1, lat: -41.0, lon: 174.0, tags: {}),
        Node(id: 2, lat: -41.1, lon: 174.1, tags: {}),
      ];
      final ways = [
        Way(id: 100, nodeIds: [1, 2], points: [], tags: {}),
      ];
      final relations = [
        Relation(id: 200, nodeIds: [1, 2], points: [], tags: {}),
      ];

      final overpass = Overpass(
        nodes: nodes,
        ways: ways,
        relations: relations,
      );

      expect(overpass.nodes, hasLength(2));
      expect(overpass.ways, hasLength(1));
      expect(overpass.relations, hasLength(1));
    });

    test('should create overpass with default empty lists', () {
      final overpass = Overpass();

      expect(overpass.nodes, isEmpty);
      expect(overpass.ways, isEmpty);
      expect(overpass.relations, isEmpty);
    });

    test('should parse simple JSON with nodes only', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "node",
            "id": 3001,
            "lat": -41.2866,
            "lon": 174.7772,
            "tags": {
              "golf": "pin",
              "name": "Hole 1"
            }
          },
          {
            "type": "node",
            "id": 3002,
            "lat": -41.2867,
            "lon": 174.7773,
            "tags": {
              "golf": "tee",
              "tee": "blue"
            }
          }
        ]
      }
      ''';

      final overpass = Overpass.fromJson(jsonString);

      expect(overpass.nodes, hasLength(2));
      expect(overpass.ways, isEmpty);
      expect(overpass.relations, isEmpty);

      expect(overpass.nodes[0].id, equals(3001));
      expect(overpass.nodes[0].lat, equals(-41.2866));
      expect(overpass.nodes[0].lon, equals(174.7772));
      expect(overpass.nodes[0].tags['golf'], equals('pin'));

      expect(overpass.nodes[1].id, equals(3002));
      expect(overpass.nodes[1].tags['golf'], equals('tee'));
      expect(overpass.nodes[1].tags['tee'], equals('blue'));
    });

    test('should parse JSON with nodes and ways', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "node",
            "id": 4001,
            "lat": -41.2866,
            "lon": 174.7772,
            "tags": {}
          },
          {
            "type": "node",
            "id": 4002,
            "lat": -41.2867,
            "lon": 174.7773,
            "tags": {}
          },
          {
            "type": "node",
            "id": 4003,
            "lat": -41.2868,
            "lon": 174.7774,
            "tags": {}
          },
          {
            "type": "way",
            "id": 5001,
            "nodes": [4001, 4002, 4003],
            "tags": {
              "golf": "fairway",
              "surface": "grass"
            }
          }
        ]
      }
      ''';

      final overpass = Overpass.fromJson(jsonString);

      expect(overpass.nodes, hasLength(3));
      expect(overpass.ways, hasLength(1));
      expect(overpass.relations, isEmpty);

      // Check nodes
      expect(overpass.nodes[0].id, equals(4001));
      expect(overpass.nodes[1].id, equals(4002));
      expect(overpass.nodes[2].id, equals(4003));

      // Check way
      final way = overpass.ways[0];
      expect(way.id, equals(5001));
      expect(way.nodeIds, equals([4001, 4002, 4003]));
      expect(way.points, hasLength(3));
      expect(way.points[0], equals(LatLng(-41.2866, 174.7772)));
      expect(way.points[1], equals(LatLng(-41.2867, 174.7773)));
      expect(way.points[2], equals(LatLng(-41.2868, 174.7774)));
      expect(way.tags['golf'], equals('fairway'));
      expect(way.tags['surface'], equals('grass'));
    });

    test('should parse JSON with all element types', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "node",
            "id": 6001,
            "lat": -41.2866,
            "lon": 174.7772,
            "tags": {"golf": "pin"}
          },
          {
            "type": "node",
            "id": 6002,
            "lat": -41.2867,
            "lon": 174.7773,
            "tags": {"golf": "tee"}
          },
          {
            "type": "way",
            "id": 7001,
            "nodes": [6001, 6002],
            "tags": {"golf": "green"}
          },
          {
            "type": "relation",
            "id": 8001,
            "nodes": [6001, 6002],
            "tags": {"type": "multipolygon", "golf": "course"}
          }
        ]
      }
      ''';

      final overpass = Overpass.fromJson(jsonString);

      expect(overpass.nodes, hasLength(2));
      expect(overpass.ways, hasLength(1));
      expect(overpass.relations, hasLength(1));

      // Check nodes
      expect(overpass.nodes[0].id, equals(6001));
      expect(overpass.nodes[1].id, equals(6002));

      // Check way
      final way = overpass.ways[0];
      expect(way.id, equals(7001));
      expect(way.nodeIds, equals([6001, 6002]));
      expect(way.points, hasLength(2));
      expect(way.tags['golf'], equals('green'));

      // Check relation
      final relation = overpass.relations[0];
      expect(relation.id, equals(8001));
      expect(relation.nodeIds, equals([6001, 6002]));
      expect(relation.points, hasLength(2));
      expect(relation.tags['type'], equals('multipolygon'));
      expect(relation.tags['golf'], equals('course'));
    });

    test('should handle ways with missing node references', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "node",
            "id": 9001,
            "lat": -41.2866,
            "lon": 174.7772,
            "tags": {}
          },
          {
            "type": "way",
            "id": 9100,
            "nodes": [9001, 9999, 9003],
            "tags": {"golf": "bunker"}
          }
        ]
      }
      ''';

      final overpass = Overpass.fromJson(jsonString);

      expect(overpass.nodes, hasLength(1));
      expect(overpass.ways, hasLength(1));

      final way = overpass.ways[0];
      expect(way.id, equals(9100));
      expect(way.nodeIds, equals([9001])); // Only valid node
      expect(way.points, hasLength(1));
      expect(way.points[0], equals(LatLng(-41.2866, 174.7772)));
    });

    test('should handle empty elements array', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": []
      }
      ''';

      final overpass = Overpass.fromJson(jsonString);

      expect(overpass.nodes, isEmpty);
      expect(overpass.ways, isEmpty);
      expect(overpass.relations, isEmpty);
    });

    test('should handle real golf course data structure', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API 0.7.61.8",
        "elements": [
          {
            "type": "node",
            "id": 12345,
            "lat": -41.2866553,
            "lon": 174.7772200,
            "tags": {
              "golf": "pin"
            }
          },
          {
            "type": "node",
            "id": 12346,
            "lat": -41.2860000,
            "lon": 174.7770000,
            "tags": {
              "golf": "tee",
              "tee": "blue",
              "distance": "350"
            }
          },
          {
            "type": "way",
            "id": 747473941,
            "nodes": [12345, 12346],
            "tags": {
              "golf": "fairway",
              "surface": "grass"
            }
          }
        ]
      }
      ''';

      final overpass = Overpass.fromJson(jsonString);

      expect(overpass.nodes, hasLength(2));
      expect(overpass.ways, hasLength(1));

      // Check pin node
      final pinNode = overpass.nodes.firstWhere((n) => n.tags['golf'] == 'pin');
      expect(pinNode.id, equals(12345));
      expect(pinNode.lat, equals(-41.2866553));
      expect(pinNode.lon, equals(174.7772200));

      // Check tee node
      final teeNode = overpass.nodes.firstWhere((n) => n.tags['golf'] == 'tee');
      expect(teeNode.id, equals(12346));
      expect(teeNode.tags['tee'], equals('blue'));
      expect(teeNode.tags['distance'], equals('350'));

      // Check fairway way
      final fairway = overpass.ways[0];
      expect(fairway.id, equals(747473941));
      expect(fairway.tags['golf'], equals('fairway'));
      expect(fairway.tags['surface'], equals('grass'));
      expect(fairway.points, hasLength(2));
    });

    test('should throw FormatException for invalid JSON', () {
      const invalidJson = '{ invalid json }';

      expect(
        () => Overpass.fromJson(invalidJson),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Golf Course Integration Tests', () {
    test('should parse typical golf hole data', () {
      const golfHoleJson = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "node",
            "id": 100001,
            "lat": -41.28665,
            "lon": 174.77722,
            "tags": {
              "golf": "pin",
              "ref": "1"
            }
          },
          {
            "type": "node",
            "id": 100002,
            "lat": -41.28600,
            "lon": 174.77700,
            "tags": {
              "golf": "tee",
              "tee": "blue",
              "distance": "350"
            }
          },
          {
            "type": "node",
            "id": 100003,
            "lat": -41.28610,
            "lon": 174.77710,
            "tags": {
              "golf": "tee",
              "tee": "red",
              "distance": "280"
            }
          },
          {
            "type": "way",
            "id": 200001,
            "nodes": [100002, 100003, 100001],
            "tags": {
              "golf": "hole",
              "ref": "1",
              "par": "4",
              "handicap": "10"
            }
          },
          {
            "type": "way",
            "id": 200002,
            "nodes": [100002, 100001],
            "tags": {
              "golf": "fairway",
              "surface": "grass"
            }
          },
          {
            "type": "way",
            "id": 200003,
            "nodes": [100001],
            "tags": {
              "golf": "green",
              "surface": "grass"
            }
          }
        ]
      }
      ''';

      final overpass = Overpass.fromJson(golfHoleJson);

      // Verify parsing
      expect(overpass.nodes, hasLength(3));
      expect(overpass.ways, hasLength(3));

      // Find golf elements
      final pin = overpass.nodes.firstWhere((n) => n.tags['golf'] == 'pin');
      final blueTee = overpass.nodes.firstWhere(
        (n) => n.tags['golf'] == 'tee' && n.tags['tee'] == 'blue',
      );
      final redTee = overpass.nodes.firstWhere(
        (n) => n.tags['golf'] == 'tee' && n.tags['tee'] == 'red',
      );

      final holeWay = overpass.ways.firstWhere((w) => w.tags['golf'] == 'hole');
      final fairway = overpass.ways.firstWhere((w) => w.tags['golf'] == 'fairway');
      final green = overpass.ways.firstWhere((w) => w.tags['golf'] == 'green');

      // Verify hole data
      expect(pin.tags['ref'], equals('1'));
      expect(blueTee.tags['distance'], equals('350'));
      expect(redTee.tags['distance'], equals('280'));
      expect(holeWay.tags['par'], equals('4'));
      expect(holeWay.tags['handicap'], equals('10'));

      // Verify coordinates are populated
      expect(holeWay.points, hasLength(3));
      expect(fairway.points, hasLength(2));
      expect(green.points, hasLength(1));

      // Verify coordinate accuracy
      expect(pin.toLatLng().latitude, equals(-41.28665));
      expect(pin.toLatLng().longitude, equals(174.77722));
    });
    test('should parse bounds from way and relation JSON', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "way",
            "id": 12345,
            "bounds": {
              "minlat": -41.2879424,
              "minlon": 174.6886983,
              "maxlat": -41.2878162,
              "maxlon": 174.6888293
            },
            "geometry": [
              {"lat": -41.2879424, "lon": 174.6886983},
              {"lat": -41.2878162, "lon": 174.6888293}
            ],
            "tags": {"golf": "tee", "surface": "grass"}
          },
          {
            "type": "relation",
            "id": 67890,
            "bounds": {
              "minlat": -41.2860000,
              "minlon": 174.6900000,
              "maxlat": -41.2850000,
              "maxlon": 174.6910000
            },
            "geometry": [
              {"lat": -41.2860000, "lon": 174.6900000},
              {"lat": -41.2850000, "lon": 174.6910000}
            ],
            "tags": {"type": "multipolygon", "golf": "course"}
          }
        ]
      }
      ''';

      final overpass = Overpass.fromJson(jsonString);

      expect(overpass.ways, hasLength(1));
      expect(overpass.relations, hasLength(1));

      // Check way bounds
      final way = overpass.ways[0];
      expect(way.id, equals(12345));
      expect(way.bounds, isNotNull);

      // Debug output to understand LatLngBounds behavior
      print('Way bounds - SW: ${way.bounds!.southWest}, NE: ${way.bounds!.northEast}');

      // LatLngBounds constructor automatically sorts coordinates
      // southWest should be the minimum lat/lon
      // northEast should be the maximum lat/lon
      expect(way.bounds!.southWest.latitude, equals(-41.2879424)); // min lat
      expect(way.bounds!.southWest.longitude, equals(174.6886983)); // min lon
      expect(way.bounds!.northEast.latitude, equals(-41.2878162)); // max lat
      expect(way.bounds!.northEast.longitude, equals(174.6888293)); // max lon

      // Check relation bounds
      final relation = overpass.relations[0];
      expect(relation.id, equals(67890));
      expect(relation.bounds, isNotNull);
      expect(relation.bounds!.southWest.latitude, equals(-41.2860000)); // min lat
      expect(relation.bounds!.southWest.longitude, equals(174.6900000)); // min lon
      expect(relation.bounds!.northEast.latitude, equals(-41.2850000)); // max lat
      expect(relation.bounds!.northEast.longitude, equals(174.6910000)); // max lon
    });

    test('should handle missing or malformed bounds', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "way",
            "id": 11111,
            "geometry": [
              {"lat": -41.2879424, "lon": 174.6886983}
            ],
            "tags": {"golf": "tee"}
          },
          {
            "type": "way",
            "id": 22222,
            "bounds": {
              "minlat": -41.2879424
            },
            "geometry": [
              {"lat": -41.2879424, "lon": 174.6886983}
            ],
            "tags": {"golf": "green"}
          }
        ]
      }
      ''';

      final overpass = Overpass.fromJson(jsonString);

      expect(overpass.ways, hasLength(2));

      // Check way without bounds
      final wayWithoutBounds = overpass.ways[0];
      expect(wayWithoutBounds.id, equals(11111));
      expect(wayWithoutBounds.bounds, isNull);

      // Check way with malformed bounds
      final wayWithMalformedBounds = overpass.ways[1];
      expect(wayWithMalformedBounds.id, equals(22222));
      expect(wayWithMalformedBounds.bounds, isNull);
    });

    test('should create JTS polygons from way and relation points', () {
      const jsonString = '''
      {
        "version": 0.6,
        "generator": "Overpass API",
        "elements": [
          {
            "type": "way",
            "id": 12345,
            "geometry": [
              {"lat": -41.2879424, "lon": 174.6886983},
              {"lat": -41.2878162, "lon": 174.6888293},
              {"lat": -41.2877000, "lon": 174.6887000},
              {"lat": -41.2879424, "lon": 174.6886983}
            ],
            "tags": {"golf": "tee", "surface": "grass"}
          },
          {
            "type": "relation",
            "id": 67890,
            "geometry": [
              {"lat": -41.2860000, "lon": 174.6900000},
              {"lat": -41.2850000, "lon": 174.6910000},
              {"lat": -41.2855000, "lon": 174.6915000},
              {"lat": -41.2860000, "lon": 174.6900000}
            ],
            "tags": {"type": "multipolygon", "golf": "course"}
          },
          {
            "type": "way",
            "id": 11111,
            "geometry": [
              {"lat": -41.2879424, "lon": 174.6886983},
              {"lat": -41.2878162, "lon": 174.6888293}
            ],
            "tags": {"golf": "path"}
          }
        ]
      }
      ''';

      final overpass = Overpass.fromJson(jsonString);

      expect(overpass.ways, hasLength(2));
      expect(overpass.relations, hasLength(1));

      // Check way with enough points for polygon (4 points)
      final wayWithPolygon = overpass.ways.firstWhere((w) => w.id == 12345);
      expect(wayWithPolygon.polygon, isNotNull, reason: 'Way with 4+ points should have JTS polygon');
      expect(wayWithPolygon.polygon!.getArea(), greaterThan(0), reason: 'Polygon should have positive area');

      // Check relation with enough points for polygon (4 points)
      final relation = overpass.relations[0];
      expect(relation.polygon, isNotNull, reason: 'Relation with 4+ points should have JTS polygon');
      expect(relation.polygon!.getArea(), greaterThan(0), reason: 'Polygon should have positive area');

      // Check way with insufficient points for polygon (2 points)
      final wayWithoutPolygon = overpass.ways.firstWhere((w) => w.id == 11111);
      expect(wayWithoutPolygon.polygon, isNull, reason: 'Way with <3 points should not have polygon');
    });
  });

  group('Karori Golf Course Real Data Tests', () {
    test('should parse actual Karori golf course JSON file', () async {
      // Load the real Karori golf course data
      final file = File('karori.json');
      if (!await file.exists()) {
        // Skip test if file doesn't exist
        markTestSkipped('karori.json file not found');
        return;
      }

      final jsonString = await file.readAsString();
      final overpass = Overpass.fromJson(jsonString);

      // Verify basic parsing worked
      expect(overpass.nodes, isNotEmpty);
      expect(overpass.ways, isNotEmpty);

      print('Karori data parsed:');
      print('  - Nodes: ${overpass.nodes.length}');
      print('  - Ways: ${overpass.ways.length}');
      print('  - Relations: ${overpass.relations.length}');

      // Find the main golf course way
      final golfCourseWays = overpass.ways.where(
        (way) => way.tags['leisure'] == 'golf_course',
      ).toList();

      print('  - Golf course ways found: ${golfCourseWays.length}');
      for (final way in golfCourseWays) {
        print('    - Way ${way.id}: ${way.tags}');
      }

      final golfCourseWay = overpass.ways.firstWhere(
        (way) => way.tags['leisure'] == 'golf_course' &&
                 way.tags['name'] == 'Karori Golf Club',
        orElse: () => throw Exception('Golf course way not found'),
      );

      // Verify golf course details
      expect(golfCourseWay.id, equals(747473941));
      expect(golfCourseWay.tags['name'], equals('Karori Golf Club'));
      expect(golfCourseWay.tags['leisure'], equals('golf_course'));
      expect(golfCourseWay.tags['addr:street'], equals('South Makara Road'));

      // Verify geometry points are populated (from geometry array, not nodes)
      expect(golfCourseWay.points, isNotEmpty);
      print('  - Golf course boundary points: ${golfCourseWay.points.length}');

      // Check some specific coordinates from the boundary
      final firstPoint = golfCourseWay.points.first;
      expect(firstPoint.latitude, equals(-41.2846553));
      expect(firstPoint.longitude, equals(174.6895637));

      // Find golf-specific nodes
      final golfNodes = overpass.nodes.where(
        (node) => node.tags.containsKey('golf'),
      ).toList();

      expect(golfNodes, isNotEmpty);
      print('  - Golf-specific nodes: ${golfNodes.length}');

      // Categorize golf features
      final pins = golfNodes.where((n) => n.tags['golf'] == 'pin').toList();
      final teeNodes = golfNodes.where((n) => n.tags['golf'] == 'tee').toList();
      final teeWays = overpass.ways.where((w) => w.tags['golf'] == 'tee').toList();
      final greens = overpass.ways.where((w) => w.tags['golf'] == 'green').toList();
      final fairways = overpass.ways.where((w) => w.tags['golf'] == 'fairway').toList();

      print('  - Pins: ${pins.length}');
      print('  - Tee nodes: ${teeNodes.length}');
      print('  - Tee ways: ${teeWays.length}');
      print('  - Total tees: ${teeNodes.length + teeWays.length}');
      print('  - Greens: ${greens.length}');
      print('  - Fairways: ${fairways.length}');

      // Verify we have golf course features
      expect(pins.length, greaterThan(0), reason: 'Should have golf pins');

      // Verify bounds parsing from real data
      expect(golfCourseWay.bounds, isNotNull, reason: 'Golf course way should have bounds');
      print('  - Golf course bounds: ${golfCourseWay.bounds}');

      // Check that tee ways also have bounds
      if (teeWays.isNotEmpty) {
        final teeWayWithBounds = teeWays.firstWhere(
          (tee) => tee.bounds != null,
          orElse: () => teeWays.first
        );
        if (teeWayWithBounds.bounds != null) {
          print('  - Sample tee bounds: ${teeWayWithBounds.bounds}');
          expect(teeWayWithBounds.bounds!.southWest.latitude, lessThan(0), reason: 'Should be in southern hemisphere');
          expect(teeWayWithBounds.bounds!.southWest.longitude, greaterThan(170), reason: 'Should be in New Zealand longitude range');
        }
      }

      // Verify JTS polygons are created from real data
      expect(golfCourseWay.polygon, isNotNull, reason: 'Golf course way should have JTS polygon');
      expect(golfCourseWay.polygon!.getArea(), greaterThan(0), reason: 'Golf course polygon should have positive area');
      print('  - Golf course polygon area: ${golfCourseWay.polygon!.getArea()} square degrees');

      // Check that tee ways have JTS polygons
      final teeWaysWithPolygons = teeWays.where((tee) => tee.polygon != null).toList();
      print('  - Tee ways with polygons: ${teeWaysWithPolygons.length}/${teeWays.length}');

      if (teeWaysWithPolygons.isNotEmpty) {
        final sampleTeePolygon = teeWaysWithPolygons.first;
        expect(sampleTeePolygon.polygon!.getArea(), greaterThan(0), reason: 'Tee polygon should have positive area');
        print('  - Sample tee polygon area: ${sampleTeePolygon.polygon!.getArea()} square degrees');
      }

      // Check green polygons
      final greensWithPolygons = greens.where((green) => green.polygon != null).toList();
      print('  - Green ways with polygons: ${greensWithPolygons.length}/${greens.length}');

      if (greensWithPolygons.isNotEmpty) {
        final sampleGreenPolygon = greensWithPolygons.first;
        expect(sampleGreenPolygon.polygon!.getArea(), greaterThan(0), reason: 'Green polygon should have positive area');
        print('  - Sample green polygon area: ${sampleGreenPolygon.polygon!.getArea()} square degrees');
      }

      // Test specific pin data if available
      if (pins.isNotEmpty) {
        final pin = pins.first;
        expect(pin.lat, isA<double>());
        expect(pin.lon, isA<double>());
        expect(pin.lat, greaterThan(-42.0)); // Reasonable latitude for Wellington
        expect(pin.lat, lessThan(-41.0));
        expect(pin.lon, greaterThan(174.0)); // Reasonable longitude for Wellington
        expect(pin.lon, lessThan(175.0));
      }

      // Test tee data if available
      if (teeNodes.isNotEmpty) {
        final tee = teeNodes.first;
        expect(tee.tags['golf'], equals('tee'));

        // Check if tee has color/type information
        if (tee.tags.containsKey('tee')) {
          final teeColor = tee.tags['tee'];
          expect(teeColor, isA<String>());
          print('    - Found tee node color: $teeColor');
        }
      }

      // Test tee way data if available
      if (teeWays.isNotEmpty) {
        final teeWay = teeWays.first;
        expect(teeWay.tags['golf'], equals('tee'));
        expect(teeWay.points, isNotEmpty, reason: 'Tee way should have polygon points');
        print('    - Found tee way ${teeWay.id} with ${teeWay.points.length} points');

        // Check if tee way has surface information
        if (teeWay.tags.containsKey('surface')) {
          final surface = teeWay.tags['surface'];
          expect(surface, isA<String>());
          print('    - Tee way surface: $surface');
        }
      }
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('should handle Karori data with JtsHelper integration', () async {
      // Load the real data
      final file = File('karori.json');
      if (!await file.exists()) {
        markTestSkipped('karori.json file not found');
        return;
      }

      final jsonString = await file.readAsString();
      final overpass = Overpass.fromJson(jsonString);

      // Find ways that can be converted to polygons
      final golfWays = overpass.ways.where(
        (way) => way.tags.containsKey('golf') && way.points.length >= 3,
      ).toList();

      if (golfWays.isNotEmpty) {
        print('Found ${golfWays.length} golf ways suitable for polygon conversion');

        for (final way in golfWays.take(3)) { // Test first 3 ways
          expect(way.points, hasLength(greaterThanOrEqualTo(3)));
          expect(way.tags['golf'], isNotNull);

          print('  - Way ${way.id}: ${way.tags['golf']} with ${way.points.length} points');

          // Verify coordinates are reasonable for Wellington area
          for (final point in way.points.take(3)) {
            expect(point.latitude, greaterThan(-42.0));
            expect(point.latitude, lessThan(-41.0));
            expect(point.longitude, greaterThan(174.0));
            expect(point.longitude, lessThan(175.0));
          }
        }
      }

      // Test the main golf course boundary
      final mainCourse = overpass.ways.firstWhere(
        (way) => way.tags['leisure'] == 'golf_course',
        orElse: () => throw Exception('Main golf course not found'),
      );

      expect(mainCourse.points, isNotEmpty);
      print('Main course boundary has ${mainCourse.points.length} points');

      // Verify the boundary forms a reasonable area
      expect(mainCourse.points.length, greaterThan(10)); // Should have many boundary points
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}