class Scorecard {
  late List<int> scores;

  Scorecard({int holeCount = 18}) {
    scores = List<int>.filled(holeCount, 0);
  }

  void setScore(int holeIndex, int score) {
    if (holeIndex >= 0 && holeIndex < scores.length) {
      scores[holeIndex] = score;
    }
  }

  int getScore(int holeIndex) {
    if (holeIndex >= 0 && holeIndex < scores.length) {
      return scores[holeIndex];
    }
    return 0;
  }

  int get totalScore {
    return scores.reduce((a, b) => a + b);
  }
}
