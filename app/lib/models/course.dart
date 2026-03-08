import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:collection/collection.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'overpass.dart';
import 'jts.dart';

// for a course, info for a named/colored tee. e.g. black: 5380y par: 72 courseRatings: 110.2 slopeRatings:
class TeeInfo {
  final String name;
  final String color; // name or color. pro, black, lady red, man white, man red
  final double yardage; // total distance. all holes combined
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

// tee box (a point) & tee platform (a rect) for a hole
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
  final LatLngBounds? bounds;
  final jts.Polygon? polygon;

  TeePlatform({
    required this.id,
    required this.points,
    required this.tags,
    this.bounds,
    this.polygon,
  });

  String? get color => tags['color'] as String?;

  // Axis-aligned bounding rect as a closed polygon ring (5 points).
  // Use this for rendering instead of the raw polygon — easier to read on map.
  List<LatLng> get boundingRect {
    final src = bounds != null
        ? [bounds!.southWest, bounds!.northEast]
        : points;
    if (src.isEmpty) return [];
    final minLat = src.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = src.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLon = src.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLon = src.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);
    return [
      LatLng(minLat, minLon),
      LatLng(maxLat, minLon),
      LatLng(maxLat, maxLon),
      LatLng(minLat, maxLon),
      LatLng(minLat, minLon),
    ];
  }

  static TeePlatform? fromWay(Way way) {
    if (way.tags['golf'] != 'tee' || way.points.length < 3) return null;
    return TeePlatform(
      id: way.id,
      points: way.points,
      tags: way.tags,
      bounds: way.bounds,
      polygon: way.polygon,
    );
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
  final LatLngBounds? bounds;
  final jts.Polygon? polygon;

  Fairway({
    required this.id,
    required this.points,
    required this.tags,
    this.bounds,
    this.polygon,
  });

  static Fairway? fromWay(Way way) {
    if (way.tags['golf'] != 'fairway' || way.points.length < 3) return null;
    return Fairway(
      id: way.id,
      points: way.points,
      tags: way.tags,
      bounds: way.bounds,
      polygon: way.polygon,
    );
  }

  /// Calculates the area of the fairway in square degrees
  double? getArea() {
    return polygon?.getArea();
  }

  /// Checks if a point is inside this fairway
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

class Bunker {
  final int id;
  final Map<String, dynamic> tags;
  final jts.Polygon? polygon;

  Bunker({required this.id, required this.tags, this.polygon});

  static Bunker? fromWay(Way way) => null;

  double? getArea() => polygon?.getArea();

  bool containsPoint(LatLng point) {
    if (polygon == null) return false;
    return JtsHelper.pointInPolygon(point, polygon!);
  }

  @override
  String toString() => 'Bunker(id: $id)';
}

class Hazard {
  final int id;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final LatLngBounds? bounds;
  final jts.Polygon? polygon;
  final List<Node> nodes;

  Hazard({
    required this.id,
    required this.points,
    required this.tags,
    this.bounds,
    this.polygon,
    this.nodes = const [],
  });

  static Hazard? fromWay(Way way) {}

  /// Calculates the area of the hazard in square degrees
  double? getArea() {
    return polygon?.getArea();
  }

  /// Checks if a point is inside this hazard
  bool containsPoint(LatLng point) {
    if (polygon == null) return false;
    return JtsHelper.pointInPolygon(point, polygon!);
  }

  /// Gets the hazard type (water_hazard, lateral_water_hazard, etc.)
  String? getHazardType() {
    return tags['golf'] as String?;
  }

  @override
  String toString() {
    final hazardType = getHazardType() ?? 'unknown';
    return 'Hazard(id: $id, type: $hazardType, points: ${points.length}, area: ${getArea()?.toStringAsFixed(8) ?? 'unknown'} sq degrees)';
  }
}

class Green {
  final int id;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final LatLngBounds? bounds;
  final jts.Polygon? polygon;

  Green({
    required this.id,
    required this.points,
    required this.tags,
    this.bounds,
    this.polygon,
  });

  static Green? fromWay(Way way) {
    if (way.tags['golf'] != 'green' || way.points.length < 3) return null;
    return Green(
      id: way.id,
      points: way.points,
      tags: way.tags,
      bounds: way.bounds,
      polygon: way.polygon,
    );
  }

  /// Calculates the area of the green in square degrees
  double? getArea() {
    return polygon?.getArea();
  }

  /// Checks if a point is inside this green
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
  // japan/double-grenen: different glass for different season.
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

  // All geometry points across every feature assigned to this hole.
  // Recomputed on access so it grows as fairways/greens/teePlatforms are added.
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

  // Ordered waypoints from tee to pin representing the intended playing line.
  // Tee centroid → fairway centroids (sorted by distance from tee) → pin.
  // Used for map rotation and future play-line overlay rendering.
  List<LatLng> playLine() {
    LatLng? _centroid(List<LatLng> pts) {
      if (pts.isEmpty) return null;
      return LatLng(
        pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
        pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
      );
    }

    final List<LatLng> line = [];

    // Tee end: prefer teeBox nodes, fall back to all teePlatform vertices
    final teePoint = _centroid([
      ...teeBoxes.map((t) => t.position),
      ...teePlatforms.expand((tp) => tp.points),
    ]);
    if (teePoint != null) line.add(teePoint);

    // Fairway centroids sorted by distance from tee (or pin when no tee)
    if (fairways.isNotEmpty) {
      final ref = teePoint ?? pin;
      final dist = const Distance();
      final centroids =
          fairways
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

  // arg Way: the specific Way object we want to parse as hole
  // arg overpass: whole overpass object from json
  static Hole? fromWay(Way way, Overpass overpass) {
    // for type:way/golf:hole, ref is hole number
    if (!way.tags.containsKey('ref')) {
      return null;
    }
    final holeNumber = int.parse(way.tags['ref']);
    final par = int.parse(way.tags['par'] ?? '0');
    final handicapIndex = int.parse(way.tags['handicap'] ?? '0');

    LatLng? pin;
    List<TeeBox> teeBoxes = [];

    void matchNode(Node node) {
      if (node.tags['golf'] == 'pin') {
        pin = node.toLatLng();
      } else if (node.tags['golf'] == 'tee') {
        teeBoxes.add(TeeBox(position: node.toLatLng()));
      }
    }

    if (way.nodeIds.isNotEmpty) {
      // Way was parsed with nodes array — cross-reference by ID
      for (final nodeId in way.nodeIds) {
        final node = overpass.nodes.firstWhereOrNull((n) => n.id == nodeId);
        if (node != null) matchNode(node);
      }
    } else if (way.points.isNotEmpty) {
      // Way was parsed from geometry (out geom) — match tagged nodes by position
      const tolerance = 1e-7;
      for (final node in overpass.nodes) {
        if (!node.tags.containsKey('golf')) continue;
        final bool onWay = way.points.any(
          (p) =>
              (p.latitude - node.lat).abs() < tolerance &&
              (p.longitude - node.lon).abs() < tolerance,
        );
        if (onWay) matchNode(node);
      }
    }

    if (pin == null) {
      return null;
    }

    return Hole(
      holeNumber: holeNumber,
      par: par,
      handicapIndex: handicapIndex,
      pin: pin!,
      routingLine: way.points,
      teeBoxes: teeBoxes,
      teePlatforms: [],
      fairways: [],
      greens: [],
    );
  }

  @override
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

  String toString() {
    return 'Hole: $holeNumber, par: $par, hcp: $handicapIndex, pin: $pin';
  }
}

class Course {
  final String id;
  final String name;
  final Overpass overpass;

  final jts.Polygon boundary;
  final List<TeeInfo> teeInfos;

  final List<Hole> holes;
  final List<List<LatLng>> cartPaths;
  // bunker, hazard, addr/phone etc. in tags

  Course({
    required this.id,
    required this.name,
    required this.overpass,
    required this.boundary,
    this.teeInfos = const [],
    this.holes = const [],
    this.cartPaths = const [],
  });

  // Minimal course for scorecard display — no geometry, no Overpass data.
  factory Course.stub({required String id, required String name}) => Course(
        id: id,
        name: name,
        overpass: Overpass(),
        boundary: JtsHelper.fromLatLngPoints([
          LatLng(0, 0), LatLng(0, 1), LatLng(1, 0), LatLng(0, 0),
        ]),
      );

  // Reconstruct a Course from Firestore maps (no Overpass object).
  // [courseData] is the root document map.
  // [holeMaps] is the ordered list of hole sub-document maps.
  factory Course.fromFirestore(
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
      overpass: Overpass(),
      boundary: boundary,
      teeInfos: (courseData['teeInfos'] as List? ?? [])
          .map((t) => TeeInfo.fromMap(t as Map<String, dynamic>))
          .toList(),
      holes: holeMaps.map(Hole.fromMap).toList(),
      cartPaths: cartPaths,
    );
  }

  // Firestore root document map (excludes holes sub-collection and Overpass blob).
  Map<String, dynamic> toFirestoreMap(List<LatLng> boundaryPoints) => {
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

  static Course fromJson(String json) {
    final overpass = Overpass.fromJson(json);

    // Find the main golf course way for boundary and course info
    final golfCourseWay = overpass.ways.firstWhere(
      (way) => way.tags['leisure'] == 'golf_course',
      orElse: () => throw Exception('No golf course way found in data'),
    );

    // Extract course name and ID
    final courseName =
        golfCourseWay.tags['name'] as String? ?? 'Unknown Golf Course';
    final courseId = 'course_${golfCourseWay.id}';

    // Create course boundary polygon
    final boundary =
        golfCourseWay.polygon ??
        (golfCourseWay.points.isNotEmpty
            ? JtsHelper.fromLatLngPoints(golfCourseWay.points)
            : throw Exception(
                'Golf course way has no valid polygon or points',
              ));

    // Extract holes from ways with golf=hole tag
    final List<Hole> holes = [];
    final holeWays = overpass.ways
        .where((way) => way.tags['golf'] == 'hole')
        .toList();

    for (final holeWay in holeWays) {
      final hole = Hole.fromWay(holeWay, overpass);
      if (hole != null) {
        holes.add(hole);
      }
    }

    // Sort holes by hole number
    holes.sort((a, b) => a.holeNumber.compareTo(b.holeNumber));

    // Build shared lookup maps for hole assignment.
    // Use a padded bounding box — hole ways are routing lines (tee→pin) so
    // their geometry polygon is degenerate. Padding handles par-3 holes whose
    // line runs in one direction leaving almost no perpendicular area.
    const pad = 0.0003; // ~33 m, enough to catch features at box edges
    final Map<int, jts.Polygon?> holePolygons = {};
    final Map<int, LatLng> holeCentroids = {};
    for (final holeWay in holeWays) {
      final refStr = holeWay.tags['ref'] as String?;
      if (refStr == null) continue;
      final refNum = int.tryParse(refStr);
      if (refNum == null) continue;
      if (holeWay.bounds != null) {
        final b = holeWay.bounds!;
        final minLat = b.southWest.latitude - pad;
        final minLon = b.southWest.longitude - pad;
        final maxLat = b.northEast.latitude + pad;
        final maxLon = b.northEast.longitude + pad;
        holePolygons[refNum] = JtsHelper.fromLatLngPoints([
          LatLng(minLat, minLon),
          LatLng(minLat, maxLon),
          LatLng(maxLat, maxLon),
          LatLng(maxLat, minLon),
        ]);
        holeCentroids[refNum] = LatLng(
          (b.southWest.latitude + b.northEast.latitude) / 2,
          (b.southWest.longitude + b.northEast.longitude) / 2,
        );
      } else if (holeWay.points.length >= 3) {
        holePolygons[refNum] =
            holeWay.polygon ?? JtsHelper.fromLatLngPoints(holeWay.points);
      }
    }
    final Map<int, Hole> holeByNumber = {
      for (final hole in holes) hole.holeNumber: hole,
    };

    // Assign a feature to its hole:
    //   1. by ref tag
    //   2. by padded bounding box containment
    //   3. fallback: nearest hole by centroid distance
    void assignToHole(dynamic feature, void Function(Hole) add) {
      final refStr = feature.tags['ref'] as String?;
      if (refStr != null) {
        final refNum = int.tryParse(refStr);
        if (refNum != null && holeByNumber.containsKey(refNum)) {
          add(holeByNumber[refNum]!);
          return;
        }
      }

      if (feature.polygon == null) return;
      final centroid = feature.polygon!.getCentroid();
      final centroidLatLng = LatLng(centroid.getY(), centroid.getX());

      double pinDist(Hole hole) {
        final dLat = centroidLatLng.latitude - hole.pin.latitude;
        final dLon = centroidLatLng.longitude - hole.pin.longitude;
        return dLat * dLat + dLon * dLon;
      }

      // Among all holes whose padded bbox contains the feature, pick the one
      // whose pin is nearest — the green/tee is always at the pin end.
      Hole? nearest;
      double minDist = double.infinity;
      for (final hole in holes) {
        final holePoly = holePolygons[hole.holeNumber];
        if (holePoly == null) continue;
        if (!JtsHelper.pointInPolygon(centroidLatLng, holePoly)) continue;
        final d = pinDist(hole);
        if (d < minDist) {
          minDist = d;
          nearest = hole;
        }
      }
      if (nearest != null) {
        add(nearest);
        return;
      }

      // Fallback: no bbox match — assign to nearest hole by pin distance
      minDist = double.infinity;
      for (final hole in holes) {
        final d = pinDist(hole);
        if (d < minDist) {
          minDist = d;
          nearest = hole;
        }
      }
      if (nearest != null) add(nearest);
    }

    // Add fairways to their respective holes
    for (final way in overpass.ways.where((w) => w.tags['golf'] == 'fairway')) {
      final fw = Fairway.fromWay(way);
      if (fw != null) assignToHole(fw, (h) => h.fairways.add(fw));
    }

    // Add greens to their respective holes
    for (final way in overpass.ways.where((w) => w.tags['golf'] == 'green')) {
      final gr = Green.fromWay(way);
      if (gr != null) assignToHole(gr, (h) => h.greens.add(gr));
    }

    // Add tee platforms to their respective holes
    for (final way in overpass.ways.where((w) => w.tags['golf'] == 'tee')) {
      final tp = TeePlatform.fromWay(way);
      if (tp != null) assignToHole(tp, (h) => h.teePlatforms.add(tp));
    }

    // Extract tee information (basic implementation)
    final List<TeeInfo> teeInfos = [];
    final teeWays = overpass.ways
        .where((way) => way.tags['golf'] == 'tee')
        .toList();
    final teeColors = <String>{};

    for (final teeWay in teeWays) {
      final color = teeWay.tags['tee'] as String? ?? 'unknown';
      teeColors.add(color);
    }

    // Create TeeInfo objects for each unique color found
    for (final color in teeColors) {
      teeInfos.add(
        TeeInfo(
          name: color,
          color: color,
          yardage: 0.0, // Would need to calculate from hole distances
          courseRating: 0.0, // Not available in basic Overpass data
          slopeRating: 0.0, // Not available in basic Overpass data
        ),
      );
    }

    final cartPaths = overpass.ways
        .where((w) => w.tags['golf'] == 'cartpath' && w.points.length >= 2)
        .map((w) => w.points)
        .toList();

    return Course(
      id: courseId,
      name: courseName,
      overpass: overpass,
      boundary: boundary,
      teeInfos: teeInfos,
      holes: holes,
      cartPaths: cartPaths,
    );
  }
}
