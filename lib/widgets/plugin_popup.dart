import 'dart:ui' as ui;
import 'package:adiman/src/rust/api/plugin_man.dart' as plugin_api;
import 'package:flutter/material.dart';
import 'package:adiman/widgets/misc.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'package:adiman/icons/broken_icons.dart';
import 'package:adiman/screens/plugin_template_screen.dart';

class PluginPopupDialog extends StatefulWidget {
  final String pluginPath;
  final Map<String, dynamic> popup;
  final Color dominantColor;

  const PluginPopupDialog({
    super.key,
    required this.pluginPath,
    required this.popup,
    required this.dominantColor,
  });

  @override
  State<PluginPopupDialog> createState() => _PluginPopupDialogState();
}

class _PluginPopupDialogState extends State<PluginPopupDialog> {
  @override
  Widget build(BuildContext context) {
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
                  widget.dominantColor.withAlpha(30),
                  Colors.black.withAlpha(200),
                ],
              ),
              border: Border.all(
                color: widget.dominantColor.withAlpha(100),
                width: 1.2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _buildPopupContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPopupContent() {
    final popup = widget.popup;
    final children = <Widget>[];

    // Add title if exists
    if (popup['title'] != null) {
      children.addAll([
        GlowText(
          popup['title']!,
          glowColor: widget.dominantColor.withAlpha(80),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: widget.dominantColor.computeLuminance() > 0.01
                ? widget.dominantColor
                : Colors.white,
          ),
        ),
        const SizedBox(height: 20),
      ]);
    }

    // Add labels
    if (popup['labels'] != null) {
      for (final label in popup['labels']) {
        children.add(_buildLabel(label));
        children.add(const SizedBox(height: 8));
      }
    }

    // Add buttons
    if (popup['buttons'] != null) {
      for (final button in popup['buttons']) {
        children.add(_buildButton(button));
        children.add(const SizedBox(height: 12));
      }
    }

    return children;
  }

  Widget _buildLabel(Map<String, dynamic> label) {
    return Text(
      label['text'] ?? '',
      style: TextStyle(
        color: Colors.white,
        fontSize: (label['size'] ?? 14.0).toDouble(),
        fontWeight: FontWeight.w400,
      ),
    );
  }

  Widget _buildButton(Map<String, dynamic> button) {
    return Material(
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
    );
  }

  Widget _buildButtonIcon(String? iconName) {
    IconData getIconFromName(String? iconName) {
      if (iconName == null) return Broken.cpu;
      
      final iconMap = {
        'settings': Broken.setting_2,
        'playlist': Broken.music_playlist,
        'download': Broken.document_download,
        'cd': Broken.cd,
        'info': Broken.info_circle,
        'search': Broken.search_normal,
        'shuffle': Broken.shuffle,
        'sort': Broken.sort,
        'add': Broken.add,
        'delete': Broken.trash,
        'edit': Broken.edit,
      };
      
      return iconMap[iconName] ?? Broken.cpu;
    }

    return GlowIcon(
      getIconFromName(iconName),
      color: widget.dominantColor.computeLuminance() > 0.01
          ? widget.dominantColor
          : Colors.white,
      blurRadius: 8,
      size: 24,
    );
  }

  void _handleButtonCallback(Map<String, dynamic> button) {
    final callback = button['callback'];
    if (callback.startsWith("rf_")) {
      final func = callback.substring(3);
      plugin_api.callPluginFunc(func: func, plugin: widget.pluginPath);
      Navigator.pop(context); // Close popup after action
    } else if (callback.startsWith("scr_")) {
      final screenName = callback.substring(4);
      Navigator.pop(context); // Close popup first
      _showPluginScreen(widget.pluginPath, screenName, button);
    } else if (callback.startsWith("pop_")) {
      final popupName = callback.substring(4);
      Navigator.pop(context); // Close current popup first
      _showPluginPopup(widget.pluginPath, popupName, button);
    } else {
      Navigator.pop(context); // Close popup for unknown callback types
    }
  }

  void _showPluginScreen(String pluginPath, String screenName, Map<String, dynamic> button) {
    // Navigate to screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PluginScreen(
          pluginPath: pluginPath,
          screen: {}, // You'd need to fetch the actual screen data here
          dominantColor: widget.dominantColor,
        ),
      ),
    );
  }

  void _showPluginPopup(String pluginPath, String popupName, Map<String, dynamic> button) {
    // Show new popup - similar to _showPluginPopup in SongSelectionScreen
    // You might want to refactor this to avoid code duplication
  }
}
