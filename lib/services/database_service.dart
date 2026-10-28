import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/playlist.dart';
import '../models/radio_station.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('soundwave.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabla para almacenar estaciones de radio y favoritos
    await db.execute('''
      CREATE TABLE radios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        genre TEXT,
        country TEXT,
        favicon TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        isFavorite INTEGER NOT NULL DEFAULT 0,
        lastPlayed INTEGER
      )
    ''');
    await _createLibraryTables(db);
  }

  // La versión 1 (la de Gemini) solo tenía la tabla de radios con 3 ejemplos.
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE radios ADD COLUMN country TEXT');
      await db.execute('ALTER TABLE radios ADD COLUMN favicon TEXT');
      await db.execute(
        "ALTER TABLE radios ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'",
      );
      await db.execute('ALTER TABLE radios ADD COLUMN lastPlayed INTEGER');
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS radios_url ON radios(url)',
      );
      await _createLibraryTables(db);
    }
  }

  Future<void> _createLibraryTables(Database db) async {
    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE playlist_songs (
        playlistId INTEGER NOT NULL,
        songId INTEGER NOT NULL,
        position INTEGER NOT NULL,
        PRIMARY KEY (playlistId, songId)
      )
    ''');
    await db.execute('''
      CREATE TABLE favorite_songs (
        songId INTEGER PRIMARY KEY
      )
    ''');
  }

  // ---------- Radios ----------

  // Obtener todas las estaciones: favoritas primero, luego por nombre
  Future<List<RadioStation>> getRadioStations() async {
    final db = await instance.database;
    final result = await db.query(
      'radios',
      orderBy: 'isFavorite DESC, name COLLATE NOCASE ASC',
    );
    return result.map((json) => RadioStation.fromMap(json)).toList();
  }

  /// Guarda una radio nueva. Si ya existe una con el mismo link, la deja como está.
  Future<void> addRadio(RadioStation radio) async {
    final db = await instance.database;
    final map = radio.toMap()..remove('id');
    await db.insert('radios', map, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Agrega muchas radios de una vez y devuelve cuántas eran nuevas.
  Future<int> addRadios(List<RadioStation> radios) async {
    final db = await instance.database;
    var added = 0;
    await db.transaction((txn) async {
      for (final radio in radios) {
        final map = radio.toMap()..remove('id');
        final id = await txn.insert(
          'radios',
          map,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (id > 0) added++;
      }
    });
    return added;
  }

  Future<void> updateRadio(RadioStation radio) async {
    final db = await instance.database;
    await db.update(
      'radios',
      radio.toMap(),
      where: 'id = ?',
      whereArgs: [radio.id],
    );
  }

  Future<void> deleteRadio(int id) async {
    final db = await instance.database;
    await db.delete('radios', where: 'id = ?', whereArgs: [id]);
  }

  // Alternar estado de favorito (0 a 1, o 1 a 0)
  Future<void> toggleFavorite(int id, bool currentStatus) async {
    final db = await instance.database;
    await db.update(
      'radios',
      {'isFavorite': currentStatus ? 0 : 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markRadioPlayed(int id) async {
    final db = await instance.database;
    await db.update(
      'radios',
      {'lastPlayed': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- Canciones favoritas ----------

  Future<Set<int>> getFavoriteSongIds() async {
    final db = await instance.database;
    final rows = await db.query('favorite_songs');
    return rows.map((r) => r['songId'] as int).toSet();
  }

  Future<void> setSongFavorite(int songId, bool favorite) async {
    final db = await instance.database;
    if (favorite) {
      await db.insert('favorite_songs', {
        'songId': songId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete(
        'favorite_songs',
        where: 'songId = ?',
        whereArgs: [songId],
      );
    }
  }

  // ---------- Playlists ----------

  Future<List<Playlist>> getPlaylists() async {
    final db = await instance.database;
    final lists = await db.query('playlists', orderBy: 'createdAt DESC');
    final songs = await db.query('playlist_songs', orderBy: 'position ASC');
    return lists.map((row) {
      final id = row['id'] as int;
      return Playlist(
        id: id,
        name: row['name'] as String,
        songIds: songs
            .where((s) => s['playlistId'] == id)
            .map((s) => s['songId'] as int)
            .toList(),
      );
    }).toList();
  }

  Future<int> createPlaylist(String name) async {
    final db = await instance.database;
    return db.insert('playlists', {
      'name': name,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> renamePlaylist(int id, String name) async {
    final db = await instance.database;
    await db.update(
      'playlists',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deletePlaylist(int id) async {
    final db = await instance.database;
    await db.delete('playlist_songs', where: 'playlistId = ?', whereArgs: [id]);
    await db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addSongsToPlaylist(int playlistId, List<int> songIds) async {
    final db = await instance.database;
    final last =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT MAX(position) FROM playlist_songs WHERE playlistId = ?',
            [playlistId],
          ),
        ) ??
        -1;
    var position = last + 1;
    final batch = db.batch();
    for (final songId in songIds) {
      batch.insert('playlist_songs', {
        'playlistId': playlistId,
        'songId': songId,
        'position': position++,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeSongFromPlaylist(int playlistId, int songId) async {
    final db = await instance.database;
    await db.delete(
      'playlist_songs',
      where: 'playlistId = ? AND songId = ?',
      whereArgs: [playlistId, songId],
    );
  }
}
