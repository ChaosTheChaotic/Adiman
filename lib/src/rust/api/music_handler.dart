// This file is automatically generated, so please do not edit it.
// @generated by `flutter_rust_bridge`@ 2.11.1.

// ignore_for_file: invalid_use_of_internal_member, unused_import, unnecessary_import

import '../frb_generated.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

// These functions are ignored because they are not marked as `pub`: `background_worker`, `crossfade`, `extract_metadata`, `get_cached_mp3_path`, `get_mp3_cache_dir`, `get_position`, `new`, `parse_lrc_metadata`, `pause`, `play`, `resume`, `seek`, `stop`
// These types are ignored because they are neither used by any `pub` functions nor (for structs and enums) marked `#[frb(unignore)]`: `AudioChunk`, `AudioPlayer`, `PlayerMessage`, `StreamWrapper`, `StreamingBuffer`, `StreamingSource`, `Track`
// These function are ignored because they are on traits that is not defined in current crate (put an empty `#[frb]` on it to unignore): `channels`, `clone`, `clone`, `clone`, `current_frame_len`, `drop`, `fmt`, `fmt`, `fmt`, `fmt`, `next`, `sample_rate`, `total_duration`

Future<bool> initializePlayer() =>
    RustLib.instance.api.crateApiMusicHandlerInitializePlayer();

Future<List<SongMetadata>> scanMusicDirectory(
        {required String dirPath, required bool autoConvert}) =>
    RustLib.instance.api.crateApiMusicHandlerScanMusicDirectory(
        dirPath: dirPath, autoConvert: autoConvert);

Future<bool> playSong({required String path}) =>
    RustLib.instance.api.crateApiMusicHandlerPlaySong(path: path);

Future<bool> pauseSong() =>
    RustLib.instance.api.crateApiMusicHandlerPauseSong();

Future<bool> resumeSong() =>
    RustLib.instance.api.crateApiMusicHandlerResumeSong();

Future<bool> stopSong() => RustLib.instance.api.crateApiMusicHandlerStopSong();

Future<double> getPlaybackPosition() =>
    RustLib.instance.api.crateApiMusicHandlerGetPlaybackPosition();

Future<bool> seekToPosition({required double position}) =>
    RustLib.instance.api.crateApiMusicHandlerSeekToPosition(position: position);

Future<bool> skipToNext(
        {required List<String> songs, required BigInt currentIndex}) =>
    RustLib.instance.api.crateApiMusicHandlerSkipToNext(
        songs: songs, currentIndex: currentIndex);

Future<bool> skipToPrevious(
        {required List<String> songs, required BigInt currentIndex}) =>
    RustLib.instance.api.crateApiMusicHandlerSkipToPrevious(
        songs: songs, currentIndex: currentIndex);

Future<Uint8List?> getCachedAlbumArt({required String path}) =>
    RustLib.instance.api.crateApiMusicHandlerGetCachedAlbumArt(path: path);

Future<String?> getCurrentSongPath() =>
    RustLib.instance.api.crateApiMusicHandlerGetCurrentSongPath();

Future<Float32List> getRealtimePeaks() =>
    RustLib.instance.api.crateApiMusicHandlerGetRealtimePeaks();

Future<bool> isPlaying() =>
    RustLib.instance.api.crateApiMusicHandlerIsPlaying();

/// Extracts waveform data from an MP3 file using FFmpeg to decode it to PCM data.
///
/// This function launches FFmpeg with arguments to decode [mp3_path] to 16-bit PCM (s16le)
/// using the given number of [channels] (default is 2). It then downsamples the resulting PCM
/// stream to return [sampleCount] normalized amplitude values (between 0 and 1).
///
/// Note: This requires FFmpeg to be installed on your Linux system.
Future<Float64List> extractWaveformFromMp3(
        {required String mp3Path, int? sampleCount, int? channels}) =>
    RustLib.instance.api.crateApiMusicHandlerExtractWaveformFromMp3(
        mp3Path: mp3Path, sampleCount: sampleCount, channels: channels);

Future<void> addSeparator({required String separator}) =>
    RustLib.instance.api.crateApiMusicHandlerAddSeparator(separator: separator);

Future<void> removeSeparator({required String separator}) =>
    RustLib.instance.api
        .crateApiMusicHandlerRemoveSeparator(separator: separator);

Future<List<String>> getCurrentSeparators() =>
    RustLib.instance.api.crateApiMusicHandlerGetCurrentSeparators();

Future<void> resetSeparators() =>
    RustLib.instance.api.crateApiMusicHandlerResetSeparators();

Future<void> setSeparators({required List<String> separators}) =>
    RustLib.instance.api
        .crateApiMusicHandlerSetSeparators(separators: separators);

Future<String> downloadToTemp({required String query}) =>
    RustLib.instance.api.crateApiMusicHandlerDownloadToTemp(query: query);

Future<void> cancelDownload() =>
    RustLib.instance.api.crateApiMusicHandlerCancelDownload();

Future<bool> clearMp3Cache() =>
    RustLib.instance.api.crateApiMusicHandlerClearMp3Cache();

Future<List<String>> getArtistViaFfprobe({required String filePath}) =>
    RustLib.instance.api
        .crateApiMusicHandlerGetArtistViaFfprobe(filePath: filePath);

Future<List<SongMetadata>> searchLyrics(
        {required String lyricsDir,
        required String query,
        required String songDir}) =>
    RustLib.instance.api.crateApiMusicHandlerSearchLyrics(
        lyricsDir: lyricsDir, query: query, songDir: songDir);

class PlayerState {
  final bool initialized;

  const PlayerState({
    required this.initialized,
  });

  static Future<PlayerState> default_() =>
      RustLib.instance.api.crateApiMusicHandlerPlayerStateDefault();

  @override
  int get hashCode => initialized.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerState &&
          runtimeType == other.runtimeType &&
          initialized == other.initialized;
}

class SongMetadata {
  final String title;
  final String artist;
  final String album;
  final BigInt duration;
  final String path;
  final Uint8List? albumArt;
  final String genre;

  const SongMetadata({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.path,
    this.albumArt,
    required this.genre,
  });

  @override
  int get hashCode =>
      title.hashCode ^
      artist.hashCode ^
      album.hashCode ^
      duration.hashCode ^
      path.hashCode ^
      albumArt.hashCode ^
      genre.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongMetadata &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          artist == other.artist &&
          album == other.album &&
          duration == other.duration &&
          path == other.path &&
          albumArt == other.albumArt &&
          genre == other.genre;
}
