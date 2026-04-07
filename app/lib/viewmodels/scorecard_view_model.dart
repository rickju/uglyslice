import 'package:ugly_slice_shared/club.dart';
import 'package:ugly_slice_shared/round_data.dart';

import 'display_models.dart';

/// Pure Dart computation layer for the scorecard screen.
/// All methods are static — no state, no Flutter imports.
class ScorecardViewModel {
  /// Builds one [ScorecardRow] per [HolePlay].
  ///
  /// [pars] maps holeNumber → par. May be empty while loading.
  static List<ScorecardRow> buildRows({
    required List<HolePlay> holePlays,
    required Map<int, int> pars,
  }) {
    return holePlays.map((hp) {
      final par = pars[hp.holeNumber];
      final rel = par != null && par > 0 ? hp.score - par : null;
      return ScorecardRow(
        holeNumber: hp.holeNumber,
        par: par,
        score: hp.score,
        relToPar: rel,
        putts: putts(hp),
        gir: gir(hp, par ?? 0),
        fir: fir(hp, par ?? 0),
        clubs: clubs(hp),
      );
    }).toList();
  }

  /// Aggregates all [HolePlay]s into summary totals.
  static ScorecardSummary buildSummary({
    required List<HolePlay> holePlays,
    required Map<int, int> pars,
  }) {
    final totalScore = holePlays.fold(0, (s, hp) => s + hp.score);
    final totalPar = pars.values.fold(0, (s, p) => s + p);
    final totalRelToPar = totalPar > 0 ? totalScore - totalPar : null;
    final totalPutts = holePlays.fold(0, (s, hp) => s + putts(hp));

    final girValues = holePlays.map((hp) => gir(hp, pars[hp.holeNumber] ?? 0));
    final girHit = girValues.where((v) => v == true).length;
    final girTotal = girValues.where((v) => v != null).length;

    final firValues = holePlays.map((hp) => fir(hp, pars[hp.holeNumber] ?? 0));
    final firHit = firValues.where((v) => v == true).length;
    final firTotal = firValues.where((v) => v != null).length;

    return ScorecardSummary(
      totalScore: totalScore,
      totalPar: totalPar,
      totalRelToPar: totalRelToPar,
      totalPutts: totalPutts,
      girHit: girHit,
      girTotal: girTotal,
      firHit: firHit,
      firTotal: firTotal,
      girPct: _pct(girHit, girTotal),
      firPct: _pct(firHit, firTotal),
    );
  }

  // ── Individually testable helpers ─────────────────────────────────────────

  /// Count of putts: shots where club is putter OR lie is green.
  static int putts(HolePlay hp) => hp.shots
      .where((s) => s.club?.type == ClubType.putter || s.lieType == LieType.green)
      .length;

  /// true = hit green in regulation (first putt/green shot at index ≤ par-2).
  /// null when par == 0 (unknown).
  static bool? gir(HolePlay hp, int par) {
    if (par == 0) return null;
    final idx = hp.shots.indexWhere(
        (s) => s.club?.type == ClubType.putter || s.lieType == LieType.green);
    if (idx < 0) return false;
    return idx <= par - 2;
  }

  /// true = first shot after tee landed in fairway. null for par 3 (or par < 4).
  static bool? fir(HolePlay hp, int par) {
    if (par < 4) return null;
    if (hp.shots.length < 2) return null;
    return hp.shots[1].lieType == LieType.fairway;
  }

  /// Formats score-vs-par as "E", "+3", "-1", or "-" (unknown).
  static String relDisplay(int? rel) {
    if (rel == null) return '-';
    if (rel == 0) return 'E';
    return '${rel > 0 ? '+' : ''}$rel';
  }

  /// Formatted club sequence e.g. "Dr·7i·2Pu".
  static String clubs(HolePlay hp) {
    final labels = hp.shots
        .map((s) => s.club == null ? '?' : clubLabel(s.club!))
        .toList();
    // Collapse consecutive putters into e.g. "2Pu".
    final collapsed = <String>[];
    for (final l in labels) {
      if (collapsed.isNotEmpty && collapsed.last.endsWith('Pu') && l == 'Pu') {
        final prev = collapsed.removeLast();
        final n = int.tryParse(prev.replaceAll('Pu', '')) ?? 1;
        collapsed.add('${n + 1}Pu');
      } else {
        collapsed.add(l);
      }
    }
    return collapsed.join('·');
  }

  /// Short label for a single club e.g. "Dr", "7i", "Pu", "SW".
  static String clubLabel(Club club) {
    switch (club.type) {
      case ClubType.driver:
        return 'Dr';
      case ClubType.wood:
        return '${club.number}w';
      case ClubType.hybrid:
        return '${club.number}h';
      case ClubType.putter:
        return 'Pu';
      case ClubType.iron:
        if (club.name == 'LW') return 'LW';
        if (club.name == 'SW') return 'SW';
        if (club.name == 'GW') return 'GW';
        if (club.name == 'PW') return 'PW';
        return club.number.isNotEmpty ? '${club.number}i' : '?';
    }
  }

  static String _pct(int hit, int total) =>
      total > 0 ? '${(hit / total * 100).round()}%' : '-';
}
