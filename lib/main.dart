import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path/path.dart' as path;
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/src/rust/api/color_extractor.dart' as color_extractor;
import 'package:adiman/src/rust/frb_generated.dart';
import 'package:flutter/material.dart';
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
import 'broken_icons.dart';

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
      duration: Duration(seconds: (metadata.duration as BigInt).toInt()),
      genre: metadata.genre as String,
    );
  }
}

ThemeData _buildDynamicTheme(Color dominantColor) {
  final bool isDark = dominantColor.computeLuminance() < 0.4;
  final textColor = isDark ? Colors.white : dominantColor;
  return ThemeData.dark().copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: dominantColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: textColor),
      bodyMedium: TextStyle(color: textColor),
      titleLarge: TextStyle(color: textColor),
      titleMedium: TextStyle(color: textColor),
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    useMaterial3: true,
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
    if (song.albumArt == null) return const Color(0xFF383770);

    try {
      final colorValue =
          await color_extractor.getDominantColor(data: song.albumArt!);
      return Color(colorValue ?? 0xFF383770);
    } catch (e) {
      return const Color(0xFF383770);
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
    final textColor = widget.dominantColor.computeLuminance() > 0.01
        ? widget.dominantColor
        : Theme.of(context).textTheme.bodyLarge?.color;
    return GestureDetector(
      onTap: () async {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        final result = await Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, _, __) => MusicPlayerScreen(
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
        _checkPlayingState();
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCirc,
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return ScaleTransition(
                      scale: Tween<double>(begin: 0.8, end: 1.0)
                          .animate(animation),
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    );
                  },
                  child: Hero(
                    key: ValueKey(widget.song.path),
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
                        child: widget.song.albumArt != null
                            ? Image.memory(
                                widget.song.albumArt!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            : GlowIcon(
                                Broken.musicnote,
                                color: Colors.white,
                                glowColor: Colors.white,
                              ),
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
                          color: textColor!.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Hero(
                  tag: 'controls-prev',
                  child: Material(
                    color: widget.dominantColor.withValues(alpha: 0.2),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: GlowIcon(
                        Broken.previous,
                        color: textColor,
                        glowColor: widget.dominantColor.withValues(alpha: 0.3),
                      ),
                      onPressed: widget.currentIndex > 0
                          ? () => _handleSkip(false)
                          : null,
                    ),
                  ),
                ),
                Hero(
                  tag: 'controls-playPause',
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
                        icon: GlowIcon(
                          _playPauseController.isForwardOrCompleted
                              ? Broken.pause
                              : Broken.play,
                          color: textColor,
                          glowColor:
                              widget.dominantColor.withValues(alpha: 0.2),
                        ),
                        onPressed: _togglePlayPause,
                      ),
                    ),
                  ),
                ),
                Hero(
                  tag: 'controls-next',
                  child: Material(
                    color: widget.dominantColor.withValues(alpha: 0.2),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: GlowIcon(
                        Broken.next,
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
      theme: _buildDynamicTheme(Color(0xFF383770)),
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
  Color dominantColor = Color(0xFF383770);
  final ScrollController _scrollController = ScrollController();
  double _lastOffset = 0;
  late AnimationController _extraHeaderController;
  late Animation<Offset> _extraHeaderOffsetAnimation;
  bool _isDrawerOpen = false;
  String currentMusicDirectory = '';
  String? _currentPlaylistName;
  late final AdimanService service;
  final Set<Song> _selectedSongs = {};
  List<Song> metadataSongs = [];
  List<Song> lyricsSongs = [];
  Map<String, bool> _visibleSongs = {};
  Map<String, bool> _deletingSongs = {};
  DateTime? _lastGKeyPressTime;
  late bool _vimKeybindings;

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

  late FocusNode _mainFocusNode;
  late FocusNode _searchFocusNode;

  List<String> customSeparators = [];

  @override
  void initState() {
    super.initState();
    service = globalService;
    _mainFocusNode = FocusNode();
    _searchFocusNode = FocusNode();
    _mainFocusNode.requestFocus();
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

    _getVimBindings();

    _searchController.addListener(_updateSearchResults);
  }

  Future<void> _getVimBindings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _vimKeybindings = prefs.getBool('vimKeybindings') ?? false;
      });
    }
  }

  void _toggleSongSelection(Song song, bool selected) {
    setState(() {
      if (selected) {
        _selectedSongs.add(song);
        _mainFocusNode.requestFocus();
      } else {
        _selectedSongs.remove(song);
      }
      _mainFocusNode.requestFocus();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedSongs.clear();
    });
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
    final iconColor = isDestructive
        ? Colors.redAccent
        : dominantColor.computeLuminance() > 0.01
            ? dominantColor
            : Theme.of(context).textTheme.bodyLarge?.color;
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
              GlowIcon(icon, color: iconColor, blurRadius: 8, size: 24),
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
                            glowColor: (dominantColor.computeLuminance() > 0.01)
                                ? dominantColor
                                : Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color!
                                    .withValues(alpha: 0.3),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: dominantColor.computeLuminance() > 0.01
                                  ? dominantColor
                                  : Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color,
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
                                      ScaffoldMessenger.of(context)
                                          .hideCurrentSnackBar();
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
                                            Broken.music_playlist,
                                            color: dominantColor
                                                        .computeLuminance() >
                                                    0.01
                                                ? dominantColor
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
                                            blurRadius: 8,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Text(
                                              playlist,
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: GlowIcon(
                                              Broken.edit,
                                              color: dominantColor
                                                          .computeLuminance() >
                                                      0.01
                                                  ? dominantColor
                                                  : Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.color,
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
                                                  ).showSnackBar(NamidaSnackbar(
                                                      backgroundColor:
                                                          dominantColor,
                                                      content:
                                                          'Playlist renamed to "$newName"'));
                                                } catch (e) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(NamidaSnackbar(
                                                      backgroundColor:
                                                          dominantColor,
                                                      content:
                                                          'Error renaming playlist: $e'));
                                                }
                                              }
                                            },
                                          ),
                                          IconButton(
                                            icon: GlowIcon(
                                              Broken.cross,
                                              color: Colors.redAccent,
                                              blurRadius: 8,
                                              size: 20,
                                            ),
                                            onPressed: () async {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (context) =>
                                                    AlertDialog(
                                                  backgroundColor:
                                                      dominantColor.withValues(
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
                                                                Colors.white70,
                                                          ),
                                                        ),
                                                        onPressed: () {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .hideCurrentSnackBar();
                                                          Navigator.pop(
                                                            context,
                                                            false,
                                                          );
                                                        }),
                                                    TextButton(
                                                        child: Text(
                                                          'Delete',
                                                          style: TextStyle(
                                                            color: Colors
                                                                .redAccent,
                                                          ),
                                                        ),
                                                        onPressed: () {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .hideCurrentSnackBar();
                                                          Navigator.pop(
                                                            context,
                                                            true,
                                                          );
                                                        }),
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
                                                  ).showSnackBar(NamidaSnackbar(
                                                      backgroundColor:
                                                          dominantColor,
                                                      content:
                                                          'Playlist deleted'));
                                                  // Remove the deleted playlist from the list.
                                                  setStateDialog(() {
                                                    localPlaylists.remove(
                                                      playlist,
                                                    );
                                                  });
                                                } catch (e) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(NamidaSnackbar(
                                                      backgroundColor:
                                                          dominantColor,
                                                      content:
                                                          'Error deleting playlist: $e'));
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
                            icon: Broken.hierarchy_3,
                            label: 'Merge Playlists',
                            onTap: () async {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
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
                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
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
                                      Broken.music_library_2,
                                      color: dominantColor.computeLuminance() >
                                              0.01
                                          ? dominantColor
                                          : Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.color,
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      'Switch to Main Library',
                                      style: TextStyle(
                                        color: Theme.of(
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

  void _handleMultiSelectAction() async {
    if (_selectedSongs.isEmpty) return;

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
                        'Selected Songs (${_selectedSongs.length})',
                        glowColor: dominantColor.withValues(alpha: 0.3),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: dominantColor.computeLuminance() > 0.01
                              ? dominantColor
                              : Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildPlaylistOptionButton(
                        icon: Broken.folder_add,
                        label: 'Create New Playlist',
                        onTap: () async {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pop(context);
                          final playlistName = await _showPlaylistNameDialog();
                          if (playlistName != null && playlistName.isNotEmpty) {
                            await createPlaylist(_musicFolder, playlistName);
                            for (final song in _selectedSongs) {
                              await addSongToPlaylist(
                                  song.path, _musicFolder, playlistName);
                            }
                            _exitSelectionMode();
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Broken.music_playlist,
                        label: 'Add to Existing Playlist',
                        onTap: () async {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pop(context);
                          final playlists = await listPlaylists(_musicFolder);
                          final selectedPlaylist =
                              await _showSelectPlaylistDialog(playlists);
                          if (selectedPlaylist != null &&
                              selectedPlaylist.isNotEmpty) {
                            for (final song in _selectedSongs) {
                              await addSongToPlaylist(
                                  song.path, _musicFolder, selectedPlaylist);
                            }
                            _exitSelectionMode();
                          }
                        },
                      ),
                      if (_currentPlaylistName != null) ...[
                        const SizedBox(height: 12),
                        _buildPlaylistOptionButton(
                          icon: Broken.cross,
                          label: 'Remove from Playlist',
                          onTap: () async {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            Navigator.pop(context);
                            for (final song in _selectedSongs) {
                              await _removeSongFromCurrentPlaylist(song);
                            }
                            _exitSelectionMode();
                          },
                          isDestructive: true,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Broken.trash,
                        label: 'Delete Selected Songs',
                        onTap: () async {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pop(context);
                          final confirmed = await _showDeleteConfirmationDialog(
                            _selectedSongs
                                .first, // Show first song name as reference
                            multipleItems: true,
                          );
                          if (confirmed) {
                            for (final song in _selectedSongs) {
                              await _deleteSongFile(song);
                            }
                            _exitSelectionMode();
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

  Future<String?> _showRenamePlaylistDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
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
                        cursorColor: dominantColor.computeLuminance() > 0.01
                            ? dominantColor
                            : Theme.of(context).textTheme.bodyLarge?.color,
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
                          onPressed: () {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            Navigator.pop(context);
                          },
                        ),
                        const SizedBox(width: 12),
                        DynamicIconButton(
                          icon: Broken.tick,
                          onPressed: () {
                            final newName = controller.text.trim();
                            if (newName.isNotEmpty && newName != currentName) {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
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
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Error counting audio files: $e');
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

      // Initialize all songs as invisible
      _visibleSongs = {};

      do {
        final metadata = await rust_api.scanMusicDirectory(
          dirPath: currentMusicDirectory,
          autoConvert: prefs.getBool('autoConvert') ?? false,
        );
        loadedSongs = metadata.map((m) => Song.fromMetadata(m)).toList();
        currentCount = loadedSongs.length;

        // Sort the songs
        loadedSongs.sort((a, b) => a.title.compareTo(b.title));

        setState(() {
          songs = loadedSongs;
          if (_searchController.text.isEmpty) {
            displayedSongs = loadedSongs;
          }
          // Initialize all new songs as invisible
          for (var song in loadedSongs) {
            _visibleSongs[song.path] = false;
          }
        });

        if (currentCount >= expectedCount) {
          break;
        } else if (prefs.getBool('autoConvert') ?? false) {
          await Future.delayed(const Duration(seconds: 1));
        }
      } while (currentCount >= expectedCount);

      // Animate songs in with a stagger effect
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            for (var song in loadedSongs) {
              _visibleSongs[song.path] = true;
            }
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
            backgroundColor: dominantColor,
            content: 'Error loading songs: $e'));
      }
    }
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  void _updateSearchResults() async {
    final query = _searchController.text.toLowerCase();

    setState(() {
      for (var song in displayedSongs) {
        _visibleSongs[song.path] = false;
      }
    });

    if (query.isEmpty) {
      await Future.delayed(Duration(milliseconds: 200));
      if (!mounted) return;

      setState(() {
        metadataSongs = [];
        lyricsSongs = [];
        displayedSongs = songs;
        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              for (var song in songs) {
                _visibleSongs[song.path] = true;
              }
            });
          }
        });
      });
      return;
    }

    try {
      final tDir = await getTemporaryDirectory();
      final lyricResults = await rust_api.searchLyrics(
        lyricsDir: "${tDir.path}/lyrics",
        query: query,
        songDir: currentMusicDirectory,
      );

      final lyricPaths = lyricResults.map((r) => r.path).toSet();

      await Future.delayed(Duration(milliseconds: 200));
      if (!mounted) return;

      setState(() {
        metadataSongs = songs.where((song) {
          return song.title.toLowerCase().contains(query) ||
              song.artist.toLowerCase().contains(query) ||
              song.album.toLowerCase().contains(query) ||
              song.genre.toLowerCase().contains(query);
        }).toList();

        lyricsSongs = songs.where((song) {
          return lyricPaths.contains(song.path);
        }).toList();

        displayedSongs = {...metadataSongs, ...lyricsSongs}.toList();

        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              for (var i = 0; i < displayedSongs.length; i++) {
                final song = displayedSongs[i];
                Future.delayed(Duration(milliseconds: i * 30), () {
                  if (mounted) {
                    setState(() {
                      _visibleSongs[song.path] = true;
                    });
                  }
                });
              }
            });
          }
        });
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(NamidaSnackbar(content: 'Error searching lyrics: $e'));

      await Future.delayed(Duration(milliseconds: 200));
      if (!mounted) return;

      setState(() {
        displayedSongs = songs
            .where((song) =>
                song.title.toLowerCase().contains(query) ||
                song.artist.toLowerCase().contains(query) ||
                song.album.toLowerCase().contains(query) ||
                song.genre.toLowerCase().contains(query))
            .toList();

        Future.delayed(Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              for (var i = 0; i < displayedSongs.length; i++) {
                final song = displayedSongs[i];
                Future.delayed(Duration(milliseconds: i * 30), () {
                  if (mounted) {
                    setState(() {
                      _visibleSongs[song.path] = true;
                    });
                  }
                });
              }
            });
          }
        });
      });
    }
  }

  Future<Color> _getDominantColor(Song song) async {
    if (song.albumArt == null) return const Color(0xFF383770);

    try {
      final colorValue =
          await color_extractor.getDominantColor(data: song.albumArt!);
      return Color(colorValue ?? 0xFF383770);
    } catch (e) {
      NamidaSnackbar(content: 'Failed to get dominant color $e');
      return Color(0xFF383770);
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
        _mainFocusNode.requestFocus();
      } else {
        _searchFocusNode.requestFocus();
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
        NamidaSnackbar(
            backgroundColor: dominantColor,
            content: 'Added $songPath to playlist $playlistName');
      } else {
        NamidaSnackbar(
            backgroundColor: dominantColor,
            content: 'Song already in playlist.');
      }
    } else {
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Song file does not exist: $songPath');
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
            NamidaSnackbar(
                backgroundColor: dominantColor,
                content: 'Error merging playlist "$playlist": $e');
          }
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content:
              'Merged ${playlistsToMerge.length} playlists into "$mergedName"'),
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
                            glowColor: (dominantColor.computeLuminance() > 0.01)
                                ? dominantColor
                                : Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color!
                                    .withValues(alpha: 0.3),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: dominantColor.computeLuminance() > 0.01
                                  ? dominantColor
                                  : Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.color,
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
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          dominantColor.withValues(
                                            alpha: isSelected ? 0.25 : 0.05,
                                          ),
                                          Colors.black.withValues(
                                            alpha: isSelected ? 0.3 : 0.2,
                                          ),
                                        ],
                                      ),
                                      border: Border.all(
                                        color: isSelected
                                            ? dominantColor.withValues(
                                                alpha: 0.8)
                                            : dominantColor.withValues(
                                                alpha: 0.2),
                                        width: isSelected ? 1.2 : 0.5,
                                      ),
                                    ),
                                    child: ListTile(
                                      leading: GestureDetector(
                                        onTap: () {
                                          setStateDialog(() {
                                            if (isSelected) {
                                              selected.remove(playlist);
                                            } else {
                                              selected.add(playlist);
                                            }
                                          });
                                        },
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: isSelected
                                                  ? dominantColor.withValues(
                                                      alpha: 0.8)
                                                  : Colors.white
                                                      .withValues(alpha: 0.2),
                                              width: 1.0,
                                            ),
                                            color: isSelected
                                                ? dominantColor.withValues(
                                                    alpha: 0.15)
                                                : Colors.black
                                                    .withValues(alpha: 0.3),
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                      color: dominantColor
                                                          .withValues(
                                                              alpha: 0.4),
                                                      blurRadius: 8,
                                                      spreadRadius: 1.5,
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                          child: isSelected
                                              ? Center(
                                                  child: GlowIcon(
                                                    Broken.tick,
                                                    color: dominantColor
                                                                .computeLuminance() >
                                                            0.01
                                                        ? dominantColor
                                                        : Theme.of(context)
                                                            .textTheme
                                                            .bodyLarge
                                                            ?.color,
                                                    size: 18,
                                                    glowColor: dominantColor
                                                                .computeLuminance() >
                                                            0.01
                                                        ? dominantColor
                                                        : Theme.of(context)
                                                            .textTheme
                                                            .bodyLarge
                                                            ?.color!
                                                            .withValues(
                                                                alpha: 0.5),
                                                    blurRadius: 8,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                      title: Text(
                                        playlist,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.color,
                                          fontSize: 16,
                                        ),
                                      ),
                                      onTap: () {
                                        setStateDialog(() {
                                          if (isSelected) {
                                            selected.remove(playlist);
                                          } else {
                                            selected.add(playlist);
                                          }
                                        });
                                      },
                                    ),
                                  ),
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
                                onPressed: () {
                                  ScaffoldMessenger.of(context)
                                      .hideCurrentSnackBar();
                                  Navigator.pop(context);
                                },
                              ),
                              const SizedBox(width: 12),
                              DynamicIconButton(
                                icon: Broken.tick,
                                onPressed: () {
                                  ScaffoldMessenger.of(context)
                                      .hideCurrentSnackBar();
                                  Navigator.pop(context, selected);
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
                          cursorColor: dominantColor.computeLuminance() > 0.01
                              ? dominantColor
                              : Theme.of(context).textTheme.bodyLarge?.color,
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
                              Broken.music_playlist,
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
                            onPressed: () {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
                              Navigator.pop(context);
                            },
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DynamicIconButton(
                            icon: Broken.tick,
                            onPressed: () {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
                              Navigator.pop(
                                context,
                                controller.text.trim(),
                              );
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
                              onTap: () {
                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
                                Navigator.pop(context, playlist);
                              },
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
                                      Broken.music_playlist,
                                      color: dominantColor.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        playlist,
                                        style: TextStyle(
                                          color: Theme.of(
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
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Removed $filename from playlist $_currentPlaylistName');
      _loadSongs();
    } else {
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Song link does not exist: $filename');
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
                          color: dominantColor.computeLuminance() > 0.01
                              ? dominantColor
                              : Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildPlaylistOptionButton(
                        icon: Broken.next,
                        label: 'Play Next',
                        onTap: () {
                          final selectedSong = song;
                          // Find the current song's index in the main songs list
                          int mainCurrentIndex = songs
                              .indexWhere((s) => s.path == currentSong!.path);
                          if (mainCurrentIndex == -1) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(NamidaSnackbar(
                              backgroundColor: dominantColor,
                              content: 'Current song not found in library.',
                            ));
                            return;
                          }
                          if (selectedSong == currentSong) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                NamidaSnackbar(
                                    backgroundColor: dominantColor,
                                    content:
                                        'Cannot make currently playing song next, use repeat function'));
                            return;
                          }
                          // Insert into the main songs list
                          List<Song> newSongs = List.from(songs);
                          newSongs
                              .removeWhere((s) => s.path == selectedSong.path);
                          newSongs.insert(mainCurrentIndex + 1, selectedSong);
                          // Update displayedSongs if not searching
                          if (_searchController.text.isEmpty) {
                            displayedSongs = List.from(newSongs);
                          }
                          // Update the service's playlist
                          service.updatePlaylist(newSongs, mainCurrentIndex);
                          setState(() {
                            songs = newSongs;
                          });
                          ScaffoldMessenger.of(context)
                              .showSnackBar(NamidaSnackbar(
                            backgroundColor: dominantColor,
                            content:
                                'Added "${selectedSong.title}" to play next.',
                          ));
                          Navigator.pop(context);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Broken.folder_add,
                        label: 'Create New Playlist',
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pop(context);
                          _handleCreatePlaylist(song);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Broken.music_playlist,
                        label: 'Add to Existing',
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pop(context);
                          _handleAddToExistingPlaylist(song);
                        },
                      ),
                      if (_currentPlaylistName != null) ...[
                        const SizedBox(height: 12),
                        _buildPlaylistOptionButton(
                          icon: Broken.cross,
                          label: 'Remove from Playlist',
                          onTap: () async {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            Navigator.pop(context);
                            await _removeSongFromCurrentPlaylist(song);
                          },
                          isDestructive: true,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Broken.trash,
                        label: 'Delete Song',
                        onTap: () async {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
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

  Future<bool> _showDeleteConfirmationDialog(Song song,
      {bool multipleItems = false}) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: dominantColor.withAlpha(30),
            title: Text(
              multipleItems ? 'Delete Songs?' : 'Delete Song?',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              multipleItems
                  ? 'This will permanently delete ${_selectedSongs.length} songs from your device.'
                  : 'This will permanently delete "${song.title}" from your device.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white70),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  Navigator.pop(context, false);
                },
              ),
              TextButton(
                child: Text(
                  'Delete',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  Navigator.pop(context, true);
                },
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
        setState(() {
          _deletingSongs[song.path] = true;
        });
        await Future.delayed(const Duration(milliseconds: 300));
        await file.delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
              backgroundColor: dominantColor,
              content: 'Song deleted successfully'));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _deletingSongs.remove(song.path);
        });
        ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
            backgroundColor: dominantColor,
            content: 'Error deleting song: ${e.toString()}'));
      }
    }
  }

  void _onSongDeletionComplete(Song song) {
    setState(() {
      songs.remove(song);
      displayedSongs.remove(song);
      _deletingSongs.remove(song.path);
    });
  }

  @override
  void dispose() {
    _mainFocusNode.dispose();
    _searchFocusNode.dispose();
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
                  Broken.arrow_right_3,
                  color: textColor.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataSectionHeader(BuildContext context) {
    final iconColor =
        dominantColor.computeLuminance() > 0.01 ? dominantColor : Colors.white;
    final glowIntensity = dominantColor.withAlpha(60);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  dominantColor.withAlpha(20),
                  Colors.black.withAlpha(80),
                ],
              ),
              border: Border.all(
                color: dominantColor.withAlpha(100),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: dominantColor.withAlpha(40),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  GlowIcon(
                    Broken.info_circle,
                    color: iconColor,
                    glowColor: glowIntensity,
                    blurRadius: 10,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  GlowText(
                    'Metadata Matches',
                    glowColor: glowIntensity,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: iconColor,
                      letterSpacing: 0.8,
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

  Widget _buildLyricsSectionHeader(BuildContext context) {
    final iconColor =
        dominantColor.computeLuminance() > 0.01 ? dominantColor : Colors.white;
    final glowIntensity = dominantColor.withAlpha(60);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  dominantColor.withAlpha(20),
                  Colors.black.withAlpha(80),
                ],
              ),
              border: Border.all(
                color: dominantColor.withAlpha(100),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: dominantColor.withAlpha(40),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  GlowIcon(
                    Broken.document,
                    color: iconColor,
                    glowColor: glowIntensity,
                    blurRadius: 10,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  GlowText(
                    'Lyrics Matches',
                    glowColor: glowIntensity,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: iconColor,
                      letterSpacing: 0.8,
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

  Widget _buildSongItem(Song song) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTap: () {
        _showPlaylistPopup(song);
      },
      child: AnimatedListItem(
        visible: _visibleSongs[song.path] ?? false,
        child: AnimatedDeletionWrapper(
          key: ValueKey(song.path),
          isDeleting: _deletingSongs[song.path] ?? false,
          onDeletionComplete: () => _onSongDeletionComplete(song),
          duration: const Duration(milliseconds: 300),
          child: EnhancedSongListTile(
            song: song,
            onSelectedChanged: (selected) =>
                _toggleSongSelection(song, selected),
            isInSelectionMode: _selectedSongs.isNotEmpty,
            isSelected: _selectedSongs.contains(song),
            dominantColor: dominantColor,
            onTap: () async {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              final result = await Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, _, __) => MusicPlayerScreen(
                    onReloadLibrary: _loadSongs,
                    musicFolder: _musicFolder,
                    service: service,
                    song: song,
                    songList: displayedSongs,
                    currentPlaylistName: _currentPlaylistName,
                    currentIndex: displayedSongs.indexOf(song),
                  ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.95, end: 1.0).animate(
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
              if (result != null && result is Map<String, dynamic>) {
                setState(() {
                  currentSong = result['song'] ?? currentSong;
                  currentIndex = result['index'] ?? currentIndex;
                  dominantColor = result['dominantColor'] ?? dominantColor;
                  showMiniPlayer = true;
                });
              }
              if (mounted) {
                FocusScope.of(context).requestFocus(_mainFocusNode);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        dominantColor.computeLuminance() > 0.01 ? dominantColor : Colors.white;
    return KeyboardListener(
      focusNode: _mainFocusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (_selectedSongs.isNotEmpty) {
              setState(() {
                _exitSelectionMode();
              });
            } else if (_isSearchExpanded) {
              _toggleSearch();
            } else if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
              _scaffoldKey.currentState?.closeDrawer();
              _isDrawerOpen = false;
              _mainFocusNode.requestFocus();
            } else {
              _scaffoldKey.currentState?.openDrawer();
              _isDrawerOpen = true;
              _mainFocusNode.requestFocus();
            }
          } else if (event.logicalKey == LogicalKeyboardKey.space &&
              !_isSearchExpanded &&
              !isTextInputFocused()) {
            _togglePauseSong();
          }
          if (_vimKeybindings) {
            if (event.logicalKey == LogicalKeyboardKey.slash &&
                !_isSearchExpanded) {
              _toggleSearch();
            }
            if (event.logicalKey == LogicalKeyboardKey.keyG) {
              final isShiftPressed = HardwareKeyboard
                      .instance.physicalKeysPressed
                      .contains(PhysicalKeyboardKey.shiftLeft) ||
                  HardwareKeyboard.instance.physicalKeysPressed
                      .contains(PhysicalKeyboardKey.shiftRight);

              if (isShiftPressed) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration:
                      const Duration(milliseconds: 100),
                  curve: Curves.easeOut,
                );
              }
              else {
                final now = DateTime.now();
                if (_lastGKeyPressTime != null &&
                    now.difference(_lastGKeyPressTime!) <
                        const Duration(milliseconds: 300)) {
                  _scrollController.animateTo(
                    0,
                    duration:
                        const Duration(milliseconds: 100),
                    curve: Curves.easeOut,
                  );
                  _lastGKeyPressTime = null;
                } else {
                  _lastGKeyPressTime = now;
                }
              }
            }
          }
        }
      },
      child: FocusScope(
        autofocus: true,
        child: Listener(
          onPointerDown: (_) => _isDrawerOpen = true,
          onPointerUp: (_) => _isDrawerOpen = false,
          child: Scaffold(
            floatingActionButton: _selectedSongs.isNotEmpty
                ? AnimatedScale(
                    duration: const Duration(milliseconds: 200),
                    scale: _selectedSongs.isNotEmpty ? 1.0 : 0.0,
                    child: FloatingActionButton(
                      onPressed: _handleMultiSelectAction,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      highlightElevation: 0,
                      child: Container(
                        width: 56,
                        height: 56,
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
                          border: Border.all(
                            color: dominantColor.withValues(alpha: 0.3),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: dominantColor.withValues(alpha: 0.3),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                            BoxShadow(
                              color: dominantColor.withValues(alpha: 0.2),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                dominantColor.withValues(alpha: 0.2),
                                Colors.black.withValues(alpha: 0.2),
                              ],
                            ),
                          ),
                          child: GlowIcon(
                            Broken.music_playlist,
                            color: Colors.white,
                            size: 28,
                            glowColor: dominantColor,
                            blurRadius: 15,
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
            key: _scaffoldKey,
            drawer: KeyboardListener(
              focusNode: FocusNode(),
              autofocus: true,
              onKeyEvent: (event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  if (_isDrawerOpen) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
                                        ? Broken.cross
                                        : Broken.menu_1,
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
                                icon: Broken.setting_2,
                                title: 'Settings',
                                onTap: () {
                                  ScaffoldMessenger.of(context)
                                      .hideCurrentSnackBar();
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    NamidaPageTransitions.createRoute(
                                      SettingsScreen(
                                        onReloadLibrary: _loadSongs,
                                        currentPlaylistName:
                                            _currentPlaylistName,
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
                                  ).then((_) => _getVimBindings());
                                },
                              ),
                              _buildMenuTile(
                                icon: Broken.music_playlist,
                                title: 'Playlists',
                                onTap: () async {
                                  ScaffoldMessenger.of(context)
                                      .hideCurrentSnackBar();
                                  Navigator.pop(context);
                                  await _showPlaylistSelectionPopup();
                                },
                              ),
                              _buildMenuTile(
                                icon: Broken.document_download,
                                title: 'Download Songs (spotdl required)',
                                onTap: () {
                                  _pauseSong();
                                  ScaffoldMessenger.of(context)
                                      .hideCurrentSnackBar();
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
                        double topPadding = fixedHeaderHeight +
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
                                    Color(0xFF383770),
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
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (_searchController.text.isNotEmpty) {
                                    int currentPos = 0;

                                    // Metadata Section
                                    if (metadataSongs.isNotEmpty) {
                                      if (index == currentPos) {
                                        return _buildMetadataSectionHeader(
                                            context);
                                      }
                                      currentPos++;
                                      if (index <
                                          currentPos + metadataSongs.length) {
                                        final song =
                                            metadataSongs[index - currentPos];
                                        return _buildSongItem(song);
                                      }
                                      currentPos += metadataSongs.length;
                                    }

                                    // Lyrics Section
                                    if (lyricsSongs.isNotEmpty) {
                                      if (index == currentPos) {
                                        return _buildLyricsSectionHeader(
                                            context);
                                      }
                                      currentPos++;
                                      if (index <
                                          currentPos + lyricsSongs.length) {
                                        final song =
                                            lyricsSongs[index - currentPos];
                                        return _buildSongItem(song);
                                      }
                                      currentPos += lyricsSongs.length;
                                    }

                                    return null; // Out of bounds
                                  } else {
                                    // Non-search mode: Display all songs without headers
                                    if (index < displayedSongs.length) {
                                      final song = displayedSongs[index];
                                      return _buildSongItem(song);
                                    }
                                    return null;
                                  }
                                },
                                childCount: _searchController.text.isNotEmpty
                                    ? (metadataSongs.isNotEmpty
                                            ? 1 + metadataSongs.length
                                            : 0) +
                                        (lyricsSongs.isNotEmpty
                                            ? 1 + lyricsSongs.length
                                            : 0)
                                    : displayedSongs.length,
                              ),
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
                                    icon:
                                        Icon(Broken.shuffle, color: textColor),
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
                                icon: Icon(Broken.sort, color: textColor),
                                color: Colors.black.withValues(alpha: 0.9),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: dominantColor.withValues(alpha: 0.2),
                                  ),
                                ),
                                onSelected: (option) => _sortSongs(option),
                                itemBuilder: (context) =>
                                    <PopupMenuEntry<SortOption>>[
                                  PopupMenuItem(
                                    value: SortOption.title,
                                    child: Row(
                                      children: [
                                        if (_selectedSortOption ==
                                            SortOption.title)
                                          Icon(
                                            Broken.tick,
                                            color: dominantColor
                                                        .computeLuminance() >
                                                    0.01
                                                ? dominantColor
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
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
                                            Broken.tick,
                                            color: dominantColor
                                                        .computeLuminance() >
                                                    0.01
                                                ? dominantColor
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
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
                                            Broken.tick,
                                            color: dominantColor
                                                        .computeLuminance() >
                                                    0.01
                                                ? dominantColor
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
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
                                            Broken.tick,
                                            color: dominantColor
                                                        .computeLuminance() >
                                                    0.01
                                                ? dominantColor
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
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
                                            Broken.tick,
                                            color: dominantColor
                                                        .computeLuminance() >
                                                    0.01
                                                ? dominantColor
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
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
                                            Broken.tick,
                                            color: dominantColor
                                                        .computeLuminance() >
                                                    0.01
                                                ? dominantColor
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
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
                              icon: Icon(Broken.menu_1, color: textColor),
                              onPressed: () {
                                _scaffoldKey.currentState?.openDrawer();
                              },
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _isSearchExpanded
                                  ? Container(
                                      key: const ValueKey('searchField'),
                                      width: MediaQuery.of(context).size.width -
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
                                        focusNode: _searchFocusNode,
                                        style: TextStyle(
                                          color: textColor,
                                          fontSize: 16,
                                        ),
                                        cursorColor:
                                            dominantColor.computeLuminance() >
                                                    0.01
                                                ? dominantColor
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
                                        decoration: InputDecoration(
                                          hintText: 'Search songs...',
                                          hintStyle: TextStyle(
                                            color: textColor.withValues(
                                              alpha: 0.6,
                                            ),
                                            fontWeight: FontWeight.w300,
                                          ),
                                          prefixIcon: Icon(
                                            Broken.search_normal,
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
                                        onChanged: (value) =>
                                            _updateSearchResults(),
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
                                _isSearchExpanded
                                    ? Broken.cross
                                    : Broken.search_normal,
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
                            onClose: () =>
                                setState(() => showMiniPlayer = false),
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
    this.dominantColor = const Color(0xFF383770),
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
  bool _autoConvert = false;
  bool _clearMp3Cache = false;
  bool _vimKeybindings = false;
  late FocusNode _escapeNode;

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
    _escapeNode = FocusNode();
    _escapeNode.requestFocus();
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
      _vimKeybindings = prefs.getBool('vimKeybindings') ?? false;
    });
    final savedSeparators = prefs.getStringList('separators');
    if (savedSeparators != null) {
      rust_api.setSeparators(separators: savedSeparators);
    }
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

  Future<void> _saveVimKeybindings(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vimKeybindings', value);
    setState(() => _vimKeybindings = value);
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
            NamidaSnackbar(
                backgroundColor: widget.dominantColor,
                content: 'Failed to delete ${entity.path}: $e');
          }
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Cache cleared successfully'));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Error clearing cache: $e'));
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
    ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
        backgroundColor: widget.dominantColor,
        content:
            'Music library reloaded successfully (if you are waiting for your songs to be converted, you might have to do this again due to the waiting list of songs needing conversion)'));
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        hoverColor: widget.dominantColor.withAlpha(30),
        onTap: () => onChanged(!value),
        child: ListTile(
          title: GlowText(
            title,
            glowColor: glowColor,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
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
                      value ? Broken.tick : Broken.cross,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
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
    final textColor = _currentColor.computeLuminance() > 0.01
        ? _currentColor
        : Theme.of(context).textTheme.bodyLarge?.color;
    final buttonTextColor = Theme.of(context).textTheme.bodyLarge?.color;

    return KeyboardListener(
      focusNode: _escapeNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (ModalRoute.of(context)?.isCurrent ?? false) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              Navigator.pop(context);
            }
          } else if (event.logicalKey == LogicalKeyboardKey.space &&
              FocusScope.of(context).hasFocus &&
              FocusScope.of(context).focusedChild is EditableText) {
            _togglePauseSong();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Broken.arrow_left)),
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
                        cursorColor: _currentColor.computeLuminance() > 0.01
                            ? _currentColor
                            : Theme.of(context).textTheme.bodyLarge?.color,
                        decoration: InputDecoration(
                          hintText: 'Enter music folder path...',
                          hintStyle: TextStyle(
                            color: textColor!.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w300,
                          ),
                          prefixIcon: Icon(
                            Broken.folder,
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

                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pop(context, expandedPath);
                        },
                        icon: Icon(Broken.save_2, color: buttonTextColor),
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
                      icon: Broken.refresh,
                      label: 'Reload Music Library',
                      isLoading: _isReloadingLibrary,
                      onPressed: _reloadLibrary,
                    ),
                    const SizedBox(height: 16),
                    _buildActionButton(
                      icon: Broken.text,
                      label: 'Manage Artist Seperators',
                      isLoading: _isManagingSeparators,
                      onPressed: _showSeparatorManagementPopup,
                    ),
                    const SizedBox(height: 16),
                    _buildActionButton(
                      icon: Broken.trash,
                      label: 'Clear Cache',
                      isLoading: _isClearingCache,
                      onPressed: _clearCache,
                    ),
                    _buildSettingsSwitch(context,
                        title: 'Vim keybindings',
                        value: _vimKeybindings,
                        onChanged: _saveVimKeybindings),
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
                    onClose: () => widget.onUpdateMiniPlayer?.call(
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
                            'Artist Separators',
                            glowColor: _currentColor.withAlpha(80),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _currentColor,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Used to detect multiple artists in song metadata',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
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
                                cursorColor:
                                    _currentColor.computeLuminance() > 0.01
                                        ? _currentColor
                                        : Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.color,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  hintText: 'Add new separator...',
                                  hintStyle: TextStyle(color: Colors.white70),
                                  prefixIcon: GlowIcon(
                                    Broken.add_circle,
                                    color: _currentColor,
                                    size: 24,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  suffixIcon: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    child: DynamicIconButton(
                                      icon: Broken.tick,
                                      onPressed: () async {
                                        if (_formKey.currentState!.validate()) {
                                          final newSep =
                                              _addController.text.trim();
                                          if (newSep.isEmpty) return;

                                          if (currentSeparators
                                              .contains(newSep)) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(NamidaSnackbar(
                                              backgroundColor: _currentColor,
                                              content:
                                                  'Separator "$newSep" already exists!',
                                            ));
                                            return;
                                          }

                                          try {
                                            rust_api.addSeparator(
                                                separator: newSep);
                                            final updatedSeparators =
                                                await rust_api
                                                    .getCurrentSeparators();
                                            final prefs =
                                                await SharedPreferences
                                                    .getInstance();
                                            await prefs.setStringList(
                                                'separators',
                                                updatedSeparators);

                                            setStateDialog(() {
                                              currentSeparators =
                                                  updatedSeparators;
                                              _addController.clear();
                                            });

                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(NamidaSnackbar(
                                              backgroundColor: _currentColor,
                                              content:
                                                  'Added "$newSep" separator',
                                            ));
                                          } catch (e) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(NamidaSnackbar(
                                              backgroundColor: Colors.redAccent,
                                              content:
                                                  'Failed to add separator: $e',
                                            ));
                                          }
                                        }
                                      },
                                      backgroundColor: _currentColor,
                                      size: 36,
                                    ),
                                  ),
                                ),
                                validator: (value) => value!.isEmpty
                                    ? 'Enter a separator character'
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Flexible(
                            child: currentSeparators.isEmpty
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Broken.grid_9,
                                        color: _currentColor.withAlpha(80),
                                        size: 48,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No custom separators\nAdd some to help identify multiple artists',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: currentSeparators.length,
                                    itemBuilder: (context, index) {
                                      final separator =
                                          currentSeparators[index];
                                      return Container(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          gradient: LinearGradient(
                                            colors: [
                                              _currentColor.withAlpha(30),
                                              Colors.black.withAlpha(50),
                                            ],
                                          ),
                                        ),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16),
                                          leading: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: RadialGradient(
                                                colors: [
                                                  _currentColor.withAlpha(80),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                            child: Text(
                                              separator,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          title: Text(
                                            'Separator ${index + 1}',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          trailing: IconButton(
                                            icon: GlowIcon(
                                              Broken.trash,
                                              color: Colors.redAccent,
                                              size: 20,
                                            ),
                                            onPressed: () async {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  backgroundColor: Colors.black
                                                      .withAlpha(200),
                                                  title: Text(
                                                      'Delete Separator?',
                                                      style: TextStyle(
                                                          color: Colors.white)),
                                                  content: Text(
                                                      'Remove "$separator"?',
                                                      style: TextStyle(
                                                          color:
                                                              Colors.white70)),
                                                  actions: [
                                                    TextButton(
                                                      child: Text('Cancel',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .white70)),
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, false),
                                                    ),
                                                    TextButton(
                                                      child: Text('Delete',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .redAccent)),
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, true),
                                                    ),
                                                  ],
                                                ),
                                              );

                                              if (confirmed ?? false) {
                                                try {
                                                  rust_api.removeSeparator(
                                                      separator: separator);
                                                  final updatedSeparators =
                                                      await rust_api
                                                          .getCurrentSeparators();
                                                  final prefs =
                                                      await SharedPreferences
                                                          .getInstance();
                                                  await prefs.setStringList(
                                                      'separators',
                                                      updatedSeparators);

                                                  setStateDialog(() =>
                                                      currentSeparators =
                                                          updatedSeparators);

                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                          NamidaSnackbar(
                                                    backgroundColor:
                                                        _currentColor,
                                                    content:
                                                        'Removed "$separator" separator',
                                                  ));
                                                } catch (e) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                          NamidaSnackbar(
                                                    backgroundColor:
                                                        Colors.redAccent,
                                                    content:
                                                        'Failed to remove separator: $e',
                                                  ));
                                                }
                                              }
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 16),
                          Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor:
                                        Colors.black.withAlpha(200),
                                    title: Text('Reset Separators?',
                                        style: TextStyle(color: Colors.white)),
                                    content: Text(
                                        'Restore to default separators? This cannot be undone.',
                                        style:
                                            TextStyle(color: Colors.white70)),
                                    actions: [
                                      TextButton(
                                        child: Text('Cancel',
                                            style: TextStyle(
                                                color: Colors.white70)),
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                      ),
                                      TextButton(
                                        child: Text('Reset',
                                            style: TextStyle(
                                                color: _currentColor)),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmed ?? false) {
                                  try {
                                    rust_api.resetSeparators();
                                    final updatedSeparators =
                                        await rust_api.getCurrentSeparators();
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setStringList(
                                        'separators', updatedSeparators);

                                    setStateDialog(() =>
                                        currentSeparators = updatedSeparators);

                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(NamidaSnackbar(
                                      backgroundColor: _currentColor,
                                      content: 'Restored default separators',
                                    ));
                                  } catch (e) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(NamidaSnackbar(
                                      backgroundColor: Colors.redAccent,
                                      content: 'Failed to reset: $e',
                                    ));
                                  }
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 20),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _currentColor.withAlpha(100),
                                    width: 1.2,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      _currentColor.withAlpha(30),
                                      Colors.black.withAlpha(50),
                                    ],
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Broken.refresh, color: _currentColor),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Reset to Defaults',
                                      style: TextStyle(
                                        color: _currentColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    //final textColor =
    //    _currentColor.computeLuminance() > 0.01 ? Colors.white : Colors.black;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;

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
                child: isLoading
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
                Broken.arrow_right,
                color: textColor!.withValues(alpha: 0.5),
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
              tag: 'albumArt-${song.path}',
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF383770).withValues(alpha: 0.2),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: song.albumArt != null
                      ? Image.memory(
                          song.albumArt!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stackTrace) =>
                              const GlowIcon(
                            Broken.musicnote,
                            color: Colors.white,
                          ),
                        )
                      : const GlowIcon(
                          Broken.musicnote,
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
  late final _particlePaint = Paint()
    ..style = PaintingStyle.fill
    ..color = Colors.white;

  RepeatMode _repeatMode = RepeatMode.normal;
  bool _hasRepeated = false;

  List<int>? _shuffleOrder;
  int _shuffleIndex = 0;

  late AnimationController _lyricsAnimationController;
  late Animation<double> _lyricsEntranceScale;
  late Animation<double> _lyricsEntranceOpacity;

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
    dominantColor = Color(0xFF383770);
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

    rust_api.isPlaying().then((value) {
      isPlaying = value;
    });

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
    _initializeLyricsAnimation();
  }

  void _initializeLyricsAnimation() {
    _lyricsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _lyricsEntranceScale = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _lyricsAnimationController,
        curve: Curves.easeOutBack,
      ),
    );

    _lyricsEntranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _lyricsAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  void _toggleLyrics() {
    if (_showLyrics) {
      // Reverse the animation and hide lyrics after it completes
      _lyricsAnimationController.reverse().then((_) {
        if (mounted) {
          setState(() => _showLyrics = false);
        }
      });
    } else {
      setState(() {
        _showLyrics = true;
        _lyricsAnimationController.forward();
      });
    }
  }

  void _showPlaylistPopup(BuildContext context) {
    final currentSong = widget.song;
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
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildPlaylistOptionButton(
                        icon: Broken.folder_add,
                        label: 'Create New Playlist',
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pop(context);
                          _handleCreatePlaylist(currentSong);
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Broken.music_playlist,
                        label: 'Add to Existing',
                        onTap: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pop(context);
                          _handleAddToExistingPlaylist(currentSong);
                        },
                      ),
                      if (widget.currentPlaylistName != null) ...[
                        const SizedBox(height: 12),
                        _buildPlaylistOptionButton(
                          icon: Broken.cross,
                          label: 'Remove from Playlist',
                          onTap: () async {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            Navigator.pop(context);
                            await _removeSongFromCurrentPlaylist(currentSong);
                          },
                          isDestructive: true,
                        ),
                      ],
                      const SizedBox(height: 12),
                      _buildPlaylistOptionButton(
                        icon: Broken.trash,
                        label: 'Delete Song',
                        onTap: () async {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pop(context);
                          final confirmed =
                              await _showDeleteConfirmationDialog(currentSong);
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
    final iconColor = isDestructive
        ? Colors.redAccent
        : Theme.of(context).textTheme.bodyLarge?.color;
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
              GlowIcon(icon, color: iconColor, size: 24),
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
                          cursorColor: dominantColor.computeLuminance() > 0.01
                              ? dominantColor
                              : Theme.of(context).textTheme.bodyLarge?.color,
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
                              Broken.music_playlist,
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
                            onPressed: () {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
                              Navigator.pop(context);
                            },
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DynamicIconButton(
                            icon: Broken.tick,
                            onPressed: () {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
                              Navigator.pop(
                                context,
                                controller.text.trim(),
                              );
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
        );
      },
    );
  }

  Future<void> _handleCreatePlaylist(Song song) async {
    final playlistName = await _showPlaylistNameDialog();
    if (playlistName != null && playlistName.isNotEmpty) {
      await createPlaylist(widget.musicFolder, playlistName);
      await addSongToPlaylist(song.path, widget.musicFolder, playlistName);
      ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Created playlist $playlistName'));
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
      ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Added to $selectedPlaylist'));
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
                              onTap: () {
                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
                                Navigator.pop(context, playlist);
                              },
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
                                      Broken.music_playlist,
                                      color: dominantColor.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        playlist,
                                        style: TextStyle(
                                          color: Theme.of(
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
        NamidaSnackbar(
            backgroundColor: dominantColor,
            content: 'Added $songPath to playlist $playlistName');
      } else {
        NamidaSnackbar(
            backgroundColor: dominantColor,
            content: 'Song already in playlist.');
      }
    } else {
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Song file does not exist: $songPath');
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
    final linkPath =
        '${widget.musicFolder}/.adilists/${widget.currentPlaylistName}/$filename';
    final link = Link(linkPath);
    if (await link.exists()) {
      await link.delete();
      ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
          backgroundColor: dominantColor, content: 'Removed from playlist'));
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
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  Navigator.pop(context, false);
                },
              ),
              TextButton(
                child:
                    Text('Delete', style: TextStyle(color: Colors.redAccent)),
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  Navigator.pop(context, true);
                },
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
        await widget.onReloadLibrary();
        if (mounted) {
          _handleSkipNext();
          ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
              backgroundColor: dominantColor, content: 'Song deleted'));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Error deleting: ${e.toString()}'));
    }
  }

  void _updateParticleOptions() {
    final peakSpeed = (_waveformData.isNotEmpty
                ? _waveformData[
                    (_currentSliderValue * _waveformData.length).toInt()]
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
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: "Error extracting waveform: $e");
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
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Error reading cached lyrics: $e');
    }
    return null;
  }

  Future<void> _saveLyricsToCache(Song song, String lrcContent) async {
    try {
      final dir = await getTemporaryDirectory();
      final cacheDir = Directory('${dir.path}/lyrics');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);

      // Generate hash from original song's path
      final hash = md5.convert(utf8.encode(song.path)).toString();
      final file = File('${cacheDir.path}/$hash.lrc');

      // Use original song's metadata
      await file.writeAsString("#TITLE: ${song.title}\n"
          "#ARTIST: ${song.artist}\n"
          "#PATH: ${song.path}\n"
          "#GENRE: ${song.genre}\n"
          "#ALBUM: ${song.album}\n"
          "$lrcContent");
    } catch (e) {
      NamidaSnackbar(
        backgroundColor: dominantColor,
        content: 'Error saving lyrics cache: $e',
      );
    }
  }

  Future<void> _loadLyrics() async {
    // Capture current song details at start of process
    final originalSong = currentSong;
    final originalSongPath = originalSong.path;

    _lrcData = null;
    try {
      // 1. Check cache using original song path
      final cachedLrc = await _getCachedLyrics(originalSongPath);
      if (cachedLrc != null) {
        if (currentSong.path != originalSongPath)
          return; // Verify still same song
        _lrcData = cachedLrc;
        _updateLyricsStatus();
        setState(() {});
        return;
      }

      // 2. Check if required fields are present using original song
      if (originalSong.title.isEmpty || originalSong.artist.isEmpty) {
        _checkLocalLyrics();
        return;
      }

      // 3. Fetch from API using original song's metadata
      final params = {
        'track_name': originalSong.title,
        'artist_name': originalSong.artist,
        if (originalSong.album.isNotEmpty) 'album_name': originalSong.album,
        'duration': originalSong.duration.inSeconds.toString(),
      };

      final uri = Uri.https('lrclib.net', '/api/get', params);
      final response = await http.get(uri, headers: {
        'User-Agent': 'Adiman (https://github.com/ChaosTheChaotic/Adiman)',
      });

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final syncedLyrics = jsonResponse['syncedLyrics'] as String?;
        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          // Check if song hasn't changed before processing
          if (currentSong.path != originalSongPath) return;

          _lrcData = lrc_pkg.Lrc.parse(syncedLyrics);
          if (_lrcData!.lyrics.isNotEmpty) {
            await _saveLyricsToCache(originalSong, syncedLyrics);
            _updateLyricsStatus();
            if (mounted) setState(() {});
            return;
          }
        }
      }
    } catch (e) {
      NamidaSnackbar(
        backgroundColor: dominantColor,
        content: 'Error fetching lyrics from API: $e',
      );
    }

    // 4. Fallback only if still same song
    if (currentSong.path == originalSongPath) {
      _checkLocalLyrics();
    }
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
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Error loading local lyrics: $e');
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
    _hasLyrics = _lrcData != null &&
        _lrcData!.lyrics.isNotEmpty &&
        _lrcData!.lyrics.any((line) => line.lyrics.trim().isNotEmpty);
  }

  bool _rupdateLyricsStatus() {
    _hasLyrics = _lrcData != null &&
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
          _currentSliderValue =
              (position / currentSong.duration.inSeconds).clamp(0.0, 1.0);
        });
        if (position >= currentSong.duration.inSeconds - 0.1) {
          await _handleSongFinished();
        }
      }
    } catch (e) {
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Error updating progress: $e');
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
        NamidaSnackbar(
            backgroundColor: dominantColor, content: 'Error seeking: $e');
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
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Error starting playback: $e');
    }
  }

  Future<void> _updateDominantColor() async {
    try {
      if (currentSong.albumArt == null) return;

      final colorValue =
          await color_extractor.getDominantColor(data: currentSong.albumArt!);

      if (mounted) {
        setState(() {
          dominantColor = Color(colorValue ?? 0xFF383770);
        });
      }
    } catch (e) {
      NamidaSnackbar(
        backgroundColor: dominantColor,
        content: 'Error generating dominant color: $e',
      );
      if (mounted) {
        setState(() => dominantColor = const Color(0xFF383770));
      }
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
      NamidaSnackbar(
          backgroundColor: dominantColor,
          content: 'Error toggling playback: $e');
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
                onTap: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  Navigator.pop(context);
                },
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.black.withAlpha(50)),
                ),
              ),
            ),
            // Menu positioning
            Positioned(
              top: offset.dy + 50,
              right: MediaQuery.of(context).size.width -
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
                            icon: Broken.search_normal,
                            label: 'Find new song',
                            onTap: () {
                              _handleSearchAnother();
                            },
                          ),
                          _buildMenuOption(
                            icon: Broken.save_2,
                            label: 'Save to Library',
                            onTap: () {
                              ScaffoldMessenger.of(context)
                                  .hideCurrentSnackBar();
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
              GlowIcon(icon,
                  color: dominantColor.computeLuminance() > 0.007
                      ? dominantColor
                      : Theme.of(context).textTheme.bodyLarge?.color,
                  blurRadius: 8,
                  size: 24),
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
        NamidaSnackbar(
            backgroundColor: dominantColor,
            content: 'Error deleting temp file: $e');
      }
    }
    await rust_api.pauseSong();
    widget.service._playbackStateController.add(false);
    _playPauseController.reverse();
    widget.service.onPause();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    Navigator.pushAndRemoveUntil(
        context,
        NamidaPageTransitions.createRoute(
          DownloadScreen(
            service: widget.service,
            musicFolder: widget.musicFolder,
            onReloadLibrary: widget.onReloadLibrary,
          ),
        ),
        (route) => route.isFirst);
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

      ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
          backgroundColor: dominantColor, content: 'Song saved to library!'));

      widget.onReloadLibrary.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
          backgroundColor: dominantColor, content: 'Error saving song: $e'));
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
    _lyricsAnimationController.dispose();
    if (widget.isTemp && widget.tempPath != null) {
      try {
        final file = File(widget.tempPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        NamidaSnackbar(content: 'Error deleting temp file: $e');
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waveformIndex = (_currentSliderValue * _waveformData.length)
        .clamp(0, _waveformData.length - 1)
        .toInt();
    final currentPeak =
        _waveformData.isNotEmpty ? _waveformData[waveformIndex] : 0.0;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    _updateParticleOptions();

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (_isTempFile) {
              _handleSearchAnother();
            } else if (!_isTempFile) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
                            icon: Broken.arrow_down,
                            backgroundColor: dominantColor,
                            size: 40,
                            onPressed: () {
                              if (_isTempFile) {
                                _handleSearchAnother();
                              } else {
                                ScaffoldMessenger.of(context)
                                    .hideCurrentSnackBar();
                                Navigator.pop(context, {
                                  'song': currentSong,
                                  'index': currentIndex,
                                  'dominantColor': dominantColor,
                                });
                              }
                            },
                          ),
                          DynamicIconButton(
                            icon: Broken.more,
                            onPressed: () => _isTempFile
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
                                color: dominantColor.computeLuminance() > 0.01
                                    ? dominantColor
                                    : Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color,
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
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 600),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                            return SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.5, 0.0),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              )),
                              child: FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.8,
                                    end: 1.0,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutBack,
                                  )),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: Hero(
                            key: ValueKey<String>(
                                'albumArt-${currentSong.path}'),
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
                              image: currentSong.albumArt != null
                                  ? MemoryImage(
                                      currentSong.albumArt!,
                                    )
                                  : const AssetImage(
                                      'assets/default_album.png', // do this sometime soon (cuz i will and wont procastinate)
                                    ) as ImageProvider,
                              isPlaying: isPlaying,
                              currentPeak: currentPeak,
                              showBreathingEffect: true,
                              sharedBreathingValue: _breathingAnimation.value,
                            ),
                          ),
                        ),
                        if (_showLyrics &&
                            _lrcData != null &&
                            _rupdateLyricsStatus())
                          Positioned.fill(
                            child: LyricsOverlay(
                              isPlaying: isPlaying,
                              key: ValueKey(currentSong.path),
                              lrc: _lrcData!,
                              currentPosition: Duration(
                                seconds: (_currentSliderValue *
                                        currentSong.duration.inSeconds)
                                    .toInt(),
                              ),
                              dominantColor: dominantColor,
                              currentPeak: currentPeak,
                              entranceScale: _lyricsEntranceScale,
                              entranceOpacity: _lyricsEntranceOpacity,
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
                            icon: _hasLyrics
                                ? (_showLyrics
                                    ? Broken.card_slash
                                    : Broken.document)
                                : Broken.danger,
                            onPressed:
                                _hasLyrics ? () => _toggleLyrics() : null,
                            backgroundColor: dominantColor,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Hero(
                                tag: 'controls-prev',
                                child: DynamicIconButton(
                                  icon: Broken.previous,
                                  onPressed: currentIndex > 0
                                      ? _handleSkipPrevious
                                      : null,
                                  backgroundColor: dominantColor,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Hero(
                                tag: 'controls-playPause',
                                child: ParticlePlayButton(
                                  isPlaying: isPlaying,
                                  color: dominantColor,
                                  onPressed: _togglePlayPause,
                                ),
                              ),
                              const SizedBox(width: 24),
                              Hero(
                                tag: 'controls-next',
                                child: DynamicIconButton(
                                  icon: Broken.next,
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
                            icon: _repeatMode == RepeatMode.repeatOnce
                                ? Broken.repeate_one
                                : _repeatMode == RepeatMode.repeatAll
                                    ? Broken.repeat
                                    : Broken.arrow_2,
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
      name: 'Adiman',
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
      NamidaSnackbar(content: 'Error caching album art: $e');
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
    NamidaSnackbar(backgroundColor: dominantColor, content: "LOOP");
  }

  @override
  Future<void> onShuffle(bool shuffle) async {
    // Implement shuffle if needed
    NamidaSnackbar(backgroundColor: dominantColor, content: "SHUFFLE");
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
  Color _dominantColor = Color(0xFF383770);
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
            final colorValue = await color_extractor.getDominantColor(
                data: _tempSong!.albumArt!);
            setState(() {
              _dominantColor = Color(colorValue ?? 0xFF383770);
            });
          } catch (e) {
            NamidaSnackbar(
                backgroundColor: Color(0xFF383770),
                content: 'Error generating dominant color: $e');
            setState(() => _dominantColor = Color(0xFF383770));
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
      ScaffoldMessenger.of(context).showSnackBar(NamidaSnackbar(
          backgroundColor: _dominantColor, content: 'Download failed: $e'));
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
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
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
                      child: _currentTrack == null ? _buildEmptyState() : null,
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
                                  valueColor:
                                      AlwaysStoppedAnimation(_dominantColor),
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
                      _dominantColor = Color(0xFF383770);
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

class AnimatedDeletionWrapper extends StatefulWidget {
  final Widget child;
  final bool isDeleting;
  final VoidCallback onDeletionComplete;
  final Duration duration;

  const AnimatedDeletionWrapper({
    super.key,
    required this.child,
    required this.isDeleting,
    required this.onDeletionComplete,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<AnimatedDeletionWrapper> createState() =>
      _AnimatedDeletionWrapperState();
}

class _AnimatedDeletionWrapperState extends State<AnimatedDeletionWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutQuad,
    ));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.3, 0.0),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutQuad,
    ));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDeletionComplete();
      }
    });
  }

  @override
  void didUpdateWidget(AnimatedDeletionWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDeleting && !oldWidget.isDeleting) {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Transform.translate(
              offset: Offset(
                _slideAnimation.value.dx * MediaQuery.of(context).size.width,
                0,
              ),
              child: child,
            ),
          ),
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

class AnimatedListItem extends StatefulWidget {
  final Widget child;
  final bool visible;
  final Duration duration;
  final VoidCallback? onRemove;

  const AnimatedListItem({
    super.key,
    required this.child,
    required this.visible,
    this.duration = const Duration(milliseconds: 200),
    this.onRemove,
  });

  @override
  State<AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutQuad,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutQuad,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutQuad,
      ),
    );

    if (widget.visible) _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      widget.visible ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.translate(
        offset: _slideAnimation.value,
        child: Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: child,
          ),
        ),
      ),
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && widget.onRemove != null) {
      widget.onRemove!();
    }
  }
}
