import 'package:latlong2/latlong.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:collection/collection.dart';
import 'overpass.dart';
import 'jts_helper.dart';

// ---------------------------------------------------------------------------
// Data model classes (backend copies — use BBox instead of LatLngBounds)
// ---------------------------------------------------------------------------

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
}

class TeeBox {
  final LatLng position;
  TeeBox({required this.position});

  Map<String, dynamic> toMap() => {
        'lat': position.latitude,
        'lng': position.longitude,
      };
}

class TeePlatform {
  final int id;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final BBox? bounds;
  final jts.Polygon? polygon;

  TeePlatform({
    required this.id,
    required this.points,
    required this.tags,
    this.bounds,
    this.polygon,
  });

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
}

class Fairway {
  final int id;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final BBox? bounds;
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'tags': tags,
        'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      };
}

class Green {
  final int id;
  final List<LatLng> points;
  final Map<String, dynamic> tags;
  final BBox? bounds;
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'tags': tags,
        'points': points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      };
}

class Hole {
  final int holeNumber;
  final int par;
  final int handicapIndex;
  LatLng pin;
  List<LatLng> routingLine;
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
    List<TeePlatform>? teePlatforms,
    List<Fairway>? fairways,
    List<Green>? greens,
  })  : teePlatforms = teePlatforms ?? [],
        fairways = fairways ?? [],
        greens = greens ?? [];

  static Hole? fromWay(Way way, Overpass overpass) {
    if (!way.tags.containsKey('ref')) return null;
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
      for (final nodeId in way.nodeIds) {
        final node = overpass.nodes.firstWhereOrNull((n) => n.id == nodeId);
        if (node != null) matchNode(node);
      }
    } else if (way.points.isNotEmpty) {
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

    // Fallback: last point of the hole way is the pin (OSM convention)
    pin ??= way.points.isNotEmpty ? way.points.last : null;
    if (pin == null) return null;

    return Hole(
      holeNumber: holeNumber,
      par: par,
      handicapIndex: handicapIndex,
      pin: pin!,
      routingLine: way.points,
      teeBoxes: teeBoxes,
    );
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
}

// ---------------------------------------------------------------------------
// Parse result
// ---------------------------------------------------------------------------

class ParsedCourse {
  final String courseId;
  final Map<String, dynamic> courseDoc;
  final List<Map<String, dynamic>> holeDocs;

  ParsedCourse({
    required this.courseId,
    required this.courseDoc,
    required this.holeDocs,
  });
}

// ---------------------------------------------------------------------------
// Main parse functions
// ---------------------------------------------------------------------------

/// Parse raw Overpass JSON containing a single course.
ParsedCourse parseCourse(String json) {
  final overpass = Overpass.fromJson(json);

  final golfCourseWay = overpass.ways.firstWhere(
    (way) => way.tags['leisure'] == 'golf_course',
    orElse: () => throw Exception('No golf course way found in data'),
  );

  return _parseCourseFromWay(overpass, golfCourseWay);
}

/// Parse all courses found in a multi-course Overpass bbox response.
/// Skips courses with no polygon geometry (node-only).
List<ParsedCourse> parseAllCourses(String json) {
  final overpass = Overpass.fromJson(json);

  final courseWays = overpass.ways
      .where((w) =>
          w.tags['leisure'] == 'golf_course' &&
          (w.polygon != null || w.points.length >= 3))
      .toList();

  final results = <ParsedCourse>[];
  for (final courseWay in courseWays) {
    try {
      final parsed = _parseCourseFromWay(overpass, courseWay);
      if (parsed.holeDocs.isEmpty) continue;
      if ((parsed.courseDoc['name'] as String) == 'Unknown Golf Course') continue;
      results.add(parsed);
    } catch (_) {
      // Skip individual failures silently — caller can compare counts
    }
  }
  return results;
}

/// Parse a single course way from a (possibly multi-course) Overpass dataset.
/// Features are scoped to the course boundary polygon.
ParsedCourse _parseCourseFromWay(Overpass overpass, Way golfCourseWay) {
  final courseName = golfCourseWay.tags['name'] as String? ?? 'Unknown Golf Course';
  final courseId = 'course_${golfCourseWay.id}';

  final boundary = golfCourseWay.polygon ??
      (golfCourseWay.points.isNotEmpty
          ? JtsHelper.fromLatLngPoints(golfCourseWay.points)
          : throw Exception('Golf course way has no valid polygon or points'));

  // Scope features to this course boundary (important for multi-course datasets)
  bool withinBoundary(Way way) {
    if (way.polygon != null) return boundary.intersects(way.polygon!);
    if (way.points.isNotEmpty) {
      final c = way.points.fold(
        LatLng(0, 0),
        (sum, p) => LatLng(sum.latitude + p.latitude, sum.longitude + p.longitude),
      );
      final centroid = LatLng(c.latitude / way.points.length, c.longitude / way.points.length);
      return JtsHelper.pointInPolygon(centroid, boundary);
    }
    return false;
  }

  final scopedWays = overpass.ways.where((w) => w.id != golfCourseWay.id && withinBoundary(w)).toList();

  // Extract holes
  final List<Hole> holes = [];
  final holeWays = scopedWays.where((way) => way.tags['golf'] == 'hole').toList();

  for (final holeWay in holeWays) {
    final hole = Hole.fromWay(holeWay, overpass);
    if (hole != null) holes.add(hole);
  }
  holes.sort((a, b) => a.holeNumber.compareTo(b.holeNumber));

  // Build padded bounding box polygons for hole assignment
  const pad = 0.0003;
  final Map<int, jts.Polygon?> holePolygons = {};
  final Map<int, LatLng> holeCentroids = {};
  for (final holeWay in holeWays) {
    final refStr = holeWay.tags['ref'] as String?;
    if (refStr == null) continue;
    final refNum = int.tryParse(refStr);
    if (refNum == null) continue;
    if (holeWay.bounds != null) {
      final b = holeWay.bounds!;
      final minLat = b.minLat - pad;
      final minLon = b.minLon - pad;
      final maxLat = b.maxLat + pad;
      final maxLon = b.maxLon + pad;
      holePolygons[refNum] = JtsHelper.fromLatLngPoints([
        LatLng(minLat, minLon),
        LatLng(minLat, maxLon),
        LatLng(maxLat, maxLon),
        LatLng(maxLat, minLon),
      ]);
      holeCentroids[refNum] = LatLng(
        (b.minLat + b.maxLat) / 2,
        (b.minLon + b.maxLon) / 2,
      );
    } else if (holeWay.points.length >= 3) {
      holePolygons[refNum] =
          holeWay.polygon ?? JtsHelper.fromLatLngPoints(holeWay.points);
    }
  }
  final Map<int, Hole> holeByNumber = {
    for (final hole in holes) hole.holeNumber: hole,
  };

  double _sq(LatLng a, LatLng b) {
    final dLat = a.latitude - b.latitude;
    final dLon = a.longitude - b.longitude;
    return dLat * dLat + dLon * dLon;
  }

  LatLng _polyCentroid(List<LatLng> pts) {
    final sumLat = pts.fold(0.0, (s, p) => s + p.latitude);
    final sumLon = pts.fold(0.0, (s, p) => s + p.longitude);
    return LatLng(sumLat / pts.length, sumLon / pts.length);
  }

  // ── Step 1: assign greens ──────────────────────────────────────────────────
  // Use hole polygon for containment; fallback to nearest routing.last
  // (the tentative pin end before orientation is confirmed).
  for (final way in scopedWays.where((w) => w.tags['golf'] == 'green')) {
    final gr = Green.fromWay(way);
    if (gr == null) continue;

    final refStr = way.tags['ref'] as String?;
    final refNum = refStr != null ? int.tryParse(refStr) : null;
    if (refNum != null && holeByNumber.containsKey(refNum)) {
      holeByNumber[refNum]!.greens.add(gr);
      continue;
    }

    if (gr.polygon == null) continue;
    final gc = gr.polygon!.getCentroid();
    final gcLatLng = LatLng(gc.getY(), gc.getX());

    // Try polygon containment first
    Hole? best;
    double minD = double.infinity;
    for (final hole in holes) {
      final poly = holePolygons[hole.holeNumber];
      if (poly == null || !JtsHelper.pointInPolygon(gcLatLng, poly)) continue;
      final d = _sq(gcLatLng, hole.routingLine.last);
      if (d < minD) { minD = d; best = hole; }
    }
    if (best != null) { best.greens.add(gr); continue; }

    // Fallback: nearest routing.last
    for (final hole in holes) {
      final d = _sq(gcLatLng, hole.routingLine.last);
      if (d < minD) { minD = d; best = hole; }
    }
    best?.greens.add(gr);
  }

  // ── Step 2: update pin to green centroid ──────────────────────────────────
  for (final hole in holes) {
    if (hole.greens.isEmpty) continue;
    final pts = hole.greens.first.points;
    if (pts.isNotEmpty) hole.pin = _polyCentroid(pts);
  }

  // ── Step 3: orient routing tee→pin ────────────────────────────────────────
  // Anchor priority: green centroid (reliable) → nearest scoped green within
  // 150 m. Result: routing.first = tee end, routing.last = pin end.
  for (final hole in holes) {
    if (hole.routingLine.length < 2) continue;

    LatLng anchor;
    if (hole.greens.isNotEmpty) {
      anchor = hole.pin; // already green centroid from step 2
    } else {
      // Find nearest green centroid to either endpoint
      LatLng? best;
      double minSq = double.infinity;
      for (final gw in scopedWays.where((w) => w.tags['golf'] == 'green')) {
        if (gw.points.isEmpty) continue;
        final gc = _polyCentroid(gw.points);
        for (final ep in [hole.routingLine.first, hole.routingLine.last]) {
          final d = _sq(ep, gc);
          if (d < minSq) { minSq = d; best = gc; }
        }
      }
      const thresh = (150.0 / 111000) * (150.0 / 111000);
      if (best == null || minSq > thresh) continue;
      anchor = best;
      hole.pin = anchor;
    }

    if (_sq(hole.routingLine.first, anchor) < _sq(hole.routingLine.last, anchor)) {
      hole.routingLine = hole.routingLine.reversed.toList();
    }
  }

  // ── Step 4: assign tee platforms ──────────────────────────────────────────
  // routing.first is now the reliable tee end. Assign each tee platform to
  // the hole whose routing.first is nearest (within 200 m).
  for (final way in scopedWays.where((w) => w.tags['golf'] == 'tee')) {
    final tp = TeePlatform.fromWay(way);
    if (tp == null || tp.points.isEmpty) continue;

    final refStr = way.tags['ref'] as String?;
    final refNum = refStr != null ? int.tryParse(refStr) : null;
    if (refNum != null && holeByNumber.containsKey(refNum)) {
      holeByNumber[refNum]!.teePlatforms.add(tp);
      continue;
    }

    final tc = _polyCentroid(tp.points);
    Hole? best;
    double minD = double.infinity;
    for (final hole in holes) {
      if (hole.routingLine.isEmpty) continue;
      final d = _sq(tc, hole.routingLine.first);
      if (d < minD) { minD = d; best = hole; }
    }
    const thresh = (200.0 / 111000) * (200.0 / 111000);
    if (best != null && minD < thresh) best.teePlatforms.add(tp);
  }

  // ── Step 5: assign fairways ───────────────────────────────────────────────
  // Fairways use polygon containment; fallback nearest pin.
  for (final way in scopedWays.where((w) => w.tags['golf'] == 'fairway')) {
    final fw = Fairway.fromWay(way);
    if (fw == null) continue;

    final refStr = way.tags['ref'] as String?;
    final refNum = refStr != null ? int.tryParse(refStr) : null;
    if (refNum != null && holeByNumber.containsKey(refNum)) {
      holeByNumber[refNum]!.fairways.add(fw);
      continue;
    }

    if (fw.polygon == null) continue;
    final fc = fw.polygon!.getCentroid();
    final fcLatLng = LatLng(fc.getY(), fc.getX());

    Hole? best;
    double minD = double.infinity;
    for (final hole in holes) {
      final poly = holePolygons[hole.holeNumber];
      if (poly == null || !JtsHelper.pointInPolygon(fcLatLng, poly)) continue;
      final d = _sq(fcLatLng, hole.pin);
      if (d < minD) { minD = d; best = hole; }
    }
    if (best != null) { best.fairways.add(fw); continue; }

    // Fallback: nearest pin
    for (final hole in holes) {
      final d = _sq(fcLatLng, hole.pin);
      if (d < minD) { minD = d; best = hole; }
    }
    best?.fairways.add(fw);
  }

  // Extract tee info from unique tee colors
  final teeColors = <String>{};
  for (final way in scopedWays.where((w) => w.tags['golf'] == 'tee')) {
    teeColors.add(way.tags['tee'] as String? ?? 'unknown');
  }
  final teeInfos = teeColors
      .map((color) => TeeInfo(name: color, color: color))
      .toList();

  final cartPaths = scopedWays
      .where((w) => w.tags['golf'] == 'cartpath' && w.points.length >= 2)
      .map((w) => w.points)
      .toList();

  // Extract boundary points from JTS polygon
  final boundaryPoints = <Map<String, double>>[];
  try {
    for (final c in boundary.getExteriorRing().getCoordinates()) {
      boundaryPoints.add({'lat': c.y, 'lng': c.x});
    }
  } catch (_) {}

  final courseDoc = {
    'id': courseId,
    'name': courseName,
    'holeCount': holes.length,
    'boundaryPoints': boundaryPoints,
    'teeInfos': teeInfos.map((t) => t.toMap()).toList(),
    'cartPaths': cartPaths
        .map((path) =>
            path.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList())
        .toList(),
    'updatedAt': DateTime.now().toIso8601String(),
  };

  final holeDocs = holes.map((h) => h.toMap()).toList();

  return ParsedCourse(
    courseId: courseId,
    courseDoc: courseDoc,
    holeDocs: holeDocs,
  );
}
