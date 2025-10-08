import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path/path.dart' as path;
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/src/rust/api/color_extractor.dart' as color_extractor;
import 'package:flutter/material.dart';
import 'package:adiman/main.dart';
import 'package:adiman/widgets/miniplayer.dart';
import 'package:adiman/widgets/services.dart';
import 'package:adiman/widgets/settings.dart';
import 'package:adiman/widgets/icon_buttons.dart';
import 'package:adiman/widgets/misc.dart';
import 'music_player_screen.dart';
import 'package:adiman/widgets/snackbar.dart';
import 'playlist_reorder_screen.dart';
import 'download_screen.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:adiman/icons/broken_icons.dart';

class SongSelectionScreen extends StatefulWidget {
  final Function(Color)? updateThemeColor;
  const SongSelectionScreen({super.key, this.updateThemeColor});

  @override
  State<SongSelectionScreen> createState() => _SongSelectionScreenState();
}

class _SongSelectionScreenState extends State<SongSelectionScreen>
    with TickerProviderStateMixin {
  List<Song> songs = [];
  List<Song> displayedSongs = [];
  bool isLoading = true;
  Song? currentSong;
  int currentIndex = 0;
  bool showMiniPlayer = false;
  Color dominantColor = defaultThemeColorNotifier.value;
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
  final Map<String, bool> _deletingSongs = {};
  DateTime? _lastGKeyPressTime;
  late bool _vimKeybindings;

  final double fixedHeaderHeight = 60.0;
  final double slidingHeaderHeight = 48.0;
  final double miniPlayerHeight = 80.0;
  late AnimationController _playlistTransitionController;
  late Animation<double> _playlistTransitionAnimation;
  bool _isPlaylistTransitioning = false;
  bool _isLoadingCD = false;
  bool _cdLoadingCancelled = false;

  late SortOption _selectedSortOption;

  bool _isSearchExpanded = false;
  final TextEditingController _searchController = TextEditingController();

  // GlobalKey for accessing the Scaffold to open the drawer.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // GlobalKey to access MiniPlayer state for triggering play/pause.
  final GlobalKey<MiniPlayerState> _miniPlayerKey =
      GlobalKey<MiniPlayerState>();

  // Music folder path (default to '~/Music')
  String _musicFolder = '~/Music';

  late FocusNode _mainFocusNode;
  late FocusNode _searchFocusNode;

  List<String> customSeparators = [];

  @override
  void initState() {
    super.initState();
    dominantColor = defaultThemeColorNotifier.value;
    defaultThemeColorNotifier.addListener(_handleDefaultColorChange);
    useDominantColorsNotifier.addListener(_updateDominantColor);
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
    _selectedSortOption =
        (_currentPlaylistName == null) ? SortOption.title : SortOption.playlist;
    _sortSongs(_selectedSortOption);
  }

  void _updateDominantColor() {
    if (currentSong != null) {
      _getDominantColor(currentSong!).then((newColor) {
        if (mounted) {
          setState(() => dominantColor = newColor);
        }
      });
    } else {
      setState(() => dominantColor = defaultThemeColorNotifier.value);
    }
  }

  Future<void> _getVimBindings() async {
    if (mounted) {
      setState(() {
        _vimKeybindings =
            SharedPreferencesService.instance.getBool('vimKeybindings') ??
                false;
      });
    }
  }

  void _handleDefaultColorChange() {
    if (currentSong == null) {
      setState(() => dominantColor = defaultThemeColorNotifier.value);
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
    String musicFolder =
        SharedPreferencesService.instance.getString('musicFolder') ?? '~/Music';
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

  void _showReorderPlaylistScreen(String playlistName) async {
    // Load songs for this specific playlist
    final playlistPath = '$_musicFolder/.adilists/$playlistName';
    final metadata = await rust_api.scanMusicDirectory(
      dirPath: playlistPath,
      autoConvert:
          SharedPreferencesService.instance.getBool('autoConvert') ?? false,
    );

    List<Song> playlistSongs =
        metadata.map((m) => Song.fromMetadata(m)).toList();

    // Get the stored order if available
    List<String> orderedPaths =
        await PlaylistOrderDatabase().getPlaylistOrder(playlistName);

    if (orderedPaths.isNotEmpty) {
      final pathToSong = {for (var song in playlistSongs) song.path: song};

      final orderedSongs = <Song>[];
      for (final path in orderedPaths) {
        if (pathToSong.containsKey(path)) {
          orderedSongs.add(pathToSong[path]!);
        }
      }

      // Add any songs that weren't in the database (newly added)
      for (final song in playlistSongs) {
        if (!orderedPaths.contains(song.path)) {
          orderedSongs.add(song);
        }
      }

      playlistSongs = orderedSongs;
    }

    Navigator.push(
      context,
      NamidaPageTransitions.createRoute(
        PlaylistReorderScreen(
          playlistName: playlistName,
          musicFolder: _musicFolder,
          songs: playlistSongs,
        ),
      ),
    ).then((_) {
      // Refresh the playlist when returning from reorder screen
      _loadSongs();
    });
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
                          ...localPlaylists.map(
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
                                    _selectedSortOption = SortOption.playlist;
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
                                        color:
                                            dominantColor.computeLuminance() >
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
                                          color:
                                              dominantColor.computeLuminance() >
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
                                              ).showSnackBar(AdiSnackbar(
                                                  backgroundColor:
                                                      dominantColor,
                                                  content:
                                                      'Playlist renamed to "$newName"'));
                                            } catch (e) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(AdiSnackbar(
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
                                          Broken.sort,
                                          color:
                                              dominantColor.computeLuminance() >
                                                      0.01
                                                  ? dominantColor
                                                  : Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.color,
                                          blurRadius: 8,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          ScaffoldMessenger.of(context)
                                              .hideCurrentSnackBar();
                                          Navigator.pop(context);
                                          _showReorderPlaylistScreen(playlist);
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
                                            builder: (context) => AlertDialog(
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
                                                        color: Colors.white70,
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
                                                        color: Colors.redAccent,
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
                                              ).showSnackBar(AdiSnackbar(
                                                  backgroundColor:
                                                      dominantColor,
                                                  content: 'Playlist deleted'));
                                              // Remove the deleted playlist from the list.
                                              setStateDialog(() {
                                                localPlaylists.remove(
                                                  playlist,
                                                );
                                              });
                                            } catch (e) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(AdiSnackbar(
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
                          ),
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
                                  _selectedSortOption = SortOption.title;
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
      AdiSnackbar(
          backgroundColor: dominantColor,
          content: 'Error counting audio files: $e');
    }
    return count;
  }

  Future<void> _loadSongs() async {
    setState(() => isLoading = true);
    try {
      final expectedCount = await countAudioFiles(currentMusicDirectory);
      int currentCount = 0;
      List<Song> loadedSongs = [];

      // Initialize all songs as invisible
      _visibleSongs = {};

      do {
        final metadata = await rust_api.scanMusicDirectory(
          dirPath: currentMusicDirectory,
          autoConvert:
              SharedPreferencesService.instance.getBool('autoConvert') ?? false,
        );
        loadedSongs = metadata.map((m) => Song.fromMetadata(m)).toList();
        currentCount = loadedSongs.length;

        // Sort the songs
        loadedSongs.sort((a, b) => a.title.compareTo(b.title));

        List<String> orderedPaths = [];
        if (_currentPlaylistName != null) {
          try {
            orderedPaths = await PlaylistOrderDatabase()
                .getPlaylistOrder(_currentPlaylistName!);
          } catch (e) {
            print('Error getting playlist order: $e');
          }
        }

        // Sort songs according to stored order if available
        if (orderedPaths.isNotEmpty) {
          final pathToSong = {for (var song in loadedSongs) song.path: song};

          final orderedSongs = <Song>[];
          for (final path in orderedPaths) {
            if (pathToSong.containsKey(path)) {
              orderedSongs.add(pathToSong[path]!);
            }
          }

          // Add any songs that weren't in the database (newly added)
          for (final song in loadedSongs) {
            if (!orderedPaths.contains(song.path)) {
              orderedSongs.add(song);
            }
          }

          loadedSongs = orderedSongs;
        }

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
        } else if (SharedPreferencesService.instance.getBool('autoConvert') ??
            false) {
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
        ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
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
        if (currentSong != null) {
          currentIndex = songs.indexWhere((s) => s.path == currentSong!.path);
          if (currentIndex == -1) currentIndex = 0;
        }
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
          .showSnackBar(AdiSnackbar(content: 'Error searching lyrics: $e'));

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
    final bool useDom =
        SharedPreferencesService.instance.getBool('useDominantColors') ?? true;
    if (song.albumArt == null || !useDom) {
      return defaultThemeColorNotifier.value;
    }

    try {
      final colorValue =
          await color_extractor.getDominantColor(data: song.albumArt!);
      return Color(colorValue ?? defaultThemeColorNotifier.value.toARGB32());
    } catch (e) {
      AdiSnackbar(content: 'Failed to get dominant color $e');
      return defaultThemeColorNotifier.value;
    }
  }

  void _shufflePlay() async {
    if (displayedSongs.isEmpty) return;
    List<Song> shuffled = List.from(displayedSongs);
    shuffled.shuffle();
    Song first = shuffled.first;
    await rust_api.playSong(path: first.path);
    await rust_api.preloadNextSong(path: shuffled.elementAt(1).path);
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
        case SortOption.playlist:
          _loadSongs();
          break;
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
            AdiSnackbar(
                backgroundColor: dominantColor,
                content: 'Error merging playlist "$playlist": $e');
          }
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      AdiSnackbar(
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

  /// Show a styled dialog to choose an existing playlist.
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

  Future<void> _removeSongFromCurrentPlaylist(Song song) async {
    if (_currentPlaylistName == null) return;
    final songFile = File(song.path);
    final filename = songFile.uri.pathSegments.last;
    final linkPath = '$_musicFolder/.adilists/$_currentPlaylistName/$filename';
    final link = Link(linkPath);
    if (await link.exists()) {
      await link.delete();
      AdiSnackbar(
          backgroundColor: dominantColor,
          content: 'Removed $filename from playlist $_currentPlaylistName');
      _loadSongs();
    } else {
      AdiSnackbar(
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
                        'Song Options',
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
                                .showSnackBar(AdiSnackbar(
                              backgroundColor: dominantColor,
                              content: 'Current song not found in library.',
                            ));
                            return;
                          }
                          if (selectedSong == currentSong) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                AdiSnackbar(
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
                              .showSnackBar(AdiSnackbar(
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
          ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
              backgroundColor: dominantColor,
              content: 'Song deleted successfully'));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _deletingSongs.remove(song.path);
        });
        ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
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
    defaultThemeColorNotifier.removeListener(_handleDefaultColorChange);
    useDominantColorsNotifier.removeListener(_updateDominantColor);
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

  Future<void> _showAudioCDSelection() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    setState(() => isLoading = true);
    try {
      final cds = await rust_api.listAudioCds(); // Fine you win.
      if (!mounted) return;

      if (cds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          backgroundColor: dominantColor,
          content: 'No audio CDs found',
        ));
        return;
      }

      await showDialog(
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
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GlowText(
                          'Audio CDs',
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
                        ...cds.map(
                          (device) => Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(15),
                            child: InkWell(
                              onTap: () => _loadCDTracks(device),
                              borderRadius: BorderRadius.circular(15),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: dominantColor.withValues(alpha: 0.2),
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
                                      Broken.cd,
                                      color: dominantColor.computeLuminance() >
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
                                        'CD Drive: ${device.split('/').last}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.color,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
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
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
        backgroundColor: dominantColor,
        content: 'Error loading CDs: $e',
      ));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _cancelCDLoading() {
    setState(() {
      _cdLoadingCancelled = true;
      _isLoadingCD = false;
      isLoading = false;
    });

    _loadSongs();

    ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
      backgroundColor: dominantColor,
      content: 'CD loading cancelled',
    ));
  }

  Future<void> _loadCDTracks(String device) async {
    Navigator.pop(context);
    setState(() {
      isLoading = true;
      _cdLoadingCancelled = false;
      _isLoadingCD = true;
    });
    int tracks = await rust_api.trackNum(device: device);
    if (tracks <= -1) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
        backgroundColor: dominantColor,
        content: 'trackNum returned $tracks due to failure',
      ));
      return;
    }

    try {
      List<Song> cdTracks = [];
      for (int i = 1; i <= tracks; i++) {
        if (_cdLoadingCancelled) break;
        final trackMeta = await rust_api.getCdTrackMetadata(
            device: device, track: i); // Fine you win.
        final track = Song.fromMetadata(trackMeta);
        cdTracks.add(track);
      }

      if (cdTracks.isEmpty || _cdLoadingCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          backgroundColor: dominantColor,
          content: 'No tracks found on CD',
        ));
        return;
      }

      setState(() {
        songs = cdTracks;
        displayedSongs = cdTracks;
        _currentPlaylistName = 'Audio CD';
        currentMusicDirectory = 'cdda://$device';
      });

      // Animate in CD tracks
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            for (var track in cdTracks) {
              _visibleSongs[track.path] = true;
            }
          });
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
        backgroundColor: dominantColor,
        content: 'Error loading CD tracks: $e',
      ));
    } finally {
      if (mounted) setState(() => isLoading = false);
      if (mounted) setState(() => _isLoadingCD = false);
    }
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
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeOut,
                );
              } else {
                final now = DateTime.now();
                if (_lastGKeyPressTime != null &&
                    now.difference(_lastGKeyPressTime!) <
                        const Duration(milliseconds: 300)) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 100),
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
                              Icon(
                                Broken.adiman,
                                key: ValueKey<bool>(_isDrawerOpen),
                                color: textColor,
                                size: 32,
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
                                        updateThemeColor:
                                            widget.updateThemeColor,
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
                              _buildMenuTile(
                                icon: Broken.cd,
                                title: 'Audio CD',
                                onTap: _showAudioCDSelection,
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
                                    defaultThemeColorNotifier.value,
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
                                  if (_currentPlaylistName != null) ...[
                                    PopupMenuItem(
                                      value: SortOption.playlist,
                                      child: Row(
                                        children: [
                                          if (_selectedSortOption ==
                                              SortOption.playlist)
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
                                              SortOption.playlist)
                                            const SizedBox(width: 8),
                                          const Text('Playlist set order'),
                                        ],
                                      ),
                                    ),
                                  ],
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
                    if (_isLoadingCD)
                      CDLoadingScreen(
                          dominantColor: dominantColor,
                          onCancel: _cancelCDLoading),
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

class CDLoadingScreen extends StatefulWidget {
  final Color dominantColor;
  final VoidCallback onCancel;
  const CDLoadingScreen({
    super.key,
    required this.dominantColor,
    required this.onCancel,
  });

  @override
  State<CDLoadingScreen> createState() => _CDLoadingScreenState();
}

class _CDLoadingScreenState extends State<CDLoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(_rotationController);

    _rotationController.repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background with blur
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.85),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(),
            ),
          ),
        ),
        // Content
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RotationTransition(
                turns: _animation,
                child: GlowIcon(
                  Broken.cd,
                  color: widget.dominantColor,
                  size: 80,
                  glowColor: widget.dominantColor.withAlpha(100),
                  blurRadius: 20,
                ),
              ),
              const SizedBox(height: 30),
              GlowText(
                'Loading CD Tracks...',
                glowColor: widget.dominantColor.withAlpha(80),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    backgroundColor: Colors.black.withAlpha(100),
                    color: widget.dominantColor,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(widget.dominantColor),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Material(
                color: Colors.transparent,
                child: DynamicIconButton(
                  icon: Broken.close_circle,
                  onPressed: widget.onCancel,
                  backgroundColor: Colors.redAccent,
                  size: 60,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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

class EnhancedSongListTile extends StatefulWidget {
  final Song song;
  final VoidCallback onTap;
  final bool isCurrent;
  final Color dominantColor;
  final bool isSelected;
  final bool isInSelectionMode;
  final ValueChanged<bool>? onSelectedChanged;

  const EnhancedSongListTile({
    super.key,
    required this.song,
    required this.onTap,
    this.isCurrent = false,
    required this.dominantColor,
    this.isSelected = false,
    this.isInSelectionMode = false,
    this.onSelectedChanged,
  });

  @override
  State<EnhancedSongListTile> createState() => _EnhancedSongListTileState();
}

class _EnhancedSongListTileState extends State<EnhancedSongListTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _selectionController;
  late Animation<double> _selectionAnimation;
  late Animation<Offset> _contentSlideAnimation;

  @override
  void initState() {
    super.initState();
    _selectionController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    )..value = widget.isInSelectionMode ? 1.0 : 0.0;

    _selectionAnimation = CurvedAnimation(
      parent: _selectionController,
      curve: Curves.easeOutCubic,
    );

    _contentSlideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(40, 0),
    ).animate(CurvedAnimation(
      parent: _selectionController,
      curve: Curves.easeOutQuad,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final primaryColor = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
          color: Colors.transparent,
          surfaceTintColor:
              widget.isCurrent ? widget.dominantColor : Colors.transparent,
          elevation: widget.isCurrent ? 2 : 0,
          child: InkWell(
              onTap: widget.isInSelectionMode
                  ? () => widget.onSelectedChanged?.call(!widget.isSelected)
                  : widget.onTap,
              onLongPress: widget.isInSelectionMode
                  ? null
                  : () => widget.onSelectedChanged?.call(true),
              hoverColor: widget.dominantColor.withValues(alpha: 0.1),
              splashColor: widget.dominantColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(15),
              child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: widget.isSelected
                          ? widget.dominantColor
                          : (widget.isCurrent
                              ? widget.dominantColor.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.1)),
                      width: widget.isSelected || widget.isCurrent ? 1.2 : 0.5,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.dominantColor.withValues(
                            alpha: widget.isSelected
                                ? 0.25
                                : (widget.isCurrent ? 0.15 : 0.05)),
                        Colors.black
                            .withValues(alpha: (widget.isSelected ? 0.3 : 0.2)),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedBuilder(
                              animation: _selectionAnimation,
                              builder: (context, child) {
                                return Transform.translate(
                                  offset: _contentSlideAnimation.value,
                                  child: Row(
                                    children: [
                                      _AlbumArt(
                                        heroTag: 'albumArt-${widget.song.path}',
                                        image: widget.song.albumArt != null
                                            ? MemoryImage(widget.song.albumArt!)
                                            : null,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.song.title,
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${widget.song.artists?.join('/') ?? widget.song.artist} • ${widget.song.album} ${widget.song.genre != "Unknown Genre" ? '•  ${widget.song.genre}' : ""}',
                                              style: TextStyle(
                                                color: textColor.withValues(
                                                    alpha: 0.8),
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          Text(
                            '${widget.song.duration.inMinutes}:${(widget.song.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: textColor.withValues(alpha: 0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      AnimatedBuilder(
                        animation: _selectionAnimation,
                        builder: (context, child) {
                          return Positioned(
                            left: -28 * (1 - _selectionAnimation.value),
                            top: 0,
                            bottom: 0,
                            child: Opacity(
                              opacity: _selectionAnimation.value,
                              child: Center(
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        widget.dominantColor.withValues(
                                          alpha:
                                              widget.isSelected ? 0.25 : 0.05,
                                        ),
                                        Colors.black.withValues(
                                          alpha: widget.isSelected ? 0.3 : 0.2,
                                        ),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: widget.isSelected
                                          ? widget.dominantColor
                                              .withValues(alpha: 0.8)
                                          : Colors.white.withValues(alpha: 0.2),
                                      width: widget.isSelected ? 1.2 : 0.5,
                                    ),
                                    boxShadow: widget.isSelected
                                        ? [
                                            BoxShadow(
                                              color: widget.dominantColor
                                                  .withValues(alpha: 0.4),
                                              blurRadius: 8,
                                              spreadRadius: 1.5,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: widget.isSelected
                                      ? Center(
                                          child: GlowIcon(
                                            Broken.tick,
                                            color: widget.dominantColor
                                                        .computeLuminance() >
                                                    0.01
                                                ? widget.dominantColor
                                                : Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color,
                                            size: 18,
                                            glowColor: widget.dominantColor
                                                .withValues(alpha: 0.5),
                                            blurRadius: 8,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (widget.isCurrent && !widget.isInSelectionMode)
                        Positioned(
                            top: 8,
                            right: 8,
                            child: GlowIcon(
                              Broken.sound,
                              color: primaryColor,
                              blurRadius: 8,
                              size: 20,
                            ))
                    ],
                  )))), //I dont know what the hell this is lmao
    );
  }

  @override
  void didUpdateWidget(EnhancedSongListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isInSelectionMode != oldWidget.isInSelectionMode) {
      if (widget.isInSelectionMode) {
        _selectionController.forward();
      } else {
        _selectionController.reverse();
      }
    }
    // Immediately reflect selection state without animation
    if (widget.isSelected != oldWidget.isSelected) {
      _selectionController.value = widget.isSelected ? 1.0 : 0.0;
    }
  }

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }
}

class _AlbumArt extends StatelessWidget {
  final ImageProvider? image;
  final String heroTag;

  const _AlbumArt({
    this.image,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.transparent,
            image: image != null
                ? DecorationImage(
                    image: image!,
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: image == null
              ? Center(
                  child: GlowIcon(
                    Broken.adiman,
                    color: Colors.white,
                    glowColor: Colors.white.withValues(alpha: 0.5),
                    size: 28,
                  ),
                )
              : null,
        ),
        Positioned.fill(
          child: Hero(
            tag: heroTag,
            flightShuttleBuilder: (
              BuildContext flightContext,
              Animation<double> animation,
              HeroFlightDirection flightDirection,
              BuildContext fromHeroContext,
              BuildContext toHeroContext,
            ) {
              return Stack(
                children: [
                  if (flightDirection == HeroFlightDirection.push)
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: image != null
                            ? DecorationImage(
                                image: image!,
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: image == null
                          ? Center(
                              child: GlowIcon(
                                Broken.adiman,
                                color: Colors.white,
                                glowColor: Colors.white,
                                size: 28,
                              ),
                            )
                          : null,
                    ),
                  AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      return Container(
                        width: Tween<double>(
                          begin: 56.0,
                          end: MediaQuery.of(context).size.width * 0.8,
                        ).evaluate(animation),
                        height: Tween<double>(
                          begin: 56.0,
                          end: MediaQuery.of(context).size.width * 0.8,
                        ).evaluate(animation),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            Tween<double>(begin: 12.0, end: 20.0)
                                .evaluate(animation),
                          ),
                          image: image != null
                              ? DecorationImage(
                                  image: image!,
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: image == null
                            ? Center(
                                child: GlowIcon(
                                  Broken.adiman,
                                  color: Colors.white,
                                  glowColor: Colors.white,
                                  size: Tween<double>(begin: 28, end: 80)
                                      .evaluate(animation),
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ],
              );
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.transparent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
