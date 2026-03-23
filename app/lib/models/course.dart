import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'jts.dart';

// for a course, info for a named/colored tee. e.g. black: 5380y par: 72
class TeeInfo {
  final String name;
  final String color;
  final double yardage;
  final double courseRating;
  final double slopeRating;

  TeeInfo({
    required this.name,
    required this.color,
    this.yardage = 0.0,
    this.courseRating = 0.0,
    this.slopeRating = 0.0,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'color': color,
        'yardage': yardage,
        'courseRating': courseRating,
        'slopeRating': slopeRating,
      };

  factory TeeInfo.fromMap(Map<String, dynamic> m) => TeeInfo(
        name: m['name'] as String,
        color: m['color'] as String,
        yardage: (m['yardage'] as num).toDouble(),
        courseRating: (m['courseRating'] as num).toDouble(),
        slopeRating: (m['slopeRating'] as num).toDouble(),
      );

  @override
  String toString() {
    return 'TeeInfo: $color, $yardage, course rating: $courseRating, slope rating: $slopeRating\n';
  }
}

// tee box (a point) for a hole
class TeeBox {
  final LatLng position;
  TeeBox({required this.position});

  Map<String, dynamic> toMap() => {
        'lat': position.latitude,
        'lng': position.longitude,
      };

  factory TeeBox.fromMap(Map<String, dynamic> m) =>
      TeeBox(position: LatLng(m['lat'] as double, m['lng'] as double));
}

class TeePlatform {
  final int id;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final jts.Polygon? polygon;

  TeePlatform({
    required this.id,
    required this.points,
    required this.tags,
    this.polygon,
  });

  String? get color => tags['color'] as String?;

  /// Oriented bounding rectangle aligned with [bearingDeg] (degrees CW from north).
  /// Major axis is along the playing direction. Returns a closed 5-point ring.
  List<LatLng> orientedRect(double bearingDeg) {
    if (points.isEmpty) return [];
    final cLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
    final cLon = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
    const metersPerDeg = 111320.0;
    final cosLat = math.cos(cLat * math.pi / 180);
    final bRad = bearingDeg * math.pi / 180;
    final sinB = math.sin(bRad);
    final cosB = math.cos(bRad);

    // Project each point into (along, across) frame.
    // along = projection onto playing direction; across = perpendicular.
    var minAlong = double.infinity, maxAlong = double.negativeInfinity;
    var minAcross = double.infinity, maxAcross = double.negativeInfinity;
    for (final p in points) {
      final xm = (p.longitude - cLon) * metersPerDeg * cosLat;
      final ym = (p.latitude - cLat) * metersPerDeg;
      final along = xm * sinB + ym * cosB;
      final across = xm * cosB - ym * sinB;
      if (along < minAlong) minAlong = along;
      if (along > maxAlong) maxAlong = along;
      if (across < minAcross) minAcross = across;
      if (across > maxAcross) maxAcross = across;
    }

    // Minimum dimensions: 6 m along, 3 m across.
    if (maxAlong - minAlong < 6.0) {
      final mid = (maxAlong + minAlong) / 2;
      minAlong = mid - 3.0; maxAlong = mid + 3.0;
    }
    if (maxAcross - minAcross < 3.0) {
      final mid = (maxAcross + minAcross) / 2;
      minAcross = mid - 1.5; maxAcross = mid + 1.5;
    }

    LatLng corner(double along, double across) {
      final xm = along * sinB + across * cosB;
      final ym = along * cosB - across * sinB;
      return LatLng(cLat + ym / metersPerDeg, cLon + xm / (metersPerDeg * cosLat));
    }

    return [
      corner(minAlong, minAcross),
      corner(maxAlong, minAcross),
      corner(maxAlong, maxAcross),
      corner(minAlong, maxAcross),
      corner(minAlong, minAcross),
    ];
  }

  // Axis-aligned bounding rect as a closed polygon ring (5 points).
  List<LatLng> get boundingRect {
    if (points.isEmpty) return [];
    final minLat = points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLon = points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLon = points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    return [
      LatLng(minLat, minLon),
      LatLng(maxLat, minLon),
      LatLng(maxLat, maxLon),
      LatLng(minLat, maxLon),
      LatLng(minLat, minLon),
    ];
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'tags': tags,
        'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      };

  factory TeePlatform.fromMap(Map<String, dynamic> m) {
    final pts = (m['points'] as List)
        .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
        .toList();
    jts.Polygon? poly;
    if (pts.length >= 3) {
      try { poly = JtsHelper.fromLatLngPoints(pts); } catch (_) {}
    }
    return TeePlatform(
      id: m['id'] as int,
      tags: Map<String, dynamic>.from(m['tags'] as Map),
      points: pts,
      polygon: poly,
    );
  }

  @override
  String toString() => 'TeePlatform(id: $id, color: $color)';
}

class Fairway {
  final int id;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final jts.Polygon? polygon;

  Fairway({
    required this.id,
    required this.points,
    required this.tags,
    this.polygon,
  });

  double? getArea() => polygon?.getArea();

  bool containsPoint(LatLng point) {
    if (polygon == null) return false;
    return JtsHelper.pointInPolygon(point, polygon!);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'tags': tags,
        'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      };

  factory Fairway.fromMap(Map<String, dynamic> m) {
    final pts = (m['points'] as List)
        .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
        .toList();
    jts.Polygon? poly;
    if (pts.length >= 3) {
      try { poly = JtsHelper.fromLatLngPoints(pts); } catch (_) {}
    }
    return Fairway(
      id: m['id'] as int,
      tags: Map<String, dynamic>.from(m['tags'] as Map),
      points: pts,
      polygon: poly,
    );
  }

  @override
  String toString() {
    return 'Fairway(id: $id, points: ${points.length}, area: ${getArea()?.toStringAsFixed(8) ?? 'unknown'} sq degrees)';
  }
}

class Green {
  final int id;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final jts.Polygon? polygon;

  Green({
    required this.id,
    required this.points,
    required this.tags,
    this.polygon,
  });

  double? getArea() => polygon?.getArea();

  bool containsPoint(LatLng point) {
    if (polygon == null) return false;
    return JtsHelper.pointInPolygon(point, polygon!);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'tags': tags,
        'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      };

  factory Green.fromMap(Map<String, dynamic> m) {
    final pts = (m['points'] as List)
        .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
        .toList();
    jts.Polygon? poly;
    if (pts.length >= 3) {
      try { poly = JtsHelper.fromLatLngPoints(pts); } catch (_) {}
    }
    return Green(
      id: m['id'] as int,
      tags: Map<String, dynamic>.from(m['tags'] as Map),
      points: pts,
      polygon: poly,
    );
  }

  @override
  String toString() {
    return 'Green(id: $id, points: ${points.length}, area: ${getArea()?.toStringAsFixed(8) ?? 'unknown'} sq degrees)';
  }
}

class Hole {
  final int holeNumber;
  final int par;
  final int handicapIndex;
  final LatLng pin;

  final List<LatLng> routingLine;
  final List<TeeBox> teeBoxes;
  final List<TeePlatform> teePlatforms;
  final List<Fairway> fairways;
  final List<Green> greens;

  Hole({
    required this.holeNumber,
    required this.par,
    this.handicapIndex = 0,
    required this.pin,
    this.routingLine = const [],
    this.teeBoxes = const [],
    this.teePlatforms = const [],
    this.fairways = const [],
    this.greens = const [],
  });

  List<LatLng> get _allPoints => [
        ...routingLine,
        ...teePlatforms.expand((tp) => tp.points),
        ...fairways.expand((fw) => fw.points),
        ...greens.expand((g) => g.points),
        pin,
      ];

  LatLng get boundMin {
    final pts = _allPoints;
    return LatLng(
      pts.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
      pts.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
    );
  }

  LatLng get boundMax {
    final pts = _allPoints;
    return LatLng(
      pts.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
      pts.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
    );
  }

  List<LatLng> playLine() {
    LatLng? _centroid(List<LatLng> pts) {
      if (pts.isEmpty) return null;
      return LatLng(
        pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
        pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
      );
    }

    final List<LatLng> line = [];

    final teePoint = _centroid([
      ...teeBoxes.map((t) => t.position),
      ...teePlatforms.expand((tp) => tp.points),
    ]);
    if (teePoint != null) line.add(teePoint);

    if (fairways.isNotEmpty) {
      final ref = teePoint ?? pin;
      final dist = const Distance();
      final centroids = fairways
          .map((fw) => _centroid(fw.points))
          .whereType<LatLng>()
          .toList()
        ..sort(
          (a, b) => dist
              .as(LengthUnit.Meter, ref, a)
              .compareTo(dist.as(LengthUnit.Meter, ref, b)),
        );
      line.addAll(centroids);
    }

    line.add(pin);
    return line;
  }

  Map<String, dynamic> toMap() => {
        'holeNumber': holeNumber,
        'par': par,
        'handicapIndex': handicapIndex,
        'pin': {'lat': pin.latitude, 'lng': pin.longitude},
        'routingLine': routingLine
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'teeBoxes': teeBoxes.map((t) => t.toMap()).toList(),
        'teePlatforms': teePlatforms.map((tp) => tp.toMap()).toList(),
        'fairways': fairways.map((fw) => fw.toMap()).toList(),
        'greens': greens.map((g) => g.toMap()).toList(),
      };

  factory Hole.fromMap(Map<String, dynamic> m) => Hole(
        holeNumber: m['holeNumber'] as int,
        par: m['par'] as int,
        handicapIndex: m['handicapIndex'] as int? ?? 0,
        pin: LatLng(
          (m['pin'] as Map)['lat'] as double,
          (m['pin'] as Map)['lng'] as double,
        ),
        routingLine: (m['routingLine'] as List? ?? [])
            .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
            .toList(),
        teeBoxes: (m['teeBoxes'] as List? ?? [])
            .map((t) => TeeBox.fromMap(t as Map<String, dynamic>))
            .toList(),
        teePlatforms: (m['teePlatforms'] as List? ?? [])
            .map((t) => TeePlatform.fromMap(t as Map<String, dynamic>))
            .toList(),
        fairways: (m['fairways'] as List? ?? [])
            .map((t) => Fairway.fromMap(t as Map<String, dynamic>))
            .toList(),
        greens: (m['greens'] as List? ?? [])
            .map((t) => Green.fromMap(t as Map<String, dynamic>))
            .toList(),
      );

  @override
  String toString() {
    return 'Hole: $holeNumber, par: $par, hcp: $handicapIndex, pin: $pin';
  }
}

class Course {
  final String id;
  final String name;

  final jts.Polygon boundary;
  final List<TeeInfo> teeInfos;

  final List<Hole> holes;
  final List<List<LatLng>> cartPaths;

  Course({
    required this.id,
    required this.name,
    required this.boundary,
    this.teeInfos = const [],
    this.holes = const [],
    this.cartPaths = const [],
  });

  // Minimal course for scorecard display — no geometry.
  factory Course.stub({required String id, required String name}) => Course(
        id: id,
        name: name,
        boundary: JtsHelper.fromLatLngPoints([
          LatLng(0, 0), LatLng(0, 1), LatLng(1, 0), LatLng(0, 0),
        ]),
      );

  // Reconstruct a Course from stored maps (no Overpass object).
  factory Course.fromMap(
    Map<String, dynamic> courseData,
    List<Map<String, dynamic>> holeMaps,
  ) {
    final boundaryPts = (courseData['boundaryPoints'] as List? ?? [])
        .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
        .toList();
    final boundary = boundaryPts.length >= 3
        ? JtsHelper.fromLatLngPoints(boundaryPts)
        : JtsHelper.fromLatLngPoints([
            LatLng(0, 0), LatLng(0, 1), LatLng(1, 0), LatLng(0, 0),
          ]);
    final cartPaths = (courseData['cartPaths'] as List? ?? [])
        .map((path) => (path as List)
            .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
            .toList())
        .toList();
    return Course(
      id: courseData['id'] as String,
      name: courseData['name'] as String,
      boundary: boundary,
      teeInfos: (courseData['teeInfos'] as List? ?? [])
          .map((t) => TeeInfo.fromMap(t as Map<String, dynamic>))
          .toList(),
      holes: holeMaps.map(Hole.fromMap).toList(),
      cartPaths: cartPaths,
    );
  }

  // Root document map (excludes holes sub-collection).
  Map<String, dynamic> toDocMap(List<LatLng> boundaryPoints) => {
        'id': id,
        'name': name,
        'holeCount': holes.length,
        'boundaryPoints': boundaryPoints
            .map((p) => {'lat': p.latitude, 'lng': p.longitude})
            .toList(),
        'teeInfos': teeInfos.map((t) => t.toMap()).toList(),
        'cartPaths': cartPaths
            .map((path) =>
                path.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList())
            .toList(),
        'updatedAt': DateTime.now(),
      };
}
