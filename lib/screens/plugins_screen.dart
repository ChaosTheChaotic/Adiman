import 'dart:io';
import 'dart:convert';
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
      _pluginDir = SharedPreferencesService.instance.getString('pluginDir') ??
          '~/AdiPlugins';

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

  void _showPluginSettings(String pluginPath) {
    showDialog(
      context: context,
      builder: (context) => PluginSettingsDialog(
        pluginPath: pluginPath,
        dominantColor: dominantColor,
      ),
    );
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

                DynamicIconButton(
                  icon: Broken.setting_2,
                  onPressed:
                      isLoading ? null : () => _showPluginSettings(pluginPath),
                  backgroundColor: dominantColor,
                  size: 40,
                ),
                const SizedBox(width: 12),
                // Actions
                if (isLoaded) ...[
                  DynamicIconButton(
                    icon: Broken.refresh,
                    onPressed:
                        isLoading ? null : () => _reloadPlugin(pluginPath),
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
                                        color:
                                            dominantColor.computeLuminance() >
                                                    0.01
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

class PluginSettingsDialog extends StatefulWidget {
  final String pluginPath;
  final Color dominantColor;

  const PluginSettingsDialog({
    super.key,
    required this.pluginPath,
    required this.dominantColor,
  });

  @override
  State<PluginSettingsDialog> createState() => _PluginSettingsDialogState();
}

class _PluginSettingsDialogState extends State<PluginSettingsDialog> {
  Map<String, dynamic>? _pluginMetadata;
  bool _isLoading = true;
  final Map<String, bool> _savingStates = {};

  @override
  void initState() {
    super.initState();
    _loadPluginMetadata();
  }

  Future<void> _loadPluginMetadata() async {
    try {
      final metadataJson =
          await rust_api.getPluginConfig(path: widget.pluginPath);

      // Check if the response is an error message
      if (metadataJson.startsWith('Failed to get plugin config:') ||
          metadataJson.startsWith('[ERR]:')) {
        // No metadata found or error occurred
        setState(() {
          _pluginMetadata = null;
        });
      } else {
        // Parse the metadata JSON
        final metadataMap = jsonDecode(metadataJson) as Map<String, dynamic>;
        setState(() {
          _pluginMetadata = metadataMap;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AdiSnackbar(
            backgroundColor: widget.dominantColor,
            content: 'Error loading plugin metadata: $e',
          ),
        );
      }
      setState(() {
        _pluginMetadata = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateConfigValue(
      String key, dynamic newValue, String ctype) async {
    setState(() {
      _savingStates[key] = true;
    });

    try {
      // Convert the new value to the appropriate ConfigTypes using the ctype
      final configValue = _convertToConfigType(newValue, ctype);

      final result = await rust_api.setPluginConfig(
        path: widget.pluginPath,
        key: key,
        value: configValue,
      );

      if (result.contains('Updated config')) {
        // Update local state
        setState(() {
          if (_pluginMetadata != null && _pluginMetadata!['rpc'] != null) {
            final rpcArray = _pluginMetadata!['rpc'] as List<dynamic>;
            for (var i = 0; i < rpcArray.length; i++) {
              final item = rpcArray[i] as Map<String, dynamic>;
              if (item['key'] == key) {
                item['set_val'] = newValue;
                break;
              }
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          AdiSnackbar(
            backgroundColor: widget.dominantColor,
            content: 'Setting updated successfully',
          ),
        );
      } else {
        throw Exception(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AdiSnackbar(
            backgroundColor: widget.dominantColor,
            content: 'Error updating setting: $e',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingStates[key] = false;
        });
      }
    }
  }

  rust_api.ConfigTypes _convertToConfigType(dynamic value, String ctype) {
    switch (ctype) {
      case 'String':
        return rust_api.ConfigTypes.string(value.toString());
      case 'Bool':
        if (value is bool) return rust_api.ConfigTypes.bool(value);
        if (value is String)
          return rust_api.ConfigTypes.bool(value.toLowerCase() == 'true');
        return rust_api.ConfigTypes.bool(value == 1 || value == '1');
      case 'Int':
        if (value is int) return rust_api.ConfigTypes.int(value);
        if (value is String)
          return rust_api.ConfigTypes.int(int.tryParse(value) ?? 0);
        return rust_api.ConfigTypes.int(value.toInt());
      case 'UInt':
        if (value is int) return rust_api.ConfigTypes.uInt(value);
        if (value is String) {
          final parsed = int.tryParse(value);
          return rust_api.ConfigTypes.uInt(
              parsed != null && parsed >= 0 ? parsed : 0);
        }
        return rust_api.ConfigTypes.uInt(value.toInt());
      case 'BigInt':
        if (value is int)
          return rust_api.ConfigTypes.bigInt(BigInt.from(value));
        if (value is String)
          return rust_api.ConfigTypes.bigInt(BigInt.parse(value));
        if (value is BigInt) return rust_api.ConfigTypes.bigInt(value);
        return rust_api.ConfigTypes.bigInt(BigInt.from(value.toInt()));
      case 'BigUInt':
        if (value is int)
          return rust_api.ConfigTypes.bigUInt(BigInt.from(value));
        if (value is String)
          return rust_api.ConfigTypes.bigUInt(BigInt.parse(value));
        if (value is BigInt) return rust_api.ConfigTypes.bigUInt(value);
        return rust_api.ConfigTypes.bigUInt(BigInt.from(value.toInt()));
      case 'Float':
        if (value is double) return rust_api.ConfigTypes.float(value);
        if (value is int) return rust_api.ConfigTypes.float(value.toDouble());
        if (value is String)
          return rust_api.ConfigTypes.float(double.tryParse(value) ?? 0.0);
        return rust_api.ConfigTypes.float(value.toDouble());
      default:
        // Fallback to string for unknown types
        return rust_api.ConfigTypes.string(value.toString());
    }
  }

  Widget _buildConfigField(Map<String, dynamic> config) {
    final key = config['key'] as String;
    final ctype = config['ctype'] as String;
    final defaultValue = config['default_val'];
    final currentValue = config['set_val'] ?? defaultValue;
    final isLoading = _savingStates[key] ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.dominantColor.withAlpha(20),
                Colors.black.withAlpha(80),
              ],
            ),
            border: Border.all(
              color: widget.dominantColor.withAlpha(50),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                key,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _buildFieldByType(key, ctype, currentValue, isLoading),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldByType(
      String key, String ctype, dynamic value, bool isLoading) {
    switch (ctype) {
      case 'String':
        return _buildStringField(key, value as String, isLoading);
      case 'Bool':
        return _buildBoolField(key, value as bool, isLoading);
      case 'Int':
      case 'UInt':
        return _buildIntField(key, value, isLoading, ctype == 'UInt');
      case 'BigInt':
      case 'BigUInt':
        return _buildBigIntField(key, value, isLoading, ctype == 'BigUInt');
      case 'Float':
        return _buildDoubleField(key, value, isLoading);
      default:
        return _buildStringField(key, value.toString(), isLoading);
    }
  }

  Widget _buildStringField(String key, String value, bool isLoading) {
    final controller = TextEditingController(text: value);

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !isLoading,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.dominantColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: widget.dominantColor.withAlpha(150)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (newValue) {
              if (newValue != value) {
                _updateConfigValue(key, newValue, "String");
              }
            },
          ),
        ),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(widget.dominantColor),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBoolField(String key, bool value, bool isLoading) {
    return Row(
      children: [
        Transform.scale(
          scale: 1.2,
          child: Switch(
            value: value,
            onChanged: isLoading
                ? null
                : (newValue) {
                    _updateConfigValue(key, newValue, "Bool");
                  },
            activeColor: widget.dominantColor,
            activeTrackColor: widget.dominantColor.withAlpha(100),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value ? 'Enabled' : 'Disabled',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(widget.dominantColor),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildIntField(
      String key, dynamic value, bool isLoading, bool unsigned) {
    final controller = TextEditingController(text: value.toString());

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !isLoading,
            keyboardType: TextInputType.number,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.dominantColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: widget.dominantColor.withAlpha(150)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (newValue) {
              final parsedValue = int.tryParse(newValue);
              if (parsedValue != null && parsedValue != value) {
                final String ctype = unsigned ? "UInt" : "Int";
                _updateConfigValue(key, parsedValue, ctype);
              }
            },
          ),
        ),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(widget.dominantColor),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBigIntField(
      String key, dynamic value, bool isLoading, bool unsigned) {
    final controller = TextEditingController(text: value.toString());

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !isLoading,
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.dominantColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: widget.dominantColor.withAlpha(150)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (newValue) {
              try {
                final parsedValue = BigInt.parse(newValue);
                if (parsedValue != BigInt.parse(value.toString())) {
                  final String ctype = unsigned ? "BigUInt" : "BigInt";
                  _updateConfigValue(key, parsedValue, ctype);
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  AdiSnackbar(
                    backgroundColor: widget.dominantColor,
                    content: 'Invalid number format',
                  ),
                );
              }
            },
          ),
        ),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(widget.dominantColor),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDoubleField(String key, dynamic value, bool isLoading) {
    final controller = TextEditingController(text: value.toString());

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !isLoading,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: Colors.white),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: widget.dominantColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: widget.dominantColor.withAlpha(150)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (newValue) {
              final parsedValue = double.tryParse(newValue);
              if (parsedValue != null && parsedValue != value) {
                _updateConfigValue(key, parsedValue, 'Float');
              }
            },
          ),
        ),
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(widget.dominantColor),
              ),
            ),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> _getRpcConfigs() {
    if (_pluginMetadata == null || _pluginMetadata!['rpc'] == null) {
      return [];
    }

    final rpcArray = _pluginMetadata!['rpc'] as List<dynamic>;
    return rpcArray.cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    final rpcConfigs = _getRpcConfigs();
    final hasSettings = rpcConfigs.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withAlpha(220),
              Colors.black.withAlpha(240),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.dominantColor.withAlpha(100),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.dominantColor.withAlpha(40),
                    Colors.black.withAlpha(150),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  GlowIcon(
                    Broken.setting,
                    color: widget.dominantColor,
                    size: 24,
                    glowColor: widget.dominantColor.withAlpha(80),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${_getPluginName(widget.pluginPath)} Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: GlowIcon(
                      Broken.close_square,
                      color: widget.dominantColor,
                      glowColor: widget.dominantColor.withAlpha(80),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(widget.dominantColor),
                      ),
                    )
                  : !hasSettings
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GlowIcon(
                                Broken.setting,
                                color: Colors.white70,
                                size: 48,
                                glowColor: Colors.white30,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Settings Available',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'This plugin has no configurable settings',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(16),
                          child: ListView(
                            children: rpcConfigs
                                .map((config) => _buildConfigField(config))
                                .toList(),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPluginName(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    return fileName.replaceAll('.wasm', '');
  }
}
