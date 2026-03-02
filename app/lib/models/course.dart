import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'dart:convert';
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
  final jts.Polygon polygon;
  // final List<Tee> tees;

  TeePlatform({required this.polygon});

  @override
  String toString() {
    return 'TeePlatform: XXX';
  }

  // arg Way: the specific Way object we want to parse as tee
  static TeePlatform? fromWay(Way way) {}
}

class Fairway {
  final List<Node> nodes;

  Fairway({required this.nodes});

  static Fairway? fromWay(Way way) {
    return null; // TODO: Implement fairway parsing
  }
}

class Bunker {}

class Hazard {}

class Green {
  final List<Node> nodes;

  Green({required this.nodes});

  static Green? fromWay(
    dynamic element,
    Way way,
    Map<int, Map<String, dynamic>> nodeTags,
    List<Node> nodes,
  ) {
    final bounds = LatLngBounds(
      LatLng(40.712, -74.006),
      LatLng(40.730, -73.935),
    );
    return null; // TODO: Implement green parsing
  }
}

class Hole {
  final int holeNumber;
  final int par;
  final int handicapIndex;
  final LatLng pin;

  final LatLng boundMin, boundMax;
  final List<TeeBox> tees;
  final List<Fairway> fairways;
  // japan/double-grenen: different glass for different season.
  final List<Green> greens;

  Hole({
    required this.holeNumber,
    required this.par,
    this.handicapIndex = 0,
    required this.pin,
    this.tees = const [],
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

    // pin/tee
    LatLng? pin;
    List<TeeBox> tees = [];
    print(
      '  - Processing hole ${way.tags["ref"]} with ${way.nodeIds.length} nodes.',
    );
    for (var i = 0; i < way.nodeIds.length; i++) {
      final nodeId = way.nodeIds[i];

      // nodes list. lj: overpass out geom does NOT include all nodes
      final Node? node = overpass.nodes.firstWhereOrNull((n) => n.id == nodeId);
      if (node != null) {
        print('    - Node ${node.id} tags: ${node.tags}');
        // node for pin/tee
        if (node.tags['golf'] == 'pin') {
          pin = node.toLatLng();
          print('      - Found pin at ${pin}');
        } else if (node.tags['golf'] == 'tee') {
          final tee = TeeBox(
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
      fairways: [], // TODO: Extract fairways from overpass data
      greens: [], // TODO: Extract greens from overpass data
      boundMin: boundMin,
      boundMax: boundMax,
    );
  }

  @override
  String toString() {
    return 'Hole: $holeNumber, par: $par, hcp: $handicapIndex, pin: $pin, tees: ${tees.toString()}';
  }
}

class Course {
  final String id;
  final String name;
  final Overpass overpass;

  final jts.Polygon boundary;
  final List<TeeInfo> teeInfos;

  final List<Hole> holes;
  // final List<Fairway> fairways;
  // final List<Tee> tees;
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
    final courseName = golfCourseWay.tags['name'] as String? ?? 'Unknown Golf Course';
    final courseId = 'course_${golfCourseWay.id}';

    // Create course boundary polygon
    final boundary = golfCourseWay.polygon ??
        (golfCourseWay.points.isNotEmpty
            ? JtsHelper.fromLatLngPoints(golfCourseWay.points)
            : throw Exception('Golf course way has no valid polygon or points'));

    // Extract holes from ways with golf=hole tag
    final List<Hole> holes = [];
    final holeWays = overpass.ways.where((way) => way.tags['golf'] == 'hole').toList();

    for (final holeWay in holeWays) {
      final hole = Hole.fromWay(holeWay, overpass);
      if (hole != null) {
        holes.add(hole);
      }
    }

    // Sort holes by hole number
    holes.sort((a, b) => a.holeNumber.compareTo(b.holeNumber));

    // Extract tee information (basic implementation)
    final List<TeeInfo> teeInfos = [];
    final teeWays = overpass.ways.where((way) => way.tags['golf'] == 'tee').toList();
    final teeColors = <String>{};

    for (final teeWay in teeWays) {
      final color = teeWay.tags['tee'] as String? ?? 'unknown';
      teeColors.add(color);
    }

    // Create TeeInfo objects for each unique color found
    for (final color in teeColors) {
      teeInfos.add(TeeInfo(
        name: color,
        color: color,
        yardage: 0.0, // Would need to calculate from hole distances
        courseRating: 0.0, // Not available in basic Overpass data
        slopeRating: 0.0, // Not available in basic Overpass data
      ));
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
