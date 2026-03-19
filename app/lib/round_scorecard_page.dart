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
  // hole number → par (loaded from local course data if available)
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

  @override
  Widget build(BuildContext context) {
    final holePlays = widget.round.holePlays;
    final totalScore = holePlays.fold(0, (s, hp) => s + hp.score);
    final totalPar = _pars.values.fold(0, (s, p) => s + p);
    final diff = totalPar > 0 ? totalScore - totalPar : null;
    final date = widget.round.date;
    final dateStr =
        '${date.day} ${_month(date.month)} ${date.year}';

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
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(52),  // hole
                  1: FixedColumnWidth(44),  // par
                  2: FlexColumnWidth(),     // score
                  3: FixedColumnWidth(52),  // +/-
                },
                children: [
                  _headerRow(),
                  ...holePlays.map((hp) => _holeRow(hp)),
                ],
              ),
            ),
          ),
          _footer(totalScore, totalPar, diff),
        ],
      ),
    );
  }

  TableRow _headerRow() => TableRow(
        decoration: BoxDecoration(color: Colors.grey[850]),
        children: const [
          _Cell('Hole', header: true),
          _Cell('Par', header: true),
          _Cell('Score', header: true),
          _Cell('+/-', header: true),
        ],
      );

  TableRow _holeRow(HolePlay hp) {
    final par = _pars[hp.holeNumber] ?? 0;
    final score = hp.score;
    final rel = par > 0 ? score - par : null;
    final color = _relColor(rel);

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
          color: color,
          bold: true,
        ),
      ],
    );
  }

  Widget _footer(int total, int par, int? diff) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _FooterStat(label: 'Score', value: '$total'),
          if (par > 0) _FooterStat(label: 'Par', value: '$par'),
          if (diff != null)
            _FooterStat(
              label: 'Result',
              value: diff == 0 ? 'E' : '${diff > 0 ? '+' : ''}$diff',
              valueColor: _relColor(diff),
            ),
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
  final Color? color;

  const _Cell(this.text,
      {this.header = false, this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color ?? (header ? Colors.grey[400] : Colors.white),
          fontWeight:
              (header || bold) ? FontWeight.bold : FontWeight.normal,
          fontSize: header ? 12 : 15,
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
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}
