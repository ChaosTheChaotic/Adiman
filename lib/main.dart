import 'dart:async';
import 'dart:io';
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/src/rust/api/value_store.dart' as value_store;
import 'package:adiman/src/rust/api/plugin_man.dart' as plugin_api;
import 'package:adiman/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:adiman/widgets/services.dart';
import 'package:adiman/screens/song_selection_screen.dart';
import 'package:adiman/widgets/volume.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:google_fonts/google_fonts.dart';

final ValueNotifier<Color> defaultThemeColorNotifier =
    ValueNotifier<Color>(const Color(0xFF383770));
final ValueNotifier<bool> useDominantColorsNotifier = ValueNotifier<bool>(true);

class Song {
  final String title;
  final String artist;
  final List<String>? artists;
  final String album;
  final String path;
  final Uint8List? albumArt;
  final Duration duration;
  final String genre;

  Song({
    required this.title,
    required this.artist,
    this.artists,
    required this.album,
    required this.path,
    this.albumArt,
    required this.duration,
    required this.genre,
  });

  factory Song.fromMetadata(dynamic metadata, {List<String>? artists}) {
    return Song(
      title: metadata.title as String,
      artist: (artists ?? [metadata.artist as String]).join(', '),
      artists: artists ?? [metadata.artist as String],
      album: metadata.album as String,
      path: metadata.path as String,
      albumArt: metadata.albumArt as Uint8List?,
      //duration: Duration(seconds: (metadata.duration as BigInt).toInt()),
      duration: metadata.duration as BigInt > BigInt.from(0)
          ? Duration(seconds: (metadata.duration as BigInt).toInt())
          : Duration.zero,
      genre: metadata.genre as String,
    );
  }
  rust_api.SongMetadata toMetadata() {
    return rust_api.SongMetadata(
      title: title,
      artist: artist,
      genre: genre,
      duration: BigInt.from(duration.inSeconds),
      album: album,
      albumArt: albumArt,
      path: path,
    );
  }
}

ThemeData _buildDynamicTheme(BuildContext context, Color dominantColor) {
  final theme = Theme.of(context);
  final bool isDark = dominantColor.computeLuminance() < 0.4;
  final textColor = isDark ? Colors.white : dominantColor;
  return theme.copyWith(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: dominantColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ),
    textTheme: TextTheme(
      bodyLarge: GoogleFonts.inter(color: textColor),
      bodyMedium: GoogleFonts.inter(color: textColor),
      titleLarge: GoogleFonts.inter(color: textColor),
      titleMedium: GoogleFonts.inter(color: textColor),
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    iconTheme: IconThemeData(color: textColor),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      selectedIconTheme: IconThemeData(color: dominantColor),
      unselectedIconTheme:
          IconThemeData(color: dominantColor.withValues(alpha: 0.5)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: Colors.transparent,
      scrimColor: Colors.black.withValues(alpha: 0.4),
    ),
  );
}

enum SortOption {
  playlist,
  title,
  titleReversed,
  artist,
  artistReversed,
  genre,
  genreReversed,
}

enum RepeatMode { normal, repeatOnce, repeatAll }

enum SeekbarType { waveform, alt, dyn }

late final AdimanService globalService;
Future<void> main() async {
  await RustLib.init();
  await rust_api.initializePlayer();
  await SharedPreferencesService.init();
  if (SharedPreferencesService.instance.getBool('enablePlugins') ?? false) {
    await plugin_api.initPluginMan();
  }
  await value_store.initValueStore();
  globalService = AdimanService();
  VolumeController();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await PlaylistOrderDatabase().database;
  syncRust();
  useDominantColorsNotifier.value =
      SharedPreferencesService.instance.getBool('useDominantColors') ?? true;
  runApp(const Adiman());
}

void syncRust() async {
  final autoCreate =
      SharedPreferencesService.instance.getBool('autoCreateDirs') ?? true;
  final home = Platform.environment['HOME'] ?? '';
  String musicFolder =
      SharedPreferencesService.instance.getString('musicFolder') ?? '~/Music';
  if (musicFolder.startsWith('~')) {
    musicFolder = musicFolder.replaceFirst('~', home);
  }
  final Directory musicFolderDir = Directory(musicFolder);
  final bool mfe = await musicFolderDir.exists();
  if (autoCreate && !mfe) {
    await musicFolderDir.create(recursive: true);
  }
  String pluginRwDir =
      SharedPreferencesService.instance.getString('pluginRwDir') ?? '~/AdiDir';
  if (pluginRwDir.startsWith('~')) {
    pluginRwDir = pluginRwDir.replaceFirst('~', home);
  }
  final Directory pluginRwDirDir = Directory(pluginRwDir);
  final bool rwe = await pluginRwDirDir.exists();
  if (autoCreate && !rwe) {
    await pluginRwDirDir.create(recursive: true);
  }
  final updater = await value_store.updateStore();
  await updater.setMusicFolder(folder: musicFolder);
  await updater.setPluginRwDir(folder: pluginRwDir);
  await updater.setUnsafeApis(
      value: SharedPreferencesService.instance.getBool('unsafeAPIs') ?? false);
  await updater.apply();
}

class Adiman extends StatefulWidget {
  const Adiman({super.key});

  @override
  State<Adiman> createState() => _AdimanState();
}

class _AdimanState extends State<Adiman> {
  @override
  void initState() {
    super.initState();
  }

  void updateThemeColor(Color newColor) {
    defaultThemeColorNotifier.value = newColor;
    SharedPreferencesService.instance
        .setInt('defaultThemeColor', newColor.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final savedColor =
          SharedPreferencesService.instance.getInt('defaultThemeColor');
      if (savedColor != null) {
        defaultThemeColorNotifier.value = Color(savedColor);
      }
    });

    return ValueListenableBuilder<Color>(
      valueListenable: defaultThemeColorNotifier,
      builder: (context, color, _) {
        return MaterialApp(
          scrollBehavior:
              const MaterialScrollBehavior().copyWith(scrollbars: false),
          title: 'Adiman',
          theme: _buildDynamicTheme(context, color),
          home: Builder(
            builder: (context) => SongSelectionScreen(
              updateThemeColor: updateThemeColor,
            ),
          ),
        );
      },
    );
  }
}
