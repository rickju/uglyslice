import 'package:latlong2/latlong.dart';
import 'dart:convert';

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
}

class Hole {
  final int holeNumber;
  final int par;
  final int handicapIndex;
  final LatLng pin;
  final List<Tee> tees;

  Hole({
    required this.holeNumber,
    required this.par,
    this.handicapIndex = 0,
    required this.pin,
    this.tees = const [],
  });

  static Hole? fromWay(
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

    // pin/tee
    LatLng? pin;
    List<Tee> tees = [];

    print(
      '  - Processing hole ${way.tags["ref"]} with ${way.nodeIds.length} nodes.',
    );
    for (var i = 0; i < way.nodeIds.length; i++) {
      final nodeId = way.nodeIds[i];
      // Find the corresponding node in the allNodes list
      final node = allNodes.firstWhere(
        (n) => n.id == nodeId,
        orElse: () => throw Exception('Node $nodeId not found'),
      );
      print('    - Node ${node.id} tags: ${node.tags}');
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
    );
  }

  @override
  String toString() {
    return 'Hole: $holeNumber, par: $par, hcp: $handicapIndex, pin: $pin, tees: ${tees.toString()}\n';
  }
}

// course: holes list
class GolfCourse {
  final String id;
  final String name;
  final LatLng location;
  final int holesCount;
  final List<Hole> holes;

  // These are for parsing from OpenStreetMap data
  final List<Way> features;
  final List<Node> nodes;

  GolfCourse({
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
    return 'GolfCourse: $name, $id, $location, holes count: $holesCount, holes: ${holes.toString()}\n';
  }
}

//
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

class CourseParser {
  static GolfCourse fromJson(String jsonString, String courseName) {
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> elements = data['elements'];
    print('json parsed: elements num: ${elements.length}');
    print('elements list: ${elements.toString()}');

    // 1. 预处理所有 Node，建立坐标索引映射
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

    // 2. 初始化集合
    final List<Hole> holes = [];
    final List<Way> allFeatures = []; // 存储所有地理要素（果岭、球道、沙坑等）

    // 3. 第一次遍历 Way：建立基础地理要素
    for (var element in elements) {
      if (element['type'] == 'way') {
        final Map<String, dynamic> tags = Map<String, dynamic>.from(
          element['tags'] ?? {},
        );
        print('Way found: ${tags.toString()}');

        // 解析坐标路径
        List<LatLng> polyline = [];
        if (element['geometry'] != null) {
          // 如果查询用了 out geom
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

    // 4. 第二次处理：识别 Hole (球洞)
    // 注意：有些数据标记 golf=hole 在 Way 上，有些在 Relation 上
    for (var element in elements) {
      if (element['type'] == 'way' || element['type'] == 'relation') {
        final tags = element['tags'] ?? {};
        if (tags['golf'] == 'hole' || tags['type'] == 'hole') {
          // 这里调用你的 Hole.fromWay 或 Hole.fromRelation
          // 逻辑：寻找该球洞关联的 fairway, green, tee 等成员
          final hole = _parseHole(element, allFeatures, nodeTags, allNodes);
          if (hole != null) holes.add(hole);
        }
      }
    }
    print('json parsed: cycle 2: holes len: ${holes.length}');

    // 如果没有明确的 hole relation，可以尝试从 features 里的 tags 推断球洞
    if (holes.isEmpty) {
      _inferHolesFromFeatures(allFeatures, holes, allNodes);
    }

    // 按球洞编号排序
    holes.sort((a, b) => a.holeNumber.compareTo(b.holeNumber));
    print('json parsed: cycle 3: holes len: ${holes.length}');

    // 5. 计算球场中心点 (取所有 Node 的平均值)
    LatLng center = _calculateCenter(nodeCoordinates.values.toList());

    return GolfCourse(
      id: "course_${DateTime.now().millisecondsSinceEpoch}",
      name: courseName,
      location: center,
      holes: holes,
      features: allFeatures,
      nodes: allNodes,
    );
  }

  // 计算中心点助手函数
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

  // 从 Way 或 Relation 解析球洞逻辑
  static Hole? _parseHole(
    dynamic element,
    List<Way> allFeatures,
    Map<int, Map<String, dynamic>> nodeTags,
    List<Node> allNodes,
  ) {
    final wayId = element['id'];
    final way = allFeatures.firstWhere((w) => w.id == wayId);
    return Hole.fromWay(way, nodeTags, allNodes);
  }

  // 兜底方案：如果没有 hole relation，将所有标记了 ref 的 feature 归类
  static void _inferHolesFromFeatures(
    List<Way> features,
    List<Hole> holes,
    List<Node> allNodes,
  ) {
    final Map<int, List<Way>> holesFeatures = {};
    for (var feature in features) {
      if (feature.tags.containsKey('ref')) {
        final holeNum = int.tryParse(feature.tags['ref']);
        if (holeNum != null) {
          if (!holesFeatures.containsKey(holeNum)) {
            holesFeatures[holeNum] = [];
          }
          holesFeatures[holeNum]!.add(feature);
        }
      }
    }

    for (var holeNum in holesFeatures.keys) {
      final ways = holesFeatures[holeNum]!;
      LatLng? pin;
      final List<Tee> tees = [];
      int par = 0;

      for (var way in ways) {
        for (var nodeId in way.nodeIds) {
          final node = allNodes.firstWhere((n) => n.id == nodeId);
          if (node.tags['golf'] == 'tee') {
            tees.add(
              Tee(
                color: node.tags['tee'] ?? 'white',
                position: LatLng(node.lat, node.lon),
              ),
            );
          }
        }
        if (way.tags['golf'] == 'pin') {
          pin = way.points.first;
        } else if (way.tags.containsKey('par')) {
          par = int.tryParse(way.tags['par']) ?? 0;
        }
      }

      if (pin != null && par > 0) {
        holes.add(Hole(holeNumber: holeNum, par: par, pin: pin, tees: tees));
      }
    }
  }
}
