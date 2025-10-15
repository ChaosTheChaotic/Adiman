import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adiman/main.dart';
import 'package:adiman/widgets/services.dart';
import 'package:adiman/widgets/icon_buttons.dart';
import 'package:adiman/widgets/snackbar.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'package:adiman/icons/broken_icons.dart';
import 'package:adiman/src/rust/api/plugin_man.dart' as rust_api;

class PluginsScreen extends StatefulWidget {
  final Function()? onReloadLibrary;
  
  const PluginsScreen({
    super.key,
    this.onReloadLibrary,
  });

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  List<String> availablePlugins = [];
  List<String> loadedPlugins = [];
  bool isLoading = true;
  Color dominantColor = defaultThemeColorNotifier.value;
  final Map<String, bool> _pluginLoadingStates = {};
  String _pluginDir = '';

  @override
  void initState() {
    super.initState();
    _loadPluginData();
  }

  Future<void> _loadPluginData() async {
    setState(() => isLoading = true);
    
    try {
      _pluginDir = SharedPreferencesService.instance.getString('pluginDir') ?? '~/AdiPlugins';
      
      if (_pluginDir.startsWith('~')) {
        final home = Platform.environment['HOME'] ?? '';
        _pluginDir = _pluginDir.replaceFirst('~', home);
      }

      final scannedPlugins = await rust_api.scanDir(path: _pluginDir);
      if (scannedPlugins != null) {
        setState(() {
          availablePlugins = scannedPlugins;
        });
      }

      final loaded = await rust_api.listLoadedPlugins();
      setState(() {
        loadedPlugins = loaded;
      });

      for (final plugin in availablePlugins) {
        _pluginLoadingStates[plugin] = false;
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AdiSnackbar(
            backgroundColor: dominantColor,
            content: 'Error loading plugins: $e',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _togglePlugin(String pluginPath, bool currentlyLoaded) async {
    setState(() {
      _pluginLoadingStates[pluginPath] = true;
    });

    try {
      if (currentlyLoaded) {
        // Unload plugin
        final result = await rust_api.removePlugin(path: pluginPath);
        if (result.startsWith('Removed plugin')) {
          setState(() {
            loadedPlugins.remove(pluginPath);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            AdiSnackbar(
              backgroundColor: dominantColor,
              content: 'Plugin disabled successfully',
            ),
          );
        } else {
          throw Exception(result);
        }
      } else {
        final result = await rust_api.loadPlugin(path: pluginPath);
        if (result.startsWith('Loaded plugin')) {
          setState(() {
            loadedPlugins.add(pluginPath);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            AdiSnackbar(
              backgroundColor: dominantColor,
              content: 'Plugin enabled successfully',
            ),
          );
        } else {
          throw Exception(result);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AdiSnackbar(
            backgroundColor: dominantColor,
            content: 'Error toggling plugin: $e',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pluginLoadingStates[pluginPath] = false;
        });
      }
    }
  }

  Future<void> _reloadPlugin(String pluginPath) async {
    setState(() {
      _pluginLoadingStates[pluginPath] = true;
    });

    try {
      final result = await rust_api.reloadPlugin(path: pluginPath);
      if (result.startsWith('Reloaded plugin')) {
        ScaffoldMessenger.of(context).showSnackBar(
          AdiSnackbar(
            backgroundColor: dominantColor,
            content: 'Plugin reloaded successfully',
          ),
        );
      } else {
        throw Exception(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AdiSnackbar(
            backgroundColor: dominantColor,
            content: 'Error reloading plugin: $e',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pluginLoadingStates[pluginPath] = false;
        });
      }
    }
  }

  String _getPluginName(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    return fileName.replaceAll('.wasm', '');
  }

  Widget _buildPluginTile(String pluginPath) {
    final isLoaded = loadedPlugins.contains(pluginPath);
    final isLoading = _pluginLoadingStates[pluginPath] ?? false;
    final pluginName = _getPluginName(pluginPath);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: isLoading ? null : () => _togglePlugin(pluginPath, isLoaded),
          borderRadius: BorderRadius.circular(20),
          splashColor: dominantColor.withAlpha(50),
          highlightColor: dominantColor.withAlpha(30),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  dominantColor.withAlpha(isLoaded ? 40 : 20),
                  Colors.black.withAlpha(100),
                ],
              ),
              border: Border.all(
                color: dominantColor.withAlpha(isLoaded ? 100 : 50),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: dominantColor.withAlpha(isLoaded ? 30 : 10),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Plugin Icon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        dominantColor.withAlpha(60),
                        dominantColor.withAlpha(20),
                      ],
                    ),
                  ),
                  child: Center(
                    child: GlowIcon(
                      Broken.cpu,
                      color: dominantColor.computeLuminance() > 0.01
                          ? dominantColor
                          : Colors.white,
                      size: 24,
                      glowColor: dominantColor.withAlpha(80),
                      blurRadius: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Plugin Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pluginName,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pluginPath,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isLoaded 
                              ? Colors.green.withAlpha(80)
                              : Colors.grey.withAlpha(80),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isLoaded ? 'Enabled' : 'Disabled',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Actions
                if (isLoaded) ...[
                  DynamicIconButton(
                    icon: Broken.refresh,
                    onPressed: isLoading ? null : () => _reloadPlugin(pluginPath),
                    backgroundColor: dominantColor,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                ],
                
                // Toggle Switch
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 50,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isLoaded
                          ? [
                              dominantColor,
                              dominantColor.withAlpha(200),
                            ]
                          : [
                              Colors.grey.withAlpha(150),
                              Colors.grey.withAlpha(100),
                            ],
                    ),
                    boxShadow: [
                      if (isLoaded)
                        BoxShadow(
                          color: dominantColor.withAlpha(100),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        left: isLoaded ? 22 : 2,
                        top: 2,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(80),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isLoading)
                        Positioned.fill(
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  dominantColor.computeLuminance() > 0.01
                                      ? dominantColor
                                      : Colors.white,
                                ),
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
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            dominantColor.withAlpha(40),
            Colors.black.withAlpha(150),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: dominantColor.withAlpha(80),
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlowIcon(
                Broken.cpu,
                color: dominantColor.computeLuminance() > 0.01
                    ? dominantColor
                    : Colors.white,
                size: 32,
                glowColor: dominantColor.withAlpha(80),
                blurRadius: 12,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GlowText(
                  'Plugins',
                  glowColor: dominantColor.withAlpha(80),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: dominantColor.computeLuminance() > 0.01
                        ? dominantColor
                        : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Plugin Directory: $_pluginDir',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${loadedPlugins.length} enabled • ${availablePlugins.length} total',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, dominantColor],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: GlowIcon(
              Broken.arrow_left_2,
              color: dominantColor.computeLuminance() > 0.01
                  ? dominantColor
                  : Colors.white,
              glowColor: dominantColor.withAlpha(80),
            ),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: GlowText(
            'Plugins',
            glowColor: dominantColor.withAlpha(80),
            style: TextStyle(
              color: dominantColor.computeLuminance() > 0.01
                  ? dominantColor
                  : Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            DynamicIconButton(
              icon: Broken.refresh,
              onPressed: _loadPluginData,
              backgroundColor: dominantColor,
              size: 40,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Content
            Expanded(
              child: isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          dominantColor.computeLuminance() > 0.01
                              ? dominantColor
                              : Colors.white,
                        ),
                      ),
                    )
                  : availablePlugins.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GlowIcon(
                                Broken.cpu,
                                color: Colors.white70,
                                size: 64,
                                glowColor: Colors.white30,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'No Plugins Found',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Add plugin files to your plugin directory',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(15),
                                child: InkWell(
                                  onTap: _loadPluginData,
                                  borderRadius: BorderRadius.circular(15),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(
                                        color: dominantColor.withAlpha(100),
                                      ),
                                    ),
                                    child: Text(
                                      'Rescan Directory',
                                      style: TextStyle(
                                        color: dominantColor.computeLuminance() > 0.01
                                            ? dominantColor
                                            : Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          itemCount: availablePlugins.length,
                          itemBuilder: (context, index) {
                            return _buildPluginTile(availablePlugins[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
