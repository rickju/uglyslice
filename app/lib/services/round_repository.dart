import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/round.dart';

class RoundRepository {
  static Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'ugly_slice.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE rounds (
            id TEXT PRIMARY KEY,
            player_name TEXT NOT NULL,
            date INTEGER NOT NULL,
            data TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// Save a new round. Returns the generated document ID.
  Future<String> saveRound(Round round) async {
    final db = await _database;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final map = round.toMap();
    map['date'] = round.date.millisecondsSinceEpoch;
    await db.insert('rounds', {
      'id': id,
      'player_name': round.player.name,
      'date': round.date.millisecondsSinceEpoch,
      'data': jsonEncode(map),
    });
    return id;
  }

  /// Overwrite an existing round document.
  Future<void> updateRound(String roundId, Round round) async {
    final db = await _database;
    final map = round.toMap();
    map['date'] = round.date.millisecondsSinceEpoch;
    await db.update(
      'rounds',
      {
        'player_name': round.player.name,
        'date': round.date.millisecondsSinceEpoch,
        'data': jsonEncode(map),
      },
      where: 'id = ?',
      whereArgs: [roundId],
    );
  }

  /// List all rounds for a player, newest first.
  /// Returns raw maps including the document id.
  Future<List<Map<String, dynamic>>> listRoundsForPlayer(
      String playerName) async {
    final db = await _database;
    final rows = await db.query(
      'rounds',
      where: 'player_name = ?',
      whereArgs: [playerName],
      orderBy: 'date DESC',
    );
    return rows.map((row) {
      final data =
          jsonDecode(row['data'] as String) as Map<String, dynamic>;
      // Normalise date back to DateTime for callers
      data['date'] =
          DateTime.fromMillisecondsSinceEpoch(row['date'] as int);
      return {'id': row['id'] as String, ...data};
    }).toList();
  }

  /// Load a single round. Returns null if not found.
  Future<Round?> loadRound(String roundId) async {
    final db = await _database;
    final rows = await db.query(
      'rounds',
      where: 'id = ?',
      whereArgs: [roundId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final data =
        jsonDecode(row['data'] as String) as Map<String, dynamic>;
    data['date'] =
        DateTime.fromMillisecondsSinceEpoch(row['date'] as int);
    return Round.fromScoreMap(data);
  }
}
