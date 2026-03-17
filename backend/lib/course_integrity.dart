import 'dart:math';
import 'course_parser.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

enum IssueSeverity { error, warning }

class CourseIssue {
  final IssueSeverity severity;
  final String message;
  final int? holeNumber; // null = course-level

  const CourseIssue({
    required this.severity,
    required this.message,
    this.holeNumber,
  });

  @override
  String toString() {
    final prefix = severity == IssueSeverity.error ? '[ERROR]' : '[WARN] ';
    final location =
        holeNumber != null ? 'Hole ${holeNumber.toString().padLeft(2)}: ' : 'Course:    ';
    return '$prefix $location$message';
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Run all integrity checks on a parsed course and return the issue list.
List<CourseIssue> checkIntegrity(ParsedCourse course) {
  final issues = <CourseIssue>[];

  _checkCourseLevelIssues(course, issues);

  for (final h in course.holeDocs) {
    _checkHole(h, issues);
  }

  return issues;
}

// ---------------------------------------------------------------------------
// Course-level checks
// ---------------------------------------------------------------------------

void _checkCourseLevelIssues(
    ParsedCourse course, List<CourseIssue> issues) {
  final holeCount = course.holeDocs.length;

  // Expected hole count
  if (holeCount == 0) {
    issues.add(const CourseIssue(
        severity: IssueSeverity.error, message: 'No holes parsed at all'));
    return;
  }
  if (holeCount != 9 && holeCount != 18) {
    issues.add(CourseIssue(
        severity: IssueSeverity.warning,
        message: 'Unusual hole count: $holeCount (expected 9 or 18)'));
  }

  // Boundary polygon
  final boundary =
      (course.courseDoc['boundaryPoints'] as List?)?.cast<Map>() ?? [];
  if (boundary.isEmpty) {
    issues.add(const CourseIssue(
        severity: IssueSeverity.warning,
        message: 'No boundary polygon — course way has no geometry'));
  }

  // Sequential hole numbers with no gaps or duplicates
  final nums = course.holeDocs
      .map((h) => h['holeNumber'] as int)
      .toList()
    ..sort();

  final dupes = <int>[];
  for (int i = 1; i < nums.length; i++) {
    if (nums[i] == nums[i - 1]) dupes.add(nums[i]);
  }
  if (dupes.isNotEmpty) {
    issues.add(CourseIssue(
        severity: IssueSeverity.error,
        message: 'Duplicate hole numbers: $dupes'));
  }

  final gaps = <int>[];
  for (int i = 1; i <= holeCount; i++) {
    if (!nums.contains(i)) gaps.add(i);
  }
  if (gaps.isNotEmpty) {
    issues.add(CourseIssue(
        severity: IssueSeverity.error,
        message: 'Missing holes: $gaps'));
  }

  // Total par sanity
  final totalPar = course.holeDocs.fold<int>(
      0, (sum, h) => sum + ((h['par'] as int?) ?? 0));
  if (holeCount == 18 && (totalPar < 68 || totalPar > 74)) {
    issues.add(CourseIssue(
        severity: IssueSeverity.warning,
        message: 'Unusual total par for 18 holes: $totalPar (expected 68–74)'));
  }
  if (holeCount == 9 && (totalPar < 33 || totalPar > 38)) {
    issues.add(CourseIssue(
        severity: IssueSeverity.warning,
        message: 'Unusual total par for 9 holes: $totalPar (expected 33–38)'));
  }
}

// ---------------------------------------------------------------------------
// Per-hole checks
// ---------------------------------------------------------------------------

void _checkHole(Map<String, dynamic> h, List<CourseIssue> issues) {
  final num = h['holeNumber'] as int;
  final par = (h['par'] as int?) ?? 0;

  void add(IssueSeverity sev, String msg) =>
      issues.add(CourseIssue(severity: sev, holeNumber: num, message: msg));

  // Par value
  if (par == 0) {
    add(IssueSeverity.error, 'Missing par tag');
  } else if (par < 3 || par > 5) {
    add(IssueSeverity.error, 'Invalid par: $par (must be 3–5)');
  }

  final greens = _polyList(h['greens']);
  final tees = _polyList(h['teePlatforms']);
  final fairways = _polyList(h['fairways']);
  final routingLine = _pointList(h['routingLine']);
  final pin = _latLng(h['pin']);

  // Green
  if (greens.isEmpty) {
    add(IssueSeverity.error, 'No green polygon');
  }

  // Tee platform
  if (tees.isEmpty) {
    final hasTeeBoxes = (_pointList(h['teeBoxes'])).isNotEmpty;
    if (hasTeeBoxes) {
      add(IssueSeverity.warning,
          'No tee platform polygon (has tee box node only)');
    } else {
      add(IssueSeverity.error, 'No tee platform or tee box');
    }
  }

  // Fairway (par 4/5 should have one)
  if (par >= 4 && fairways.isEmpty) {
    add(IssueSeverity.warning, 'Par $par hole has no fairway polygon');
  }

  // Routing line
  if (routingLine.length < 2) {
    add(IssueSeverity.error,
        'Routing line has only ${routingLine.length} point(s)');
  } else {
    // Routing length plausibility (degrees ≈ metres / 111000)
    final lengthDeg = _polylineLength(routingLine);
    final lengthM = lengthDeg * 111000;
    final (minM, maxM) = switch (par) {
      3 => (40.0, 280.0),
      4 => (90.0, 520.0),
      _ => (140.0, 650.0), // par 5
    };
    if (lengthM < minM) {
      add(IssueSeverity.warning,
          'Routing line very short for par $par: ${lengthM.toStringAsFixed(0)} m (min ~${minM.toInt()} m)');
    } else if (lengthM > maxM) {
      add(IssueSeverity.warning,
          'Routing line very long for par $par: ${lengthM.toStringAsFixed(0)} m (max ~${maxM.toInt()} m)');
    }
  }

  // Pin inside (or very near) a green
  if (pin != null && greens.isNotEmpty) {
    final pinInAnyGreen = greens.any((poly) => _pointInPolygon(pin, poly));
    if (!pinInAnyGreen) {
      final nearestDist = greens
          .map((poly) => _distToPolygon(pin, poly))
          .reduce(min);
      final nearestM = nearestDist * 111000;
      if (nearestM > 30) {
        add(IssueSeverity.error,
            'Pin is ${nearestM.toStringAsFixed(0)} m from nearest green');
      } else {
        add(IssueSeverity.warning,
            'Pin is outside green polygon but close (${nearestM.toStringAsFixed(0)} m) — likely tagging gap');
      }
    }
  }

  // Tee should not be co-located with pin (routing goes somewhere)
  if (pin != null && tees.isNotEmpty && routingLine.length >= 2) {
    final teeCenter = _polygonCentroid(tees.first);
    final teeToPinDeg = _dist(teeCenter, pin);
    final teeToPinM = teeToPinDeg * 111000;
    if (teeToPinM < 30) {
      add(IssueSeverity.error,
          'Tee platform and pin are co-located (${teeToPinM.toStringAsFixed(0)} m apart) — bad geometry');
    }
  }

  // Routing start should be near a tee (if tees exist)
  if (tees.isNotEmpty && routingLine.isNotEmpty) {
    final routeStart = routingLine.first;
    final teeCenter = _polygonCentroid(tees.first);
    final distM = _dist(routeStart, teeCenter) * 111000;
    if (distM > 100) {
      add(IssueSeverity.warning,
          'Routing line starts ${distM.toStringAsFixed(0)} m from tee centroid — may be reversed or misaligned');
    }
  }

  // Routing end should be near pin / green
  if (pin != null && routingLine.length >= 2) {
    final routeEnd = routingLine.last;
    final distM = _dist(routeEnd, pin) * 111000;
    if (distM > 80) {
      add(IssueSeverity.warning,
          'Routing line ends ${distM.toStringAsFixed(0)} m from pin — may not reach green');
    }
  }
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

typedef _Pt = ({double lat, double lng});

List<List<_Pt>> _polyList(dynamic raw) {
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .where((m) => (m['points'] as List?)?.isNotEmpty == true)
      .map((m) => _pointList(m['points']))
      .where((pts) => pts.length >= 3)
      .toList();
}

List<_Pt> _pointList(dynamic raw) {
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((m) => (lat: (m['lat'] as num).toDouble(), lng: (m['lng'] as num).toDouble()))
      .toList();
}

_Pt? _latLng(dynamic raw) {
  if (raw is! Map) return null;
  final lat = raw['lat'];
  final lng = raw['lng'];
  if (lat == null || lng == null) return null;
  return (lat: (lat as num).toDouble(), lng: (lng as num).toDouble());
}

double _dist(_Pt a, _Pt b) {
  final dLat = a.lat - b.lat;
  final dLng = a.lng - b.lng;
  return sqrt(dLat * dLat + dLng * dLng);
}

double _polylineLength(List<_Pt> pts) {
  double total = 0;
  for (int i = 1; i < pts.length; i++) {
    total += _dist(pts[i - 1], pts[i]);
  }
  return total;
}

_Pt _polygonCentroid(List<_Pt> poly) {
  final lat = poly.map((p) => p.lat).reduce((a, b) => a + b) / poly.length;
  final lng = poly.map((p) => p.lng).reduce((a, b) => a + b) / poly.length;
  return (lat: lat, lng: lng);
}

/// Ray-casting point-in-polygon.
bool _pointInPolygon(_Pt pt, List<_Pt> poly) {
  bool inside = false;
  int j = poly.length - 1;
  for (int i = 0; i < poly.length; j = i++) {
    final xi = poly[i].lng, yi = poly[i].lat;
    final xj = poly[j].lng, yj = poly[j].lat;
    final intersect = ((yi > pt.lat) != (yj > pt.lat)) &&
        (pt.lng < (xj - xi) * (pt.lat - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

/// Minimum distance from [pt] to any edge of [poly].
double _distToPolygon(_Pt pt, List<_Pt> poly) {
  double minDist = double.infinity;
  int j = poly.length - 1;
  for (int i = 0; i < poly.length; j = i++) {
    final d = _distToSegment(pt, poly[j], poly[i]);
    if (d < minDist) minDist = d;
  }
  return minDist;
}

double _distToSegment(_Pt p, _Pt a, _Pt b) {
  final dx = b.lat - a.lat;
  final dy = b.lng - a.lng;
  if (dx == 0 && dy == 0) return _dist(p, a);
  final t = ((p.lat - a.lat) * dx + (p.lng - a.lng) * dy) / (dx * dx + dy * dy);
  final clamped = t.clamp(0.0, 1.0);
  return _dist(p, (lat: a.lat + clamped * dx, lng: a.lng + clamped * dy));
}
