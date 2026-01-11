import 'dart:async';
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/src/rust/api/color_extractor.dart' as color_extractor;
import 'package:flutter/material.dart';
import 'package:adiman/main.dart';
import 'icon_buttons.dart';
import 'package:adiman/screens/music_player_screen.dart';
import 'snackbar.dart';
import 'package:adiman/services/mpris_service.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'seekbars.dart';
import 'volume.dart';
import 'package:adiman/icons/broken_icons.dart';

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
  MiniPlayerState createState() => MiniPlayerState();
}

class MiniPlayerState extends State<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _playPauseController;
  bool isPlaying = true;
  late Timer _progressTimer;
  double _volume = 1.0;
  StreamSubscription<bool>? _playbackStateSubscription;
  bool _isHoveringVol = false;
  Color? _localDominantColor;
  late VoidCallback _useDominantColorsListener;

  @override
  void initState() {
    super.initState();
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
    _localDominantColor = widget.dominantColor;
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

  Future<void> _updateDominantColor() async {
    final color = await _getDominantColor(widget.song);
    if (mounted) {
      setState(() {
        _localDominantColor = color;
      });
    }
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
      if (pos >= widget.song.duration.inSeconds - 0.0) {
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

    try {
      if (widget.song.path.contains('cdda://') ||
          widget.songList[newIndex].path.contains('cdda://')) {
        await rust_api.stopSong();
        await rust_api.playSong(path: widget.songList[newIndex].path);
      } else {
        await rust_api.switchToPreloadedNow();
        if (newIndex + 1 < widget.songList.length) {
          final nextNextSong = widget.songList[newIndex + 1];
          if (!nextNextSong.path.contains('cdda://')) {
            await rust_api.preloadNextSong(path: nextNextSong.path);
          }
        }
      }
      // Add delay to ensure backend has processed the change
      await Future.delayed(Duration(milliseconds: 100));

      Color newColor = await _getDominantColor(widget.songList[newIndex]);
      widget.onUpdate(widget.songList[newIndex], newIndex, newColor);
      widget.service.updatePlaylist(widget.songList, newIndex);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(AdiSnackbar(content: "Error skipping song $e"));
    }
  }

  Future<Color> _getDominantColor(Song song) async {
    final bool useDom = useDominantColorsNotifier.value;
    if (song.albumArt == null || !useDom) {
      return defaultThemeColorNotifier.value;
    }

    try {
      final colorValue =
          await color_extractor.getDominantColor(data: song.albumArt!);
      return Color(colorValue ?? defaultThemeColorNotifier.value.toARGB32());
    } catch (e) {
      return defaultThemeColorNotifier.value;
    }
  }

  @override
  void didUpdateWidget(MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song != widget.song) {
      _updateDominantColor();
    }
  }

  @override
  void dispose() {
    _progressTimer.cancel();
    _playPauseController.dispose();
    _playbackStateSubscription?.cancel();
    useDominantColorsNotifier.removeListener(_useDominantColorsListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = _localDominantColor ?? widget.dominantColor;
    final textColor = effectiveColor.computeLuminance() > 0.01
        ? effectiveColor
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
        surfaceTintColor: effectiveColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: effectiveColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                effectiveColor.withValues(alpha: 0.15),
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
                            color: effectiveColor.withValues(alpha: 0.3),
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
                                Broken.adiman,
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
		      Hero(
      		        tag: 'title-${widget.song.path}',
      		        flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
      		          return AnimatedBuilder(
      		            animation: animation,
      		            builder: (context, child) {
      		              return Transform.translate(
      		                offset: Offset(0, -20 * (1 - animation.value)),
      		                child: Opacity(
      		                  opacity: Tween<double>(begin: 0.0, end: 1.0)
      		                      .animate(CurvedAnimation(
      		                        parent: animation,
      		                        curve: Interval(0.5, 1.0),
      		                      ))
      		                      .value,
      		                  child: child,
      		                ),
      		              );
      		            },
      		            child: Material(
      		              color: Colors.transparent,
      		              child: GlowText(
      		                widget.song.title,
      		                glowColor: effectiveColor.withValues(alpha: 0.2),
      		                style: TextStyle(
      		                  color: textColor,
      		                  fontWeight: FontWeight.w600,
      		                  fontSize: 14,
      		                ),
      		                maxLines: 1,
      		                overflow: TextOverflow.ellipsis,
      		              ),
      		            ),
      		          );
      		        },
      		        child: Material(
      		          color: Colors.transparent,
      		          child: GlowText(
      		            widget.song.title,
      		            glowColor: effectiveColor.withValues(alpha: 0.2),
      		            style: TextStyle(
      		              color: textColor,
      		              fontWeight: FontWeight.w600,
      		              fontSize: 14,
      		            ),
      		            maxLines: 1,
      		            overflow: TextOverflow.ellipsis,
      		          ),
      		        ),
      		      ),
      		      const SizedBox(height: 4),
      		      Hero(
      		        tag: 'artist-${widget.song.path}',
      		        flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
      		          return AnimatedBuilder(
      		            animation: animation,
      		            builder: (context, child) {
      		              return Transform.translate(
      		                offset: Offset(0, -20 * (1 - animation.value)),
      		                child: Opacity(
      		                  opacity: Tween<double>(begin: 0.0, end: 1.0)
      		                      .animate(CurvedAnimation(
      		                        parent: animation,
      		                        curve: Interval(0.6, 1.0),
      		                      ))
      		                      .value,
      		                  child: child,
      		                ),
      		              );
      		            },
      		            child: Material(
      		              color: Colors.transparent,
      		              child: Text(
      		                widget.song.artist,
      		                style: TextStyle(
      		                  color: textColor.withValues(alpha: 0.8),
      		                  fontSize: 12,
      		                ),
      		                maxLines: 1,
      		                overflow: TextOverflow.ellipsis,
      		              ),
      		            ),
      		          );
      		        },
      		        child: Material(
      		          color: Colors.transparent,
      		          child: Text(
      		            widget.song.artist,
      		            style: TextStyle(
      		              color: textColor!.withValues(alpha: 0.8),
      		              fontSize: 12,
      		            ),
      		            maxLines: 1,
      		            overflow: TextOverflow.ellipsis,
      		          ),
      		        ),
      		      ),
                    ],
                  ),
                ),
                ValueListenableBuilder<double>(
                  valueListenable: VolumeController().volume,
                  builder: (context, volume, _) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _isHoveringVol = true),
                        onExit: (_) => setState(() => _isHoveringVol = false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                          width: _isHoveringVol ? 150 : 40,
                          child: Row(
                            children: [
                              Hero(
                                tag: 'volume-${widget.song.path}',
                                child: VolumeIcon(
                                  volume: _volume,
                                  dominantColor: effectiveColor,
                                ),
                              ),
                              if (_isHoveringVol) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AdaptiveSlider(
                                    dominantColor: effectiveColor,
                                    value: _volume,
                                    onChanged: (newVolume) async {
                                      await VolumeController()
                                          .setVolume(newVolume);
                                      setState(() => _volume = newVolume);
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
                    );
                  },
                ),
                const SizedBox(width: 3),
                Hero(
                  tag: 'controls-prev',
                  child: Material(
                    color: effectiveColor.withValues(alpha: 0.2),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: GlowIcon(
                        Broken.previous,
                        color: textColor,
                        glowColor: effectiveColor.withValues(alpha: 0.3),
                      ),
                      onPressed: widget.currentIndex > 0
                          ? () => _handleSkip(false)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Hero(
                  tag: 'controls-playPause',
                  child: Material(
                    color: effectiveColor.withValues(alpha: 0.2),
                    shape: const CircleBorder(),
                    child: ParticlePlayButton(
                      isPlaying: isPlaying,
                      color: effectiveColor,
                      onPressed: _togglePlayPause,
                      miniP: true,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Hero(
                  tag: 'controls-next',
                  child: Material(
                    color: effectiveColor.withValues(alpha: 0.2),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: GlowIcon(
                        Broken.next,
                        color: textColor,
                        glowColor: effectiveColor.withValues(alpha: 0.3),
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
