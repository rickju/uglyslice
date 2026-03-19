import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite store for raw Overpass API responses.
/// Every fetch is appended as a new row — no overwrites — so the full history
/// is preserved for re-parsing and debugging.
class RawJsonStore {
  final String dbPath;

  Database? _db;

  // Initialise sqflite FFI once per process.
  static bool _ffiInitialised = false;
  static void _ensureFfi() {
    if (_ffiInitialised) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _ffiInitialised = true;
  }

  RawJsonStore({String? path}) : dbPath = path ?? '/tmp/overpass_cache.db';

  Future<Database> _open() async {
    if (_db != null) return _db!;
    _ensureFfi();
    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE overpass_cache (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            name          TEXT NOT NULL,
            raw_json      TEXT NOT NULL,
            element_count INTEGER NOT NULL,
            fetched_at    INTEGER NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_overpass_cache_name ON overpass_cache (name)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Migrate: drop old name-keyed table, create append-only one.
          await db.execute('DROP TABLE IF EXISTS overpass_cache');
          await db.execute('''
            CREATE TABLE overpass_cache (
              id            INTEGER PRIMARY KEY AUTOINCREMENT,
              name          TEXT NOT NULL,
              raw_json      TEXT NOT NULL,
              element_count INTEGER NOT NULL,
              fetched_at    INTEGER NOT NULL
            )
          ''');
          await db.execute(
              'CREATE INDEX idx_overpass_cache_name ON overpass_cache (name)');
        }
      },
    );
    return _db!;
  }

  /// Returns the most recent cached raw JSON for [name], or null if not found.
  Future<String?> load(String name) async {
    final db = await _open();
    final rows = await db.query(
      'overpass_cache',
      columns: ['raw_json'],
      where: 'name = ?',
      whereArgs: [name],
      orderBy: 'fetched_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['raw_json'] as String;
  }

  Future<void> save(String name, String rawJson, int elementCount) async {
    final db = await _open();
    await db.insert('overpass_cache', {
      'name': name,
      'raw_json': rawJson,
      'element_count': elementCount,
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // System cache keys like __all_nz__ start with '__'. Filter them out.
  static const _systemKeyFilter = "name NOT LIKE '\\_%' ESCAPE '\\'";

  /// Returns all distinct course names in the cache, sorted alphabetically.
  Future<List<String>> listNames() async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT DISTINCT name FROM overpass_cache WHERE $_systemKeyFilter ORDER BY name',
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Returns names that contain [query] (case-insensitive).
  Future<List<String>> search(String query) async {
    final db = await _open();
    final rows = await db.rawQuery(
      'SELECT DISTINCT name FROM overpass_cache '
      'WHERE name LIKE ? AND $_systemKeyFilter '
      'ORDER BY name',
      ['%$query%'],
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
