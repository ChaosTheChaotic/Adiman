import 'dart:convert';
import 'package:adiman/src/rust/api/plugin_man.dart' as plugin_api;
import 'snackbar.dart';
import 'package:flutter/material.dart';
import 'package:adiman/icons/broken_icons.dart';
import 'package:adiman/screens/plugin_template_screen.dart';
import 'package:adiman/widgets/plugin_popup.dart';

class PluginService {
  static IconData getIconFromName(String? iconName) {
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
      'arrow_right': Broken.arrow_right,
      'arrow_left': Broken.arrow_left,
      'arrow_up': Broken.arrow_up,
      'arrow_down': Broken.arrow_down,
    };
    
    return iconMap[iconName] ?? Broken.cpu;
  }

  static String getScreenTitle(Map<String, dynamic> screen) {
    return screen['title'] ?? 'Plugin Screen';
  }
  
  static String getPopupTitle(Map<String, dynamic> popup) {
    return popup['title'] ?? 'Plugin Popup';
  }

  static void handleButtonCallback({
    required BuildContext context,
    required String callback,
    required String pluginPath,
    required Color dominantColor,
    Map<String, dynamic>? button,
  }) {
    if (callback.startsWith("rf_")) {
      final func = callback.substring(3);
      plugin_api.callPluginFunc(func: func, plugin: pluginPath);
    } else if (callback.startsWith("scr_")) {
      final screenName = callback.substring(4);
      showPluginScreen(context, pluginPath, screenName, dominantColor);
    } else if (callback.startsWith("pop_")) {
      final popupName = callback.substring(4);
      showPluginPopup(context, pluginPath, popupName, dominantColor, button);
    }
  }

  static Future<void> showPluginScreen(
    BuildContext context,
    String pluginPath,
    String screenName,
    Color dominantColor,
  ) async {
    try {
      final screensJson = await plugin_api.getAllScreens();
      final List<dynamic> decoded = jsonDecode(screensJson);
      
      // Find the screen for this plugin
      final screenData = decoded.firstWhere(
        (item) => item[0] == pluginPath && getScreenTitle(item[1]) == screenName,
        orElse: () => null,
      );
      
      if (screenData != null) {
        final screen = screenData[1];
        navigateToPluginScreen(context, pluginPath, screen, dominantColor);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          AdiSnackbar(content: 'Screen "$screenName" not found in plugin'),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(content: 'Error loading plugin screen: $e'),
      );
    }
  }

  static Future<void> showPluginPopup(
    BuildContext context,
    String pluginPath,
    String popupName,
    Color dominantColor,
    Map<String, dynamic>? button,
  ) async {
    try {
      final popupsJson = await plugin_api.getAllPopups();
      final List<dynamic> decoded = jsonDecode(popupsJson);
      
      // Find the popup for this plugin
      final popupData = decoded.firstWhere(
        (item) => item[0] == pluginPath && getPopupTitle(item[1]) == popupName,
        orElse: () => null,
      );
      
      if (popupData != null) {
        final popup = popupData[1];
        showPluginPopupDialog(context, pluginPath, popup, dominantColor);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          AdiSnackbar(content: 'Popup "$popupName" not found in plugin'),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(content: 'Error loading plugin popup: $e'),
      );
    }
  }

  static void navigateToPluginScreen(
    BuildContext context,
    String pluginPath,
    Map<String, dynamic> screen,
    Color dominantColor,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PluginScreen(
          pluginPath: pluginPath,
          screen: screen,
          dominantColor: dominantColor,
        ),
      ),
    );
  }

  static void showPluginPopupDialog(
    BuildContext context,
    String pluginPath,
    Map<String, dynamic> popup,
    Color dominantColor,
  ) {
    showDialog(
      context: context,
      builder: (context) => PluginPopupDialog(
        pluginPath: pluginPath,
        popup: popup,
        dominantColor: dominantColor,
      ),
    );
  }

  static Future<List<Map<String, dynamic>>> getPluginButtons({
    String? locationFilter,
  }) async {
    try {
      final buttonsJson = await plugin_api.getAllButtons(locationFilter: locationFilter);
      final List<dynamic> decoded = jsonDecode(buttonsJson);
      return decoded.map((item) {
        return {
          'pluginPath': item[0],
          'button': item[1],
        };
      }).toList();
    } catch (e) {
      print('Error loading plugin buttons: $e');
      return [];
    }
  }
}
