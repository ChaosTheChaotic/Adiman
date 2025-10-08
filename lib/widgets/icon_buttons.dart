import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_glow/flutter_glow.dart';
import 'broken_icons.dart';

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
        color: Colors.white,
        onPressed: onPressed,
      ),
    );
  }
}

class ParticlePlayButton extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final VoidCallback onPressed;
  final bool miniP;

  const ParticlePlayButton({
    super.key,
    required this.isPlaying,
    required this.color,
    required this.onPressed,
    this.miniP = false,
  });

  @override
  State<ParticlePlayButton> createState() => _ParticlePlayButtonState();
}

class _ParticlePlayButtonState extends State<ParticlePlayButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    // Start with the appropriate state
    if (widget.isPlaying) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void didUpdateWidget(ParticlePlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.miniP
        ? SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedOpacity(
                  opacity: widget.isPlaying ? 0.3 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          widget.color.withValues(alpha: 0.5),
                          widget.color.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                  ),
                ),
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: IconButton(
                    icon: GlowIcon(
                      widget.isPlaying ? Broken.pause : Broken.play,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      glowColor: widget.color.withValues(alpha: 0.3),
                      size: 48 * 0.6,
                    ),
                    onPressed: widget.onPressed,
                    padding: EdgeInsets.zero,
                    iconSize: 48 * 0.6,
                  ),
                ),
              ],
            ),
          )
        : Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: widget.isPlaying ? 0.3 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.color.withValues(alpha: 0.5),
                        widget.color.withValues(alpha: 0.1),
                      ],
                    ),
                  ),
                ),
              ),
              ScaleTransition(
                scale: _scaleAnimation,
                child: DynamicIconButton(
                  icon: widget.isPlaying ? Broken.pause : Broken.play,
                  onPressed: widget.onPressed,
                  backgroundColor: widget.color,
                  size: 64,
                ),
              ),
            ],
          );
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
