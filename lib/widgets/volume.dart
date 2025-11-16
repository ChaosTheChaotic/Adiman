import 'dart:async';
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:flutter/material.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'package:adiman/icons/broken_icons.dart';

class VolumeIcon extends StatelessWidget {
  final double volume;
  final Color dominantColor;

  const VolumeIcon({
    super.key,
    required this.volume,
    required this.dominantColor,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    if (volume <= 0) {
      icon = Broken.volume_slash;
    } else if (volume < 0.3) {
      icon = Broken.volume_low;
    } else if (volume < 0.7) {
      icon = Broken.volume_mute;
    } else {
      icon = Broken.volume_high;
    }

    return GestureDetector(
      child: GlowIcon(
        icon,
        color: dominantColor.computeLuminance() > 0.01
            ? dominantColor
            : Theme.of(context).textTheme.bodyLarge?.color,
        glowColor: dominantColor.withValues(alpha: 0.3),
      ),
    );
  }
}

class VolumeController {
  static final VolumeController _instance = VolumeController._internal();
  factory VolumeController() => _instance;
  VolumeController._internal() {
    _init();
  }

  final ValueNotifier<double> volume = ValueNotifier(1.0);

  Future<void> _init() async {
    volume.value = await rust_api.getCvol();
  }

  Future<void> setVolume(double value) async {
    await rust_api.setVolume(volume: value);
    volume.value = value;
  }
}
