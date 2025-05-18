import 'package:flutter/material.dart';
import 'dart:convert';
import 'main.dart';
import 'package:lrc/lrc.dart' as lrc_pkg;
import 'dart:ui' as ui;
import 'package:flutter_glow/flutter_glow.dart';

class NamidaTheme {
  static ThemeData dynamicTheme(Color dominantColor) {
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
}

class WaveformSeekBar extends StatefulWidget {
  final List<double> waveformData;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final Function(double) onSeek;

  const WaveformSeekBar({
    super.key,
    required this.waveformData,
    required this.progress,
    this.activeColor = const Color(0xFF383770),
    this.inactiveColor = Colors.grey,
    required this.onSeek,
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);
    if (widget.waveformData.isNotEmpty) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(WaveformSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.waveformData != oldWidget.waveformData &&
        widget.waveformData.isNotEmpty) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);
        final progress = localPosition.dx / box.size.width;
        widget.onSeek(progress.clamp(0.0, 1.0));
      },
      child: CustomPaint(
        painter: _WaveformPainter(
          waveformData: widget.waveformData,
          progress: widget.progress,
          activeColor: widget.activeColor,
          inactiveColor: widget.inactiveColor,
          animationValue: _animation.value,
        ),
        size: const Size(double.infinity, 50),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double animationValue;

  _WaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final barWidth = size.width / waveformData.length;
    final progressIndex = (waveformData.length * progress).round();

    for (var i = 0; i < waveformData.length; i++) {
      final height =
          size.height * (waveformData[i] * 0.8 + 0.2) * animationValue;
      final yPos = (size.height - height) / 2;

      paint.color = i < progressIndex ? activeColor : inactiveColor;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * barWidth,
            yPos,
            barWidth * 0.6,
            height,
          ),
          Radius.circular(barWidth * 0.3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.waveformData != waveformData ||
        oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.animationValue != animationValue;
  }
}

class NamidaThumbnail extends StatefulWidget {
  final ImageProvider image;
  final bool isPlaying;
  final bool showBreathingEffect;
  final double currentPeak;
  final double? sharedBreathingValue;
  final String? heroTag;

  const NamidaThumbnail({
    super.key,
    required this.image,
    required this.isPlaying,
    this.showBreathingEffect = true,
    this.currentPeak = 0.0,
    this.sharedBreathingValue,
    this.heroTag,
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

    return AnimatedBuilder(
        animation: Listenable.merge([_breathingController, _peakController]),
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return Transform.scale(
                scale: breathingValue + (peakValue - 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white
                            .withAlpha((breathingValue * 70).toInt()),
                        spreadRadius: breathingValue * 6,
                        blurRadius: 30,
                        blurStyle: BlurStyle.outer,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image(
                      image: widget.image,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              );
            },
          );
        });
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
    );

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
                                      _AlbumArtWithPlayCount(
                                        image: widget.song.albumArt != null
                                            ? MemoryImage(base64Decode(
                                                widget.song.albumArt!))
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
                                            Icons.check_rounded,
                                            color: widget.dominantColor,
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
                              Icons.graphic_eq_rounded,
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
  }

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }
}

class _AlbumArtWithPlayCount extends StatelessWidget {
  final ImageProvider? image;

  const _AlbumArtWithPlayCount({
    required this.image,
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
            image: image != null
                ? DecorationImage(
                    image: image!,
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: image == null
              ? const Icon(Icons.music_note, color: Colors.white, size: 32)
              : null,
        ),
      ],
    );
  }
}

class DynamicIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final double size;

  const DynamicIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.backgroundColor,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon),
        color: backgroundColor.computeLuminance() > 0.5
            ? Colors.black
            : Colors.white,
        onPressed: onPressed,
      ),
    );
  }
}

class ParticlePlayButton extends StatelessWidget {
  final bool isPlaying;
  final Color color;
  final VoidCallback onPressed;

  const ParticlePlayButton({
    super.key,
    required this.isPlaying,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: isPlaying ? 0.3 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.5),
                  color.withValues(alpha: 0.1),
                ],
              ),
            ),
          ),
        ),
        DynamicIconButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          onPressed: onPressed,
          backgroundColor: color,
          size: 64,
        ),
      ],
    );
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

  const LyricsOverlay({
    super.key,
    required this.lrc,
    required this.currentPosition,
    required this.dominantColor,
    required this.isPlaying,
    this.scale = 1.0,
    this.currentPeak = 0.0,
    this.sharedBreathingValue,
    this.onLyricTap,
  });

  @override
  State<LyricsOverlay> createState() => _LyricsOverlayState();
}

class _LyricsOverlayState extends State<LyricsOverlay>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _currentLyricNotifier = ValueNotifier<int>(-1);
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
    _currentLyricNotifier.addListener(_scrollToCurrentLyric);
    _updateCurrentLyric();
  }

  void _scrollToCurrentLyric() {
    final index = _currentLyricNotifier.value;
    if (index >= 0) {
      final scrollPosition =
          index * 45.0; // I need a better way of calculating this
      _scrollController.animateTo(
        scrollPosition.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutQuint,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant LyricsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCurrentLyric();
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

  void _updateCurrentLyric() {
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
  Widget build(BuildContext context) {
    final breathingValue =
        widget.sharedBreathingValue ?? _breathingAnimation.value;
    final peakValue = _peakAnimation.value;

    return AnimatedBuilder(
        animation: Listenable.merge([_breathingController, _peakController]),
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              return Transform.scale(
                scale: breathingValue + (peakValue - 1.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (details) {
                      if (widget.lrc.lyrics.isEmpty) return;
                      final box = context.findRenderObject() as RenderBox;
                      final localPosition =
                          box.globalToLocal(details.globalPosition);
                      final lyricIndex = (localPosition.dy ~/ 65)
                          .clamp(0, widget.lrc.lyrics.length - 1);
                      widget.onLyricTap
                          ?.call(widget.lrc.lyrics[lyricIndex].timestamp);
                    },
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: Container(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        decoration:
                            const BoxDecoration(color: Colors.transparent),
                        child: ValueListenableBuilder<int>(
                          valueListenable: _currentLyricNotifier,
                          builder: (context, currentIndex, _) {
                            return ListView.builder(
                              controller: _scrollController,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: widget.lrc.lyrics.length,
                              itemBuilder: (context, index) {
                                final lyric = widget.lrc.lyrics[index];
                                final isCurrent = index == currentIndex;
                                final textColor = isCurrent
                                    ? widget.dominantColor
                                    : (widget.dominantColor.computeLuminance() >
                                                0.3
                                            ? Colors.black
                                            : Colors.white)
                                        .withValues(alpha: 0.6);
                                return InkWell(
                                  onTap: () =>
                                      widget.onLyricTap?.call(lyric.timestamp),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: AnimatedDefaultTextStyle(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                      style: TextStyle(
                                        fontSize: isCurrent ? 28 : 20,
                                        color: textColor,
                                        fontWeight: isCurrent
                                            ? FontWeight.w800
                                            : FontWeight.normal,
                                        shadows: isCurrent
                                            ? [
                                                Shadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.5),
                                                  blurRadius: 15,
                                                )
                                              ]
                                            : null,
                                      ),
                                      child: GlowText(
                                        lyric.lyrics,
                                        textAlign: TextAlign.center,
                                        glowColor: isCurrent
                                            ? (widget.dominantColor
                                                        .withValues(alpha: 0.3)
                                                        .computeLuminance() >
                                                    0.3
                                                ? Colors.black
                                                : Colors.white)
                                            : Colors.transparent,
                                        blurRadius: 15,
                                        style: TextStyle(
                                          shadows: [
                                            Shadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.7),
                                              blurRadius: 0,
                                              offset: Offset(1, 1),
                                            ),
                                          ],
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
              );
            },
          );
        });
  }

  @override
  void dispose() {
    _currentLyricNotifier.dispose();
    super.dispose();
  }
}

class NamidaPageTransitions {
  static Route createRoute(Widget page, {Color? dominantColor}) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final color = dominantColor ?? Theme.of(context).colorScheme.primary;

        return Stack(
          children: [
            // Blurred background
            BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: 30 * animation.value,
                sigmaY: 30 * animation.value,
              ),
              child: Container(color: Colors.transparent),
            ),
            // Glowing overlay
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 2.0,
                  colors: [
                    color.withValues(alpha: 0.2 * animation.value),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            // Content transition
            ScaleTransition(
              scale: Tween<double>(
                begin: 0.95,
                end: 1.0,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.05),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  static Route createMaterialRoute(Widget page) {
    return MaterialPageRoute(
      builder: (context) => page,
      fullscreenDialog: true,
    );
  }

  static Route createRadialRevealRoute(Widget page, Offset origin,
      {Color? color}) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.fastOutSlowIn,
        );

        return Stack(
          children: [
            Positioned.fill(
              child: ClipPath(
                clipper: _CircleRevealClipper(
                  fraction: curvedAnimation.value,
                  origin: origin,
                ),
                child: child,
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: 30 * animation.value,
                  sigmaY: 30 * animation.value,
                ),
                child: Container(
                  color: Colors.black
                      .withValues(alpha: 0.3 * (1 - animation.value)),
                ),
              ),
            ),
          ],
        );
      },
      transitionDuration: const Duration(milliseconds: 800),
    );
  }
}

class _CircleRevealClipper extends CustomClipper<Path> {
  final double fraction;
  final Offset origin;

  const _CircleRevealClipper({required this.fraction, required this.origin});

  @override
  Path getClip(Size size) {
    final center = origin;
    final radius = size.longestSide * fraction;
    return Path()..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
}

class DownloadProgressCard extends StatelessWidget {
  final double progress;
  final Color color;

  const DownloadProgressCard({
    super.key,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: color.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: progress,
              color: color,
              strokeWidth: 3,
            ),
            const SizedBox(height: 12),
            GlowText(
              'Downloading... ${(progress * 100).toStringAsFixed(1)}%',
              glowColor: color,
              style: TextStyle(
                color: color,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NamidaTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final IconData prefixIcon;
  final Widget? suffix;
  final Function(String)? onSubmitted;

  const NamidaTextField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
    required this.prefixIcon,
    this.suffix,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withAlpha(30),
            Colors.black.withAlpha(100),
          ],
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: TextStyle(color: Colors.white),
        cursorColor: Theme.of(context).colorScheme.primary,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.white70),
          prefixIcon: GlowIcon(
            prefixIcon,
            color: Theme.of(context).colorScheme.primary,
            blurRadius: 8,
          ),
          suffixIcon: suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        onSubmitted: onSubmitted,
      ),
    );
  }
}

class NamidaSnackbar extends SnackBar {
  NamidaSnackbar({
    Key? key,
    required String content,
    Color? backgroundColor,
  }) : super(
          key: key,
          content: _NamidaSnackbarContent(content: content),
          backgroundColor:
              backgroundColor?.withValues(alpha: 0.3) ?? Colors.transparent,
          elevation: 4,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          margin: EdgeInsets.all(20),
          padding: EdgeInsets.zero,
          duration: const Duration(seconds: 3),
        );
}

class _NamidaSnackbarContent extends StatefulWidget {
  final String content;

  const _NamidaSnackbarContent({required this.content});

  @override
  _NamidaSnackbarContentState createState() => _NamidaSnackbarContentState();
}

class _NamidaSnackbarContentState extends State<_NamidaSnackbarContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward().then((_) {
      Future.delayed(const Duration(seconds: 1), _closeSnackbar);
    });
  }

  void _closeSnackbar() {
    if (mounted && _controller.status != AnimationStatus.dismissed) {
      _controller.reverse().then((_) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withOpacity(0.15),
              Colors.black.withOpacity(0.3),
            ],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            GlowIcon(Icons.info),
            const SizedBox(width: 12),
            GlowText(
              widget.content,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            Expanded(child: Container()),
            IconButton(
                onPressed: () {
                  _closeSnackbar();
                },
                icon: GlowIcon(Icons.close))
          ],
        ),
      ),
    );
  }
}
