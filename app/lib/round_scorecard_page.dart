import 'package:flutter/material.dart';

import 'models/round.dart';
import 'services/course_repository.dart';
import 'viewmodels/scorecard_view_model.dart';
import 'viewmodels/display_models.dart';
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final holePlays = widget.round.holePlays;
    final rows    = ScorecardViewModel.buildRows(holePlays: holePlays, pars: _pars);
    final summary = ScorecardViewModel.buildSummary(holePlays: holePlays, pars: _pars);

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
                    ...rows.map((row) => _holeRow(row)),
                  ],
                ),
              ),
            ),
          ),
          _footer(summary),
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

  TableRow _holeRow(ScorecardRow row) {
    return TableRow(
      decoration: BoxDecoration(
        color: row.holeNumber.isEven ? Colors.grey[900] : Colors.grey[850],
      ),
      children: [
        _Cell('${row.holeNumber}'),
        _Cell(row.par != null && row.par! > 0 ? '${row.par}' : '-'),
        _Cell('${row.score}', bold: true),
        _Cell(
          ScorecardViewModel.relDisplay(row.relToPar),
          color: _relColor(row.relToPar),
          bold: true,
        ),
        _Cell(row.score > 0 ? '${row.putts}' : '-'),
        _Cell(
          row.gir == null ? '-' : row.gir! ? '✓' : '✗',
          color: row.gir == null ? null : row.gir! ? Colors.green[300] : Colors.red[300],
        ),
        _Cell(
          row.fir == null ? '-' : row.fir! ? '✓' : '✗',
          color: row.fir == null ? null : row.fir! ? Colors.green[300] : Colors.red[300],
        ),
        _Cell(row.score > 0 ? row.clubs : '-', left: true),
      ],
    );
  }

  Widget _footer(ScorecardSummary s) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _FooterStat(label: 'Score', value: '${s.totalScore}'),
          if (s.totalPar > 0) _FooterStat(label: 'Par', value: '${s.totalPar}'),
          if (s.totalRelToPar != null)
            _FooterStat(
              label: 'Result',
              value: ScorecardViewModel.relDisplay(s.totalRelToPar),
              valueColor: _relColor(s.totalRelToPar),
            ),
          _FooterStat(label: 'Putts', value: '${s.totalPutts}'),
          _FooterStat(label: 'GIR', value: s.girPct),
          _FooterStat(label: 'FIR', value: s.firPct),
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
