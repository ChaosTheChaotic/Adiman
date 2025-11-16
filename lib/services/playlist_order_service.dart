import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PlaylistOrderDatabase {
  static final PlaylistOrderDatabase _instance =
      PlaylistOrderDatabase._internal();
  factory PlaylistOrderDatabase() => _instance;
  PlaylistOrderDatabase._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final home = Platform.environment['HOME'] ?? '';
    final dbPath = '$home/.local/share/adiman';
    final path = '$dbPath/playlist_orders.db';

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE playlist_orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            playlist_name TEXT NOT NULL,
            song_path TEXT NOT NULL,
            position INTEGER NOT NULL,
            UNIQUE(playlist_name, song_path)
          )
        ''');
        await db.execute('''
          CREATE INDEX idx_playlist_name ON playlist_orders (playlist_name)
        ''');
      },
    );
  }

  Future<void> updatePlaylistOrder(
      String playlistName, List<String> songPaths) async {
    final db = await database;

    // Start a transaction to ensure atomic update
    await db.transaction((txn) async {
      // Delete existing order for this playlist
      await txn.delete(
        'playlist_orders',
        where: 'playlist_name = ?',
        whereArgs: [playlistName],
      );

      // Insert new order
      for (int i = 0; i < songPaths.length; i++) {
        await txn.insert(
          'playlist_orders',
          {
            'playlist_name': playlistName,
            'song_path': songPaths[i],
            'position': i,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<String>> getPlaylistOrder(String playlistName) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'playlist_orders',
      where: 'playlist_name = ?',
      whereArgs: [playlistName],
      orderBy: 'position ASC',
    );

    return maps.map((map) => map['song_path'] as String).toList();
  }

  Future<void> clearPlaylist(String playlistName) async {
    final db = await database;
    await db.delete(
      'playlist_orders',
      where: 'playlist_name = ?',
      whereArgs: [playlistName],
    );
  }

  Future<void> clearAllPlaylists() async {
    final db = await database;
    await db.delete('playlist_orders');
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
