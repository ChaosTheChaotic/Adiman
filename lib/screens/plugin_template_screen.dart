import 'package:flutter/material.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'package:adiman/icons/broken_icons.dart';
import 'package:adiman/widgets/plugin_service.dart';

class PluginScreen extends StatefulWidget {
  final String pluginPath;
  final Map<String, dynamic> screen;
  final Color dominantColor;

  const PluginScreen({
    super.key,
    required this.pluginPath,
    required this.screen,
    required this.dominantColor,
  });

  @override
  State<PluginScreen> createState() => _PluginScreenState();
}

class _PluginScreenState extends State<PluginScreen> {
  @override
  Widget build(BuildContext context) {
    final textColor = widget.dominantColor.computeLuminance() > 0.01
        ? widget.dominantColor
        : Colors.white;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: GlowText(
          widget.screen['title'] ?? 'Plugin Screen',
          glowColor: widget.dominantColor.withAlpha(80),
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: Icon(Broken.arrow_left, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              widget.dominantColor.withAlpha(50),
            ],
          ),
        ),
        child: _buildScreenContent(),
      ),
    );
  }

  Widget _buildScreenContent() {
    final screen = widget.screen;
    final children = <Widget>[];

    if (screen['labels'] != null) {
      for (final label in screen['labels']) {
        children.add(_buildLabel(label));
      }
    }

    if (screen['buttons'] != null) {
      for (final button in screen['buttons']) {
        children.add(_buildButton(button));
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }

  Widget _buildLabel(Map<String, dynamic> label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        label['text'] ?? '',
        style: TextStyle(
          color: Colors.white,
          fontSize: (label['size'] ?? 16.0).toDouble(),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildButton(Map<String, dynamic> button) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: () => _handleButtonCallback(button),
          borderRadius: BorderRadius.circular(15),
          splashColor: widget.dominantColor.withAlpha(50),
          highlightColor: widget.dominantColor.withAlpha(30),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: widget.dominantColor.withAlpha(100),
                width: 1.2,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.dominantColor.withAlpha(30),
                  Colors.black.withAlpha(100),
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (button['icon'] != null) ...[
                  _buildButtonIcon(button['icon']),
                  const SizedBox(width: 16),
                ],
                Expanded(
                  child: Text(
                    button['name'] ?? 'Button',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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

  Widget _buildButtonIcon(String? iconName) {
    return GlowIcon(
      PluginService.getIconFromName(iconName),
      color: widget.dominantColor.computeLuminance() > 0.01
          ? widget.dominantColor
          : Colors.white,
      blurRadius: 8,
      size: 24,
    );
  }

  void _handleButtonCallback(Map<String, dynamic> button) {
    PluginService.handleButtonCallback(
      context: context,
      callback: button['callback'],
      pluginPath: widget.pluginPath,
      dominantColor: widget.dominantColor,
      button: button,
    );
  }
}
