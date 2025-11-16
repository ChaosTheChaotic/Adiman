import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/main.dart';
import 'package:adiman/widgets/snackbar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:anni_mpris_service/anni_mpris_service.dart';
import 'package:dbus/dbus.dart';

class AdimanService extends MPRISService {
  List<Song> _currentPlaylist = [];
  int _currentIndex = 0;
  Song? _currentSong;
  final Function(Song, int)? _onSongChange;
  final playbackStateController = StreamController<bool>.broadcast();
  Stream<bool> get playbackStateStream => playbackStateController.stream;
  final _trackChangeController = StreamController<Song>.broadcast();
  Stream<Song> get trackChanges => _trackChangeController.stream;

  Timer? _positionUpdateTimer;
  bool _isUpdatingPosition = false;

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
	  emitSeekedSignal: true,
        ) {
    playbackStatus = PlaybackStatus.stopped;
    _startPositionUpdates();
  }

  void _startPositionUpdates() {
    // Update position every second
    _positionUpdateTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
      if (_isUpdatingPosition || _currentSong == null) return;
      
      try {
        _isUpdatingPosition = true;
        final position = await rust_api.getPlaybackPosition();
        if (position > 0) {
          updatePosition(Duration(milliseconds: (position * 1000).round()));
        }
      } catch (e) {
        print('Error updating position: $e');
      } finally {
        _isUpdatingPosition = false;
      }
    });
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
    _startPositionUpdates();
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
    if (_positionUpdateTimer == null) {
      _startPositionUpdates();
    }
  }

  @override
  Future<void> onPause() async {
    await rust_api.pauseSong();
    playbackStatus = PlaybackStatus.paused;
    playbackStateController.add(false);
    try {
      final position = await rust_api.getPlaybackPosition();
      if (position > 0) {
        updatePosition(Duration(milliseconds: (position * 1000).round()));
      }
    } catch (e) {
      print('Error updating position on pause: $e');
    }
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
      updatePosition(Duration.zero);
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
      updatePosition(Duration.zero);
    }
  }

  @override
  Future<void> onSeek(int offset) async {
    final newPosition =
        (await rust_api.getPlaybackPosition()) + (offset / 1000000);
    await rust_api.seekToPosition(position: newPosition);
    try {
      final position = await rust_api.getPlaybackPosition();
      if (position > 0) {
        updatePosition(Duration(milliseconds: (position * 1000).round()), forceEmitSeeked: true);
      }
    } catch (e) {
      print('Error updating position after seek: $e');
    }
  }

  @override
  Future<void> onSetPosition(String trackId, int position) async {
    await rust_api.seekToPosition(position: position / 1000000);
    try {
      final currentPosition = await rust_api.getPlaybackPosition();
      if (currentPosition > 0) {
        updatePosition(Duration(milliseconds: (currentPosition * 1000).round()), forceEmitSeeked: true);
      }
    } catch (e) {
      print('Error updating position after setPosition: $e');
    }
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
