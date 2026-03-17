import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite cache for raw Overpass API responses.
/// Allows re-parsing without re-querying Overpass.
class RawJsonStore {
  final String dbPath;

  RawJsonStore({String? path}) : dbPath = path ?? '/tmp/overpass_cache.db';

  Future<Database> _open() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE overpass_cache (
            name          TEXT PRIMARY KEY,
            raw_json      TEXT NOT NULL,
            element_count INTEGER NOT NULL,
            fetched_at    INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> save(
      String courseName, String rawJson, int elementCount) async {
    final db = await _open();
    try {
      await db.insert(
        'overpass_cache',
        {
          'name': courseName,
          'raw_json': rawJson,
          'element_count': elementCount,
          'fetched_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } finally {
      await db.close();
    }
  }
}
