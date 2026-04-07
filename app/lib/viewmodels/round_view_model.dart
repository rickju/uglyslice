import 'package:latlong2/latlong.dart';

import '../models/course.dart';
import 'display_models.dart';

/// Pure Dart computation layer for the round-play screen.
/// All methods are static — no state, no Flutter imports.
class RoundViewModel {
  static const double _metersToYards = 1.09361;

  /// Green polygon points further than this from the pin are ignored.
  /// Prevents outlier OSM nodes from skewing front/back distances.
  static const double _greenFilterM = 60.0;

  /// Computes B/P/F yard distances from [playerPos] to the hole at [holeIndex].
  ///
  /// Returns null when [holes] is empty, [holeIndex] is out of range, or
  /// [playerPos] is null.
  static HoleDistanceDisplay? computeDistances({
    required List<Hole> holes,
    required int holeIndex,
    required LatLng? playerPos,
  }) {
    if (playerPos == null) return null;
    if (holes.isEmpty || holeIndex < 0 || holeIndex >= holes.length) return null;

    final hole = holes[holeIndex];
    final dist = const Distance();

    final distPinM = dist.as(LengthUnit.Meter, playerPos, hole.pin);
    final distPin = (distPinM * _metersToYards).round();

    // Front = green polygon point closest to player.
    // Back  = green polygon point farthest from player.
    // Filter to points within _greenFilterM of pin to exclude outlier nodes.
    final greenPoints = hole.greens
        .expand((g) => g.points)
        .where((pt) => dist.as(LengthUnit.Meter, hole.pin, pt) < _greenFilterM)
        .toList();

    if (greenPoints.isEmpty) {
      return HoleDistanceDisplay(distPin: distPin);
    }

    double minM = double.infinity, maxM = 0;
    for (final pt in greenPoints) {
      final m = dist.as(LengthUnit.Meter, playerPos, pt);
      if (m < minM) minM = m;
      if (m > maxM) maxM = m;
    }

    return HoleDistanceDisplay(
      distBack: (maxM * _metersToYards).round(),
      distPin: distPin,
      distFront: (minM * _metersToYards).round(),
    );
  }

  /// Display values for the stroke-count bar.
  ///
  /// [strokes] maps holeIndex → manual stroke count. Falls back to the hole's
  /// par when the index is absent (hole not yet touched).
  static HoleStrokeDisplay computeStrokeDisplay({
    required List<Hole> holes,
    required int holeIndex,
    required Map<int, int> strokes,
  }) {
    final hole = holes[holeIndex];
    return HoleStrokeDisplay(
      holeNumber: hole.holeNumber,
      par: hole.par,
      strokes: strokes[holeIndex] ?? hole.par,
    );
  }

  /// Shot-to-shot distance in yards between two GPS positions.
  static int shotDistanceYards(LatLng from, LatLng to) {
    final m = const Distance().as(LengthUnit.Meter, from, to);
    return (m * _metersToYards).round();
  }
}
