import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'overpass.dart';

/* 
class Bunker {}
class Hazard {}
class {}
*/

// 不规则多边形 list of nodes
class Boundary {

 static Boundary? fromWay() {
 }
}

// overpass:way with tags:golf=pin
class Green {
  final List<Node> allNodes;
  final Boundary bounary ;

  static Green? fromWay(
    dynamic element,
    Way way,
    Map<int, Map<String, dynamic>> nodeTags,
    List<Node> allNodes,
  ) {
      final bounds = LatLngBounds(
        LatLng(40.712, -74.006), 
        LatLng(40.730, -73.935)
      );
  }
}

class Fairway {
  final List<Node> allNodes;

  static Fairway? fromWay(
    dynamic element,
    Way way) {
  }
}


class Tee {
  final String color;
  final double distance;
  final double courseRating;
  final double slopeRating;
  final LatLng position;

  Tee({
    required this.color,
    this.distance = 0.0,
    this.courseRating = 0.0,
    this.slopeRating = 0.0,
    required this.position,
  });

  @override
  String toString() {
    return 'Tee: $color, $distance, course rating: $courseRating, slope rating: $slopeRating\n';
  }

  static Tee? fromWay(
    dynamic element,
    Way way,
    Map<int, Map<String, dynamic>> nodeTags,
    List<Node> allNodes,
  ) {
      // XXX
      final bounds = LatLngBounds(
        LatLng(40.712, -74.006), 
        LatLng(40.730, -73.935)
      );

  }
}

class Hole {
  final int holeNumber;
  final int par;
  final int handicapIndex;
  final LatLng pin;

  final LatLng boundMin, boundMax;
  final boundary;
  final List<Tee> tees;
  final Fairway fairway; // list ???
  final Green green;

  Hole({
    required this.holeNumber,
    required this.par,
    this.handicapIndex = 0,
    required this.pin,
    this.tees = const [],
    required this.boundMin,
    required this.boundMax,
  });

  static Hole? fromWay(
    dynamic element,
    Way way,
    Map<int, Map<String, dynamic>> nodeTags,
    List<Node> allNodes,
  ) {
    // for type:way/golf:hole, ref is hole number
    if (!way.tags.containsKey('ref')) {
      return null;
    }
    final holeNumber = int.parse(way.tags['ref']);
    final par = int.parse(way.tags['par'] ?? '0');
    final handicapIndex = int.parse(way.tags['handicap'] ?? '0');

    // bounds
    final bounds = element['bounds'];
    final LatLng boundMin = LatLng(
      bounds['minlat'] ?? 0.0,
      bounds['minlon'] ?? 0.0,
    );
    final LatLng boundMax = LatLng(
      bounds['maxlat'] ?? 0.0,
      bounds['maxlon'] ?? 0.0,
    );

    // pin/tee
    LatLng? pin;
    List<Tee> tees = [];
    print(
      '  - Processing hole ${way.tags["ref"]} with ${way.nodeIds.length} nodes.',
    );
    for (var i = 0; i < way.nodeIds.length; i++) {
      final nodeId = way.nodeIds[i];

      // nodes list. lj: overpass out geom does NOT include all nodes
      final Node? node = allNodes.firstWhereOrNull((n) => n.id == nodeId);
      if (node != null) {
        print('    - Node ${node.id} tags: ${node.tags}');
        // node for pin/tee
        if (node.tags['golf'] == 'pin') {
          pin = node.toLatLng();
          print('      - Found pin at ${pin}');
        } else if (node.tags['golf'] == 'tee') {
          final tee = Tee(
            color: node.tags['tee'] ?? 'white',
            distance: double.parse(node.tags['distance'] ?? '0'),
            position: node.toLatLng(),
          );
          print('      - Found tee at ${tee}');
          tees.add(tee);
        }
      }
    }

    if (pin == null) {
      print('  - Pin not found for hole ${way.tags["ref"]}');
      return null;
    }

    return Hole(
      holeNumber: holeNumber,
      par: par,
      handicapIndex: handicapIndex,
      pin: pin,
      tees: tees,
      boundMin: boundMin,
      boundMax: boundMax,
    );
  }

  @override
  String toString() {
    return 'Hole: $holeNumber, par: $par, hcp: $handicapIndex, pin: $pin, tees: ${tees.toString()}\n';
  }
}

// course
// ---------
class Course {
  final String id;
  final String name;

  final List<Node> nodes;
  final List<Way> ways;
  final List<Relation> relations;
  final List<Hole> holes;
  // final boundary;
  // final tags; // addr/phone etc
  // facility e.g. clubhouse/cartpath

  Course({
    required this.id,
    required this.name,
    this.nodes = const [],
    this.ways = const <Way> [],
    this.relations = const <Relation> [],
    this.holes = const [],
  });

  static Course fromJson(String json) {
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> elements = data['elements'];
    print('json parsed: elements num: ${elements.length}');

    final Map<int, LatLng> nodeCoordinates = {};
    final Map<int, Map<String, dynamic>> nodeTags = {};

    final List<Node> allNodes = [];
    final List<Way> allWays= [];
    final List<Relation> allRelations = [];
    final List<Hole> allHoles= [];

    // node/way
    for (var element in elements) {
      if (element['type'] == 'node') {
        final int id = element['id'];
        final double lat = element['lat'];
        final double lon = element['lon'];
        final LatLng position = LatLng(lat, lon);

        final node = Node.fromJson(element);
        allNodes.add(node); 
      } else if (element['type'] == 'way') {
        final way = Way.fromJson(element, null);
        allWays.add(way); 
      } else if (element['type'] == 'relation') {
        final relation = Relation.fromJson(element, null);
        allRelations.add(relation)
      }
    } // for

    // hole
    for (var way in allWays) {
    }

    return Course(
      id: "course_${DateTime.now().millisecondsSinceEpoch}",
      name: "XXX",
      nodes: allNodes,
      ways: allWays,
      relations: allRelations,
      holes: allHoles,
    );
  } // fromJson
}

class CourseHelper  {
  final String id;
  final String name;
  final LatLng location;
  final int holesCount;
  final List<Way> features;

  // from OpenStreetMap data
  final List<Node> nodes;
  final List<Hole> holes;
  // final boundary;
  // final tags; // addr/phone etc
  // facility e.g. clubhouse/cartpath

  CourseHelper({
    required this.id,
    required this.name,
    required this.location,
    this.holesCount = 18,
    required this.holes,
    this.features = const [],
    this.nodes = const [],
  });

  @override
  String toString() {
    return 'Course: $name, $id, $location, holes count: $holesCount, holes: ${holes.toString()}\n';
  }

  static Course fromJson(String jsonString, String courseName) {
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> elements = data['elements'];
    print('json parsed: elements num: ${elements.length}');
    // print('got json elements list: ${elements.toString()}');

    //  预处理所有 Node，建立坐标索引映射
    final Map<int, LatLng> nodeCoordinates = {};
    final Map<int, Map<String, dynamic>> nodeTags = {};
    final List<Node> allNodes = [];
    for (var element in elements) {
      if (element['type'] == 'node') {
        final int id = element['id'];
        final double lat = element['lat'];
        final double lon = element['lon'];
        final LatLng position = LatLng(lat, lon);

        nodeCoordinates[id] = position;
        nodeTags[id] = Map<String, dynamic>.from(element['tags'] ?? {});

        allNodes.add(Node(id: id, lat: lat, lon: lon, tags: nodeTags[id]!));
      }
    }
    print('json parsed: allNodes len: ${allNodes.length}');
    // print('allNodes: ${allNodes.toString()}');

    // 
    final List<Hole> oles = [];
    final List<Way> allFeatures = []; // 存储所有地理要素（果岭、球道、沙坑等）

    // cycle #1:  Way/基础地理要素
    for (var element in elements) {
      if (element['type'] == 'way') {
        final Map<String, dynamic> tags = Map<String, dynamic>.from(
          element['tags'] ?? {},
        );
        print('Way found: ${tags.toString()}');

        // 解析坐标路径
        List<LatLng> polyline = [];
        if (element['geometry'] != null) {
          // if overpass ql:out geom
          polyline = (element['geometry'] as List)
              .map((g) => LatLng(g['lat'].toDouble(), g['lon'].toDouble()))
              .toList();
        } else if (element['nodes'] != null) {
          // 如果查询只有 node ref
          polyline = (element['nodes'] as List)
              .map((id) => nodeCoordinates[id])
              .whereType<LatLng>()
              .toList();
        }

        final List<int> nodeIds =
            (element['nodes'] as List?)?.map((e) => e as int).toList() ?? [];
        final Way way = Way(
          id: element['id'],
          nodeIds: nodeIds,
          points: polyline,
          tags: tags,
        );
        allFeatures.add(way);
      }
    }
    print('json parsed: allFeatures len: ${allFeatures.length}');
    print('allFeatures: ${allFeatures.toString()}');

    // cyecle #2：识别 Hole (球洞)
    // 注意：有些数据标记 golf=hole 在 Way 上，有些在 Relation 上
    for (var element in elements) {
      if (element['type'] == 'way' || element['type'] == 'relation') {
        final tags = element['tags'] ?? {};
        if (tags['golf'] == 'hole' || tags['type'] == 'hole') {
          // will call Hole.fromWay 或 Hole.fromRelation: 寻找该球洞关联的 fairway, green, tee 等成员
          final hole = _parseHole(element, allFeatures, nodeTags, allNodes);
          if (hole != null) holes.add(hole);
        }
        // Tee as 'way'
        else if (tags['golf'] == 'tee' || tags['type'] == 'tee') {
          print ('tee as way: found');
        }
        // TODO/way: fairway, green, water_hazard, cartpath, clubhouse
    }
    print('json parsed: cycle 2: holes count: ${holes.length}');

    // 球洞排序
    holes.sort((a, b) => a.holeNumber.compareTo(b.holeNumber));
    //print('json parsed: cycle 3: holes count: ${holes.length}');

    // 计算球场中心点 (取所有 Node 的平均值)
    LatLng center = _calculateCenter(nodeCoordinates.values.toList());
    return Course(
      id: "course_${DateTime.now().millisecondsSinceEpoch}",
      name: courseName,
      location: center,
      holes: holes,
      features: allFeatures,
      nodes: allNodes,
    );
  }

  // helper: 计算course中心点
  static LatLng _calculateCenter(List<LatLng> points) {
    if (points.isEmpty) return LatLng(0, 0);
    double lat = 0;
    double lon = 0;
    for (var p in points) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / points.length, lon / points.length);
  }

  // 从Way/Relation解析球洞逻辑
  static Hole? _parseHole(
    dynamic element,
    List<Way> allFeatures,
    Map<int, Map<String, dynamic>> nodeTags,
    List<Node> allNodes,
  ) {
    final wayId = element['id'];
    final way = allFeatures.firstWhere((w) => w.id == wayId);
    return Hole.fromWay(element, way, nodeTags, allNodes);
  }
}
