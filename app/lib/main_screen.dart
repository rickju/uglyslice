import 'package:flutter/material.dart';
import 'play_page.dart';
import 'scorecard_page.dart';
import 'settings_page.dart';
import 'models/round.dart';
import 'models/scorecard.dart';
import 'round_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final Scorecard _scorecard = Scorecard();
  Round? _currentRound;

  void _startRound(Round round) {
    setState(() {
      _currentRound = round;
      _selectedIndex = 0; // Switch to the "Play" tab to show the round
    });
  }

  Widget _buildPlayPage() {
    if (_currentRound != null) {
      return RoundPage(round: _currentRound!);
    } else {
      return PlayPage(onRoundStarted: _startRound);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> widgetOptions = <Widget>[
      _buildPlayPage(),
      _currentRound != null
          ? ScorecardPage(
              golfCourse: _currentRound!.course,
              scorecard: _scorecard,
              onScoreChanged: (hole, score) {
                setState(() {
                  _scorecard.setScore(hole, score);
                });
              },
            )
          : Scaffold(
              appBar: AppBar(title: const Text('Scorecard')),
              body: const Center(child: Text('Please start a round from the Play tab.'))),
      const SettingsPage(),
    ];

    return Scaffold(
      body: Center(
        child: widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.play_arrow),
            label: 'Play',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.scoreboard),
            label: 'Scorecards',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.amber[800],
        onTap: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
