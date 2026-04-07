// Pure Dart value objects representing data shown to the user.
// No Flutter imports — safe to use in headless tests.

class HoleDistanceDisplay {
  /// Yards to the back edge of the green (null = no green polygon data).
  final int? distBack;

  /// Yards to the pin.
  final int distPin;

  /// Yards to the front edge of the green (null = no green polygon data).
  final int? distFront;

  const HoleDistanceDisplay({
    this.distBack,
    required this.distPin,
    this.distFront,
  });
}

class HoleStrokeDisplay {
  final int holeNumber;
  final int par;

  /// Current stroke count; defaults to par when the hole has not been touched.
  final int strokes;

  const HoleStrokeDisplay({
    required this.holeNumber,
    required this.par,
    required this.strokes,
  });
}

class ScorecardRow {
  final int holeNumber;

  /// null when par data has not loaded yet.
  final int? par;
  final int score;

  /// score − par; null when par unknown; 0 = even.
  final int? relToPar;
  final int putts;

  /// null when par == 0 (unknown).
  final bool? gir;

  /// null for par 3 (or par unknown).
  final bool? fir;

  /// Formatted club sequence e.g. "Dr·7i·2Pu".
  final String clubs;

  const ScorecardRow({
    required this.holeNumber,
    this.par,
    required this.score,
    this.relToPar,
    required this.putts,
    this.gir,
    this.fir,
    required this.clubs,
  });
}

class ScorecardSummary {
  final int totalScore;
  final int totalPar;

  /// null when par data is unavailable.
  final int? totalRelToPar;
  final int totalPutts;
  final int girHit;

  /// Holes where GIR was measurable (par known and > 0).
  final int girTotal;
  final int firHit;

  /// Holes where FIR was measurable (par 4+).
  final int firTotal;

  /// e.g. "67%" or "-" when no measurable holes.
  final String girPct;
  final String firPct;

  const ScorecardSummary({
    required this.totalScore,
    required this.totalPar,
    this.totalRelToPar,
    required this.totalPutts,
    required this.girHit,
    required this.girTotal,
    required this.firHit,
    required this.firTotal,
    required this.girPct,
    required this.firPct,
  });
}
