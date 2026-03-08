import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/round.dart';

class RoundRepository {
  final _db = FirebaseFirestore.instance;

  CollectionReference get _rounds => _db.collection('rounds');

  /// Save a new round. Returns the auto-generated Firestore document ID.
  Future<String> saveRound(Round round) async {
    final ref = await _rounds.add(_toFirestoreMap(round));
    return ref.id;
  }

  /// Overwrite an existing round document (call after each shot or hole completion).
  Future<void> updateRound(String roundId, Round round) async {
    await _rounds.doc(roundId).set(_toFirestoreMap(round));
  }

  /// List all rounds for a player, newest first.
  /// Returns raw maps — avoids loading full Course objects.
  Future<List<Map<String, dynamic>>> listRoundsForPlayer(
      String playerName) async {
    final snapshot = await _rounds
        .where('playerName', isEqualTo: playerName)
        .orderBy('date', descending: true)
        .get();
    return snapshot.docs
        .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
        .toList();
  }

  /// Load a single round with a stub Course (sufficient for scorecard display).
  Future<Round?> loadRound(String roundId) async {
    final doc = await _rounds.doc(roundId).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    // Convert Firestore Timestamp → DateTime before passing to fromScoreMap
    final normalised = {
      ...data,
      'date': (data['date'] as Timestamp).toDate(),
    };
    return Round.fromScoreMap(normalised);
  }

  Map<String, dynamic> _toFirestoreMap(Round round) {
    final m = round.toMap();
    // Replace Dart DateTime with Firestore Timestamp
    m['date'] = Timestamp.fromDate(round.date);
    return m;
  }
}
