import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path/path.dart' as path;
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'namida_ui_extensions.dart';
import 'package:lrc/lrc.dart' as lrc_pkg;
import 'package:flutter_glow/flutter_glow.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:anni_mpris_service/anni_mpris_service.dart';
import 'package:animated_background/animated_background.dart';
import 'package:dbus/dbus.dart';

class Song {
  final String title;
  final String artist;
  final List<String>? artists;
  final String album;
  final String path;
  final String? albumArt;
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
      albumArt: metadata.albumArt as String?,
      duration: Duration(seconds: (metadata.duration as BigInt).toInt()),
      genre: metadata.genre as String,
    );
  }
}

ThemeData _buildDynamicTheme(Color dominantColor) {
  return ThemeData.dark().copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: dominantColor,
      brightness: Brightness.dark,
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    useMaterial3: true,
  );
}

class MiniPlayer extends StatefulWidget {
  final Song song;
  final List<Song> songList;
  final int currentIndex;
  final VoidCallback onClose;
  final Function(Song, int, Color) onUpdate;
  final Color dominantColor;
  final bool isCurrent;
  final AdimanService service;
  final String musicFolder;
  final Future<void> Function() onReloadLibrary;
  final bool isTemp;
  final String? currentPlaylistName;

  const MiniPlayer({
    super.key,
    required this.song,
    required this.songList,
    required this.currentIndex,
    required this.onClose,
    required this.onUpdate,
    required this.dominantColor,
    required this.service,
    required this.musicFolder,
    required this.onReloadLibrary,
    this.currentPlaylistName,
    this.isTemp = false,
    this.isCurrent = true,
  });

  @override
  // Expose state so that it can be accessed via a GlobalKey.
  _MiniPlayerState createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _playPauseController;
  bool isPlaying = true;
  late Timer _progressTimer;
  StreamSubscription<bool>? _playbackStateSubscription;

  @override
  void initState() {
    super.initState();
    _playbackStateSubscription = widget.service.playbackStateStream.listen((
      isPlaying,
    ) {
      if (mounted) {
        setState(() {
          this.isPlaying = isPlaying;
          isPlaying
              ? _playPauseController.forward()
              : _playPauseController.reverse();
        });
      }
    });
    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _updatePlayback(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPlayingState());
  }

  void _checkPlayingState() async {
    final isPlaying = await rust_api.isPlaying();
    setState(() => this.isPlaying = isPlaying);
    if (isPlaying) {
      _playPauseController.forward();
    } else {
      _playPauseController.reverse();
    }
  }

  void _updatePlayback() async {
    if (!mounted) return;
    final pos = await rust_api.getPlaybackPosition();
    final currentPath = await rust_api.getCurrentSongPath();

    if (currentPath != widget.song.path) {
      final newIndex = widget.songList.indexWhere(
        (song) => song.path == currentPath,
      );
      if (newIndex != -1) {
        Color newColor = await _getDominantColor(widget.songList[newIndex]);
        widget.onUpdate(widget.songList[newIndex], newIndex, newColor);
      }
    }

    if (pos.isFinite) {
      setState(() {});
      if (pos >= widget.song.duration.inSeconds - 0.1) {
        _handleSkip(true);
      }
    }
  }

  // Public method to toggle play/pause via external calls.
  Future<void> togglePause() async {
    _togglePlayPause();
  }

  Future<void> pause() async {
    await rust_api.pauseSong();
    _playPauseController.reverse();
    widget.service.onPause();
    setState(() => isPlaying = false);
  }

  void _togglePlayPause() async {
    if (isPlaying) {
      await rust_api.pauseSong();
      _playPauseController.reverse();
      widget.service.onPause();
    } else {
      await rust_api.resumeSong();
      _playPauseController.forward();
      widget.service.onPlay();
    }
    setState(() => isPlaying = !isPlaying);
  }

  void _handleSkip(bool next) async {
    final newIndex = widget.currentIndex + (next ? 1 : -1);
    if (newIndex < 0 || newIndex >= widget.songList.length) return;

    await rust_api.stopSong();
    await rust_api.playSong(path: widget.songList[newIndex].path);
    Color newColor = await _getDominantColor(widget.songList[newIndex]);
    widget.onUpdate(widget.songList[newIndex], newIndex, newColor);
    widget.service.updatePlaylist(widget.songList, newIndex);
  }

  Future<Color> _getDominantColor(Song song) async {
    if (song.albumArt == null) return Colors.purple.shade900;
    try {
      final imageBytes = base64Decode(song.albumArt!);
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final palette = await PaletteGenerator.fromImage(frame.image);
      return palette.dominantColor?.color ?? Colors.purple.shade900;
    } catch (e) {
      return Colors.purple.shade900;
    }
  }

  @override
  void dispose() {
    _progressTimer.cancel();
    _playPauseController.dispose();
    _playbackStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        widget.dominantColor.computeLuminance() > 0.007
            ? widget.dominantColor
            : Colors.white;
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder:
                (context, _, __) => MusicPlayerScreen(
                  onReloadLibrary: widget.onReloadLibrary,
                  musicFolder: widget.musicFolder,
                  service: widget.service,
                  song: widget.song,
                  songList: widget.songList,
                  currentIndex: widget.currentIndex,
                  isTemp: widget.isTemp,
		  currentPlaylistName: widget.currentPlaylistName,
                ),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOutQuad,
                  ),
                ),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
          ),
        );
        if (result != null && result is Map<String, dynamic>) {
          widget.onUpdate(
            result['song'],
            result['index'],
            result['dominantColor'],
          );
        }
      },
      child: Material(
        elevation: 4,
        color: Colors.black.withValues(alpha: 0.4),
        surfaceTintColor: widget.dominantColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.dominantColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.dominantColor.withValues(alpha: 0.15),
                Colors.black.withValues(alpha: 0.3),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Hero(
                  tag: 'albumArt-${widget.song.path}',
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: widget.dominantColor.withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child:
                          widget.song.albumArt != null
                              ? Image.memory(
                                base64Decode(widget.song.albumArt!),
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                              : GlowIcon(
                                Icons.music_note,
                                color: Colors.white,
                                glowColor: Colors.white,
                              ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GlowText(
                        widget.song.title,
                        glowColor: widget.dominantColor.withValues(alpha: 0.2),
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.song.artist,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Hero(
                  tag: 'controls-prev-${widget.song.path}',
                  child: Material(
                    color: widget.dominantColor.withValues(alpha: 0.2),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: GlowIcon(
                        Icons.skip_previous,
                        color: textColor,
                        glowColor: widget.dominantColor.withValues(alpha: 0.3),
                      ),
                      onPressed:
                          widget.currentIndex > 0
                              ? () => _handleSkip(false)
                              : null,
                    ),
                  ),
                ),

                Hero(
                  tag: 'controls-playPause-${widget.song.path}',
                  child: Material(
                    color: widget.dominantColor.withValues(alpha: 0.2),
                    shape: const CircleBorder(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: widget.dominantColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: AnimatedIcon(
                          icon: AnimatedIcons.play_pause,
                          progress: _playPauseController,
                          color: textColor,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                    ),
                  ),
                ),

                Hero(
                  tag: 'controls-next-${widget.song.path}',
                  child: Material(
                    color: widget.dominantColor.withValues(alpha: 0.2),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: GlowIcon(
                        Icons.skip_next,
                        color: textColor,
                        glowColor: widget.dominantColor.withValues(alpha: 0.3),
                      ),
                      onPressed:
                          widget.currentIndex < widget.songList.length - 1
                              ? () => _handleSkip(true)
                              : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum SortOption {
  title,
  titleReversed,
  artist,
  artistReversed,
  genre,
  genreReversed,
}

enum RepeatMode { normal, repeatOnce, repeatAll }

late final AdimanService globalService;
Future<void> main() async {
  await RustLib.init();
  await rust_api.initializePlayer();
  globalService = AdimanService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Adiman',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        scrollbars: false,
      ),
      theme: _buildDynamicTheme(Colors.purple),
      home: const SongSelectionScreen(),
    );
  }
}

class SongSelectionScreen extends StatefulWidget {
  const SongSelectionScreen({super.key});

  @override
  State<SongSelectionScreen> createState() => _SongSelectionScreenState();
}

class _AnimatedPopupWrapper extends StatefulWidget {
  final Widget child;

  const _AnimatedPopupWrapper({required this.child});

  @override
  State<_AnimatedPopupWrapper> createState() => _AnimatedPopupWrapperState();
}

class _AnimatedPopupWrapperState extends State<_AnimatedPopupWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(opacity: _opacityAnimation.value, child: child),
        );
      },
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _SongSelectionScreenState extends State<SongSelectionScreen>
    with TickerProviderStateMixin {
  List<Song> songs = [];
  List<Song> displayedSongs = [];
  bool isLoading = true;
  Song? currentSong;
  int currentIndex = 0;
  bool showMiniPlayer = false;
  Color dominantColor = Colors.purple.shade900;
  final ScrollController _scrollController = ScrollController();
  double _lastOffset = 0;
  late AnimationController _extraHeaderController;
  late Animation<Offset> _extraHeaderOffsetAnimation;
  bool _isDrawerOpen = false;
  String currentMusicDirectory = '';
  String? _currentPlaylistName;
  late final AdimanService service;

  final double fixedHeaderHeight = 60.0;
  final double slidingHeaderHeight = 48.0;
  final double miniPlayerHeight = 80.0;
  late AnimationController _playlistTransitionController;
  late Animation<double> _playlistTransitionAnimation;
  bool _isPlaylistTransitioning = false;

  SortOption _selectedSortOption = SortOption.title;

  bool _isSearchExpanded = false;
  final TextEditingController _searchController = TextEditingController();

  // GlobalKey for accessing the Scaffold to open the drawer.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // GlobalKey to access MiniPlayer state for triggering play/pause.
  final GlobalKey<_MiniPlayerState> _miniPlayerKey =
      GlobalKey<_MiniPlayerState>();

  // Music folder path (default to '~/Music')
  String _musicFolder = '~/Music';

  final FocusNode _focusNode = FocusNode();

  List<String> customSeparators = [];

  @override
  void initState() {
    super.initState();
    service = globalService;
    _focusNode.requestFocus();
    _loadMusicFolder().then((_) {
      _loadSongs();
    });
    _scrollController.addListener(_handleScroll);

    _extraHeaderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _extraHeaderController.value = 1.0;

    _extraHeaderOffsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _extraHeaderController, curve: Curves.easeInOut),
    );

    _playlistTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _playlistTransitionAnimation = CurvedAnimation(
      parent: _playlistTransitionController,
      curve: Curves.easeInOut,
    );

    _searchController.addListener(_updateSearchResults);
  }

  Future<void> _playPlaylistTransition() async {
    setState(() {
      _isPlaylistTransitioning = true;
    });
    await _playlistTransitionController.forward();
    await _playlistTransitionController.reverse();
    setState(() {
      _isPlaylistTransitioning = false;
    });
  }

  Future<void> _loadMusicFolder() async {
    final prefs = await SharedPreferences.getInstance();
    String musicFolder = prefs.getString('musicFolder') ?? '~/Music';
    if (musicFolder.startsWith('~')) {
      final home = Platform.environment['HOME'] ?? '';
      musicFolder = musicFolder.replaceFirst('~', home);
    }
    setState(() {
      _musicFolder = musicFolder;
      if (_currentPlaylistName == null) {
        currentMusicDirectory = _musicFolder;
      }
    });
  }

  void _handleScroll() {
    double offset = _scrollController.offset;
    const double deltaThreshold = 5.0;
    if ((offset - _lastOffset) > deltaThreshold) {
      _extraHeaderController.reverse();
    } else if ((_lastOffset - offset) > deltaThreshold) {
      _extraHeaderController.forward();
    }
    _lastOffset = offset;
  }

  Widget _buildPlaylistOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.redAccent : dominantColor;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              GlowIcon(icon, color: color, blurRadius: 8, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPlaylistSelectionPopup() async {
    List<String> initialPlaylists = await listPlaylists(_musicFolder);
    List<String> localPlaylists = List.from(initialPlaylists);
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: _AnimatedPopupWrapper(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          dominantColor.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                      border: Border.all(
                        color: dominantColor.withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlowText(
                            'Select Playlist',
                            glowColor: dominantColor.withValues(alpha: 0.3),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: dominantColor,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ...localPlaylists
                              .map(
                                (playlist) => Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(15),
                                  child: InkWell(
                                    onTap: () {
                                      Navigator.pop(context);
                                      setState(() {
                                        _currentPlaylistName = playlist;
                                        currentMusicDirectory =
                                            '$_musicFolder/.adilists/$playlist';
                                      });
                                      _playPlaylistTransition();
                                      _loadSongs();
                                    },
                                    borderRadius: BorderRadius.circular(15),
                                    splashColor: dominantColor.withValues(
                                      alpha: 0.1,
                                    ),
                                    highlightColor: dominantColor.withValues(
                                      alpha: 0.05,
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(15),
                                        border: Border.all(
                                          color: dominantColor.withValues(
                                            alpha: 0.2,
                                          ),
                                          width: 0.8,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          GlowIcon(
                                            Icons.queue_music_rounded,
                                            color: dominantColor,
                                            blurRadius: 8,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              playlist,
                                              style: TextStyle(
                                                color:
                                                    Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.color,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: GlowIcon(
                                              Icons.edit_rounded,
                                              color: dominantColor,
                                              blurRadius: 8,
                                              size: 20,
                                            ),
                                            onPressed: () async {
                                              final newName =
                                                  await _showRenamePlaylistDialog(
                                                    playlist,
                                                  );
                                              if (newName != null &&
                                                  newName.isNotEmpty) {
                                                final oldPath =
                                                    '$_musicFolder/.adilists/$playlist';
                                                final newPath =
                                                    '$_musicFolder/.adilists/$newName';
                                                try {
                                                  await Directory(
                                                    oldPath,
                                                  ).rename(newPath);
                                                  setStateDialog(() {
                                                    localPlaylists.remove(
                                                      playlist,
                                                    );
                                                    localPlaylists.add(newName);
                                                    localPlaylists.sort();
                                                  });
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Playlist renamed to "$newName"',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      backgroundColor:
                                                          dominantColor,
                                                      behavior:
                                                          SnackBarBehavior
                                                              .floating,
                                                    ),
                                                  );
                                                } catch (e) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Error renaming playlist: $e',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                      behavior:
                                                          SnackBarBehavior
                                                              .floating,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                          IconButton(
                                            icon: GlowIcon(
                                              Icons.close_rounded,
                                              color: Colors.redAccent,
                                              blurRadius: 8,
                                              size: 20,
                                            ),
                                            onPressed: () async {
                                              final confirmed = await showDialog<
                                                bool
                                              >(
                                                context: context,
                                                builder:
                                                    (context) => AlertDialog(
                                                      backgroundColor:
                                                          dominantColor
                                                              .withValues(
                                                                alpha: 0.1,
                                                              ),
                                                      title: Text(
                                                        'Delete Playlist?',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      content: Text(
                                                        'Are you sure you want to delete "$playlist"?',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                        ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          child: Text(
                                                            'Cancel',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors
                                                                      .white70,
                                                            ),
                                                          ),
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    false,
                                                                  ),
                                                        ),
                                                        TextButton(
                                                          child: Text(
                                                            'Delete',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors
                                                                      .redAccent,
                                                            ),
                                                          ),
                                                          onPressed:
                                                              () =>
                                                                  Navigator.pop(
                                                                    context,
                                                                    true,
                                                                  ),
                                                        ),
                                                      ],
                                                    ),
                                              );
                                              if (confirmed ?? false) {
                                                final dir = Directory(
                                                  '$_musicFolder/.adilists/$playlist',
                                                );
                                                try {
                                                  await dir.delete(
                                                    recursive: true,
                                                  );
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Playlist deleted',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      backgroundColor:
                                                          dominantColor,
                                                      behavior:
                                                          SnackBarBehavior
                                                              .floating,
                                                    ),
                                                  );
                                                  // Remove the deleted playlist from the list.
                                                  setStateDialog(() {
                                                    localPlaylists.remove(
                                                      playlist,
                                                    );
                                                  });
                                                } catch (e) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Error deleting playlist: $e',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      backgroundColor:
                                                          Colors.red,
                                                      behavior:
                                                          SnackBarBehavior
                                                              .floating,
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          const SizedBox(height: 16),
                          Divider(
                            color: dominantColor.withValues(alpha: 0.2),
                            height: 1,
                          ),
                          const SizedBox(height: 16),
                          _buildPlaylistOptionButton(
                            icon: Icons.merge_rounded,
                            label: 'Merge Playlists',
                            onTap: () async {
                              Navigator.pop(context);
                              final selected =
                                  await _showMultiPlaylistSelection(
                                    await listPlaylists(_musicFolder),
                                  );
                              if (selected != null && selected.length > 1) {
                                await _mergePlaylists(selected);
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                          Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _currentPlaylistName = null;
                                  currentMusicDirectory = _musicFolder;
                                });
                                Navigator.pop(context);
                                _playPlaylistTransition();
                                _loadSongs();
                              },
                              borderRadius: BorderRadius.circular(15),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(15),
                                  gradient: LinearGradient(
                                    colors: [
                                      dominantColor.withValues(alpha: 0.1),
                                      Colors.transparent,
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                ),
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.library_music_rounded,
                                      color: dominantColor,
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      'Switch to Main Library',
                                      style: TextStyle(
                                        color:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyLarge?.color,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _showRenamePlaylistDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    return showDialog<String>(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: _AnimatedPopupWrapper(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        dominantColor.withAlpha(30),
                        Colors.black.withAlpha(200),
                      ],
                    ),
                    border: Border.all(
                      color: dominantColor.withAlpha(100),
                      width: 1.2,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlowText(
                          'Rename Playlist',
                          glowColor: dominantColor.withAlpha(80),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: dominantColor,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                dominantColor.withAlpha(30),
                                Colors.black.withAlpha(100),
                              ],
                            ),
                            border: Border.all(
                              color: dominantColor.withAlpha(100),
                            ),
                          ),
                          child: TextField(
                            controller: controller,
                            style: TextStyle(color: Colors.white),
                            cursorColor: dominantColor,
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              hintText: 'Enter new playlist name...',
                              hintStyle: TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: dominantColor,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              child: Text(
                                'Cancel',
                                style: TextStyle(color: Colors.white70),
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 12),
                            DynamicIconButton(
                              icon: Icons.check_rounded,
                              onPressed: () {
                                final newName = controller.text.trim();
                                if (newName.isNotEmpty &&
                                    newName != currentName) {
                                  Navigator.pop(context, newName);
                                }
                              },
                              backgroundColor: dominantColor,
                              size: 40,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
    );
  }

Future<int> countAudioFiles(String dirPath) async {
  final extensions = {'.mp3', '.flac', '.ogg', '.wav', '.m4a'};
  int count = 0;
  final dir = Directory(dirPath);
  try {
    await for (var entry in dir.list(recursive: true)) {
      if (entry is File) {
        final ext = path.extension(entry.path).toLowerCase();
        if (extensions.contains(ext)) {
          count++;
        }
      }
    }
  } catch (e) {
    print('Error counting audio files: $e');
  }
  return count;
}

Future<void> _loadSongs() async {
  setState(() => isLoading = true);
  try {
    final expectedCount = await countAudioFiles(currentMusicDirectory);
    final prefs = await SharedPreferences.getInstance();
    int currentCount = 0;
    List<Song> loadedSongs = [];
    do {
      final metadata = await rust_api.scanMusicDirectory(
        dirPath: currentMusicDirectory,
	autoConvert: prefs.getBool('autoConvert') ?? false,
      );
      loadedSongs = metadata.map((m) => Song.fromMetadata(m)).toList();
      currentCount = loadedSongs.length;
      setState(() {
        songs = loadedSongs;
        if (_searchController.text.isEmpty) {
          displayedSongs = loadedSongs;
        }
      });
      if (currentCount >= expectedCount) {
        break;
      }
      else if (prefs.getBool('autoConvert') ?? false) {
        await Future.delayed(const Duration(seconds: 1));
      }
    } while (currentCount >= expectedCount);
    loadedSongs.sort((a, b) => a.title.compareTo(b.title));
  } catch (e) {
    print('Error loading songs: $e');
  }
  setState(() => isLoading = false);
}
  void _updateSearchResults() {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        displayedSongs = songs;
      });
    } else {
      setState(() {
        displayedSongs =
            songs.where((song) {
              final titleMatch = song.title.toLowerCase().contains(query);
              final artistMatch = song.artist.toLowerCase().contains(query);
              final genreMatch = song.genre.toLowerCase().contains(query);
              return titleMatch || artistMatch || genreMatch;
            }).toList();
      });
    }
  }

  Future<Color> _getDominantColor(Song song) async {
    if (song.albumArt == null) return Colors.purple.shade900;
    try {
      final imageBytes = base64Decode(song.albumArt!);
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final palette = await PaletteGenerator.fromImage(frame.image);
      return palette.dominantColor?.color ?? Colors.purple.shade900;
    } catch (e) {
      return Colors.purple.shade900;
    }
  }

  void _shufflePlay() async {
    if (displayedSongs.isEmpty) return;
    List<Song> shuffled = List.from(displayedSongs);
    shuffled.shuffle();
    Song first = shuffled.first;
    await rust_api.playSong(path: first.path);
    Color newColor = await _getDominantColor(first);
    setState(() {
      songs = shuffled;
      displayedSongs = shuffled;
      currentSong = first;
      currentIndex = 0;
      dominantColor = newColor;
      showMiniPlayer = true;
    });
    service.updatePlaylist(songs, currentIndex);
  }

  void _sortSongs(SortOption option) {
    setState(() {
      _selectedSortOption = option;
      switch (option) {
        case SortOption.title:
          songs.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
          break;
        case SortOption.titleReversed:
          songs.sort(
            (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
          );
          break;
        case SortOption.artist:
          songs.sort(
            (a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
          );
          break;
        case SortOption.artistReversed:
          songs.sort(
            (a, b) => b.artist.toLowerCase().compareTo(a.artist.toLowerCase()),
          );
          break;
        case SortOption.genre:
          songs.sort(
            (a, b) => a.genre.toLowerCase().compareTo(b.genre.toLowerCase()),
          );
          break;
        case SortOption.genreReversed:
          songs.sort(
            (a, b) => b.genre.toLowerCase().compareTo(a.genre.toLowerCase()),
          );
          break;
      }
      _updateSearchResults();
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchController.clear();
        displayedSongs = songs;
      }
    });
  }

  void _togglePauseSong() {
    if (!showMiniPlayer) return;
    _miniPlayerKey.currentState?.togglePause();
  }


  void _pauseSong() {
    if (!showMiniPlayer) return;
    _miniPlayerKey.currentState?.pause();
  }

  bool isTextInputFocused() {
    final focusScope = FocusScope.of(context);
    return focusScope.hasFocus && focusScope.focusedChild is EditableText;
  }

  /// Returns the base directory for playlists (e.g. /home/Music/.adilists).
  Future<Directory> getPlaylistBase(String musicFolder) async {
    final baseDir = Directory('$musicFolder/.adilists');
    if (!(await baseDir.exists())) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }

  Future<Directory> createPlaylist(
    String musicFolder,
    String playlistName,
  ) async {
    final baseDir = await getPlaylistBase(musicFolder);
    final playlistDir = Directory('${baseDir.path}/$playlistName');
    if (!(await playlistDir.exists())) {
      await playlistDir.create();
    }
    return playlistDir;
  }

  /// Adds a song to the specified playlist by creating a symbolic link.
  /// If the link already exists, it is skipped.
  Future<void> addSongToPlaylist(
    String songPath,
    String musicFolder,
    String playlistName,
  ) async {
    final playlistDir = Directory('$musicFolder/.adilists/$playlistName');
    if (!(await playlistDir.exists())) {
      await playlistDir.create(recursive: true);
    }
    final songFile = File(songPath);
    if (await songFile.exists()) {
      final filename = songFile.uri.pathSegments.last;
      final linkPath = '${playlistDir.path}/$filename';
      final link = Link(linkPath);
      if (!await link.exists()) {
        await link.create(songFile.absolute.path);
        print('Added $songPath to playlist $playlistName');
      } else {
        print('Song already in playlist.');
      }
    } else {
      print('Song file does not exist: $songPath');
    }
  }

  Future<List<String>> listPlaylists(String musicFolder) async {
    final baseDir = await getPlaylistBase(musicFolder);
    final playlists = <String>[];
    await for (final entity in baseDir.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is Directory) {
        final parts = entity.path.split(Platform.pathSeparator);
        playlists.add(parts.last);
      }
    }
    return playlists;
  }

  Future<void> _handleCreatePlaylist(Song song) async {
    final playlistName = await _showPlaylistNameDialog();
    if (playlistName != null && playlistName.isNotEmpty) {
      await createPlaylist(_musicFolder, playlistName);
      await addSongToPlaylist(song.path, _musicFolder, playlistName);
    }
  }

  Future<void> _handleAddToExistingPlaylist(Song song) async {
    final playlists = await listPlaylists(_musicFolder);
    final selectedPlaylist = await _showSelectPlaylistDialog(playlists);
    if (selectedPlaylist != null && selectedPlaylist.isNotEmpty) {
      await addSongToPlaylist(song.path, _musicFolder, selectedPlaylist);
    }
  }

  Future<void> _mergePlaylists(List<String> playlistsToMerge) async {
    final mergedName = await _showPlaylistNameDialog();
    if (mergedName == null || mergedName.isEmpty) return;

    final baseDir = await getPlaylistBase(_musicFolder);
    final mergedDir = Directory('${baseDir.path}/$mergedName');
    if (!await mergedDir.exists()) {
      await mergedDir.create(recursive: true);
    }

    // Track existing filenames to avoid duplicates.
    final Set<String> existingFiles = {};

    for (final playlist in playlistsToMerge) {
      final playlistDir = Directory('${baseDir.path}/$playlist');
      await for (final entity in playlistDir.list()) {
        if (entity is Link || entity is File) {
          try {
            final target = await entity.resolveSymbolicLinks();
            final fileName = entity.path.split(Platform.pathSeparator).last;
            if (existingFiles.contains(fileName)) continue;

            final newLinkPath = '${mergedDir.path}/$fileName';
            final newLink = Link(newLinkPath);
            await newLink.create(target);
            existingFiles.add(fileName);
          } catch (e) {
            print('Error merging playlist "$playlist": $e');
          }
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Merged ${playlistsToMerge.length} playlists into "$mergedName"',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: dominantColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
    _loadSongs();
  }

  Future<List<String>?> _showMultiPlaylistSelection(
    List<String> playlists,
  ) async {
    final selected = <String>[];
    return showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: _AnimatedPopupWrapper(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          dominantColor.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.6),
                        ],
                      ),
                      border: Border.all(
                        color: dominantColor.withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlowText(
                            'Select Playlists to Merge',
                            glowColor: dominantColor.withValues(alpha: 0.3),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: dominantColor,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.4,
                            width: 300,
                            child: ListView.builder(
                              itemCount: playlists.length,
                              itemBuilder: (context, index) {
                                final playlist = playlists[index];
                                final isSelected = selected.contains(playlist);
                                return CheckboxListTile(
				  title: Text(
				    playlist,
				    style: TextStyle(
				      color: Theme.of(context).textTheme.bodyLarge?.color,
				      fontSize: 16,
				    ),
				  ),
				  value: isSelected,
				  activeColor: dominantColor,
				  checkColor: Colors.white,
				  controlAffinity: ListTileControlAffinity.leading,
				  tileColor: Colors.transparent,
				  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
				  dense: true,
				  shape: RoundedRectangleBorder(
				    borderRadius: BorderRadius.circular(12),
				  ),
				  checkboxShape: const CircleBorder(),
				  side: BorderSide(
				    color: dominantColor.withAlpha(100),
				    width: 1.5,
				  ),
				  secondary: isSelected
				  ? GlowIcon(
				    Icons.check_rounded,
				    color: dominantColor,
				    glowColor: dominantColor.withAlpha(80),
				    size: 24,
				  )
				  : null,
				  onChanged: (value) {
				    setStateDialog(() {
				      if (value == true) {
				        selected.add(playlist);
				      } else {
				        selected.remove(playlist);
				      }
				    });
				  },
				);
                              },
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 12),
                              DynamicIconButton(
                                icon: Icons.check_rounded,
                                onPressed:
                                    () => Navigator.pop(context, selected),
                                backgroundColor: dominantColor,
                                size: 40,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Show a styled dialog to input a new playlist name.
  Future<String?> _showPlaylistNameDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: _AnimatedPopupWrapper(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      dominantColor.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                  border: Border.all(
                    color: dominantColor.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlowText(
                        'New Playlist',
                        glowColor: dominantColor.withValues(alpha: 0.3),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: dominantColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              dominantColor.withValues(alpha: 0.1),
                              Colors.black.withValues(alpha: 0.3),
                            ],
                          ),
                        ),
                        child: TextField(
                          controller: controller,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: dominantColor,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            hintText: 'Playlist name...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            prefixIcon: Icon(
                              Icons.playlist_add_rounded,
                              color: dominantColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: dominantColor.withValues(
                                alpha: 0.3,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DynamicIconButton(
                            icon: Icons.check_rounded,
                            onPressed:
                                () => Navigator.pop(
                                  context,
                                  controller.text.trim(),
                                ),
                            backgroundColor: dominantColor,
                            size: 40,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Show a styled dialog to choose an existing playlist.
  Future<String?> _showSelectPlaylistDialog(List<String> playlists) async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: _AnimatedPopupWrapper(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      dominantColor.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                  border: Border.all(
                    color: dominantColor.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: GlowText(
                        'Select Playlist',
                        glowColor: dominantColor.withValues(alpha: 0.3),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: dominantColor,
                        ),
                      ),
                    ),
                    Divider(
                      color: dominantColor.withValues(alpha: 0.2),
                      height: 1,
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.pop(context, playlist),
                              splashColor: dominantColor.withValues(alpha: 0.1),
                              highlightColor: dominantColor.withValues(
                                alpha: 0.05,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: dominantColor.withValues(
                                        alpha: 0.1,
                                      ),
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.queue_music_rounded,
                                      color: dominantColor.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        playlist,
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyLarge?.color,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _removeSongFromCurrentPlaylist(Song song) async {
    if (_currentPlaylistName == null) return;
    final songFile = File(song.path);
    final filename = songFile.uri.pathSegments.last;
    final linkPath = '$_musicFolder/.adilists/$_currentPlaylistName/$filename';
    final link = Link(linkPath);
    if (await link.exists()) {
      await link.delete();
      print('Removed $filename from playlist $_currentPlaylistName');
      _loadSongs();
    } else {
      print('Song link does not exist: $filename');
    }
  }

  /// Show popup to create or add to a playlist.
  void _showPlaylistPopup(Song song) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: _AnimatedPopupWrapper(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      dominantColor.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                  border: Border.all(
                    color: dominantColor.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlowText(
                        'Playlist Options',
                        glowColor: dominantColor.withValues(alpha: 0.3),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: dominantColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildPlaylistOptionButton(
                        icon: Icons.create_new_folder,
                        label: 'Create New Playlist',
                        onTap: () {
                          Navigator.pop(context);
                          _handleCreatePlaylist(song);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Icons.playlist_add,
                        label: 'Add to Existing',
                        onTap: () {
                          Navigator.pop(context);
                          _handleAddToExistingPlaylist(song);
                        },
                      ),
                      if (_currentPlaylistName != null) ...[
                        const SizedBox(height: 12),
                        _buildPlaylistOptionButton(
                          icon: Icons.remove_circle,
                          label: 'Remove from Playlist',
                          onTap: () async {
                            Navigator.pop(context);
                            await _removeSongFromCurrentPlaylist(song);
                          },
                          isDestructive: true,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Icons.delete_forever_rounded,
                        label: 'Delete Song',
                        onTap: () async {
                          Navigator.pop(context);
                          final confirmed = await _showDeleteConfirmationDialog(
                            song,
                          );
                          if (confirmed) {
                            await _deleteSongFile(song);
                          }
                        },
                        isDestructive: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showDeleteConfirmationDialog(Song song) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                backgroundColor: dominantColor.withAlpha(30),
                title: Text(
                  'Delete Song?',
                  style: TextStyle(color: Colors.white),
                ),
                content: Text(
                  'This will permanently delete "${song.title}" from your device.',
                  style: TextStyle(color: Colors.white70),
                ),
                actions: [
                  TextButton(
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                  TextButton(
                    child: Text(
                      'Delete',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> _deleteSongFile(Song song) async {
    try {
      final file = File(song.path);
      if (await file.exists()) {
        await file.delete();
        setState(() {
          songs.removeWhere((s) => s.path == song.path);
          displayedSongs.removeWhere((s) => s.path == song.path);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Song deleted successfully',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: dominantColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error deleting song: ${e.toString()}',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    _extraHeaderController.dispose();
    _playlistTransitionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final textColor =
        dominantColor.computeLuminance() > 0.4 ? Colors.black : Colors.white;
    final glowColor =
        dominantColor.computeLuminance() < 0.5 ? Colors.white : dominantColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          hoverColor: dominantColor.withValues(alpha: 0.1),
          splashColor: dominantColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(15),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  dominantColor.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        dominantColor.withValues(alpha: 0.3),
                        dominantColor.withValues(alpha: 0.1),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: glowColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: glowColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: textColor.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        dominantColor.computeLuminance() > 0.007 ? dominantColor : Colors.white;
    return RawKeyboardListener(
      focusNode: _focusNode,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (_isSearchExpanded) {
              _toggleSearch();
            } else {
              if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
                _scaffoldKey.currentState?.closeDrawer();
                _isDrawerOpen = false;
              } else {
                _scaffoldKey.currentState?.openDrawer();
                _isDrawerOpen = true;
              }
            }
          } else if (event.logicalKey == LogicalKeyboardKey.space &&
              !_isSearchExpanded &&
              !isTextInputFocused()) {
            _togglePauseSong();
          }
        }
      },
      child: Listener(
        onPointerDown: (_) => _isDrawerOpen = true,
        onPointerUp: (_) => _isDrawerOpen = false,
        child: Scaffold(
          key: _scaffoldKey,
          drawer: RawKeyboardListener(
            focusNode: FocusNode(),
            autofocus: true,
            onKey: (event) {
              if (event is RawKeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                if (_isDrawerOpen) {
                  Navigator.pop(context);
                  _isDrawerOpen = false;
                }
              }
            },
            child: Drawer(
              width: MediaQuery.of(context).size.width * 0.55,
              elevation: 20,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(20),
                ),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.9),
                        dominantColor.withValues(alpha: 0.15),
                      ],
                    ),
                    border: Border(
                      right: BorderSide(
                        color: dominantColor.withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Menu',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            IconButton(
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Icon(
                                  _isDrawerOpen
                                      ? Icons.close_rounded
                                      : Icons.menu_rounded,
                                  key: ValueKey<bool>(_isDrawerOpen),
                                  color: textColor,
                                  size: 28,
                                ),
                              ),
                              onPressed: () {
                                if (_isDrawerOpen) {
                                  _scaffoldKey.currentState?.closeDrawer();
                                  Navigator.of(context).pop();
                                  _isDrawerOpen = false;
                                } else {
                                  _scaffoldKey.currentState?.openDrawer();
                                  _isDrawerOpen = true;
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        color: dominantColor.withValues(alpha: 0.2),
                        thickness: 1.2,
                        height: 0,
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildMenuTile(
                              icon: Icons.settings_rounded,
                              title: 'Settings',
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  NamidaPageTransitions.createRoute(
                                    SettingsScreen(
                                      onReloadLibrary: _loadSongs,
				      currentPlaylistName: _currentPlaylistName,
                                      onMusicFolderChanged: (newPath) {
                                        setState(() {
                                          _musicFolder = newPath;
                                          _currentPlaylistName = null;
                                          currentMusicDirectory = newPath;
                                        });
                                        _loadSongs();
                                      },
                                      currentSong: currentSong,
                                      currentIndex: currentIndex,
                                      dominantColor: dominantColor,
                                      service: service,
                                      songs: displayedSongs,
                                      musicFolder: _musicFolder,
                                      onUpdateMiniPlayer: (
                                        newSong,
                                        newIndex,
                                        newColor,
                                      ) {
                                        setState(() {
                                          currentSong = newSong;
                                          currentIndex = newIndex;
                                          dominantColor = newColor;
                                          showMiniPlayer = true;
                                        });
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                            _buildMenuTile(
                              icon: Icons.queue_music,
                              title: 'Playlists',
                              onTap: () async {
                                Navigator.pop(context);
                                await _showPlaylistSelectionPopup();
                              },
                            ),
                            _buildMenuTile(
                              icon: Icons.download_rounded,
                              title: 'Download Songs (spotdl required)',
                              onTap: () {
                                _pauseSong();
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  NamidaPageTransitions.createRoute(
                                    DownloadScreen(
                                      service: service,
                                      musicFolder: _musicFolder,
                                      onReloadLibrary: _loadSongs,
                                    ),
                                  ),
                                );
                              },
                            ),
                            /*_buildMenuTile(
                              icon: Icons.info_rounded,
                              title:
                                  'About & GitHub (None yet as these are test builds)',
                              onTap: () {
                                Navigator.pop(context);
                              },
                            ),*/
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, dominantColor],
              ),
            ),
            child: SafeArea(
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _extraHeaderController,
                    builder: (context, child) {
                      double topPadding =
                          fixedHeaderHeight +
                          slidingHeaderHeight * _extraHeaderController.value;
                      return Padding(
                        padding: EdgeInsets.only(
                          top: topPadding,
                          bottom: showMiniPlayer ? miniPlayerHeight : 0,
                        ),
                        child: child,
                      );
                    },
                    child: CustomScrollView(
                      controller: _scrollController,
                      slivers: [
                        if (isLoading)
                          SliverFillRemaining(
                            child: Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.purple,
                                ),
                              ),
                            ),
                          )
                        else if (displayedSongs.isEmpty)
                          const SliverFillRemaining(
                            child: Center(
                              child: Text(
                                'No songs found',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final song = displayedSongs[index];
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onSecondaryTap: () {
                                  _showPlaylistPopup(song);
                                },
                                child: EnhancedSongListTile(
                                  song: song,
                                  dominantColor: dominantColor,
                                  onTap: () async {
                                    final result = await Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder:
                                            (context, _, __) =>
                                                MusicPlayerScreen(
                                                  onReloadLibrary: _loadSongs,
                                                  musicFolder: _musicFolder,
                                                  service: service,
                                                  song: song,
                                                  songList: displayedSongs,
						  currentPlaylistName: _currentPlaylistName,
                                                  currentIndex: displayedSongs.indexOf(
                                                    song,
                                                  ),
                                                ),
                                        transitionsBuilder: (
                                          context,
                                          animation,
                                          secondaryAnimation,
                                          child,
                                        ) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: ScaleTransition(
                                              scale: Tween<double>(
                                                begin: 0.95,
                                                end: 1.0,
                                              ).animate(
                                                CurvedAnimation(
                                                  parent: animation,
                                                  curve: Curves.easeInOutQuad,
                                                ),
                                              ),
                                              child: child,
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                    if (result != null &&
                                        result is Map<String, dynamic>) {
                                      setState(() {
                                        currentSong =
                                            result['song'] ?? currentSong;
                                        currentIndex =
                                            result['index'] ?? currentIndex;
                                        dominantColor =
                                            result['dominantColor'] ??
                                            dominantColor;
                                        showMiniPlayer = true;
                                      });
                                    }
                                    if (mounted) {
                                      FocusScope.of(
                                        context,
                                      ).requestFocus(_focusNode);
                                    }
                                  },
                                ),
                              );
                            }, childCount: displayedSongs.length),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: fixedHeaderHeight,
                    left: 0,
                    right: 0,
                    height: slidingHeaderHeight,
                    child: SlideTransition(
                      position: _extraHeaderOffsetAnimation,
                      child: Container(
                        color: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.shuffle, color: textColor),
                                  onPressed: _shufflePlay,
                                ),
                                Text(
                                  '${songs.length} songs',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            PopupMenuButton<SortOption>(
                              icon: Icon(Icons.sort, color: textColor),
                              color: Colors.black.withValues(alpha: 0.9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: dominantColor.withValues(alpha: 0.2),
                                ),
                              ),
                              onSelected: (option) => _sortSongs(option),
                              itemBuilder:
                                  (context) => <PopupMenuEntry<SortOption>>[
                                    PopupMenuItem(
                                      value: SortOption.title,
                                      child: Row(
                                        children: [
                                          if (_selectedSortOption ==
                                              SortOption.title)
                                            Icon(
                                              Icons.check,
                                              color: dominantColor,
                                              size: 18,
                                            ),
                                          if (_selectedSortOption ==
                                              SortOption.title)
                                            const SizedBox(width: 8),
                                          const Text('Title (A-Z)'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: SortOption.titleReversed,
                                      child: Row(
                                        children: [
                                          if (_selectedSortOption ==
                                              SortOption.titleReversed)
                                            Icon(
                                              Icons.check,
                                              color: dominantColor,
                                              size: 18,
                                            ),
                                          if (_selectedSortOption ==
                                              SortOption.titleReversed)
                                            const SizedBox(width: 8),
                                          const Text('Title (Z-A)'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: SortOption.artist,
                                      child: Row(
                                        children: [
                                          if (_selectedSortOption ==
                                              SortOption.artist)
                                            Icon(
                                              Icons.check,
                                              color: dominantColor,
                                              size: 18,
                                            ),
                                          if (_selectedSortOption ==
                                              SortOption.artist)
                                            const SizedBox(width: 8),
                                          const Text('Artist (A-Z)'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: SortOption.artistReversed,
                                      child: Row(
                                        children: [
                                          if (_selectedSortOption ==
                                              SortOption.artistReversed)
                                            Icon(
                                              Icons.check,
                                              color: dominantColor,
                                              size: 18,
                                            ),
                                          if (_selectedSortOption ==
                                              SortOption.artistReversed)
                                            const SizedBox(width: 8),
                                          const Text('Artist (Z-A)'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: SortOption.genre,
                                      child: Row(
                                        children: [
                                          if (_selectedSortOption ==
                                              SortOption.genre)
                                            Icon(
                                              Icons.check,
                                              color: dominantColor,
                                              size: 18,
                                            ),
                                          if (_selectedSortOption ==
                                              SortOption.genre)
                                            const SizedBox(width: 8),
                                          const Text('Genre (A-Z)'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: SortOption.genreReversed,
                                      child: Row(
                                        children: [
                                          if (_selectedSortOption ==
                                              SortOption.genreReversed)
                                            Icon(
                                              Icons.check,
                                              color: dominantColor,
                                              size: 18,
                                            ),
                                          if (_selectedSortOption ==
                                              SortOption.genreReversed)
                                            const SizedBox(width: 8),
                                          const Text('Genre (Z-A)'),
                                        ],
                                      ),
                                    ),
                                  ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: fixedHeaderHeight,
                    child: Container(
                      color: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.menu_outlined, color: textColor),
                            onPressed: () {
                              _scaffoldKey.currentState?.openDrawer();
                            },
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child:
                                _isSearchExpanded
                                    ? Container(
                                      key: const ValueKey('searchField'),
                                      width:
                                          MediaQuery.of(context).size.width -
                                          120,
                                      margin: const EdgeInsets.only(left: 8.0),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            dominantColor.withValues(
                                              alpha: 0.15,
                                            ),
                                            Colors.black.withValues(alpha: 0.3),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: dominantColor.withValues(
                                              alpha: 0.2,
                                            ),
                                            blurRadius: 15,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: TextField(
                                        controller: _searchController,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 16,
                                        ),
                                        cursorColor: dominantColor,
                                        decoration: InputDecoration(
                                          hintText: 'Search songs...',
                                          hintStyle: TextStyle(
                                            color: textColor.withValues(
                                              alpha: 0.6,
                                            ),
                                            fontWeight: FontWeight.w300,
                                          ),
                                          prefixIcon: Icon(
                                            Icons.search,
                                            color: textColor.withValues(
                                              alpha: 0.8,
                                            ),
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                          filled: true,
                                          fillColor: Colors.transparent,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 14,
                                              ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            borderSide: BorderSide(
                                              color: dominantColor.withValues(
                                                alpha: 0.4,
                                              ),
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                        onChanged:
                                            (value) => _updateSearchResults(),
                                        textInputAction: TextInputAction.search,
                                      ),
                                    )
                                    : const SizedBox(
                                      key: ValueKey('empty'),
                                      width: 0,
                                    ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              _isSearchExpanded ? Icons.close : Icons.search,
                              color: textColor,
                            ),
                            onPressed: _toggleSearch,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showMiniPlayer && currentSong != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: MiniPlayer(
                          onReloadLibrary: _loadSongs,
                          musicFolder: _musicFolder,
                          key: _miniPlayerKey,
                          song: currentSong!,
                          songList: displayedSongs,
                          service: service,
			  currentPlaylistName: _currentPlaylistName,
                          currentIndex: currentIndex,
                          onClose: () => setState(() => showMiniPlayer = false),
                          onUpdate: (newSong, newIndex, newColor) {
                            setState(() {
                              currentSong = newSong;
                              currentIndex = newIndex;
                              dominantColor = newColor;
                            });
                          },
                          dominantColor: dominantColor,
                        ),
                      ),
                    ),
                  if (_isPlaylistTransitioning)
                    Positioned.fill(
                      child: FadeTransition(
                        opacity: _playlistTransitionAnimation,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                dominantColor.withValues(alpha: 0.0),
                                dominantColor.withValues(alpha: 0.3),
                                dominantColor.withValues(alpha: 0.0),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final AdimanService service;
  final Function(String)? onMusicFolderChanged;
  final Future<void> Function() onReloadLibrary;
  final Song? currentSong;
  final int currentIndex;
  final Color dominantColor;
  final List<Song> songs;
  final String musicFolder;
  final String? currentPlaylistName;
  final void Function(Song newSong, int newIndex, Color newColor)?
  onUpdateMiniPlayer;

  const SettingsScreen({
    super.key,
    required this.service,
    this.onMusicFolderChanged,
    required this.onReloadLibrary,
    this.currentSong,
    this.currentIndex = 0,
    this.dominantColor = Colors.purple,
    required this.songs,
    required this.musicFolder,
    this.onUpdateMiniPlayer,
    this.currentPlaylistName,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isClearingCache = false;
  bool _isReloadingLibrary = false;
  final bool _isManagingSeparators = false;
  bool _autoConvert = true;
  bool _clearMp3Cache = false;

  Song? _currentSong;
  int _currentIndex = 0;
  late Color _currentColor;

  late TextEditingController _musicFolderController;

  final GlobalKey<_MiniPlayerState> _miniPlayerKey =
      GlobalKey<_MiniPlayerState>();

  @override
  void initState() {
    super.initState();
    _currentSong = widget.currentSong;
    _currentIndex = widget.currentIndex;
    _currentColor = widget.dominantColor;
    _musicFolderController = TextEditingController(text: widget.musicFolder);
    _loadChecks();
}

  @override
  void dispose() {
    _musicFolderController.dispose();
    super.dispose();
  }

Future<void> _loadChecks() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    _autoConvert = prefs.getBool('autoConvert') ?? false;
    _clearMp3Cache = prefs.getBool('clearMp3Cache') ?? false;
  });
}

  String expandTilde(String path) {
    if (path.startsWith('~')) {
      final home = Platform.environment['HOME'] ?? '';
      return path.replaceFirst('~', home);
    }
    return path;
  }

Future<void> _saveAutoConvert(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('autoConvert', value);
  setState(() => _autoConvert = value);
}

Future<void> _saveClearMp3Cache(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('clearMp3Cache', value);
  setState(() => _clearMp3Cache = value);
}

  Future<void> _clearCache() async {
    setState(() => _isClearingCache = true);
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list()) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (e) {
            print('Failed to delete ${entity.path}: $e');
          }
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Cache cleared successfully',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: _currentColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error clearing cache: $e',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: _currentColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    if (_clearMp3Cache) {
      await rust_api.clearMp3Cache();
    }
    setState(() {
      _isClearingCache = false;
    });
  }

  Future<void> _reloadLibrary() async {
    setState(() {
      _isReloadingLibrary = true;
    });
    await widget.onReloadLibrary();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Music library reloaded successfully (if you are waiting for your songs to be converted, you might have to do this again due to the waiting list of songs needing conversion)',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: _currentColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() {
      _isReloadingLibrary = false;
    });
  }

  void _togglePauseSong() {
    if (_currentSong == null) return;
    _miniPlayerKey.currentState?.togglePause();
  }

Widget _buildSettingsSwitch(
  BuildContext context, {
  required String title,
  required bool value,
  required Function(bool) onChanged,
}) {
  final glowColor = widget.dominantColor.withAlpha(60);
  final trackColor = widget.dominantColor.withAlpha(30);
  final textColor = Theme.of(context).textTheme.bodyLarge?.color;

  return ListTile(
    title: GlowText(
      title,
      glowColor: glowColor,
      style: TextStyle(
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    trailing: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          width: 60,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                trackColor,
                trackColor.withAlpha(10),
              ],
            ),
            border: Border.all(
              color: widget.dominantColor.withAlpha(value ? 100 : 40),
              width: 1.5,
            ),
            boxShadow: [
              if (value)
                BoxShadow(
                  color: glowColor,
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(4),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.dominantColor.withAlpha(200),
                    widget.dominantColor.withAlpha(100),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: glowColor,
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                value ? Icons.check_rounded : Icons.close_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final textColor =
        _currentColor.computeLuminance() > 0.007 ? _currentColor : Colors.white;
    final buttonTextColor =
        _currentColor.computeLuminance() > 0.007 ? Colors.white : Colors.black;

    return RawKeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.pop(context);
          } else if (event.logicalKey == LogicalKeyboardKey.space &&
              FocusScope.of(context).hasFocus &&
              FocusScope.of(context).focusedChild is EditableText) {
            _togglePauseSong();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: GlowText(
            'Settings',
            glowColor: _currentColor.withValues(alpha: 0.3),
            style: TextStyle(
              fontSize: 24,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.black,
          surfaceTintColor: _currentColor,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.5,
              colors: [_currentColor.withValues(alpha: 0.15), Colors.black],
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
                child: ListView(
                  children: [
                    GlowText(
                      'Music Folder',
                      glowColor: _currentColor.withValues(alpha: 0.2),
                      style: TextStyle(
                        fontSize: 28,
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _currentColor.withValues(alpha: 0.1),
                            Colors.black.withValues(alpha: 0.3),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _currentColor.withValues(alpha: 0.2),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _musicFolderController,
                        style: TextStyle(color: textColor, fontSize: 16),
                        cursorColor: _currentColor,
                        decoration: InputDecoration(
                          hintText: 'Enter music folder path...',
                          hintStyle: TextStyle(
                            color: textColor.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w300,
                          ),
                          prefixIcon: Icon(
                            Icons.folder_open_rounded,
                            color: textColor.withValues(alpha: 0.8),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: _currentColor.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [_currentColor.withAlpha(220), _currentColor],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _currentColor.withAlpha(100),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () async {
                          final expandedPath = await expandTilde(
                            _musicFolderController.text,
                          );

                          SharedPreferences prefs =
                              await SharedPreferences.getInstance();
                          await prefs.setString('musicFolder', expandedPath);

                          if (widget.onMusicFolderChanged != null) {
                            await widget.onMusicFolderChanged!(expandedPath);
                          }

                          Navigator.pop(context, expandedPath);
                        },
                        icon: Icon(Icons.save, color: buttonTextColor),
                        label: Text(
                          'Save Music Folder',
                          style: TextStyle(
                            color: buttonTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildActionButton(
                      icon: Icons.refresh,
                      label: 'Reload Music Library',
                      isLoading: _isReloadingLibrary,
                      onPressed: _reloadLibrary,
                    ),
                    const SizedBox(height: 16),
                    _buildActionButton(
                      icon: Icons.text_fields_rounded,
                      label: 'Manage Artist Seperators',
                      isLoading: _isManagingSeparators,
                      onPressed: _showSeparatorManagementPopup,
                    ),
                    const SizedBox(height: 16),
                    _buildActionButton(
                      icon: Icons.delete,
                      label: 'Clear Cache',
                      isLoading: _isClearingCache,
                      onPressed: _clearCache,
                    ),
		    _buildSettingsSwitch(
		      context,
		      title: 'Auto-convert non-MP3 files',
		      value: _autoConvert,
		      onChanged: _saveAutoConvert,
		    ),
		    _buildSettingsSwitch(
		      context,
		      title: 'Clear MP3 cache with app cache',
		      value: _clearMp3Cache,
		      onChanged: _saveClearMp3Cache,
		      ),
                  ],
                ),
              ),
              if (_currentSong != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MiniPlayer(
                    onReloadLibrary: widget.onReloadLibrary,
                    musicFolder: widget.musicFolder,
                    key: _miniPlayerKey,
                    song: _currentSong!,
                    songList: widget.songs,
                    service: widget.service,
		    currentPlaylistName: widget.currentPlaylistName,
                    currentIndex: _currentIndex,
                    onClose:
                        () => widget.onUpdateMiniPlayer?.call(
                          _currentSong!,
                          _currentIndex,
                          _currentColor,
                        ),
                    onUpdate: (newSong, newIndex, newColor) {
                      setState(() {
                        _currentSong = newSong;
                        _currentIndex = newIndex;
                        _currentColor = newColor;
                      });
                      widget.onUpdateMiniPlayer?.call(
                        newSong,
                        newIndex,
                        newColor,
                      );
                    },
                    dominantColor: _currentColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSeparatorManagementPopup() async {
    List<String> currentSeparators = await rust_api.getCurrentSeparators();
    final TextEditingController _addController = TextEditingController();
    final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: _AnimatedPopupWrapper(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _currentColor.withAlpha(30),
                          Colors.black.withAlpha(200),
                        ],
                      ),
                      border: Border.all(
                        color: _currentColor.withAlpha(100),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlowText(
                            'Manage Separators',
                            glowColor: _currentColor.withAlpha(80),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _currentColor,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Form(
                            key: _formKey,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _currentColor.withAlpha(30),
                                    Colors.black.withAlpha(100),
                                  ],
                                ),
                              ),
                              child: TextFormField(
                                controller: _addController,
                                style: TextStyle(color: Colors.white),
                                cursorColor: _currentColor,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  hintText: 'Add new separator...',
                                  hintStyle: TextStyle(color: Colors.white70),
                                  prefixIcon: Icon(
                                    Icons.add,
                                    color: _currentColor,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  suffixIcon: DynamicIconButton(
                                    icon: Icons.check,
                                    onPressed: () async {
                                      if (_formKey.currentState!.validate()) {
                                        final newSep =
                                            _addController.text.trim();
                                        if (newSep.isEmpty) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Separator cannot be empty!',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              backgroundColor: Colors.redAccent,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        if (currentSeparators.contains(
                                          newSep,
                                        )) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Separator already exists!',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              backgroundColor:
                                                  Colors.orangeAccent,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        try {
                                          rust_api.addSeparator(
                                            separator: newSep,
                                          );
                                          setStateDialog(() {
                                            currentSeparators.add(newSep);
                                            _addController.clear();
                                          });
                                        } catch (e) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Failed to add separator: $e',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              backgroundColor: Colors.redAccent,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    backgroundColor: _currentColor,
                                    size: 36,
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Enter a separator';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  MediaQuery.of(context).size.height * 0.4,
                            ),
                            child:
                                currentSeparators.isEmpty
                                    ? Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Text(
                                        'No custom separators added',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                    )
                                    : ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: currentSeparators.length,
                                      itemBuilder: (context, index) {
                                        final separator =
                                            currentSeparators[index];
                                        return ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(
                                            Icons.arrow_right,
                                            color: _currentColor,
                                          ),
                                          title: Text(
                                            separator,
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          trailing: IconButton(
                                            icon: Icon(
                                              Icons.delete,
                                              color: Colors.redAccent,
                                            ),
                                            onPressed: () async {
                                              try {
                                                rust_api.removeSeparator(
                                                  separator: separator,
                                                );
                                                setStateDialog(() {
                                                  currentSeparators.removeAt(
                                                    index,
                                                  );
                                                });
                                              } catch (e) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Failed to remove separator: $e',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    backgroundColor:
                                                        Colors.redAccent,
                                                    behavior:
                                                        SnackBarBehavior
                                                            .floating,
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        );
                                      },
                                    ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: DynamicIconButton(
                                  icon: Icons.restart_alt_rounded,
                                  //label: 'Reset Defaults',
                                  onPressed: () async {
                                    try {
                                      rust_api.resetSeparators();
                                      setStateDialog(() {
                                        currentSeparators =
                                            rust_api.getCurrentSeparators();
                                      });
                                    } catch (e) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Failed to reset separators: $e',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          backgroundColor: Colors.redAccent,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                  backgroundColor: _currentColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    final textColor =
        _currentColor.computeLuminance() > 0.007 ? Colors.white : Colors.black;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(15),
        splashColor: _currentColor.withValues(alpha: 0.1),
        highlightColor: _currentColor.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _currentColor.withValues(alpha: 0.3),
                      _currentColor.withValues(alpha: 0.1),
                    ],
                  ),
                ),
                child:
                    isLoading
                        ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: textColor,
                          ),
                        )
                        : Icon(icon, color: textColor),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: textColor.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SongListTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;

  const SongListTile({super.key, required this.song, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Card(
        color: Colors.black.withValues(alpha: 0.2),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            onTap: onTap,
            leading: Hero(
              //tag: 'main-${song.path}',
              tag: 'albumArt-${song.path}',
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withValues(alpha: 0.2),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      song.albumArt != null
                          ? Image.memory(
                            base64Decode(song.albumArt!),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder:
                                (context, error, stackTrace) => const GlowIcon(
                                  Icons.music_note,
                                  color: Colors.white,
                                ),
                          )
                          : const GlowIcon(
                            Icons.music_note,
                            color: Colors.white,
                            size: 32,
                          ),
                ),
              ),
            ),
            title: Text(
              song.title,
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              '${song.artist} • ${song.album} • ${song.genre}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
            trailing: Text(
              '${song.duration.inMinutes}:${(song.duration.inSeconds % 60).toString().padLeft(2, '0')}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ),
    );
  }
}

class MusicPlayerScreen extends StatefulWidget {
  final Song song;
  final int currentIndex;
  final List<Song> songList;
  final AdimanService service;
  final String musicFolder;
  final bool isShuffled;
  final bool isTemp;
  final String? tempPath;
  final String? currentPlaylistName;
  final Future<void> Function() onReloadLibrary;

  const MusicPlayerScreen({
    super.key,
    required this.song,
    required this.songList,
    required this.currentIndex,
    required this.service,
    required this.musicFolder,
    required this.onReloadLibrary,
    this.isShuffled = false,
    this.isTemp = false,
    this.tempPath,
    this.currentPlaylistName,
  });

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with TickerProviderStateMixin {
  late AnimationController _playPauseController;
  bool isPlaying = false;
  double _currentSliderValue = 0.0;
  late Timer _progressTimer;
  bool _isSeeking = false;
  Timer? _seekTimer;
  bool _isTransitioning = false;
  late Color dominantColor;
  List<double> _waveformData = [];
  late Song currentSong;
  late int currentIndex;
  bool _showLyrics = false;
  lrc_pkg.Lrc? _lrcData;
  bool _hasLyrics = false;
  late FocusNode _focusNode;
  StreamSubscription<bool>? _playbackSubscription;
  StreamSubscription<Song>? _trackChangeSubscription;
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late bool _isTempFile;
  late ParticleOptions _particleOptions;
  late final _particlePaint =
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white;

  RepeatMode _repeatMode = RepeatMode.normal;
  bool _hasRepeated = false;

  List<int>? _shuffleOrder;
  int _shuffleIndex = 0;

  @override
  void initState() {
    super.initState();
    _isTempFile = widget.isTemp;
    _isTempFile ? _togglePlayPause : null;
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _breathingAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );

    _trackChangeSubscription = widget.service.trackChanges.listen((newSong) {
      if (mounted) {
        setState(() {
          currentSong = newSong;
          currentIndex = widget.songList.indexWhere(
            (s) => s.path == newSong.path,
          );
          _initWaveform();
          _loadLyrics();
          _updateDominantColor();
        });
        widget.service.updatePlaylist(widget.songList, currentIndex);
      }
    });

    _playbackSubscription = widget.service.playbackStateStream.listen((
      isPlaying,
    ) {
      if (mounted) {
        setState(() {
          this.isPlaying = isPlaying;
          isPlaying
              ? _playPauseController.forward()
              : _playPauseController.reverse();
        });
      }
    });

    _focusNode = FocusNode();
    _focusNode.requestFocus();
    dominantColor = Colors.purple.shade900;
    currentSong = widget.song;
    currentIndex = widget.currentIndex;
    _playPauseController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _initWaveform();
    _loadLyrics();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLyrics());

    if (currentSong.albumArt != null) {
      _updateDominantColor();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pos = await rust_api.getPlaybackPosition();
      if (mounted && currentSong.duration.inSeconds > 0) {
        setState(() {
          _currentSliderValue = (pos / currentSong.duration.inSeconds).clamp(
            0.0,
            1.0,
          );
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _startPlaying());

    isPlaying = rust_api.isPlaying();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (isPlaying && !_isSeeking && mounted) {
        _updateProgress();
      }
    });

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fadeController.forward();
    });

    _updateParticleOptions();
  }

void _showPlaylistPopup(BuildContext context) {
  final currentSong = widget.song;
  final textColor =
        dominantColor.computeLuminance() > 0.007 ? dominantColor : Colors.white;
  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: dominantColor.withValues(alpha: 0.5),
        elevation: 0,
        child: _AnimatedPopupWrapper(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    dominantColor.withAlpha(30),
                    Colors.black.withAlpha(200),
                  ],
                ),
                border: Border.all(
                  color: dominantColor.withAlpha(100),
                  width: 1.2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlowText(
                      'Song Options',
                      glowColor: dominantColor.withAlpha(80),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildPlaylistOptionButton(
                      icon: Icons.create_new_folder,
                      label: 'Create New Playlist',
                      onTap: () {
                        Navigator.pop(context);
                        _handleCreatePlaylist(currentSong);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildPlaylistOptionButton(
                      icon: Icons.playlist_add,
                      label: 'Add to Existing',
                      onTap: () {
                        Navigator.pop(context);
                        _handleAddToExistingPlaylist(currentSong);
                      },
                    ),
                    if (widget.currentPlaylistName != null) ...[
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Icons.remove_circle,
                        label: 'Remove from Playlist',
                        onTap: () async {
                          Navigator.pop(context);
                          await _removeSongFromCurrentPlaylist(currentSong);
                        },
                        isDestructive: true,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _buildPlaylistOptionButton(
                      icon: Icons.delete_forever_rounded,
                      label: 'Delete Song',
                      onTap: () async {
                        Navigator.pop(context);
                        final confirmed = await _showDeleteConfirmationDialog(currentSong);
                        if (confirmed) {
                          await _deleteSongFile(currentSong);
                        }
                      },
                      isDestructive: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget _buildPlaylistOptionButton({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  bool isDestructive = false,
}) {
  final color = isDestructive ? Colors.redAccent : dominantColor;
  return Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      splashColor: color.withAlpha(50),
      highlightColor: color.withAlpha(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withAlpha(80), width: 0.8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            GlowIcon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}


  Future<String?> _showPlaylistNameDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: _AnimatedPopupWrapper(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      dominantColor.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                  border: Border.all(
                    color: dominantColor.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlowText(
                        'New Playlist',
                        glowColor: dominantColor.withValues(alpha: 0.3),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: dominantColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              dominantColor.withValues(alpha: 0.1),
                              Colors.black.withValues(alpha: 0.3),
                            ],
                          ),
                        ),
                        child: TextField(
                          controller: controller,
                          style: const TextStyle(color: Colors.white),
                          cursorColor: dominantColor,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            hintText: 'Playlist name...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            prefixIcon: Icon(
                              Icons.playlist_add_rounded,
                              color: dominantColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: dominantColor.withValues(
                                alpha: 0.3,
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DynamicIconButton(
                            icon: Icons.check_rounded,
                            onPressed:
                                () => Navigator.pop(
                                  context,
                                  controller.text.trim(),
                                ),
                            backgroundColor: dominantColor,
                            size: 40,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

Future<void> _handleCreatePlaylist(Song song) async {
  final playlistName = await _showPlaylistNameDialog();
  if (playlistName != null && playlistName.isNotEmpty) {
    await createPlaylist(widget.musicFolder, playlistName);
    await addSongToPlaylist(song.path, widget.musicFolder, playlistName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Created playlist $playlistName'),
        backgroundColor: dominantColor,
      ),
    );
  }
}


  Future<Directory> createPlaylist(
    String musicFolder,
    String playlistName,
  ) async {
    final baseDir = await getPlaylistBase(musicFolder);
    final playlistDir = Directory('${baseDir.path}/$playlistName');
    if (!(await playlistDir.exists())) {
      await playlistDir.create();
    }
    return playlistDir;
  }

Future<void> _handleAddToExistingPlaylist(Song song) async {
  final playlists = await listPlaylists(widget.musicFolder);
  final selectedPlaylist = await _showSelectPlaylistDialog(playlists);
  if (selectedPlaylist != null && selectedPlaylist.isNotEmpty) {
    await addSongToPlaylist(song.path, widget.musicFolder, selectedPlaylist);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added to $selectedPlaylist'),
        backgroundColor: dominantColor,
      ),
    );
  }
}


  Future<String?> _showSelectPlaylistDialog(List<String> playlists) async {
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: _AnimatedPopupWrapper(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      dominantColor.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                  border: Border.all(
                    color: dominantColor.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: GlowText(
                        'Select Playlist',
                        glowColor: dominantColor.withValues(alpha: 0.3),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: dominantColor,
                        ),
                      ),
                    ),
                    Divider(
                      color: dominantColor.withValues(alpha: 0.2),
                      height: 1,
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.pop(context, playlist),
                              splashColor: dominantColor.withValues(alpha: 0.1),
                              highlightColor: dominantColor.withValues(
                                alpha: 0.05,
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: dominantColor.withValues(
                                        alpha: 0.1,
                                      ),
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.queue_music_rounded,
                                      color: dominantColor.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        playlist,
                                        style: TextStyle(
                                          color:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodyLarge?.color,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> addSongToPlaylist(
    String songPath,
    String musicFolder,
    String playlistName,
  ) async {
    final playlistDir = Directory('$musicFolder/.adilists/$playlistName');
    if (!(await playlistDir.exists())) {
      await playlistDir.create(recursive: true);
    }
    final songFile = File(songPath);
    if (await songFile.exists()) {
      final filename = songFile.uri.pathSegments.last;
      final linkPath = '${playlistDir.path}/$filename';
      final link = Link(linkPath);
      if (!await link.exists()) {
        await link.create(songFile.absolute.path);
        print('Added $songPath to playlist $playlistName');
      } else {
        print('Song already in playlist.');
      }
    } else {
      print('Song file does not exist: $songPath');
    }
  }

  Future<Directory> getPlaylistBase(String musicFolder) async {
    final baseDir = Directory('$musicFolder/.adilists');
    if (!(await baseDir.exists())) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }


  Future<List<String>> listPlaylists(String musicFolder) async {
    final baseDir = await getPlaylistBase(musicFolder);
    final playlists = <String>[];
    await for (final entity in baseDir.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is Directory) {
        final parts = entity.path.split(Platform.pathSeparator);
        playlists.add(parts.last);
      }
    }
    return playlists;
  }

Future<void> _removeSongFromCurrentPlaylist(Song song) async {
  if (widget.currentPlaylistName == null) return;
  final songFile = File(song.path);
  final filename = songFile.uri.pathSegments.last;
  final linkPath = '${widget.musicFolder}/.adilists/${widget.currentPlaylistName}/$filename';
  final link = Link(linkPath);
  if (await link.exists()) {
    await link.delete();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed from playlist'),
        backgroundColor: dominantColor,
      ),
    );
    widget.service.updatePlaylist(widget.songList, widget.currentIndex);
  }
}

Future<bool> _showDeleteConfirmationDialog(Song song) async {
  return await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: dominantColor.withAlpha(30),
      title: Text('Delete Song?', style: TextStyle(color: Colors.white)),
      content: Text('This will permanently delete "${song.title}"', 
        style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          child: Text('Cancel', style: TextStyle(color: Colors.white70)),
          onPressed: () => Navigator.pop(context, false),
        ),
        TextButton(
          child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  ) ?? false;
}

Future<void> _deleteSongFile(Song song) async {
  try {
    final file = File(song.path);
    if (await file.exists()) {
      await file.delete();
      await widget.onReloadLibrary();
      if (mounted) {
        _handleSkipNext();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Song deleted'),
            backgroundColor: dominantColor,
          ),
        );
      }
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error deleting: ${e.toString()}'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

  void _updateParticleOptions() {
    final peakSpeed =
        (_waveformData.isNotEmpty
                ? _waveformData[(_currentSliderValue * _waveformData.length)
                    .toInt()]
                : 0.0) *
            150 +
        50;

    _particleOptions = ParticleOptions(
      baseColor: Colors.white,
      spawnOpacity: 0.4,
      opacityChangeRate: 0.2,
      minOpacity: 0.1,
      maxOpacity: 0.6,
      spawnMinSpeed: peakSpeed,
      spawnMaxSpeed: 60 + peakSpeed * 0.7,
      spawnMinRadius: 2.0,
      spawnMaxRadius: 4.0,
      particleCount: 50,
    );
  }

  /// Initialize waveform data by decoding the MP3 file.
  void _initWaveform() async {
    setState(() {
      _waveformData = List.filled(1000, 0.0);
    });
    try {
      List<double> waveform = await rust_api.extractWaveformFromMp3(
        mp3Path: currentSong.path,
        sampleCount: 1000,
        channels: 2,
      );
      if (mounted) {
        setState(() {
          _waveformData = waveform;
          _updateProgress();
        });
      }
    } catch (e) {
      print("Error extracting waveform: $e");
      setState(() => _waveformData = _generateDummyWaveformData());
    }
  }

  Future<lrc_pkg.Lrc?> _getCachedLyrics(String songPath) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final hash = md5.convert(utf8.encode(songPath)).toString();
      final file = File('${cacheDir.path}/lyrics/$hash.lrc');
      if (await file.exists()) {
        final contents = await file.readAsString();
        return lrc_pkg.Lrc.parse(contents);
      }
    } catch (e) {
      print('Error reading cached lyrics: $e');
    }
    return null;
  }

  Future<void> _saveLyricsToCache(String songPath, String lrcContent) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final dir = Directory('${cacheDir.path}/lyrics');
      if (!await dir.exists()) await dir.create(recursive: true);
      final hash = md5.convert(utf8.encode(songPath)).toString();
      final file = File('${dir.path}/$hash.lrc');
      await file.writeAsString(lrcContent);
    } catch (e) {
      print('Error saving lyrics cache: $e');
    }
  }

  Future<void> _loadLyrics() async {
    _lrcData = null;
    try {
      // 1. Check cache.
      final cachedLrc = await _getCachedLyrics(currentSong.path);
      if (cachedLrc != null) {
        _lrcData = cachedLrc;
        _updateLyricsStatus();
        setState(() {});
        return;
      }

      // 2. Check if required fields are present.
      if (currentSong.title.isEmpty || currentSong.artist.isEmpty) {
        _checkLocalLyrics();
        return;
      }

      // 3. Fetch from LRCLIB API.
      final params = {
        'track_name': currentSong.title,
        'artist_name': currentSong.artist,
        if (currentSong.album.isNotEmpty) 'album_name': currentSong.album,
        //if (currentSong.duration != null)
        'duration': currentSong.duration.inSeconds.toString(),
      };

      final uri = Uri.https('lrclib.net', '/api/get', params);
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'Adiman/1.0.0 (https://github.com/notYetOnGithub/adiman)',
        },
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final syncedLyrics = jsonResponse['syncedLyrics'] as String?;
        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          _lrcData = lrc_pkg.Lrc.parse(syncedLyrics);
          if (_lrcData!.lyrics.isNotEmpty) {
            await _saveLyricsToCache(currentSong.path, syncedLyrics);
            _updateLyricsStatus();
            setState(() {});
            return;
          }
        }
      }
    } catch (e) {
      print('Error fetching lyrics from API: $e');
    }
    // 4. Fallback to local file.
    _checkLocalLyrics();
  }

  void _checkLocalLyrics() async {
    try {
      final lrcPath = currentSong.path.replaceAll('.mp3', '.lrc');
      final file = File(lrcPath);
      if (await file.exists()) {
        final contents = await file.readAsString();
        _lrcData = lrc_pkg.Lrc.parse(contents);
        _updateLyricsStatus();
        setState(() {});
        return;
      }
    } catch (e) {
      print('Error loading local lyrics: $e');
    }
    // 5. Create empty LRC as final fallback.
    _lrcData = lrc_pkg.Lrc(
      lyrics: [],
      type: lrc_pkg.LrcTypes.extended_enhanced,
      artist: currentSong.artist,
      album: currentSong.album,
      title: currentSong.title,
      length: currentSong.duration.inSeconds.toString(),
    );
    _updateLyricsStatus();
  }

  void _updateLyricsStatus() {
    _hasLyrics =
        _lrcData != null &&
        _lrcData!.lyrics.isNotEmpty &&
        _lrcData!.lyrics.any((line) => line.lyrics.trim().isNotEmpty);
  }

  bool _rupdateLyricsStatus() {
    _hasLyrics =
        _lrcData != null &&
        _lrcData!.lyrics.isNotEmpty &&
        _lrcData!.lyrics.any((line) => line.lyrics.trim().isNotEmpty);

    return _hasLyrics;
  }

  @override
  void didUpdateWidget(MusicPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song.path != oldWidget.song.path) {
      _loadLyrics();
      _updateLyricsStatus();
    }
  }

  void _updateProgress() async {
    try {
      final position = await rust_api.getPlaybackPosition();
      if (mounted && currentSong.duration.inSeconds > 0) {
        setState(() {
          _currentSliderValue = (position / currentSong.duration.inSeconds)
              .clamp(0.0, 1.0);
        });
        if (position >= currentSong.duration.inSeconds - 0.1) {
          await _handleSongFinished();
        }
      }
    } catch (e) {
      print('Error updating progress: $e');
    }
  }

  Future<void> _handleSeek(double value) async {
    if (!value.isFinite || _isTransitioning) return;
    _isSeeking = true;
    setState(() => _currentSliderValue = value.clamp(0.0, 1.0));
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 50), () async {
      try {
        final seekPosition = (value * currentSong.duration.inSeconds).clamp(
          0.0,
          currentSong.duration.inSeconds.toDouble(),
        );
        await rust_api.seekToPosition(position: seekPosition);
        if (!isPlaying && mounted) {
          setState(() {
            isPlaying = true;
            _playPauseController.forward();
          });
        }
      } catch (e) {
        print('Error seeking: $e');
      } finally {
        _isSeeking = false;
      }
    });
  }

  Future<void> _startPlaying() async {
    try {
      final currentPath = await rust_api.getCurrentSongPath();
      final isCurrentlyPlaying = await rust_api.isPlaying();
      if (currentPath == currentSong.path) {
        setState(() {
          isPlaying = isCurrentlyPlaying;
          if (isPlaying) {
            _playPauseController.forward();
          } else {
            _playPauseController.reverse();
          }
        });
        widget.service.updatePlaylist(widget.songList, currentIndex);
        widget.service._updateMetadata();
        return;
      }
      final started = await rust_api.playSong(path: currentSong.path);
      if (started && mounted) {
        widget.service.updatePlaylistStart(widget.songList, currentIndex);
        widget.service._updateMetadata();
        setState(() {
          isPlaying = true;
          _currentSliderValue = 0.0;
          _playPauseController.forward();
        });
      }
    } catch (e) {
      print('Error starting playback: $e');
    }
  }

  Future<void> _updateDominantColor() async {
    try {
      if (currentSong.albumArt == null) return;
      final imageBytes = base64Decode(currentSong.albumArt!);
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final palette = await PaletteGenerator.fromImage(frame.image);
      if (mounted) {
        setState(() {
          dominantColor =
              palette.dominantColor?.color ?? Colors.purple.shade900;
        });
      }
    } catch (e) {
      print('Error generating dominant color: $e');
      if (mounted) setState(() => dominantColor = Colors.purple.shade900);
    }
  }

  Future<void> _replaySong() async {
    final seekPosition = (0.0 * currentSong.duration.inSeconds).clamp(
      0.0,
      currentSong.duration.inSeconds.toDouble(),
    );
    await rust_api.seekToPosition(position: seekPosition);
    await rust_api.playSong(path: currentSong.path);
  }

  void _generateShuffleOrder() {
    _shuffleOrder = List.generate(widget.songList.length, (index) => index);
    _shuffleOrder!.shuffle();
    _shuffleIndex = _shuffleOrder!.indexOf(currentIndex);
    if (_shuffleIndex == -1) {
      _shuffleOrder!.insert(0, currentIndex);
      _shuffleIndex = 0;
    }
  }

  Future<void> _handleSongFinished() async {
    if (_isTransitioning) return;
    await rust_api.stopSong();
    if (_repeatMode == RepeatMode.repeatOnce) {
      // Play once then stop
      if (!_hasRepeated) {
        await _replaySong();
        _hasRepeated = true;
      } else {
        await _handleSkipNext();
      }
    } else if (_repeatMode == RepeatMode.repeatAll || _isTempFile) {
      await _replaySong();
    } else {
      await _handleSkipNext();
    }
  }

  Future<void> _handleSkipNext() async {
    if (_isTransitioning) return;
    setState(() => _isTransitioning = true);
    _hasRepeated = false;

    if (currentIndex >= widget.songList.length - 1) {
      currentIndex = 0;
    } else {
      currentIndex++;
    }

    currentSong = widget.songList[currentIndex];
    _initWaveform();
    _loadLyrics();
    await _updateDominantColor();

    final success = await rust_api.playSong(path: currentSong.path);
    if (success && mounted) {
      setState(() {
        isPlaying = true;
        _currentSliderValue = 0.0;
        _playPauseController.forward();
      });
      widget.service.updatePlaylist(widget.songList, currentIndex);
      widget.service._updateMetadata();
    }

    setState(() => _isTransitioning = false);
  }

  Future<void> _handleSkipPrevious() async {
    if (_isTransitioning || currentIndex <= 0) return;
    setState(() {
      _isTransitioning = true;
    });
    _hasRepeated = false;
    if (widget.isShuffled) {
      if (_shuffleOrder == null) {
        _generateShuffleOrder();
      }
      if (_shuffleIndex > 0) {
        _shuffleIndex--;
      } else {
        _generateShuffleOrder();
        _shuffleIndex = _shuffleOrder!.length - 1;
      }
      currentIndex = _shuffleOrder![_shuffleIndex];
    } else {
      currentIndex--;
    }
    currentSong = widget.songList[currentIndex];
    _hasRepeated = false;
    _initWaveform();
    _loadLyrics();
    await _updateDominantColor();
    final success = await rust_api.playSong(path: currentSong.path);
    if (success && mounted) {
      setState(() {
        isPlaying = true;
        _currentSliderValue = 0.0;
        _playPauseController.forward();
      });
      widget.service.updatePlaylist(widget.songList, currentIndex);
      widget.service._updateMetadata();
    }
    setState(() => _isTransitioning = false);
  }

  void _togglePlayPause() async {
    try {
      if (isPlaying) {
        await rust_api.pauseSong();
        widget.service._playbackStateController.add(false);
        _playPauseController.reverse();
        widget.service.onPause();
      } else {
        await rust_api.resumeSong();
        widget.service._playbackStateController.add(true);
        _playPauseController.forward();
        widget.service.onPlay();
      }
      setState(() => isPlaying = !isPlaying);
    } catch (e) {
      print('Error toggling playback: $e');
    }
  }

  // Cycle through the repeat modes: Normal -> RepeatOnce -> RepeatAll -> Normal.
  void _toggleRepeatMode() {
    setState(() {
      if (_repeatMode == RepeatMode.normal) {
        _repeatMode = RepeatMode.repeatOnce;
      } else if (_repeatMode == RepeatMode.repeatOnce) {
        _repeatMode = RepeatMode.repeatAll;
      } else {
        _repeatMode = RepeatMode.normal;
      }
    });
  }

  void _showPlayerMenu(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    
    showDialog(
      context: context,
      builder: (context) {
        return Stack(
          children: [
            // Background overlay
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.black.withAlpha(50)),
                ),
              ),
            ),
            // Menu positioning
            Positioned(
              top: offset.dy + 50,
              right:
                  MediaQuery.of(context).size.width -
                  offset.dx -
                  renderBox.size.width,
              child: _AnimatedPopupWrapper(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          dominantColor.withAlpha(30),
                          Colors.black.withAlpha(200),
                        ],
                      ),
                      border: Border.all(
                        color: dominantColor.withAlpha(100),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        children: [
                          _buildMenuOption(
                            icon: Icons.search,
                            label: 'Find new song',
                            onTap: () {
                              _handleSearchAnother();
                            },
                          ),
                          _buildMenuOption(
                            icon: Icons.save_rounded,
                            label: 'Save to Library',
                            onTap: () {
                              Navigator.pop(context);
                              _handleSaveToLibrary();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: dominantColor.withAlpha(50),
        highlightColor: dominantColor.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              GlowIcon(icon, color: dominantColor, blurRadius: 8, size: 24),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSearchAnother() async {
    if (widget.isTemp && widget.tempPath != null) {
      try {
        final file = File(widget.tempPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting temp file: $e');
      }
    }
    await rust_api.pauseSong();
    widget.service._playbackStateController.add(false);
    _playPauseController.reverse();
    widget.service.onPause();
    Navigator.pushAndRemoveUntil(
      context,
      NamidaPageTransitions.createRoute(
        DownloadScreen(
          service: widget.service,
          musicFolder: widget.musicFolder,
          onReloadLibrary: widget.onReloadLibrary,
        ),
      ),
      (route) => route.isFirst
    );
  }

  Future<void> _handleSaveToLibrary() async {
    if (!widget.isTemp || widget.tempPath == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final musicFolder = prefs.getString('musicFolder') ?? '~/Music';
      final expandedPath = musicFolder.replaceFirst(
        '~',
        Platform.environment['HOME'] ?? '',
      );

      final sourceFile = File(widget.tempPath!);
      final destPath = path.join(expandedPath, path.basename(widget.tempPath!));

      await sourceFile.copy(destPath);
      await sourceFile.delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Song saved to library!'),
          backgroundColor: dominantColor,
        ),
      );

      widget.onReloadLibrary.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving song: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _progressTimer.cancel();
    _seekTimer?.cancel();
    _playPauseController.dispose();
    _focusNode.dispose();
    _playbackSubscription?.cancel();
    _trackChangeSubscription?.cancel();
    _breathingController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waveformIndex =
        (_currentSliderValue * _waveformData.length)
            .clamp(0, _waveformData.length - 1)
            .toInt();
    final currentPeak =
        _waveformData.isNotEmpty ? _waveformData[waveformIndex] : 0.0;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final titleColor =
        dominantColor.computeLuminance() > 0.007 ? dominantColor : Colors.white;
    _updateParticleOptions();

    return RawKeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKey: (RawKeyEvent event) {
        if (event is RawKeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
	    if (_isTempFile){
	      _handleSearchAnother();
	    } else if (!_isTempFile) {
	      Navigator.pop(context, {
	        'song': currentSong,
		'index': currentIndex,
		'dominantColor': dominantColor,
	      });
	     }
          } else if (event.logicalKey == LogicalKeyboardKey.space &&
              (FocusScope.of(context).focusedChild is! EditableText)) {
            _togglePlayPause();
          }
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 500),
              opacity: isPlaying ? 1.0 : 0.0,
              child: AnimatedBackground(
                behaviour: RandomParticleBehaviour(
                  options: _particleOptions,
                  paint: _particlePaint,
                ),
                vsync: this,
                child: Container(),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.8,
                    colors: [
                      dominantColor.withValues(alpha: 0.25),
                      Colors.black,
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          DynamicIconButton(
                            icon: Icons.arrow_downward_rounded,
			    backgroundColor: dominantColor,
			    size: 40,
                            onPressed:
                                () {
				if (_isTempFile){
				_handleSearchAnother();
				} else {
				Navigator.pop(context, {
				  'song': currentSong,
				  'index': currentIndex,
				  'dominantColor': dominantColor,
				});
			      }
			    },
                          ),
                          DynamicIconButton(
                            icon: Icons.more_horiz_rounded,
                            onPressed:
                                () =>
                                    _isTempFile
                                        ? _showPlayerMenu(context)
                                        : _showPlaylistPopup(context),
                            backgroundColor: dominantColor,
                            size: 40,
                          ),
                        ],
                      ),
                    ),
                  ),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    // Song title and artist.
                    child: Transform.translate(
                      offset: const Offset(0, -20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                        child: Column(
                          children: [
                            GlowText(
                              currentSong.title,
                              style: TextStyle(
                                color: titleColor,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              currentSong.artist,
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.8),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Hero(
                          tag: 'albumArt-${currentSong.path}',
                          flightShuttleBuilder: (
                            flightContext,
                            animation,
                            direction,
                            fromHeroContext,
                            toHeroContext,
                          ) {
                            return AnimatedBuilder(
                              animation: animation,
                              builder: (context, child) {
                                final scale = Tween<double>(
                                  begin: 0.5,
                                  end: 1.0,
                                ).evaluate(animation);
                                return Transform.scale(
                                  scale: scale,
                                  child: child,
                                );
                              },
                              child: toHeroContext.widget,
                            );
                          },
                          child: NamidaThumbnail(
                            image:
                                currentSong.albumArt != null
                                    ? MemoryImage(
                                      base64Decode(currentSong.albumArt!),
                                    )
                                    : const AssetImage(
                                          'assets/default_album.png',
                                        )
                                        as ImageProvider,
                            isPlaying: isPlaying,
                            currentPeak: currentPeak,
                            showBreathingEffect: true,
                            sharedBreathingValue: _breathingAnimation.value,
                          ),
                        ),
                        if (_showLyrics && _lrcData != null && _rupdateLyricsStatus())
                          Positioned.fill(
                            child: LyricsOverlay(
                              key: ValueKey(currentSong.path),
                              lrc: _lrcData!,
                              currentPosition: Duration(
                                seconds:
                                    (_currentSliderValue *
                                            currentSong.duration.inSeconds)
                                        .toInt(),
                              ),
                              dominantColor: dominantColor,
                              currentPeak: currentPeak,
                              sharedBreathingValue: _breathingAnimation.value,
                              onLyricTap: (timestamp) {
                                final position = timestamp.inSeconds.toDouble();
                                final progress =
                                    position / currentSong.duration.inSeconds;
                                _handleSeek(progress.clamp(0.0, 1.0));
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Waveform Seek Bar.
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24.0,
                        vertical: 16,
                      ),
                      child: WaveformSeekBar(
                        waveformData: _waveformData,
                        progress: _currentSliderValue,
                        activeColor: dominantColor,
                        inactiveColor: Colors.grey.withValues(alpha: 0.3),
                        onSeek: (value) => _handleSeek(value),
                      ),
                    ),
                  ),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32.0,
                        vertical: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Lyrics Button.
                          DynamicIconButton(
                            icon:
                                _hasLyrics
                                    ? (_showLyrics
                                        ? Icons.lyrics
                                        : Icons.lyrics_outlined)
                                    : Icons.error_outline,
                            onPressed:
                                _hasLyrics
                                    ? () => setState(
                                      () => _showLyrics = !_showLyrics,
                                    )
                                    : null,
                            backgroundColor: dominantColor,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Hero(
                                tag: 'controls-prev-${currentSong.path}',
                                child: DynamicIconButton(
                                  icon: Icons.skip_previous_rounded,
                                  onPressed:
                                      currentIndex > 0
                                          ? _handleSkipPrevious
                                          : null,
                                  backgroundColor: dominantColor,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Hero(
                                tag: 'controls-playPause-${currentSong.path}',
                                child: ParticlePlayButton(
                                  isPlaying: isPlaying,
                                  color: dominantColor,
                                  onPressed: _togglePlayPause,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Hero(
                                tag: 'controls-next-${currentSong.path}',
                                child: DynamicIconButton(
                                  icon: Icons.skip_next_rounded,
                                  onPressed:
                                      currentIndex < widget.songList.length - 1
                                          ? _handleSkipNext
                                          : null,
                                  backgroundColor: dominantColor,
                                ),
                              ),
                            ],
                          ),
                          DynamicIconButton(
                            icon:
                                _repeatMode == RepeatMode.repeatOnce
                                    ? Icons.repeat_one_rounded
                                    : _repeatMode == RepeatMode.repeatAll
                                    ? Icons.repeat_rounded
                                    : Icons.sync_alt_rounded,
                            onPressed: _toggleRepeatMode,
                            backgroundColor: dominantColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<double> _generateDummyWaveformData() {
    return List.filled(1000, 0.0);
  }
}

class AdimanService extends MPRISService {
  List<Song> _currentPlaylist = [];
  int _currentIndex = 0;
  Song? _currentSong;
  final Function(Song, int)? _onSongChange;
  final _playbackStateController = StreamController<bool>.broadcast();
  Stream<bool> get playbackStateStream => _playbackStateController.stream;
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
        _currentSong == playlist[currentIndex]){
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
      _updateMetadata();
    }

    final isPlaying = await rust_api.isPlaying();
    playbackStatus = isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;
    _playbackStateController.add(isPlaying);
  }

  void updatePlaylistStart(List<Song> playlist, int currentIndex) {
    if (_currentPlaylist == playlist && _currentIndex == currentIndex) return;
    _currentPlaylist = playlist;
    _currentIndex = currentIndex;
    _currentSong = _currentPlaylist[currentIndex];
    if (!_trackChangeController.isClosed) {
      _trackChangeController.add(_currentSong!);
    }
    _updateMetadata();
    onPlay();
  }

  @override
  Future<void> dispose() async {
    await _playbackStateController.close();
    await _trackChangeController.close();
    await client?.close();
  await client?.callMethod(
    destination: 'org.freedesktop.DBus',
    path: DBusObjectPath('/org/freedesktop/DBus'),
    interface: 'org.freedesktop.DBus',
    name: 'ReleaseName',
    values: [DBusString('org.mpris.MediaPlayer2.adiman')],
  );
    await super.dispose();
  }

  String _generateTrackId(String path) {
    final hash = md5.convert(utf8.encode(path)).toString();
    return "/com/adiman/Track/$hash";
  }

  void _updateMetadata() async {
    if (_currentSong != null) {
      final artistString =
          _currentSong!.artists?.join("/") ?? _currentSong!.artist;

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

Future<String?> _cacheAlbumArt(String? base64Data) async {
    if (base64Data == null) return null;
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

      final hash = md5.convert(utf8.encode(base64Data)).toString();
      final file = File('${cacheDir.path}/$hash.png');
      if (!await file.exists()) {
        await file.writeAsBytes(base64Decode(base64Data));
      }
      return file.path;
    } catch (e) {
      print('Error caching album art: $e');
      return null;
    }
  }

  @override
  Future<void> onPlay() async {
    await rust_api.resumeSong();
    playbackStatus = PlaybackStatus.playing;
    _playbackStateController.add(true);
  }

  @override
  Future<void> onPause() async {
    await rust_api.pauseSong();
    playbackStatus = PlaybackStatus.paused;
    _playbackStateController.add(false);
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
      _currentIndex = newIndex;
      _currentSong = nextSong;
      _trackChangeController.add(nextSong);
      _updateMetadata();

      _onSongChange?.call(nextSong, newIndex);

      final isNowPlaying = await rust_api.isPlaying();
      playbackStatus =
          isNowPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;
      _playbackStateController.add(isNowPlaying);
      _updateMetadata();
    }
  }

  @override
  Future<void> onPrevious() async {
    if (_currentIndex > 0) {
      final newIndex = _currentIndex - 1;
      final prevSong = _currentPlaylist[newIndex];
      await rust_api.playSong(path: prevSong.path);
      _currentIndex = newIndex;
      _currentSong = prevSong;
      _trackChangeController.add(prevSong);
      _updateMetadata();
      _onSongChange?.call(prevSong, newIndex);

      final isNowPlaying = await rust_api.isPlaying();
      playbackStatus =
          isNowPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;
      _playbackStateController.add(isNowPlaying);
      _updateMetadata();
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
    print("LOOP");
  }

  @override
  Future<void> onShuffle(bool shuffle) async {
    // Implement shuffle if needed
    print("SHUFFLE");
  }*/
}

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
  Color _dominantColor = Colors.purple;
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
      final downloadedPath = await rust_api.downloadToTemp(query: query);
      final prefs = await SharedPreferences.getInstance();

      final metadata = await rust_api.scanMusicDirectory(
        dirPath: path.dirname(downloadedPath),
    	autoConvert: prefs.getBool('autoConvert') ?? true,
      );

      if (metadata.isNotEmpty) {
        _tempSong = Song.fromMetadata(metadata.first);

        if (_tempSong!.albumArt != null) {
          try {
            final imageBytes = base64Decode(_tempSong!.albumArt!);
            final codec = await ui.instantiateImageCodec(imageBytes);
            final frame = await codec.getNextFrame();
            final palette = await PaletteGenerator.fromImage(frame.image);
            setState(() {
              _dominantColor = palette.dominantColor?.color ?? Colors.purple;
            });
          } catch (e) {
            print('Error generating dominant color: $e');
            setState(() => _dominantColor = Colors.purple);
          }
        }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

@override
Widget build(BuildContext context) {
  return RawKeyboardListener(
    focusNode: _focusNode,
    autofocus: true,
    onKey: (RawKeyEvent event) {
      if (event is RawKeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape && !_isDownloading) {
	  rust_api.stopSong();
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
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => Navigator.pop(context),
                        backgroundColor: _dominantColor,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NamidaTextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          hintText: 'Search song or paste URL...',
                          prefixIcon: Icons.search_rounded,
                          onSubmitted: (_) => _startDownload(),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _currentTrack == null ? _buildEmptyState() : null,
                  ),
                ),
              ],
            ),
          ),
          if (_isDownloading)
            Positioned.fill(
	    child: RawKeyboardListener(
	    focusNode: FocusNode(),
	    autofocus: true,
	    onKey: (RawKeyEvent event) {
	      if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
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
                              valueColor: AlwaysStoppedAnimation(_dominantColor),
                            ),
                            const SizedBox(height: 16),
                            GlowText(
                              'Downloading...',
                              glowColor: _dominantColor,
                              style: TextStyle(color: Colors.white, fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 10,
			left: 10,
                        child: DynamicIconButton(
                          icon: Icons.close_rounded,
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
                    _dominantColor = Colors.purple;
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
  );
}

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 1.5,
            child: Icon(
              Icons.download_rounded,
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
