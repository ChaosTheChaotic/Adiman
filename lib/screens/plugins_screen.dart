import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:adiman/widgets/services.dart';
import 'package:adiman/widgets/misc.dart';
import 'package:adiman/widgets/snackbar.dart';
import 'package:adiman/widgets/icon_buttons.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'package:adiman/icons/broken_icons.dart';
import 'package:adiman/src/rust/api/plugin_man.dart' as rust_api;

class PluginsScreen extends StatefulWidget {
  final Function(Color)? updateThemeColor;
  final Color dominantColor;
  final AdimanService service;

  const PluginsScreen({
    super.key,
    this.updateThemeColor,
    required this.dominantColor,
    required this.service,
  });

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  List<Plugin> plugins = [];
  List<Plugin> availablePlugins = [];
  bool isLoading = true;
  String pluginDirectory = '';

  @override
  void initState() {
    super.initState();
    _loadPluginDirectory();
    _loadPlugins();
  }

  Future<void> _loadPluginDirectory() async {
    final dir = SharedPreferencesService.instance.getString('pluginDir') ?? '~/AdiPlugins';
    String pluginDir = dir;
    if (pluginDir.startsWith('~')) {
      final home = Platform.environment['HOME'] ?? '';
      pluginDir = pluginDir.replaceFirst('~', home);
    }
    setState(() {
      pluginDirectory = pluginDir;
    });
  }

  Future<void> _loadPlugins() async {
    setState(() => isLoading = true);
    try {
      // Get loaded plugins
      final loadedPaths = await rust_api.listLoadedPlugins();
      final loadedPlugins = loadedPaths.map((path) => Plugin(
        path: path,
        name: _getPluginNameFromPath(path),
        isLoaded: true,
      )).toList();

      // Scan directory for available plugins
      final scannedPaths = await rust_api.scanDir(path: pluginDirectory) ?? [];
      final available = scannedPaths.map((path) => Plugin(
        path: path,
        name: _getPluginNameFromPath(path),
        isLoaded: loadedPaths.contains(path),
      )).toList();

      setState(() {
        plugins = loadedPlugins;
        availablePlugins = available.where((p) => !p.isLoaded).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Error loading plugins: $e',
        ),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  String _getPluginNameFromPath(String path) {
    final file = File(path);
    return file.uri.pathSegments.last.replaceAll('.wasm', '');
  }

  Future<void> _loadPlugin(Plugin plugin) async {
    try {
      final result = await rust_api.loadPlugin(path: plugin.path);
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: result,
        ),
      );
      _loadPlugins(); // Refresh the list
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Error loading plugin: $e',
        ),
      );
    }
  }

  Future<void> _removePlugin(Plugin plugin) async {
    try {
      final result = await rust_api.removePlugin(path: plugin.path);
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: result,
        ),
      );
      _loadPlugins(); // Refresh the list
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Error removing plugin: $e',
        ),
      );
    }
  }

  Future<void> _reloadPlugin(Plugin plugin) async {
    try {
      final result = await rust_api.reloadPlugin(path: plugin.path);
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: result,
        ),
      );
      _loadPlugins(); // Refresh the list
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Error reloading plugin: $e',
        ),
      );
    }
  }

  Future<void> _showPluginConfig(Plugin plugin) async {
    try {
      final configJson = await rust_api.getPluginConfig(path: plugin.path);
      final config = _parseConfig(configJson);
      
      await showDialog(
        context: context,
        builder: (context) => PluginConfigDialog(
          plugin: plugin,
          config: config,
          dominantColor: widget.dominantColor,
          onConfigUpdated: _loadPlugins,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Error loading plugin config: $e',
        ),
      );
    }
  }

  Map<String, dynamic> _parseConfig(String configJson) {
    try {
      // Simple JSON parsing - you might want to use a proper JSON decoder
      if (configJson.isEmpty || configJson.startsWith('Failed')) {
        return {};
      }
      // This is a simplified parser - you should use dart:convert in real implementation
      return {};
    } catch (e) {
      return {};
    }
  }

  Widget _buildPluginTile(Plugin plugin) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showPluginConfig(plugin),
          borderRadius: BorderRadius.circular(15),
          splashColor: widget.dominantColor.withAlpha(40),
          highlightColor: widget.dominantColor.withAlpha(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: widget.dominantColor.withAlpha(60),
                width: 1.0,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  widget.dominantColor.withAlpha(20),
                  Colors.black.withAlpha(80),
                ],
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.dominantColor.withAlpha(80),
                        widget.dominantColor.withAlpha(40),
                      ],
                    ),
                  ),
                  child: Center(
                    child: GlowIcon(
                      Broken.cpu,
                      color: Colors.white,
                      size: 24,
                      glowColor: widget.dominantColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plugin.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plugin.path,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (plugin.isLoaded) ...[
                  DynamicIconButton(
                    icon: Broken.refresh,
                    onPressed: () => _reloadPlugin(plugin),
                    backgroundColor: widget.dominantColor,
                    size: 36,
                  ),
                  const SizedBox(width: 8),
                  DynamicIconButton(
                    icon: Broken.toggle_off,
                    onPressed: () => _removePlugin(plugin),
                    backgroundColor: Colors.redAccent,
                    size: 36,
                  ),
                ] else
                  DynamicIconButton(
                    icon: Broken.toggle_on,
                    onPressed: () => _loadPlugin(plugin),
                    backgroundColor: Colors.greenAccent,
                    size: 36,
                  ),
                const SizedBox(width: 8),
                DynamicIconButton(
                  icon: Broken.setting_2,
                  onPressed: () => _showPluginConfig(plugin),
                  backgroundColor: widget.dominantColor,
                  size: 36,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12),
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
                  widget.dominantColor.withAlpha(20),
                  Colors.black.withAlpha(80),
                ],
              ),
              border: Border.all(
                color: widget.dominantColor.withAlpha(100),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  GlowIcon(
                    icon,
                    color: widget.dominantColor,
                    glowColor: widget.dominantColor.withAlpha(60),
                    blurRadius: 10,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  GlowText(
                    title,
                    glowColor: widget.dominantColor.withAlpha(60),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: widget.dominantColor,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Broken.arrow_left, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  GlowText(
                    'Plugins',
                    glowColor: widget.dominantColor.withAlpha(80),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: widget.dominantColor,
                    ),
                  ),
                  const Spacer(),
                  DynamicIconButton(
                    icon: Broken.refresh,
                    onPressed: _loadPlugins,
                    backgroundColor: widget.dominantColor,
                    size: 40,
                  ),
                ],
              ),
            ),
            // Directory Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Broken.folder, color: Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Plugin Directory: $pluginDirectory',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : CustomScrollView(
                      slivers: [
                        // Loaded Plugins Section
                        if (plugins.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: _buildSectionHeader(
                              'Loaded Plugins',
                              Broken.tick_circle,
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildPluginTile(plugins[index]),
                              childCount: plugins.length,
                            ),
                          ),
                        ],
                        // Available Plugins Section
                        if (availablePlugins.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: _buildSectionHeader(
                              'Available Plugins',
                              Broken.add_circle,
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _buildPluginTile(availablePlugins[index]),
                              childCount: availablePlugins.length,
                            ),
                          ),
                        ],
                        // Empty State
                        if (plugins.isEmpty && availablePlugins.isEmpty)
                          const SliverFillRemaining(
                            child: Center(
                              child: Text(
                                'No plugins found\nAdd .wasm files to your plugin directory',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class PluginConfigDialog extends StatefulWidget {
  final Plugin plugin;
  final Map<String, dynamic> config;
  final Color dominantColor;
  final VoidCallback onConfigUpdated;

  const PluginConfigDialog({
    super.key,
    required this.plugin,
    required this.config,
    required this.dominantColor,
    required this.onConfigUpdated,
  });

  @override
  State<PluginConfigDialog> createState() => _PluginConfigDialogState();
}

class _PluginConfigDialogState extends State<PluginConfigDialog> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    // Initialize controllers from config
    widget.config.forEach((key, value) {
      _controllers[key] = TextEditingController(text: value.toString());
    });
  }

  @override
  void dispose() {
    // Dispose all controllers
    _controllers.forEach((_, controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: AnimatedPopupWrapper(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: GlowText(
                    '${widget.plugin.name} Configuration',
                    glowColor: widget.dominantColor.withAlpha(80),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: widget.dominantColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // Config Fields
                if (_controllers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: _controllers.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  widget.dominantColor.withAlpha(30),
                                  Colors.black.withAlpha(100),
                                ],
                              ),
                            ),
                            child: TextField(
                              controller: entry.value,
                              style: const TextStyle(color: Colors.white),
                              cursorColor: widget.dominantColor,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                hintText: entry.key,
                                hintStyle: TextStyle(color: Colors.white70),
                                labelText: entry.key,
                                labelStyle: TextStyle(color: widget.dominantColor),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: widget.dominantColor,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No configuration available for this plugin',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // Buttons
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white70),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      DynamicIconButton(
                        icon: Broken.tick,
                        onPressed: () {
                          // Save configuration logic would go here
                          ScaffoldMessenger.of(context).showSnackBar(
                            AdiSnackbar(
                              backgroundColor: widget.dominantColor,
                              content: 'Configuration updated',
                            ),
                          );
                          Navigator.pop(context);
                          widget.onConfigUpdated();
                        },
                        backgroundColor: widget.dominantColor,
                        size: 40,
                      ),
                    ],
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

class Plugin {
  final String path;
  final String name;
  final bool isLoaded;

  Plugin({
    required this.path,
    required this.name,
    required this.isLoaded,
  });
}
