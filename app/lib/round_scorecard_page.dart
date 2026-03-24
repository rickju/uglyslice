import 'package:flutter/material.dart';

import 'models/round.dart';
import 'services/course_repository.dart';
import 'main.dart' show db;

class RoundScorecardPage extends StatefulWidget {
  final Round round;

  const RoundScorecardPage({super.key, required this.round});

  @override
  State<RoundScorecardPage> createState() => _RoundScorecardPageState();
}

class _RoundScorecardPageState extends State<RoundScorecardPage> {
  Map<int, int> _pars = {};

  @override
  void initState() {
    super.initState();
    _loadPars();
  }

  Future<void> _loadPars() async {
    final repo = CourseRepository(db);
    final result = await repo.fetchCourseByName(widget.round.course.name);
    if (result == null) return;
    setState(() {
      _pars = {for (final h in result.course.holes) h.holeNumber: h.par};
    });
  }

  // ── Stat helpers ─────────────────────────────────────────────────────────

  int _putts(HolePlay hp) => hp.shots
      .where((s) => s.club?.type == ClubType.putter || s.lieType == LieType.green)
      .length;

  /// true = hit green in regulation (first putt at shot index ≤ par-2).
  bool? _gir(HolePlay hp, int par) {
    if (par == 0) return null;
    final idx = hp.shots.indexWhere(
        (s) => s.club?.type == ClubType.putter || s.lieType == LieType.green);
    if (idx < 0) return false;
    return idx <= par - 2;
  }

  /// true/false for par 4+5, null for par 3.
  bool? _fir(HolePlay hp, int par) {
    if (par < 4) return null;
    if (hp.shots.length < 2) return null;
    return hp.shots[1].lieType == LieType.fairway;
  }

  String _clubs(HolePlay hp) {
    final labels = hp.shots
        .map((s) => s.club == null ? '?' : _clubLabel(s.club!))
        .toList();
    // Collapse consecutive putters into e.g. "2Pu"
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

  String _clubLabel(Club club) {
    switch (club.type) {
      case ClubType.driver:  return 'Dr';
      case ClubType.wood:    return '${club.number}w';
      case ClubType.hybrid:  return '${club.number}h';
      case ClubType.putter:  return 'Pu';
      case ClubType.iron:
        if (club.name == 'LW') return 'LW';
        if (club.name == 'SW') return 'SW';
        if (club.name == 'GW') return 'GW';
        if (club.name == 'PW') return 'PW';
        return '${club.number}i';
      default:
        return club.number.isNotEmpty ? '${club.number}i' : '?';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final holePlays = widget.round.holePlays;
    final totalScore = holePlays.fold(0, (s, hp) => s + hp.score);
    final totalPar = _pars.values.fold(0, (s, p) => s + p);
    final diff = totalPar > 0 ? totalScore - totalPar : null;
    final totalPutts = holePlays.fold(0, (s, hp) => s + _putts(hp));

    final girList = holePlays.map((hp) => _gir(hp, _pars[hp.holeNumber] ?? 0));
    final girHit = girList.where((v) => v == true).length;
    final girTotal = girList.where((v) => v != null).length;

    final firList = holePlays.map((hp) => _fir(hp, _pars[hp.holeNumber] ?? 0));
    final firHit = firList.where((v) => v == true).length;
    final firTotal = firList.where((v) => v != null).length;

    final date = widget.round.date;
    final dateStr = '${date.day} ${_month(date.month)} ${date.year}';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.round.course.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(dateStr,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  children: [
                    _headerRow(),
                    ...holePlays.map((hp) => _holeRow(hp)),
                  ],
                ),
              ),
            ),
          ),
          _footer(
            totalScore: totalScore,
            totalPar: totalPar,
            diff: diff,
            totalPutts: totalPutts,
            girHit: girHit,
            girTotal: girTotal,
            firHit: firHit,
            firTotal: firTotal,
          ),
        ],
      ),
    );
  }

  TableRow _headerRow() => TableRow(
        decoration: BoxDecoration(color: Colors.grey[850]),
        children: const [
          _Cell('Hole', header: true),
          _Cell('Par',  header: true),
          _Cell('Score',header: true),
          _Cell('+/-',  header: true),
          _Cell('Putts',header: true),
          _Cell('GIR',  header: true),
          _Cell('FIR',  header: true),
          _Cell('Clubs',header: true, left: true),
        ],
      );

  TableRow _holeRow(HolePlay hp) {
    final par   = _pars[hp.holeNumber] ?? 0;
    final score = hp.score;
    final rel   = par > 0 ? score - par : null;
    final putts = _putts(hp);
    final gir   = _gir(hp, par);
    final fir   = _fir(hp, par);

    return TableRow(
      decoration: BoxDecoration(
        color: hp.holeNumber.isEven ? Colors.grey[900] : Colors.grey[850],
      ),
      children: [
        _Cell('${hp.holeNumber}'),
        _Cell(par > 0 ? '$par' : '-'),
        _Cell('$score', bold: true),
        _Cell(
          rel == null ? '-' : rel == 0 ? 'E' : '${rel > 0 ? '+' : ''}$rel',
          color: _relColor(rel),
          bold: true,
        ),
        _Cell(score > 0 ? '$putts' : '-'),
        _Cell(
          gir == null ? '-' : gir ? '✓' : '✗',
          color: gir == null ? null : gir ? Colors.green[300] : Colors.red[300],
        ),
        _Cell(
          fir == null ? '-' : fir ? '✓' : '✗',
          color: fir == null ? null : fir ? Colors.green[300] : Colors.red[300],
        ),
        _Cell(score > 0 ? _clubs(hp) : '-', left: true),
      ],
    );
  }

  Widget _footer({
    required int totalScore,
    required int totalPar,
    required int? diff,
    required int totalPutts,
    required int girHit,
    required int girTotal,
    required int firHit,
    required int firTotal,
  }) {
    String pct(int hit, int total) =>
        total > 0 ? '${(hit / total * 100).round()}%' : '-';

    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _FooterStat(label: 'Score', value: '$totalScore'),
          if (totalPar > 0) _FooterStat(label: 'Par', value: '$totalPar'),
          if (diff != null)
            _FooterStat(
              label: 'Result',
              value: diff == 0 ? 'E' : '${diff > 0 ? '+' : ''}$diff',
              valueColor: _relColor(diff),
            ),
          _FooterStat(label: 'Putts', value: '$totalPutts'),
          _FooterStat(label: 'GIR', value: pct(girHit, girTotal)),
          _FooterStat(label: 'FIR', value: pct(firHit, firTotal)),
        ],
      ),
    );
  }

  Color? _relColor(int? rel) {
    if (rel == null) return null;
    if (rel < 0) return Colors.red[300];
    if (rel == 0) return Colors.white;
    if (rel == 1) return Colors.orange[300];
    return Colors.orange[700];
  }

  String _month(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];
}

class _Cell extends StatelessWidget {
  final String text;
  final bool header;
  final bool bold;
  final bool left;
  final Color? color;

  const _Cell(this.text,
      {this.header = false, this.bold = false, this.left = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      child: Text(
        text,
        textAlign: left ? TextAlign.left : TextAlign.center,
        style: TextStyle(
          color: color ?? (header ? Colors.grey[400] : Colors.white),
          fontWeight: (header || bold) ? FontWeight.bold : FontWeight.normal,
          fontSize: header ? 11 : 14,
        ),
      ),
    );
  }
}

class _FooterStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _FooterStat(
      {required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}
