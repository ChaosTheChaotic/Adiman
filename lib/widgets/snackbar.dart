import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'broken_icons.dart';

class AdiSnackbar extends SnackBar {
  AdiSnackbar({
    super.key,
    required String content,
    Color? backgroundColor,
  }) : super(
          content: _AdiSnackbarContent(content: content),
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

class _AdiSnackbarContent extends StatefulWidget {
  final String content;

  const _AdiSnackbarContent({required this.content});

  @override
  _AdiSnackbarContentState createState() => _AdiSnackbarContentState();
}

class _AdiSnackbarContentState extends State<_AdiSnackbarContent>
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
              colorScheme.primary.withValues(alpha: 0.15),
              Colors.black.withValues(alpha: 0.3),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            GlowIcon(Broken.info_circle),
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
                icon: GlowIcon(Broken.cross))
          ],
        ),
      ),
    );
  }
}
