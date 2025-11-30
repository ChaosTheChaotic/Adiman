import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path/path.dart' as path;
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/src/rust/api/color_extractor.dart' as color_extractor;
import 'package:flutter/material.dart';
import 'package:adiman/main.dart';
import 'package:adiman/services/mpris_service.dart';
import 'package:adiman/services/prefs_service.dart';
import 'package:adiman/services/plugin_service.dart';
import 'package:adiman/widgets/seekbars.dart';
import 'package:adiman/widgets/snackbar.dart';
import 'package:adiman/widgets/volume.dart';
import 'package:adiman/widgets/icon_buttons.dart';
import 'package:adiman/widgets/misc.dart';
import 'download_screen.dart';
import 'package:lrc/lrc.dart' as lrc_pkg;
import 'package:flutter_glow/flutter_glow.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:animated_background/animated_background.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:adiman/icons/broken_icons.dart';

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
  bool _isHoveringSeekbar = false;
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
  late VoidCallback _useDominantColorsListener;

  RepeatMode _repeatMode = RepeatMode.normal;
  bool _hasRepeated = false;
  double _volume = 1.0;
  bool _isHoveringVol = false;

  List<int>? _shuffleOrder;
  int _shuffleIndex = 0;

  late AnimationController _lyricsAnimationController;
  late Animation<double> _lyricsEntranceScale;
  late Animation<double> _lyricsEntranceOpacity;
  late AnimationController _rotationController;
  late Animation<double> _animation;

  List<Map<String, dynamic>> _songOptionsPluginButtons = [];

  late GlobalKey<_LyricsOverlayState> _lyricsOverlayKey;

  @override
  void initState() {
    super.initState();
    _lyricsOverlayKey = GlobalKey<_LyricsOverlayState>();
    rust_api.getCvol().then((volume) {
      if (mounted) {
        setState(() {
          _volume = volume;
        });
      }
    });
    _useDominantColorsListener = () {
      _updateDominantColor();
    };
    useDominantColorsNotifier.addListener(_useDominantColorsListener);
    defaultThemeColorNotifier.addListener(_handleThemeColorChange);
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
    dominantColor = defaultThemeColorNotifier.value;
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
    _rotationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_rotationController);

    _rotationController.repeat();
    _loadSongOptionsPluginButtons();
  }

  void _loadSongOptionsPluginButtons() async {
    try {
      final buttons = await PluginService.getPluginButtons(locationFilter: 'songopts');
      if (mounted) {
        setState(() {
          _songOptionsPluginButtons = buttons;
        });
      }
    } catch (e) {
      print('Error loading song options plugin buttons: $e');
    }
  }

  void _handleThemeColorChange() {
    final useDominant =
        SharedPreferencesService.instance.getBool('useDominantColors') ?? true;
    if (!useDominant || currentSong.albumArt == null) {
      if (mounted) {
        setState(() {
          dominantColor = defaultThemeColorNotifier.value;
        });
      }
    }
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

  Widget _buildPluginButtonTile(Map<String, dynamic> buttonData) {
    final button = buttonData['button'];
    final iconName = button['icon'];
    final name = button['name'];
    
    return _buildPlaylistOptionButton(
      icon: PluginService.getIconFromName(iconName),
      label: name,
      onTap: () { handlePluginButtonTap(buttonData, context, dominantColor); Navigator.pop(context); }
    );
  }

  void _showPlaylistPopup(BuildContext context) async {
    final currentSong = widget.song;
    final List<Map<String, dynamic>> pluginButtons = 
        await PluginService.getPluginButtons(locationFilter: 'songopts');
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: dominantColor.withValues(alpha: 0.5),
          elevation: 0,
          child: AnimatedPopupWrapper(
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
		      if (pluginButtons.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Divider(
                          color: dominantColor.withValues(alpha: 0.2),
                          height: 1,
                        ),
                        const SizedBox(height: 12),
                        ...pluginButtons.map((buttonData) => 
                          _buildPluginButtonTile(buttonData)
                        ),
                      ],
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
          child: AnimatedPopupWrapper(
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
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
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
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
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
          child: AnimatedPopupWrapper(
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
        AdiSnackbar(
            backgroundColor: dominantColor,
            content: 'Added $songPath to playlist $playlistName');
      } else {
        AdiSnackbar(
            backgroundColor: dominantColor,
            content: 'Song already in playlist.');
      }
    } else {
      AdiSnackbar(
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
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
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
          ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
              backgroundColor: dominantColor, content: 'Song deleted'));
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          backgroundColor: dominantColor,
          content: 'Error deleting: ${e.toString()}'));
    }
  }

  void _updateParticleOptions() {
    final peakSpeed = (_waveformData.isNotEmpty
                ? _waveformData[(_currentSliderValue * _waveformData.length)
                    .clamp(0, _waveformData.length - 1)
                    .toInt()]
                : 0.0) *
            150 +
        50;

    _particleOptions = ParticleOptions(
      baseColor: Color(
          SharedPreferencesService.instance.getInt('particleBaseColor') ??
              Colors.white.toARGB32()),
      spawnOpacity:
          SharedPreferencesService.instance.getDouble('particleSpawnOpacity') ??
              0.4,
      opacityChangeRate: SharedPreferencesService.instance
              .getDouble('particleOpacityChangeRate') ??
          0.2,
      minOpacity:
          SharedPreferencesService.instance.getDouble('particleMinOpacity') ??
              0.1,
      maxOpacity:
          SharedPreferencesService.instance.getDouble('particleMaxOpacity') ??
              0.6,
      spawnMinSpeed: peakSpeed,
      spawnMaxSpeed: 60 + peakSpeed * 0.7,
      spawnMinRadius:
          SharedPreferencesService.instance.getDouble('particleMinRadius') ??
              2.0,
      spawnMaxRadius:
          SharedPreferencesService.instance.getDouble('particleMaxRadius') ??
              4.0,
      particleCount:
          SharedPreferencesService.instance.getInt('particleCount') ?? 50,
    );
  }

  /// Initialize waveform data by decoding the MP3 file.
  void _initWaveform() async {
    setState(() {
      _waveformData = List.filled(1000, 0.0);
    });
    try {
      final waveformBars =
          SharedPreferencesService.instance.getInt('waveformBars') ?? 1000;
      List<double> waveform = await rust_api.extractWaveformFromMp3(
        mp3Path: currentSong.path,
        sampleCount: waveformBars,
        channels: 2,
      );
      //List<double> waveform = await rust_api.extractWaveform(
      //    path: currentSong.path, sampleCount: waveformBars);
      if (mounted) {
        setState(() {
          _waveformData = waveform;
          _updateProgress();
        });
      }
    } catch (e) {
      AdiSnackbar(
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
      AdiSnackbar(
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
      AdiSnackbar(
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
        if (currentSong.path != originalSongPath) {
          return; // Verify still same song
        }
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
      AdiSnackbar(
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
      AdiSnackbar(
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

        // Check if song has changed (Rust auto-advanced)
        if (position < 1.0) {
          // Only check if not at beginning of new song
          final currentPath = await rust_api.getCurrentSongPath();
          if (currentPath != currentSong.path) {
            final newIndex =
                widget.songList.indexWhere((song) => song.path == currentPath);
            if (newIndex != -1) {
              setState(() {
                currentIndex = newIndex;
                currentSong = widget.songList[newIndex];
                _currentSliderValue = 0.0;
              });
              _initWaveform();
              _loadLyrics();
              await _updateDominantColor();
              widget.service.updatePlaylist(widget.songList, currentIndex);
              widget.service.updateMetadata();
	      return;
            }
          }
        }

        if (position >= currentSong.duration.inSeconds - 0.0) {
          await _handleSongFinished();
        }
      }
    } catch (e) {
      AdiSnackbar(
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
	if (_showLyrics && _lyricsOverlayKey.currentState != null) {
  	  _lyricsOverlayKey.currentState!.updateCurrentLyric();
  	  _lyricsOverlayKey.currentState!.scrollToCurrentLyric();
  	}
        //if (!isPlaying && mounted) {
        //  setState(() {
        //    isPlaying = true;
        //    _playPauseController.forward();
        //  });
        //}
      } catch (e) {
        AdiSnackbar(
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
        widget.service.updateMetadata();
        return;
      }
      final started = await rust_api.playSong(path: currentSong.path);
      if (currentIndex + 1 < widget.songList.length) {
        await rust_api.preloadNextSong(
            path: widget.songList[currentIndex + 1].path);
      }
      if (started && mounted) {
        widget.service.updatePlaylistStart(widget.songList, currentIndex);
        widget.service.updateMetadata();
        setState(() {
          isPlaying = true;
          _currentSliderValue = 0.0;
          _playPauseController.forward();
        });
      }
    } catch (e) {
      AdiSnackbar(
          backgroundColor: dominantColor,
          content: 'Error starting playback: $e');
    }
  }

  Future<void> _updateDominantColor() async {
    final useDom = useDominantColorsNotifier.value;
    if (currentSong.albumArt == null || !useDom) {
      if (mounted) {
        setState(() {
          dominantColor = defaultThemeColorNotifier.value;
        });
      }
      return;
    }

    try {
      final colorValue =
          await color_extractor.getDominantColor(data: currentSong.albumArt!);

      if (mounted) {
        setState(() {
          dominantColor =
              Color(colorValue ?? defaultThemeColorNotifier.value.toARGB32());
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => dominantColor = defaultThemeColorNotifier.value);
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
    await rust_api.preloadNextSong(
        path: widget.songList[currentIndex + 1].path);
    if (_showLyrics && _lyricsOverlayKey.currentState != null) {
      _lyricsOverlayKey.currentState!.scrollToTop();
    }
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

    // Check if Rust has already advanced to the next song
    final currentPath = await rust_api.getCurrentSongPath();
    if (currentPath != currentSong.path) {
      // Rust has already advanced, update UI accordingly
      final newIndex =
          widget.songList.indexWhere((song) => song.path == currentPath);
      if (newIndex != -1) {
        setState(() {
          currentIndex = newIndex;
          currentSong = widget.songList[newIndex];
        });
        _initWaveform();
        _loadLyrics();
        await _updateDominantColor();
        widget.service.updatePlaylist(widget.songList, currentIndex);
        widget.service.updateMetadata();
      }
      return;
    }

    // Original handling for when Rust hasn't advanced
    await rust_api.stopSong();
    if (_repeatMode == RepeatMode.repeatOnce) {
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

    if (widget.songList.isEmpty) {
      setState(() => _isTransitioning = false);
      return;
    }

    final int newIndex = (currentIndex + 1) % widget.songList.length;
    final Song newSong = widget.songList[newIndex];

    try {
      final bool success;
      if (newSong.path.contains('cdda://')) {
        success = await rust_api.playSong(path: newSong.path);
      } else {
        success = await rust_api.switchToPreloadedNow();
        if (success && newIndex + 1 < widget.songList.length) {
          final nextNextSong = widget.songList[newIndex + 1];
          if (!nextNextSong.path.contains('cdda://')) {
            await rust_api.preloadNextSong(path: nextNextSong.path);
          }
        }
      }

      if (success) {
        final currentPath = await rust_api.getCurrentSongPath();
        if (currentPath == newSong.path) {
          setState(() {
            currentIndex = newIndex;
            currentSong = newSong;
            isPlaying = true;
            _currentSliderValue = 0.0;
          });
          _initWaveform();
          _loadLyrics();
          await _updateDominantColor();
          widget.service.updatePlaylist(widget.songList, currentIndex);
          widget.service.updateMetadata();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(AdiSnackbar(content: "Error skipping song $e"));
    } finally {
      if (mounted) {
        setState(() => _isTransitioning = false);
      }
    }
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
    await rust_api.preloadNextSong(
        path: widget.songList[currentIndex + 1].path);
    if (success && mounted) {
      setState(() {
        isPlaying = true;
        _currentSliderValue = 0.0;
        _playPauseController.forward();
      });
      widget.service.updatePlaylist(widget.songList, currentIndex);
      widget.service.updateMetadata();
    }
    setState(() => _isTransitioning = false);
  }

  void _togglePlayPause() async {
    try {
      if (isPlaying) {
        await rust_api.pauseSong();
        widget.service.playbackStateController.add(false);
        _playPauseController.reverse();
        widget.service.onPause();
      } else {
        await rust_api.resumeSong();
        widget.service.playbackStateController.add(true);
        _playPauseController.forward();
        widget.service.onPlay();
      }
      setState(() => isPlaying = !isPlaying);
    } catch (e) {
      AdiSnackbar(
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
              child: AnimatedPopupWrapper(
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
        AdiSnackbar(
            backgroundColor: dominantColor,
            content: 'Error deleting temp file: $e');
      }
    }
    await rust_api.pauseSong();
    widget.service.playbackStateController.add(false);
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
      final musicFolder =
          SharedPreferencesService.instance.getString('musicFolder') ??
              '~/Music';
      final expandedPath =
          musicFolder.replaceFirst('~', Platform.environment['HOME'] ?? '');

      final sourceFile = File(widget.tempPath!);
      final fileName = path.basename(widget.tempPath!);
      final destPath = path.join(expandedPath, fileName);

      await sourceFile.copy(destPath);
      await sourceFile.delete();

      final newSong = Song(
        title: currentSong.title,
        artist: currentSong.artist,
        artists: currentSong.artists,
        album: currentSong.album,
        path: destPath,
        albumArt: currentSong.albumArt,
        duration: currentSong.duration,
        genre: currentSong.genre,
      );

      setState(() {
        currentSong = newSong;
      });

      widget.service.updatePlaylist([newSong], widget.currentIndex);

      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          backgroundColor: dominantColor, content: 'Song saved to library!'));

      widget.onReloadLibrary.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
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
    defaultThemeColorNotifier.removeListener(_handleThemeColorChange);
    useDominantColorsNotifier.removeListener(_useDominantColorsListener);
    if (widget.isTemp && widget.tempPath != null) {
      try {
        final file = File(widget.tempPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (e) {
        AdiSnackbar(content: 'Error deleting temp file: $e');
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seekbarTypeString =
        SharedPreferencesService.instance.getString('seekbarType');
    final useAltSeekbar =
        seekbarTypeString == 'alt' || widget.song.path.contains('cdda://');
    final waveformIndex = (_currentSliderValue * _waveformData.length)
        .clamp(0, _waveformData.length - 1)
        .toInt();
    final currentPeak =
        _waveformData.isNotEmpty ? _waveformData[waveformIndex] : 0.0;
    final textColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    _updateParticleOptions();

    //return KeyboardListener(
    return Theme(
        data: ThemeData(
          brightness: Brightness.dark,
          textTheme: TextTheme(
            bodyLarge: GoogleFonts.inter(color: textColor),
            bodyMedium: GoogleFonts.inter(color: textColor),
            titleLarge: GoogleFonts.inter(color: textColor),
            titleMedium: GoogleFonts.inter(color: textColor),
          ),
        ),
        child: KeyboardListener(
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
                if (SharedPreferencesService.instance.getBool('edgeBreathe') ??
                    true) ...[
                  Positioned.fill(
                    child: EdgeBreathingEffect(
                      dominantColor: dominantColor,
                      currentPeak: currentPeak,
                      isPlaying: isPlaying,
                    ),
                  ),
                ],
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
                              const SizedBox(width: 12),
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
                        child: Transform.translate(
                          offset: const Offset(0, -20),
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32.0),
                            child: Column(
                              children: [
                                GlowText(
                                  currentSong.title,
                                  style: TextStyle(
                                    color:
                                        dominantColor.computeLuminance() > 0.01
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
                                child: (currentSong.path.contains('cdda://') ||
                                        ((SharedPreferencesService.instance
                                                    .getBool(
                                                        'spinningAlbumArt') ??
                                                false) &&
                                            currentSong.albumArt != null))
                                    ? RotationTransition(
                                        turns: _animation,
                                        child: NamidaThumbnail(
                                          image: currentSong.albumArt != null
                                              ? MemoryImage(
                                                  currentSong.albumArt!,
                                                )
                                              : currentSong.path
                                                      .contains('cdda://')
                                                  ? AssetImage(
                                                      'assets/adiman_cd.png')
                                                  : null,
                                          isPlaying: isPlaying,
                                          currentPeak: currentPeak,
                                          showBreathingEffect: true,
                                          isCD: currentSong.path
                                              .contains('cdda://'),
                                          sharedBreathingValue:
                                              _breathingAnimation.value,
                                        ),
                                      )
                                    : NamidaThumbnail(
                                        image: currentSong.albumArt != null
                                            ? MemoryImage(
                                                currentSong.albumArt!,
                                              )
                                            : null,
                                        isPlaying: isPlaying,
                                        currentPeak: currentPeak,
                                        showBreathingEffect: true,
                                        isCD: currentSong.path.contains(
                                            'cdda://'), // Should be false hardcoded but copy and paste
                                        sharedBreathingValue:
                                            _breathingAnimation.value,
                                      ),
                              ),
                            ),
                            if (_showLyrics &&
                                _lrcData != null &&
                                _rupdateLyricsStatus())
                              Positioned.fill(
                                child: LyricsOverlay(
                                  isPlaying: isPlaying,
                                  //key: ValueKey(currentSong.path),
				  key: _lyricsOverlayKey,
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
                                  sharedBreathingValue:
                                      _breathingAnimation.value,
                                  onLyricTap: (timestamp) {
                                    final position =
                                        timestamp.inSeconds.toDouble();
                                    final progress = position /
                                        currentSong.duration.inSeconds;
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
                            child: Builder(builder: (context) {
                              if (useAltSeekbar) {
                                return Container(
                                  height: 32,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: MouseRegion(
                                    onEnter: (_) => setState(
                                        () => _isHoveringSeekbar = true),
                                    onExit: (_) => setState(
                                        () => _isHoveringSeekbar = false),
                                    child: TweenAnimationBuilder<double>(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      curve: Curves.easeOutCubic,
                                      tween: Tween<double>(
                                        begin: 0,
                                        end: _isHoveringSeekbar ? 1 : 0,
                                      ),
                                      builder: (context, value, child) {
                                        return AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 200),
                                          curve: Curves.easeOutCubic,
                                          height: 4 + (12 * value),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                                2 + (6 * value)),
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                dominantColor.withValues(
                                                    alpha: 0.3),
                                                dominantColor.withValues(
                                                    alpha: 0.1),
                                              ],
                                            ),
                                          ),
                                          child: SliderTheme(
                                            data: SliderThemeData(
                                              trackHeight: 4 + (12 * value),
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                      enabledThumbRadius: 0),
                                              overlayShape: SliderComponentShape
                                                  .noOverlay,
                                              activeTrackColor: dominantColor,
                                              inactiveTrackColor:
                                                  Colors.grey.withAlpha(0x30),
                                              trackShape:
                                                  CustomRoundedRectSliderTrackShape(
                                                radius: 2 + (6 * value),
                                              ),
                                            ),
                                            child: Slider(
                                              value: _currentSliderValue,
                                              onChanged: (value) =>
                                                  _handleSeek(value),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                );
                              } else if (seekbarTypeString == 'dyn') {
                                return BreathingWaveformSeekbar(
                                  waveformData: _waveformData,
                                  progress: _currentSliderValue,
                                  activeColor: dominantColor,
                                  inactiveColor: Colors.grey.withAlpha(0x30),
                                  onSeek: (value) => _handleSeek(value),
                                  isPlaying: isPlaying,
                                  currentPeak: currentPeak,
                                );
                              } else {
                                return WaveformSeekBar(
                                  waveformData: _waveformData,
                                  progress: _currentSliderValue,
                                  activeColor: dominantColor,
                                  inactiveColor: Colors.grey.withAlpha(0x30),
                                  onSeek: (value) => _handleSeek(value),
                                );
                              }
                            })),
                      ),
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32.0,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: DynamicIconButton(
                                    icon: _hasLyrics
                                        ? (_showLyrics
                                            ? Broken.card_slash
                                            : Broken.document)
                                        : Broken.danger,
                                    onPressed: _hasLyrics
                                        ? () => _toggleLyrics()
                                        : null,
                                    backgroundColor: dominantColor,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Center(
                                  child: Row(
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
                                          miniP: false,
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Hero(
                                        tag: 'controls-next',
                                        child: DynamicIconButton(
                                          icon: Broken.next,
                                          onPressed: currentIndex <
                                                  widget.songList.length - 1
                                              ? _handleSkipNext
                                              : null,
                                          backgroundColor: dominantColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      MouseRegion(
                                        onEnter: (_) => setState(
                                            () => _isHoveringVol = true),
                                        onExit: (_) => setState(
                                            () => _isHoveringVol = false),
                                        child: AnimatedContainer(
                                          duration:
                                              const Duration(milliseconds: 300),
                                          curve: Curves.easeOut,
                                          width: _isHoveringVol ? 150 : 40,
                                          child: Row(
                                            children: [
                                              Hero(
                                                tag:
                                                    'volume-${currentSong.path}',
                                                child: VolumeIcon(
                                                  volume: _volume,
                                                  dominantColor: dominantColor,
                                                ),
                                              ),
                                              if (_isHoveringVol) ...[
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: AdaptiveSlider(
                                                    dominantColor:
                                                        dominantColor,
                                                    value: _volume,
                                                    onChanged:
                                                        (newVolume) async {
                                                      await VolumeController()
                                                          .setVolume(newVolume);
                                                      setState(() =>
                                                          _volume = newVolume);
                                                      await rust_api.setVolume(
                                                          volume: newVolume);
                                                    },
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      DynamicIconButton(
                                        icon:
                                            _repeatMode == RepeatMode.repeatOnce
                                                ? Broken.repeate_one
                                                : _repeatMode ==
                                                        RepeatMode.repeatAll
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
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
  }

  List<double> _generateDummyWaveformData() {
    return List.filled(1000, 0.0);
  }
}

class CustomRoundedRectSliderTrackShape extends RoundedRectSliderTrackShape {
  final double radius;

  const CustomRoundedRectSliderTrackShape({this.radius = 2});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    assert(sliderTheme.disabledActiveTrackColor != null);
    assert(sliderTheme.disabledInactiveTrackColor != null);
    assert(sliderTheme.activeTrackColor != null);
    assert(sliderTheme.inactiveTrackColor != null);
    assert(sliderTheme.thumbShape != null);

    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final activeTrackColorTween = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    );
    final inactiveTrackColorTween = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    );
    final activePaint = Paint()
      ..color = activeTrackColorTween.evaluate(enableAnimation)!;
    final inactivePaint = Paint()
      ..color = inactiveTrackColorTween.evaluate(enableAnimation)!;

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final activeRect = RRect.fromLTRBAndCorners(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
      topLeft: Radius.circular(radius),
      bottomLeft: Radius.circular(radius),
    );
    final inactiveRect = RRect.fromLTRBAndCorners(
      thumbCenter.dx,
      trackRect.top,
      trackRect.right,
      trackRect.bottom,
      topRight: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );

    context.canvas.drawRRect(activeRect, activePaint);
    context.canvas.drawRRect(inactiveRect, inactivePaint);
  }
}

class NamidaThumbnail extends StatefulWidget {
  final ImageProvider? image;
  final bool isPlaying;
  final bool showBreathingEffect;
  final double currentPeak;
  final double? sharedBreathingValue;
  final String? heroTag;
  final bool isCD;

  const NamidaThumbnail({
    super.key,
    required this.image,
    required this.isPlaying,
    this.showBreathingEffect = true,
    this.currentPeak = 0.0,
    this.sharedBreathingValue,
    this.heroTag,
    required this.isCD,
  });

  @override
  State<NamidaThumbnail> createState() => _NamidaThumbnailState();
}

class _NamidaThumbnailState extends State<NamidaThumbnail>
    with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late AnimationController _peakController;
  late Animation<double> _breathingAnimation;
  late Animation<double> _peakAnimation;
  double _targetPeakScale = 1.0;

  @override
  void initState() {
    super.initState();

    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _breathingAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );

    _peakController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..value = 1.0;
    _peakAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _peakController, curve: Curves.easeOut),
    );

    if (widget.isPlaying) {
      _breathingController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(NamidaThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _breathingController.repeat(reverse: true);
      } else {
        _breathingController.stop();
      }
    }

    if (widget.currentPeak != oldWidget.currentPeak) {
      _targetPeakScale = 1.0 + (widget.currentPeak * 0.05);
      _peakAnimation = Tween<double>(
        begin: _peakAnimation.value,
        end: _targetPeakScale,
      ).animate(
        CurvedAnimation(parent: _peakController, curve: Curves.easeOut),
      );
      _peakController
        ..value = 0.0
        ..forward();
    }
  }

  double getMSn() {
    return SharedPreferencesService.instance.getBool('mSn') ?? false == true
        ? 0.6
        : 0.3;
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _peakController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breathingValue =
        widget.sharedBreathingValue ?? _breathingAnimation.value;
    final peakValue = _peakAnimation.value;
    final spin =
        SharedPreferencesService.instance.getBool('spinningAlbumArt') ?? false;
    final borderR = (spin || widget.isCD ? 360 : 16).toDouble();

    final mSnEnabled =
        SharedPreferencesService.instance.getBool('mSn') ?? false;
    final breathingEnabled =
        SharedPreferencesService.instance.getBool('breathe') ?? true;

    // Determine if we should apply breathing effect
    final bool shouldBreathe =
        !(widget.image != null && breathingEnabled && !mSnEnabled);

    return AnimatedBuilder(
        animation: Listenable.merge([_breathingController, _peakController]),
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return shouldBreathe
                  ? Container(
                      decoration: widget.image != null
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(borderR),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white
                                      .withAlpha((breathingValue * 70).toInt()),
                                  spreadRadius: breathingValue * 6,
                                  blurRadius: 30,
                                  blurStyle: BlurStyle.outer,
                                ),
                              ],
                            )
                          : null,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(borderR),
                        child: widget.image != null
                            ? Image(
                                image: widget.image!,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            : Center(
                                child: GlowIcon(
                                  Broken.adiman,
                                  color: Colors.white,
                                  glowColor: Colors.white,
                                  size: constraints.maxWidth * getMSn(),
                                ),
                              ),
                      ),
                    )
                  : Transform.scale(
                      scale: breathingValue + (peakValue - 1.0),
                      child: Container(
                        decoration: widget.image != null
                            ? BoxDecoration(
                                borderRadius: BorderRadius.circular(borderR),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withAlpha(
                                        (breathingValue * 70).toInt()),
                                    spreadRadius: breathingValue * 6,
                                    blurRadius: 30,
                                    blurStyle: BlurStyle.outer,
                                  ),
                                ],
                              )
                            : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(borderR),
                          child: widget.image != null
                              ? Image(
                                  image: widget.image!,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                )
                              : Center(
                                  child: GlowIcon(
                                    Broken.adiman,
                                    color: Colors.white,
                                    glowColor: Colors.white,
                                    size: constraints.maxWidth * getMSn(),
                                  ),
                                ),
                        ),
                      ),
                    );
            },
          );
        });
  }
}

class LyricsOverlay extends StatefulWidget {
  final lrc_pkg.Lrc lrc;
  final Duration currentPosition;
  final Color dominantColor;
  final double scale;
  final double currentPeak;
  final double? sharedBreathingValue;
  final Function(Duration)? onLyricTap;
  final bool isPlaying;
  // Add animation values as parameters
  final Animation<double> entranceScale;
  final Animation<double> entranceOpacity;

  const LyricsOverlay({
    super.key,
    required this.lrc,
    required this.currentPosition,
    required this.dominantColor,
    required this.isPlaying,
    required this.entranceScale,
    required this.entranceOpacity,
    this.scale = 1.0,
    this.currentPeak = 0.0,
    this.sharedBreathingValue,
    this.onLyricTap,
  });

  @override
  State<LyricsOverlay> createState() => _LyricsOverlayState();
}

class _LyricsOverlayState extends State<LyricsOverlay>
    with TickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _currentLyricNotifier = ValueNotifier<int>(-1);
  late AnimationController _breathingController;
  late AnimationController _peakController;
  late AnimationController _pulseController;
  late Animation<double> _breathingAnimation;
  late Animation<double> _peakAnimation;
  late Animation<double> _pulseAnimation;
  double _targetPeakScale = 1.0;
  double _lastScrollPos = 0.0;
  final Map<int, GlobalKey> _lyricKeys = {};

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _currentLyricNotifier.addListener(scrollToCurrentLyric);
    _scrollController.addListener(_handleParallaxScroll);
    updateCurrentLyric();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToCurrentLyric();
    });
  }

  void _initializeAnimations() {
    // Breathing animation for overall lyric container
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _breathingAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOut),
    );

    // Peak animation for audio reactivity
    _peakController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..value = 1.0;
    _peakAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _peakController, curve: Curves.easeOut),
    );

    // Pulse animation for active lyric
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    if (widget.isPlaying) {
      _breathingController.repeat(reverse: true);
      _pulseController.repeat(reverse: true);
    }
  }

  void _handleParallaxScroll() {
    final currentPos = _scrollController.offset;
    final delta = currentPos - _lastScrollPos;
    _lastScrollPos = delta;
    setState(() {
      // This will trigger a rebuild with updated parallax offsets hopefully
    });
  }

  void scrollToCurrentLyric() {
    final index = _currentLyricNotifier.value;
    if (index >= 0 && _lyricKeys.containsKey(index)) {
      final context = _lyricKeys[index]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutQuint,
          alignment: 0.5, // Center the current lyric
        );
      }
    } else if (index >= 0 && _scrollController.hasClients) {
      // Scroll to estimated position if key is not available
      final estimatedPosition = index * 65.0; // Approximate item height
      _scrollController.animateTo(
        estimatedPosition,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutQuint,
      );
    }
  }

  double _getParallaxOffset(int index) {
    if (!_scrollController.hasClients) return 0.0;

    final scrollViewHeight = _scrollController.position.viewportDimension;
    final itemPosition = index * 65.0; // Approximate item height
    final scrollPosition = _scrollController.offset;
    final relativePosition = (itemPosition - scrollPosition) / scrollViewHeight;

    return relativePosition * 20.0; // Parallax amount
  }

  void scrollToTop() {
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    _currentLyricNotifier.value = -1; // Reset current lyric highlight
  }

  @override
  Widget build(BuildContext context) {
    final breathingValue =
        widget.sharedBreathingValue ?? _breathingAnimation.value;
    final peakValue = _peakAnimation.value;

    return FadeTransition(
        opacity: widget.entranceOpacity,
        child: ScaleTransition(
            scale: widget.entranceScale,
            child: AnimatedBuilder(
              animation: Listenable.merge(
                  [_breathingController, _peakController, _pulseController]),
              builder: (context, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return Transform.scale(
                      scale: breathingValue + (peakValue - 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(100),
                              blurRadius: 40,
                              spreadRadius: 10,
                            )
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                            child: Container(
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(150),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    widget.dominantColor.withAlpha(50),
                                    Colors.black.withAlpha(200),
                                  ],
                                ),
                              ),
                              child: ShaderMask(
                                shaderCallback: (Rect bounds) {
                                  return LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.white,
                                      Colors.white,
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.1, 0.9, 1.0],
                                  ).createShader(bounds);
                                },
                                blendMode: BlendMode.dstIn,
                                child: ValueListenableBuilder<int>(
                                  valueListenable: _currentLyricNotifier,
                                  builder: (context, currentIndex, _) {
                                    return ListView.builder(
                                      controller: _scrollController,
                                      physics: const BouncingScrollPhysics(),
                                      itemCount: widget.lrc.lyrics.length,
                                      itemBuilder: (context, index) {
                                        final lyric = widget.lrc.lyrics[index];
                                        final isCurrent = index == currentIndex;
                                        final isEmptyLine =
                                            lyric.lyrics.trim().isEmpty;
                                        _lyricKeys.putIfAbsent(
                                            index, () => GlobalKey());

                                        return Transform.translate(
                                          offset: Offset(
                                              0, _getParallaxOffset(index)),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 300),
                                            curve: Curves.easeOutQuad,
                                            padding: EdgeInsets.symmetric(
                                              vertical: isCurrent ? 24.0 : 16.0,
                                              horizontal: 24.0,
                                            ),
                                            child: GestureDetector(
                                              key: _lyricKeys[index],
                                              onTap: () => widget.onLyricTap
                                                  ?.call(lyric.timestamp),
                                              child: Transform.scale(
                                                scale: isCurrent
                                                    ? _pulseAnimation.value
                                                    : 1.0,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: widget
                                                            .dominantColor
                                                            .withAlpha(isCurrent
                                                                ? 100
                                                                : 30),
                                                        blurRadius: 25,
                                                        spreadRadius: 2,
                                                      )
                                                    ],
                                                  ),
                                                  child: Stack(
                                                    children: [
                                                      // Text background
                                                      if (isCurrent)
                                                        Container(
                                                          decoration:
                                                              BoxDecoration(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        12),
                                                            color: Colors.black
                                                                .withAlpha(100),
                                                          ),
                                                        ),
                                                      if (isEmptyLine)
                                                        _AnimatedMusicNote(
                                                            isCurrent:
                                                                isCurrent),
                                                      if (!isEmptyLine)
                                                        GlowText(
                                                          lyric.lyrics,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                            fontSize: isCurrent
                                                                ? 32
                                                                : 24,
                                                            fontWeight:
                                                                isCurrent
                                                                    ? FontWeight
                                                                        .w900
                                                                    : FontWeight
                                                                        .w600,
                                                            color: Colors.white
                                                                .withAlpha(
                                                                    isCurrent
                                                                        ? 255
                                                                        : 200),
                                                            shadows: [
                                                              Shadow(
                                                                color: Colors
                                                                    .black
                                                                    .withAlpha(
                                                                        100),
                                                                blurRadius: 10,
                                                                offset:
                                                                    const Offset(
                                                                        2, 2),
                                                              )
                                                            ],
                                                          ),
                                                          glowColor: widget
                                                              .dominantColor
                                                              .withAlpha(
                                                                  isCurrent
                                                                      ? 150
                                                                      : 50),
                                                          blurRadius: 25,
                                                        ),
                                                      GlowText(
                                                        lyric.lyrics,
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          fontSize: isCurrent
                                                              ? 32
                                                              : 24,
                                                          fontWeight: isCurrent
                                                              ? FontWeight.w900
                                                              : FontWeight.w600,
                                                          color: Colors.white
                                                              .withAlpha(
                                                                  isCurrent
                                                                      ? 255
                                                                      : 200),
                                                          shadows: [
                                                            Shadow(
                                                              color: Colors
                                                                  .black
                                                                  .withAlpha(
                                                                      100),
                                                              blurRadius: 10,
                                                              offset:
                                                                  const Offset(
                                                                      2, 2),
                                                            )
                                                          ],
                                                        ),
                                                        glowColor: widget
                                                            .dominantColor
                                                            .withAlpha(isCurrent
                                                                ? 150
                                                                : 50),
                                                        blurRadius: 25,
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
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            )));
  }

  @override
  void didUpdateWidget(LyricsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateCurrentLyric();

    if ((widget.currentPosition - oldWidget.currentPosition).inSeconds.abs() > 5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToCurrentLyric();
      });
    }

    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _breathingController.repeat(reverse: true);
        _pulseController.repeat(reverse: true);
      } else {
        _breathingController.stop();
        _pulseController.stop();
      }
    }

    if (widget.currentPeak != oldWidget.currentPeak) {
      _targetPeakScale = 1.0 + (widget.currentPeak * 0.05);
      _peakAnimation = Tween<double>(
        begin: _peakAnimation.value,
        end: _targetPeakScale,
      ).animate(
          CurvedAnimation(parent: _peakController, curve: Curves.easeOut));
      _peakController
        ..value = 0.0
        ..forward();
    }
  }

  void updateCurrentLyric() {
    int newIndex = -1;
    for (var i = 0; i < widget.lrc.lyrics.length; i++) {
      if (widget.lrc.lyrics[i].timestamp <= widget.currentPosition) {
        newIndex = i;
      } else {
        break;
      }
    }
    if (newIndex != _currentLyricNotifier.value) {
      _currentLyricNotifier.value = newIndex;
    }
  }

  @override
  void dispose() {
    _currentLyricNotifier.dispose();
    _scrollController.dispose();
    _breathingController.dispose();
    _peakController.dispose();
    _pulseController.dispose();
    super.dispose();
  }
}

class _AnimatedMusicNote extends StatefulWidget {
  final bool isCurrent;

  const _AnimatedMusicNote({required this.isCurrent});

  @override
  __AnimatedMusicNoteState createState() => __AnimatedMusicNoteState();
}

class __AnimatedMusicNoteState extends State<_AnimatedMusicNote>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _floatAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _rotateAnimation = Tween<double>(begin: -0.1, end: 0.1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didUpdateWidget(_AnimatedMusicNote oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrent && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isCurrent && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, widget.isCurrent ? _floatAnimation.value : 0),
          child: Transform.rotate(
            angle: widget.isCurrent ? _rotateAnimation.value : 0,
            child: child,
          ),
        );
      },
      child: Center(
        child: GlowIcon(
          Broken.adiman,
          color: Colors.white.withAlpha(widget.isCurrent ? 255 : 200),
          glowColor: Theme.of(context).colorScheme.primary.withAlpha(100),
          size: 40,
        ),
      ),
    );
  }
}

class EdgeBreathingEffect extends StatelessWidget {
  final Color dominantColor;
  final double currentPeak;
  final bool isPlaying;

  const EdgeBreathingEffect({
    super.key,
    required this.dominantColor,
    required this.currentPeak,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final scale = isPlaying ? currentPeak * 1.5 : 0.0;
    final palette = _generatePalette(dominantColor);

    return IgnorePointer(
      child: Stack(
        children: [
          // Top edge
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              children: [
                for (final color in palette.firstHalf)
                  Expanded(
                    child: _AnimatedShadowBox(
                      color: color,
                      scale: scale,
                      isHorizontal: true,
                    ),
                  ),
              ],
            ),
          ),
          // Bottom edge
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Row(
              children: [
                for (final color in palette.secondHalf)
                  Expanded(
                    child: _AnimatedShadowBox(
                      color: color,
                      scale: scale,
                      isHorizontal: true,
                    ),
                  ),
              ],
            ),
          ),
          // Left edge
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Column(
              children: [
                for (final color in palette.firstHalf)
                  Expanded(
                    child: _AnimatedShadowBox(
                      color: color,
                      scale: scale,
                      isHorizontal: false,
                    ),
                  ),
              ],
            ),
          ),
          // Right edge
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Column(
              children: [
                for (final color in palette.secondHalf)
                  Expanded(
                    child: _AnimatedShadowBox(
                      color: color,
                      scale: scale,
                      isHorizontal: false,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _Palette _generatePalette(Color baseColor) {
    final firstHalf =
        List.generate(4, (index) => baseColor.withAlpha(150 ~/ (index + 1)));
    final secondHalf =
        List.generate(4, (index) => baseColor.withAlpha(150 ~/ (index + 2)));
    return _Palette(firstHalf, secondHalf);
  }
}

class _AnimatedShadowBox extends StatelessWidget {
  final Color color;
  final double scale;
  final bool isHorizontal;

  const _AnimatedShadowBox({
    required this.color,
    required this.scale,
    required this.isHorizontal,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      height: isHorizontal ? 2 : null,
      width: isHorizontal ? null : 2,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: color,
            spreadRadius: 140 * scale,
            blurRadius: 10 + (200 * scale),
          ),
        ],
      ),
    );
  }
}

class _Palette {
  final List<Color> firstHalf;
  final List<Color> secondHalf;

  _Palette(this.firstHalf, this.secondHalf);
}
