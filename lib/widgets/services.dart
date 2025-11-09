import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/src/rust/api/utils.dart' as rust_utils;
import 'package:adiman/main.dart';
import 'snackbar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:anni_mpris_service/anni_mpris_service.dart';
import 'package:dbus/dbus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:system_info2/system_info2.dart';

class AdimanService extends MPRISService {
  List<Song> _currentPlaylist = [];
  int _currentIndex = 0;
  Song? _currentSong;
  final Function(Song, int)? _onSongChange;
  final playbackStateController = StreamController<bool>.broadcast();
  Stream<bool> get playbackStateStream => playbackStateController.stream;
  final _trackChangeController = StreamController<Song>.broadcast();
  Stream<Song> get trackChanges => _trackChangeController.stream;

  AdimanService({Function(Song, int)? onSongChange})
      : _onSongChange = onSongChange,
        super(
          "adiman",
          identity: "Adiman",
          canGoPrevious: true,
          canGoNext: true,
          canPlay: true,
          canPause: true,
          canSeek: true,
          canControl: true,
          //For now
          supportShuffle: false,
          //Not supported yet but the person who made the package decided it was a good idea to lock the mpris updates behind supportLoopStatus so it must be true if u want ur music to update at all
          supportLoopStatus: true,
        ) {
    playbackStatus = PlaybackStatus.stopped;
  }

  void updatePlaylist(List<Song> playlist, int currentIndex) async {
    if (_currentPlaylist == playlist &&
        _currentIndex == currentIndex &&
        _currentSong == playlist[currentIndex]) {
      return;
    }

    if (playlist.isEmpty ||
        currentIndex < 0 ||
        currentIndex >= playlist.length) {
      _currentPlaylist = [];
      _currentIndex = -1;
      _currentSong = null;
      return;
    }

    _currentPlaylist = playlist;
    _currentIndex = currentIndex;
    _currentSong = _currentPlaylist[currentIndex];

    if (_currentSong != null) {
      _trackChangeController.add(_currentSong!);
      updateMetadata();
    }

    final isPlaying = await rust_api.isPlaying();
    playbackStatus = isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;
    playbackStateController.add(isPlaying);
  }

  void updatePlaylistStart(List<Song> playlist, int currentIndex) {
    if (_currentPlaylist == playlist && _currentIndex == currentIndex) return;
    _currentPlaylist = playlist;
    _currentIndex = currentIndex;
    _currentSong = _currentPlaylist[currentIndex];
    if (!_trackChangeController.isClosed) {
      _trackChangeController.add(_currentSong!);
    }
    updateMetadata();
    onPlay();
  }

  @override
  Future<void> dispose() async {
    await playbackStateController.close();
    await _trackChangeController.close();
    await client?.close();
    await client?.callMethod(
      destination: 'org.freedesktop.DBus',
      path: DBusObjectPath('/org/freedesktop/DBus'),
      interface: 'org.freedesktop.DBus',
      name: 'Adiman',
      values: [DBusString('org.mpris.MediaPlayer2.adiman')],
    );
    await super.dispose();
  }

  String _generateTrackId(String path) {
    final hash = md5.convert(utf8.encode(path)).toString();
    return "/com/adiman/Track/$hash";
  }

  void updateMetadata() async {
    if (_currentSong != null) {
      final artist =
          await rust_api.getArtistViaFfprobe(filePath: _currentSong!.path);
      // Try this but join in the same way the rust_api.extractMetadata does to remove ffprobe deps
      final artistString = artist.join("/");

      String? cachedArtPath = await _cacheAlbumArt(_currentSong!.albumArt);
      metadata = Metadata(
        trackId: _generateTrackId(_currentSong!.path),
        trackLength: _currentSong!.duration,
        artUrl:
            cachedArtPath != null ? Uri.file(cachedArtPath).toString() : null,
        albumName: _currentSong!.album,
        trackTitle: _currentSong!.title,
        trackArtist: [artistString],
      );
    }
  }

  Future<String?> _cacheAlbumArt(Uint8List? data) async {
    if (data == null) return null;
    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/album_art_cache');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

      // Clean up old files (keep last 10)
      final files = await cacheDir.list().where((f) => f is File).toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      for (var file in files.skip(10)) {
        try {
          await (file as File).delete();
        } catch (_) {}
      }

      final hash = md5.convert(utf8.encode(_currentSong!.title)).toString();
      final file = File('${cacheDir.path}/$hash.png');
      if (!await file.exists()) {
        await file.writeAsBytes(data);
      }
      return file.path;
    } catch (e) {
      AdiSnackbar(content: 'Error caching album art: $e');
      return null;
    }
  }

  @override
  Future<void> onPlay() async {
    await rust_api.resumeSong();
    playbackStatus = PlaybackStatus.playing;
    playbackStateController.add(true);
  }

  @override
  Future<void> onPause() async {
    await rust_api.pauseSong();
    playbackStatus = PlaybackStatus.paused;
    playbackStateController.add(false);
  }

  @override
  Future<void> onPlayPause() async {
    final isPlaying = await rust_api.isPlaying();
    if (isPlaying) {
      await onPause();
    } else {
      await onPlay();
    }
  }

  @override
  Future<void> onNext() async {
    if (_currentIndex + 1 < _currentPlaylist.length) {
      final newIndex = _currentIndex + 1;
      final nextSong = _currentPlaylist[newIndex];
      await rust_api.playSong(path: nextSong.path);
      await rust_api.preloadNextSong(path: _currentPlaylist[newIndex + 1].path);
      _currentIndex = newIndex;
      _currentSong = nextSong;
      _trackChangeController.add(nextSong);
      updateMetadata();

      _onSongChange?.call(nextSong, newIndex);

      final isNowPlaying = await rust_api.isPlaying();
      playbackStatus =
          isNowPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;
      playbackStateController.add(isNowPlaying);
      updateMetadata();
    }
  }

  @override
  Future<void> onPrevious() async {
    if (_currentIndex > 0) {
      final newIndex = _currentIndex - 1;
      final prevSong = _currentPlaylist[newIndex];
      await rust_api.playSong(path: prevSong.path);
      await rust_api.preloadNextSong(path: _currentPlaylist[newIndex + 1].path);
      _currentIndex = newIndex;
      _currentSong = prevSong;
      _trackChangeController.add(prevSong);
      updateMetadata();
      _onSongChange?.call(prevSong, newIndex);

      final isNowPlaying = await rust_api.isPlaying();
      playbackStatus =
          isNowPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;
      playbackStateController.add(isNowPlaying);
      updateMetadata();
    }
  }

  @override
  Future<void> onSeek(int offset) async {
    final newPosition =
        (await rust_api.getPlaybackPosition()) + (offset / 1000000);
    await rust_api.seekToPosition(position: newPosition);
  }

  @override
  Future<void> onSetPosition(String trackId, int position) async {
    await rust_api.seekToPosition(position: position / 1000000);
  }

  /*@override
  Future<void> onLoopStatus(LoopStatus loopStatus) async {
    // Implement loop status if needed
    AdiSnackbar(backgroundColor: dominantColor, content: "LOOP");
  }

  @override
  Future<void> onShuffle(bool shuffle) async {
    // Implement shuffle if needed
    AdiSnackbar(backgroundColor: dominantColor, content: "SHUFFLE");
  }*/
}

class SharedPreferencesService {
  static SharedPreferences? _instance;

  static SharedPreferences get instance {
    if (_instance == null) {
      throw Exception('SharedPreferences not initialized!');
    }
    return _instance!;
  }

  static Future<void> init() async {
    _instance = await SharedPreferences.getInstance();
  }
}

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

class AdimanUpdater {
  late final AppVersion _cvers;

  AdimanUpdater._internal({
    required AppVersion cvers,
  }) : _cvers = cvers;

  static AdimanUpdater? _instance;

  static Future<AdimanUpdater> initialize() async {
    if (_instance == null) {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final AppVersion version = AppVersion.parse(packageInfo.version);

      _instance = AdimanUpdater._internal(cvers: version);
    }
    return _instance!;
  }

  AppVersion get ver => _cvers;

  void checkUpdate(BuildContext context) async {
    final String? fetchedVersion = await rust_utils.getLatestVersion();
    if (fetchedVersion == null) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content:
              'Failed to get latest version, check your internet or the terminal'));
      return;
    }
    final AppVersion v = AppVersion.parse(fetchedVersion);
    if (v.isNewerThan(ver)) {
      _update(context);
    }
  }

  void _update(BuildContext context) async {
    final String? here = Platform.environment['APPIMAGE'];
    if (here == null) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content:
              'APPIMAGE environment variable does not exist, cannot update non-appimage'));
      return;
    }
    if (!Platform.isLinux) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content: 'OS is not linux - no github releases available'));
      return;
    }
    final String arch = SysInfo.kernelArchitecture.name
        .toLowerCase(); // I don't know what this actually returns
    if (arch != "arm64" && arch != "x86_64") {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content:
              'Architecture $arch is unsupported - no github releases available'));
      return;
    }
    final bool updateRes =
        await rust_utils.updateExecutable(arch: arch, expath: here);
    if (updateRes) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content:
              'Successfully updated! You may restart the app for updates to apply'));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          content: 'Update failed, check the terminal for more info'));
    }
  }
}

class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;

  AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
  }) : assert(major >= 0 && minor >= 0 && patch >= 0);

  factory AppVersion.parse(String versionString) {
    if (versionString.startsWith('v')) {
      versionString = versionString.substring(1);
    }
    final parts = versionString.split('.');
    if (parts.length != 3) {
      throw FormatException(
          'Invalid version string format: "$versionString". Expected format "X.Y.Z".');
    }

    try {
      final major = int.parse(parts[0]);
      final minor = int.parse(parts[1]);
      final patch = int.parse(parts[2]);

      return AppVersion(
        major: major,
        minor: minor,
        patch: patch,
      );
    } on FormatException catch (_) {
      throw FormatException(
          'Invalid version string format: "$versionString". Components must be integers.');
    }
  }

  @override
  String toString() {
    return '$major.$minor.$patch';
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    return patch.compareTo(other.patch);
  }

  bool isOlderThan(AppVersion other) => compareTo(other) < 0;
  bool isSameVersion(AppVersion other) => compareTo(other) == 0;
  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVersion &&
          runtimeType == other.runtimeType &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch;

  @override
  int get hashCode => major.hashCode ^ minor.hashCode ^ patch.hashCode;
}
