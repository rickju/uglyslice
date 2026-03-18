import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite cache for raw Overpass API responses.
/// Allows re-parsing without re-querying Overpass.
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
    return _db!;
  }

  Future<void> save(
      String courseName, String rawJson, int elementCount) async {
    final db = await _open();
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
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
