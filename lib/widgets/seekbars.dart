import 'dart:math' as math;
import 'package:flutter/material.dart';

class WaveformSeekBar extends StatefulWidget {
  final List<double> waveformData;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final Function(double) onSeek;
  final Function(double)? onSeekStart;
  final Function(double)? onSeekEnd;

  const WaveformSeekBar({
    super.key,
    required this.waveformData,
    required this.progress,
    this.activeColor = const Color(0xFF383770),
    this.inactiveColor = Colors.grey,
    required this.onSeek,
    this.onSeekStart,
    this.onSeekEnd,
  });

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isDragging = false;
  double _dragProgress = 0.0;

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

  void _handleDragStart(double progress) {
    setState(() {
      _isDragging = true;
      _dragProgress = progress;
    });
    widget.onSeekStart?.call(progress);
  }

  void _handleDragUpdate(double progress) {
    setState(() {
      _dragProgress = progress;
    });
    widget.onSeek(progress);
  }

  void _handleDragEnd(double progress) {
    setState(() {
      _isDragging = false;
    });
    widget.onSeekEnd?.call(progress);
    widget.onSeek(progress);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentProgress = _isDragging ? _dragProgress : widget.progress;

    return GestureDetector(
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);
        final progress = localPosition.dx / box.size.width;
        _handleDragStart(progress);
        _handleDragEnd(progress);
      },
      onPanStart: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);
        final progress = localPosition.dx / box.size.width;
        _handleDragStart(progress);
      },
      onPanUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final localPosition = box.globalToLocal(details.globalPosition);
        final progress = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
        _handleDragUpdate(progress);
      },
      onPanEnd: (details) {
        _handleDragEnd(_dragProgress);
      },
      onPanCancel: () {
        _handleDragEnd(_dragProgress);
      },
      child: CustomPaint(
        painter: _WaveformPainter(
          waveformData: widget.waveformData,
          progress: currentProgress,
          activeColor: widget.activeColor,
          inactiveColor: widget.inactiveColor,
          animationValue: _animation.value,
          isDragging: _isDragging,
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
  final bool isDragging;

  _WaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.animationValue,
    this.isDragging = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    // Calculate luminance to determine if we need enhancements
    final luminance = activeColor.computeLuminance();
    final needsEnhancement = luminance < 0.01;

    // Slightly lighten active color if too dark
    final enhancedActiveColor = needsEnhancement
        ? HSLColor.fromColor(activeColor).withLightness(0.4).toColor()
        : activeColor;

    // Create stroke paint if needed
    final strokePaint = needsEnhancement
        ? (Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: 0.7)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round)
        : null;

    final barWidth = size.width / waveformData.length;
    final progressIndex = (waveformData.length * progress).round();

    for (var i = 0; i < waveformData.length; i++) {
      final height =
          size.height * (waveformData[i] * 0.8 + 0.2) * animationValue;
      final yPos = (size.height - height) / 2;

      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * barWidth,
          yPos,
          barWidth * 0.6,
          height,
        ),
        Radius.circular(barWidth * 0.3),
      );

      if (i < progressIndex) {
        paint.color = enhancedActiveColor;

        // Draw stroke first (if needed)
        if (needsEnhancement) {
          canvas.drawRRect(barRect, strokePaint!);
        }

        // Draw filled bar
        canvas.drawRRect(barRect, paint);
      } else {
        paint.color = inactiveColor;
        canvas.drawRRect(barRect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.waveformData != waveformData ||
        oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.isDragging != isDragging;
  }
}

class BreathingWaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double breathingValue;
  final double currentPeak;
  final bool isHovering;
  final double hoverX;
  final bool isPlaying;

  BreathingWaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.breathingValue,
    required this.currentPeak,
    required this.isHovering,
    required this.hoverX,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    final centerY = size.height / 2;
    final barCount = waveformData.length;
    final barWidth = size.width / barCount;
    final barSpacing = barWidth * 0.2;
    final actualBarWidth = barWidth - barSpacing;

    const minBarHeight = 2.0;
    final maxBarHeight = size.height * 0.35;

    // Calculate the range of bars that should be "active" based on current progress
    final activeStart = (progress - 0.1).clamp(0.0, 1.0);
    final activeEnd = (progress + 0.1).clamp(0.0, 1.0);

    for (int i = 0; i < barCount; i++) {
      final x = i * barWidth + barSpacing / 2;
      final waveformValue = waveformData[i];
      final barProgress = i / barCount;

      final isActive = barProgress >= activeStart && barProgress <= activeEnd;
      final distanceFromProgress = (barProgress - progress).abs();

      double barHeight = minBarHeight;

      if (isPlaying) {
        // Emphasize bars near current progress
        final proximityFactor =
            1.0 - (distanceFromProgress * 5).clamp(0.0, 1.0);
        final breathingFactor = 0.3 + (breathingValue * 0.7);

        barHeight +=
            (waveformValue * maxBarHeight * breathingFactor * proximityFactor) +
                (currentPeak * maxBarHeight * 0.3 * proximityFactor);
      } else {
        // Static waveform when paused
        barHeight += waveformValue * maxBarHeight * 0.2;
      }

      // Hover effect
      if (isHovering) {
        final distanceFromHover = (x - hoverX).abs();
        if (distanceFromHover < 50) {
          final hoverFactor = 1.0 - (distanceFromHover / 50);
          barHeight *= (1.0 + hoverFactor * 0.3);
        }
      }

      barHeight = math.max(minBarHeight, barHeight);

      // Determine color based on activity
      final color = isActive ? activeColor : inactiveColor;
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.3),
            color.withValues(alpha: 0.8),
            color.withValues(alpha: 0.8),
            color.withValues(alpha: 0.3),
          ],
          stops: const [0.0, 0.4, 0.6, 1.0],
        ).createShader(Rect.fromLTWH(
            x, centerY - barHeight, actualBarWidth, barHeight * 2));

      // Draw bars
      final topRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, centerY - barHeight - 2, actualBarWidth, barHeight),
        const Radius.circular(1),
      );
      canvas.drawRRect(topRect, paint);

      final bottomRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, centerY + 2, actualBarWidth, barHeight),
        const Radius.circular(1),
      );
      canvas.drawRRect(bottomRect, paint);

      // Add glow for active bars
      if (isActive && isPlaying) {
        final glowPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

        canvas.drawRRect(topRect, glowPaint);
        canvas.drawRRect(bottomRect, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(BreathingWaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.breathingValue != breathingValue ||
        oldDelegate.currentPeak != currentPeak ||
        oldDelegate.isHovering != isHovering ||
        oldDelegate.hoverX != hoverX ||
        oldDelegate.isPlaying != isPlaying;
  }
}

class BreathingWaveformSeekbar extends StatefulWidget {
  final List<double> waveformData;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final Function(double) onSeek;
  final bool isPlaying;
  final double currentPeak;

  const BreathingWaveformSeekbar({
    super.key,
    required this.waveformData,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.onSeek,
    required this.isPlaying,
    required this.currentPeak,
  });

  @override
  State<BreathingWaveformSeekbar> createState() =>
      _BreathingWaveformSeekbarState();
}

class _BreathingWaveformSeekbarState extends State<BreathingWaveformSeekbar>
    with SingleTickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;
  bool _isHovering = false;
  double _localX = 0;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _breathingAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _breathingController,
      curve: Curves.easeInOut,
    ));

    if (widget.isPlaying) {
      _breathingController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(BreathingWaveformSeekbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _breathingController.repeat(reverse: true);
      } else {
        _breathingController.stop();
        _breathingController.animateTo(0.0);
      }
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      onHover: (event) => setState(() => _localX = event.localPosition.dx),
      child: GestureDetector(
        onTapDown: (details) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final localX = details.localPosition.dx;
          final progress = (localX / box.size.width).clamp(0.0, 1.0);
          widget.onSeek(progress);
        },
        onHorizontalDragUpdate: (details) {
          final RenderBox box = context.findRenderObject() as RenderBox;
          final localX = details.localPosition.dx;
          final progress = (localX / box.size.width).clamp(0.0, 1.0);
          widget.onSeek(progress);
        },
        child: AnimatedBuilder(
          animation: _breathingAnimation,
          builder: (context, child) {
            return SizedBox(
              height: 60,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Waveform bars
                  CustomPaint(
                    size: Size(double.infinity, 120),
                    painter: BreathingWaveformPainter(
                      waveformData: widget.waveformData,
                      progress: widget.progress,
                      activeColor: widget.activeColor,
                      inactiveColor: widget.inactiveColor,
                      breathingValue: _breathingAnimation.value,
                      currentPeak: widget.currentPeak,
                      isHovering: _isHovering,
                      hoverX: _localX,
                      isPlaying: widget.isPlaying,
                    ),
                  ),
                  // Seekbar track
                  Positioned(
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: widget.inactiveColor,
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: widget.progress,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              colors: [
                                widget.activeColor,
                                widget.activeColor.withValues(alpha: 0.8),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    widget.activeColor.withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Progress indicator (thumb)
                  if (_isHovering)
                    Positioned(
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment(widget.progress * 2 - 1, 0),
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.activeColor,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    widget.activeColor.withValues(alpha: 0.6),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class AdaptiveSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final Color dominantColor;

  const AdaptiveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.dominantColor,
  });

  @override
  Widget build(BuildContext context) {
    final luminance = dominantColor.computeLuminance();
    final isDark = luminance < 0.01;
    final activeColor = isDark ? Colors.white : dominantColor;
    final inactiveColor = activeColor.withValues(alpha: 0.3);

    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: SliderComponentShape.noOverlay,
        activeTrackColor: activeColor,
        inactiveTrackColor: inactiveColor,
        thumbColor: activeColor,
      ),
      child: Slider(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
