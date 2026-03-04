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

  @override
  String toString() {
    return 'TeeInfo: $color, $yardage, course rating: $courseRating, slope rating: $slopeRating\n';
  }
}

// tee box (a point) & tee platform (a rect) for a hole
class TeeBox {
  final LatLng position;
  TeeBox({required this.position});
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

  final LatLng boundMin, boundMax;
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
    this.teeBoxes = const [],
    this.teePlatforms = const [],
    this.fairways = const [],
    this.greens = const [],
    required this.boundMin,
    required this.boundMax,
  });

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

    // bounds - use way bounds if available, otherwise create from points
    LatLng boundMin, boundMax;
    if (way.bounds != null) {
      boundMin = way.bounds!.southWest;
      boundMax = way.bounds!.northEast;
    } else if (way.points.isNotEmpty) {
      // Calculate bounds from points
      double minLat = way.points[0].latitude;
      double minLon = way.points[0].longitude;
      double maxLat = way.points[0].latitude;
      double maxLon = way.points[0].longitude;

      for (final point in way.points) {
        if (point.latitude < minLat) minLat = point.latitude;
        if (point.longitude < minLon) minLon = point.longitude;
        if (point.latitude > maxLat) maxLat = point.latitude;
        if (point.longitude > maxLon) maxLon = point.longitude;
      }

      boundMin = LatLng(minLat, minLon);
      boundMax = LatLng(maxLat, maxLon);
    } else {
      // No bounds available
      boundMin = LatLng(0.0, 0.0);
      boundMax = LatLng(0.0, 0.0);
    }

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
      teeBoxes: teeBoxes,
      teePlatforms: [],
      fairways: [],
      greens: [],
      boundMin: boundMin,
      boundMax: boundMax,
    );
  }

  @override
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
  // bunker, hazard,
  // addr/phone etc. in tags
  // facility e.g. clubhouse/cartpath

  Course({
    required this.id,
    required this.name,
    required this.overpass,
    required this.boundary,
    this.teeInfos = const [],
    this.holes = const [],
  });

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

    return Course(
      id: courseId,
      name: courseName,
      overpass: overpass,
      boundary: boundary,
      teeInfos: teeInfos,
      holes: holes,
    );
  }
}
