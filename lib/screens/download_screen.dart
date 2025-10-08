import 'dart:async';
import 'dart:ui' as ui;
import 'package:path/path.dart' as path;
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/src/rust/api/color_extractor.dart' as color_extractor;
import 'package:flutter/material.dart';
import 'package:adiman/widgets/services.dart';
import 'package:adiman/main.dart';
import 'package:adiman/widgets/miniplayer.dart';
import 'music_player_screen.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'package:flutter/services.dart';
import 'package:adiman/icons/broken_icons.dart';
import 'package:adiman/widgets/snackbar.dart';
import 'package:adiman/widgets/icon_buttons.dart';

class Track {
  final String name;
  final String artist;
  final List<String> genres;
  final String albumName;
  final String coverUrl;

  Track({
    required this.name,
    required this.artist,
    required this.genres,
    required this.albumName,
    required this.coverUrl,
  });
}

class DownloadScreen extends StatefulWidget {
  final AdimanService service;
  final String musicFolder;
  final Future<void> Function() onReloadLibrary;

  const DownloadScreen({
    super.key,
    required this.service,
    required this.musicFolder,
    required this.onReloadLibrary,
  });

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Track? _currentTrack;
  late AnimationController _breathingController;
  Color _dominantColor = defaultThemeColorNotifier.value;
  late FocusNode _focusNode;
  bool _isDownloading = false;
  Song? _tempSong;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut);
  }

  void _startDownload() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isDownloading = true);

    try {
      final downloadedPath = await rust_api.downloadToTemp(
          query: query,
          flags: SharedPreferencesService.instance.getString('spotdlFlags'));

      final metadata = await rust_api.scanMusicDirectory(
        dirPath: path.dirname(downloadedPath),
        autoConvert:
            SharedPreferencesService.instance.getBool('autoConvert') ?? true,
      );

      if (metadata.isNotEmpty) {
        _tempSong = Song.fromMetadata(metadata.first);

        if (_tempSong!.albumArt != null) {
          try {
            final colorValue = await color_extractor.getDominantColor(
                data: _tempSong!.albumArt!);
            setState(() {
              _dominantColor = Color(
                  colorValue ?? defaultThemeColorNotifier.value.toARGB32());
            });
          } catch (e) {
            AdiSnackbar(
                backgroundColor: defaultThemeColorNotifier.value,
                content: 'Error generating dominant color: $e');
            setState(() => _dominantColor = defaultThemeColorNotifier.value);
          }
        }

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await Navigator.push(
          context,
          NamidaPageTransitions.createRoute(
            MusicPlayerScreen(
              onReloadLibrary: widget.onReloadLibrary,
              musicFolder: widget.musicFolder,
              service: widget.service,
              song: Song.fromMetadata(metadata.first),
              songList: [Song.fromMetadata(metadata.first)],
              currentIndex: 0,
              isTemp: true,
              tempPath: downloadedPath,
            ),
          ),
        ).then((_) {
          _focusNode.requestFocus();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          backgroundColor: _dominantColor, content: 'Download failed: $e'));
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
        data: ThemeData.dark(),
        child: KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape &&
                !_isDownloading) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            body: Stack(
              children: [
                // Blurred Background
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.topCenter,
                          radius: 1.8,
                          colors: [_dominantColor.withAlpha(30), Colors.black],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            DynamicIconButton(
                              icon: Broken.arrow_left,
                              onPressed: () {
                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
                                Navigator.pop(context);
                              },
                              backgroundColor: _dominantColor,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: NamidaTextField(
                                controller: _searchController,
                                focusNode: _searchFocus,
                                hintText: 'Search song or paste URL...',
                                prefixIcon: Broken.search_normal,
                                onSubmitted: (_) => _startDownload(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child:
                              _currentTrack == null ? _buildEmptyState() : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isDownloading)
                  Positioned.fill(
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      autofocus: true,
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.escape) {
                          setState(() => _isDownloading = false);
                          rust_api.cancelDownload();
                          rust_api.stopSong();
                        }
                      },
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: Colors.black54,
                          child: Stack(
                            children: [
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation(
                                          _dominantColor),
                                    ),
                                    const SizedBox(height: 16),
                                    GlowText(
                                      'Downloading...',
                                      glowColor: _dominantColor,
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 18),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                top: 10,
                                left: 10,
                                child: DynamicIconButton(
                                  icon: Broken.cross,
                                  onPressed: () {
                                    setState(() => _isDownloading = false);
                                    rust_api.cancelDownload();
                                    rust_api.pauseSong();
                                  },
                                  backgroundColor: _dominantColor,
                                  size: 40,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_tempSong != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: MiniPlayer(
                      onReloadLibrary: widget.onReloadLibrary,
                      musicFolder: widget.musicFolder,
                      song: _tempSong!,
                      songList: [_tempSong!],
                      service: widget.service,
                      dominantColor: _dominantColor,
                      currentIndex: 0,
                      isTemp: true,
                      onClose: () {
                        setState(() {
                          _tempSong = null;
                          _dominantColor = defaultThemeColorNotifier.value;
                        });
                        rust_api.stopSong();
                      },
                      onUpdate: (newSong, newIndex, newColor) {
                        setState(() {
                          _tempSong = newSong;
                          _dominantColor = newColor;
                        });
                      },
                      isCurrent: true,
                    ),
                  ),
              ],
            ),
          ),
        ));
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 1.5,
            child: Icon(
              Broken.document_download,
              color: _dominantColor.withAlpha(80),
              size: 64,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Search for a song to download',
            style: TextStyle(
              color: _dominantColor.withAlpha(150),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
