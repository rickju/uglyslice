import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'golf_course.dart';

class CourseParser {
  static GolfCourse fromJson(String jsonString, String courseName) {
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> elements = data['elements'];

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

        allNodes.add(
          Node(id: id.toString(), position: position, tags: nodeTags[id]!),
        );
      }
    }

    // 2. 初始化集合
    final List<Hole> holes = [];
    final List<Way> allFeatures = []; // 存储所有地理要素（果岭、球道、沙坑等）

    // 3. 第一次遍历 Way：建立基础地理要素
    for (var element in elements) {
      if (element['type'] == 'way') {
        final Map<String, dynamic> tags = Map<String, dynamic>.from(
          element['tags'] ?? {},
        );

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

        final Way way = Way(
          id: element['id'].toString(),
          points: polyline,
          tags: tags,
        );
        allFeatures.add(way);
      }
    }

    // 4. 第二次处理：识别 Hole (球洞)
    // 注意：有些数据标记 golf=hole 在 Way 上，有些在 Relation 上
    for (var element in elements) {
      if (element['type'] == 'way' || element['type'] == 'relation') {
        final tags = element['tags'] ?? {};
        if (tags['golf'] == 'hole' || tags['type'] == 'hole') {
          // 这里调用你的 Hole.fromWay 或 Hole.fromRelation
          // 逻辑：寻找该球洞关联的 fairway, green, tee 等成员
          final hole = _parseHole(element, allFeatures, nodeTags);
          if (hole != null) holes.add(hole);
        }
      }
    }

    // 如果没有明确的 hole relation，可以尝试从 features 里的 tags 推断球洞
    if (holes.isEmpty) {
      _inferHolesFromFeatures(allFeatures, holes);
    }

    // 按球洞编号排序
    holes.sort((a, b) => a.holeNumber.compareTo(b.holeNumber));

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
  ) {
    // 具体的 Hole 解析逻辑，需要根据你的 hole.dart 实现
    // 需处理：tags['hole_number'] 或 tags['ref']
    return null; // 此处对接你的具体业务逻辑
  }

  // 兜底方案：如果没有 hole relation，将所有标记了 ref 的 feature 归类
  static void _inferHolesFromFeatures(List<Way> features, List<Hole> holes) {
    // 逻辑示例：如果一个 fairway 有 ref=1，创建一个 Hole 1
  }
}
