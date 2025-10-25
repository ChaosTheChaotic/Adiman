import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:adiman/src/rust/api/music_handler.dart' as rust_api;
import 'package:adiman/src/rust/api/plugin_man.dart';
import 'package:adiman/src/rust/api/value_store.dart' as value_store;
import 'package:adiman/src/rust/api/color_extractor.dart' as color_extractor;
import 'package:flutter/material.dart';
import 'package:adiman/widgets/miniplayer.dart';
import 'package:adiman/widgets/services.dart';
import 'package:adiman/main.dart';
import 'package:adiman/widgets/icon_buttons.dart';
import 'package:adiman/widgets/misc.dart';
import 'package:adiman/widgets/snackbar.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:adiman/icons/broken_icons.dart';

class SettingsScreen extends StatefulWidget {
  final AdimanService service;
  final Function(String)? onMusicFolderChanged;
  final Future<void> Function() onReloadLibrary;
  final Song? currentSong;
  final int currentIndex;
  final Color dominantColor;
  final List<Song> songs;
  final String musicFolder;
  final String? currentPlaylistName;
  final void Function(Song newSong, int newIndex, Color newColor)?
      onUpdateMiniPlayer;
  final Function(Color)? updateThemeColor;

  const SettingsScreen({
    super.key,
    required this.service,
    this.onMusicFolderChanged,
    required this.onReloadLibrary,
    this.currentSong,
    this.currentIndex = 0,
    required this.dominantColor,
    required this.songs,
    required this.musicFolder,
    this.onUpdateMiniPlayer,
    this.currentPlaylistName,
    this.updateThemeColor,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isClearingCache = false;
  bool _isReloadingLibrary = false;
  final bool _isChangingParticleColor = false;
  Color _particleBaseColor = Colors.white;
  bool _spinningAlbumArt = false;
  final bool _isChangingColor = false;
  final bool _isManagingSeparators = false;
  final bool _isClearingDatabase = false;
  bool _enablePlugins = false;
  bool _unsafeAPIs = false;
  bool _autoConvert = true;
  bool _autoCreateDirs = false;
  bool _clearMp3Cache = false;
  bool _vimKeybindings = false;
  String _spotdlFlags = '';
  String _pluginDir = '';
  String _pluginRwDir = '';
  bool _fadeIn = false;
  bool _mSn = false;
  bool _breathe = true;
  bool _useDominantColors = false;
  bool _edgeBreathe = true;
  SeekbarType _seekbarType = SeekbarType.waveform;
  int _waveformBars = 1000;
  double _particleSpawnOpacity = 0.4;
  double _particleOpacityChangeRate = 0.2;
  double _particleMinOpacity = 0.1;
  double _particleMaxOpacity = 0.6;
  double _particleMinRadius = 2.0;
  double _particleMaxRadius = 4.0;
  int _particleCount = 50;
  late FocusNode _escapeNode;

  Song? _currentSong;
  int _currentIndex = 0;
  late Color _currentColor;

  late TextEditingController _musicFolderController;
  late TextEditingController _waveformBarsController;
  late TextEditingController _particleCountController;
  late TextEditingController _pluginDirController;
  late TextEditingController _pluginRwDirController;

  final GlobalKey<MiniPlayerState> _miniPlayerKey =
      GlobalKey<MiniPlayerState>();

  @override
  void initState() {
    super.initState();
    _currentSong = widget.currentSong;
    _currentIndex = widget.currentIndex;
    _currentColor = widget.dominantColor;
    _musicFolderController = TextEditingController(text: widget.musicFolder);
    _pluginDirController = TextEditingController(text: _pluginDir);
    _pluginRwDirController = TextEditingController(text: _pluginRwDir);
    _escapeNode = FocusNode();
    _escapeNode.requestFocus();
    defaultThemeColorNotifier.addListener(_handleThemeColorChange);
    useDominantColorsNotifier.addListener(_updateDominantColor);
    _waveformBarsController =
        TextEditingController(text: _waveformBars.toString());
    _particleCountController =
        TextEditingController(text: _particleCount.toString());
    _loadChecks();
  }

  Future<Color> _getDominantColor(Song song) async {
    final bool useDom = useDominantColorsNotifier.value;
    if (song.albumArt == null || !useDom) {
      return defaultThemeColorNotifier.value;
    }

    try {
      final colorValue =
          await color_extractor.getDominantColor(data: song.albumArt!);
      return Color(colorValue ?? defaultThemeColorNotifier.value.toARGB32());
    } catch (e) {
      return defaultThemeColorNotifier.value;
    }
  }

  void _updateDominantColor() {
    if (_currentSong != null) {
      _getDominantColor(_currentSong!).then((newColor) {
        if (mounted) {
          setState(() => _currentColor = newColor);
        }
      });
    } else {
      setState(() => _currentColor = defaultThemeColorNotifier.value);
    }
  }

  @override
  void dispose() {
    _musicFolderController.dispose();
    _pluginDirController.dispose();
    _pluginRwDirController.dispose();
    defaultThemeColorNotifier.removeListener(_handleThemeColorChange);
    useDominantColorsNotifier.removeListener(_updateDominantColor);
    _waveformBarsController.dispose();
    _particleCountController.dispose();
    super.dispose();
  }

  void _handleThemeColorChange() {
    final bool useDom =
        SharedPreferencesService.instance.getBool('useDominantColors') ?? true;
    if ((_currentSong?.albumArt == null || !useDom) && mounted) {
      setState(() {
        _currentColor = defaultThemeColorNotifier.value;
      });
    }
  }

  Future<void> _loadChecks() async {
    setState(() {
      _autoConvert =
          SharedPreferencesService.instance.getBool('autoConvert') ?? false;
      _autoCreateDirs =
          SharedPreferencesService.instance.getBool('autoCreateDirs') ?? true;
      _clearMp3Cache =
          SharedPreferencesService.instance.getBool('clearMp3Cache') ?? false;
      _vimKeybindings =
          SharedPreferencesService.instance.getBool('vimKeybindings') ?? false;
      _fadeIn = SharedPreferencesService.instance.getBool('fadeIn') ?? false;
      _mSn = SharedPreferencesService.instance.getBool('mSn') ?? false;
      _breathe = SharedPreferencesService.instance.getBool('breathe') ?? true;
      _useDominantColors =
          SharedPreferencesService.instance.getBool('useDominantColors') ??
              true;
      _waveformBars =
          SharedPreferencesService.instance.getInt('waveformBars') ?? 1000;
      _particleSpawnOpacity =
          SharedPreferencesService.instance.getDouble('particleSpawnOpacity') ??
              0.4;
      _particleOpacityChangeRate = SharedPreferencesService.instance
              .getDouble('particleOpacityChangeRate') ??
          0.2;
      _particleMinOpacity =
          SharedPreferencesService.instance.getDouble('particleMinOpacity') ??
              0.1;
      _particleMaxOpacity =
          SharedPreferencesService.instance.getDouble('particleMaxOpacity') ??
              0.6;
      _particleMinRadius =
          SharedPreferencesService.instance.getDouble('particleMinRadius') ??
              2.0;
      _particleMaxRadius =
          SharedPreferencesService.instance.getDouble('particleMaxRadius') ??
              4.0;
      _particleCount =
          SharedPreferencesService.instance.getInt('particleCount') ?? 50;
      _particleBaseColor = Color(
        SharedPreferencesService.instance.getInt('particleBaseColor') ??
            Colors.white.toARGB32(),
      );
      _spinningAlbumArt =
          SharedPreferencesService.instance.getBool('spinningAlbumArt') ??
              false;
      _spotdlFlags =
          SharedPreferencesService.instance.getString('spotdlFlags') ?? '';
      _pluginDir = SharedPreferencesService.instance.getString('pluginDir') ??
          '~/AdiPlugins';
      _pluginRwDir =
          SharedPreferencesService.instance.getString('pluginRwDir') ??
              '~/AdiDir';
      _edgeBreathe =
          SharedPreferencesService.instance.getBool('edgeBreathe') ?? true;
      _enablePlugins =
          SharedPreferencesService.instance.getBool('enablePlugins') ?? false;
      _unsafeAPIs =
          SharedPreferencesService.instance.getBool('unsafeAPIs') ?? false;
      final seekbarTypeString =
          SharedPreferencesService.instance.getString('seekbarType');
      _seekbarType = seekbarTypeString == 'alt'
          ? SeekbarType.alt
          : seekbarTypeString == 'dyn'
              ? SeekbarType.dyn
              : SeekbarType.waveform; // Default to waveform
    });
    final savedSeparators =
        SharedPreferencesService.instance.getStringList('separators');
    if (savedSeparators != null) {
      rust_api.setSeparators(separators: savedSeparators);
    }
  }

  String expandTilde(String path) {
    if (path.startsWith('~')) {
      final home = Platform.environment['HOME'] ?? '';
      return path.replaceFirst('~', home);
    }
    return path;
  }

  Future<void> _saveAutoConvert(bool value) async {
    await SharedPreferencesService.instance.setBool('autoConvert', value);
    setState(() => _autoConvert = value);
  }

  Future<void> _saveAutoCreateDirs(bool value) async {
    await SharedPreferencesService.instance.setBool('autoCreateDirs', value);
    setState(() => _autoCreateDirs = value);
  }

  Future<void> _saveVimKeybindings(bool value) async {
    await SharedPreferencesService.instance.setBool('vimKeybindings', value);
    setState(() => _vimKeybindings = value);
  }

  Future<void> _saveClearMp3Cache(bool value) async {
    await SharedPreferencesService.instance.setBool('clearMp3Cache', value);
    setState(() => _clearMp3Cache = value);
  }

  Future<void> _saveFadeIn(bool value) async {
    await SharedPreferencesService.instance.setBool('fadeIn', value);
    rust_api.setFadein(value: value);
    setState(() => _fadeIn = value);
  }

  Future<void> _saveMSn(bool value) async {
    await SharedPreferencesService.instance.setBool('mSn', value);
    rust_api.setFadein(value: value);
    setState(() => _mSn = value);
  }

  Future<void> _saveBreathe(bool value) async {
    await SharedPreferencesService.instance.setBool('breathe', value);
    rust_api.setFadein(value: value);
    setState(() => _breathe = value);
  }

  Future<void> _saveUseDominantColors(bool value) async {
    await SharedPreferencesService.instance.setBool('useDominantColors', value);
    useDominantColorsNotifier.value = value;
    setState(() => _useDominantColors = value);
  }

  Future<void> _saveWaveformBars(int value) async {
    await SharedPreferencesService.instance.setInt('waveformBars', value);
    setState(() => _waveformBars = value);
    _waveformBarsController.text = '';
  }

  Future<void> _saveParticleSpawnOpacity(double value) async {
    await SharedPreferencesService.instance
        .setDouble('particleSpawnOpacity', value);
    setState(() => _particleSpawnOpacity = value);
  }

  Future<void> _saveParticleOpacityChangeRate(double value) async {
    await SharedPreferencesService.instance
        .setDouble('particleOpacityChangeRate', value);
    setState(() => _particleOpacityChangeRate = value);
  }

  Future<void> _saveParticleMinOpacity(double value) async {
    await SharedPreferencesService.instance
        .setDouble('particleMinOpacity', value);
    setState(() => _particleMinOpacity = value);
  }

  Future<void> _saveParticleMaxOpacity(double value) async {
    await SharedPreferencesService.instance
        .setDouble('particleMaxOpacity', value);
    setState(() => _particleMaxOpacity = value);
  }

  Future<void> _saveParticleMinRadius(double value) async {
    await SharedPreferencesService.instance
        .setDouble('particleMinRadius', value);
    setState(() => _particleMinRadius = value);
  }

  Future<void> _saveParticleMaxRadius(double value) async {
    await SharedPreferencesService.instance
        .setDouble('particleMaxRadius', value);
    setState(() => _particleMaxRadius = value);
  }

  Future<void> _saveParticleCount(int value) async {
    await SharedPreferencesService.instance.setInt('particleCount', value);
    setState(() => _particleCount = value);
    _particleCountController.text = '';
  }

  Future<void> _saveParticleBaseColor(Color color) async {
    await SharedPreferencesService.instance
        .setInt('particleBaseColor', color.toARGB32());
    setState(() => _particleBaseColor = color);
  }

  Future<void> _saveSpinningAlbumArt(bool value) async {
    await SharedPreferencesService.instance.setBool('spinningAlbumArt', value);
    setState(() => _spinningAlbumArt = value);
  }

  Future<void> _saveSpotdlFlags(String flags) async {
    await SharedPreferencesService.instance.setString('spotdlFlags', flags);
    setState(() => _spotdlFlags = flags);
  }

  Future<void> _saveEdgeBreathe(bool value) async {
    await SharedPreferencesService.instance.setBool('edgeBreathe', value);
    setState(() => _edgeBreathe = value);
  }

  Future<void> _saveSeekbarType(SeekbarType type) async {
    await SharedPreferencesService.instance.setString('seekbarType', type.name);
    setState(() => _seekbarType = type);
  }

  Future<void> _saveEnablePlugins(bool value) async {
    await SharedPreferencesService.instance.setBool('enablePlugins', value);
    setState(() => _enablePlugins = value);
    if (value) {
      await initPluginMan();
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
        backgroundColor: widget.dominantColor,
        content: 'Plugins enabled - restart app for full effect',
      ));
    } else {
      try {
        final loadedPlugins = await listLoadedPlugins();
        for (final plugin in loadedPlugins) {
          await removePlugin(path: plugin);
        }
        ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Plugins disabled - all plugins unloaded',
        ));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content:
              'Error disabling plugins (run in terminal for more info): $e',
        ));
      }
    }
  }

  Future<void> _saveUnsafeAPIs(bool value) async {
    if (value) {
      // Show warning dialog when enabling unsafe APIs
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
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
                      Colors.orange.withAlpha(50),
                      Colors.black.withAlpha(200),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.orange.withAlpha(100),
                    width: 1.2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlowText(
                        'Unsafe APIs Warning',
                        glowColor: Colors.orange.withAlpha(80),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Enabling Unsafe APIs gives plugins access to potentially dangerous operations.\n\n'
                        'Only enable this if you trust all installed plugins completely.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          DynamicIconButton(
                            icon: Broken.close_circle,
                            onPressed: () => Navigator.pop(ctx, false),
                            backgroundColor: Colors.grey,
                            size: 40,
                          ),
                          DynamicIconButton(
                            icon: Broken.tick,
                            onPressed: () => Navigator.pop(ctx, true),
                            backgroundColor: Colors.orange,
                            size: 40,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      if (confirmed != true) {
        // User cancelled, don't enable unsafe APIs
        return;
      }
    }

    await SharedPreferencesService.instance.setBool('unsafeAPIs', value);

    final updater = await value_store.updateStore();
    updater.setUnsafeApis(value: value);
    updater.apply();

    if (mounted) {
      setState(() => _unsafeAPIs = value);
    }

    ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
      backgroundColor: value ? Colors.orange : _currentColor,
      content: value
          ? 'Unsafe APIs enabled - use with caution!'
          : 'Unsafe APIs disabled',
    ));
  }

  Future<void> _savePluginDir(String dir) async {
    await SharedPreferencesService.instance.setString('pluginDir', dir);
    setState(() => _pluginDir = dir);
  }

  Future<void> _savePluginRwDir(String dir) async {
    await SharedPreferencesService.instance.setString('pluginRwDir', dir);
    final updater = await value_store.updateStore();
    updater.setPluginRwDir(folder: dir);
    setState(() => _pluginRwDir = dir);
  }

  Future<void> _clearCache() async {
    setState(() => _isClearingCache = true);
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list()) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (e) {
            AdiSnackbar(
                backgroundColor: widget.dominantColor,
                content: 'Failed to delete ${entity.path}: $e');
          }
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Cache cleared successfully'));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
          backgroundColor: widget.dominantColor,
          content: 'Error clearing cache: $e'));
    }
    if (_clearMp3Cache) {
      await rust_api.clearMp3Cache();
    }
    setState(() {
      _isClearingCache = false;
    });
  }

  Future<void> _reloadLibrary() async {
    setState(() {
      _isReloadingLibrary = true;
    });
    await widget.onReloadLibrary();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
        backgroundColor: widget.dominantColor,
        content:
            'Music library reloaded successfully (if you are waiting for your songs to be converted, you might have to do this again due to the waiting list of songs needing conversion)'));
    setState(() {
      _isReloadingLibrary = false;
    });
  }

  void _togglePauseSong() {
    if (_currentSong == null) return;
    _miniPlayerKey.currentState?.togglePause();
  }

  Future<void> _showColorPicker() async {
    Color tempColor = defaultThemeColorNotifier.value;

    showDialog(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setStateDialog) {
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
                          children: [
                            GlowText(
                              'Default Theme Color',
                              glowColor: widget.dominantColor.withAlpha(80),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ColorPicker(
                              pickerColor: tempColor,
                              onColorChanged: (color) {
                                setState(() => tempColor = color);
                              },
                              displayThumbColor: true,
                              enableAlpha: false,
                              labelTypes: const [],
                              pickerAreaHeightPercent: 0.7,
                              hexInputBar: true,
                              portraitOnly: true,
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                DynamicIconButton(
                                  icon: Broken.refresh,
                                  onPressed: () {
                                    final defaultColor =
                                        const Color(0xFF383770);
                                    SharedPreferencesService.instance.setInt(
                                        'defaultThemeColor',
                                        defaultColor.toARGB32());
                                    setStateDialog(
                                        () => tempColor = defaultColor);
                                    if (widget.updateThemeColor != null) {
                                      widget.updateThemeColor!(defaultColor);
                                    }
                                  },
                                  backgroundColor: widget.dominantColor,
                                  size: 40,
                                ),
                                DynamicIconButton(
                                  icon: Broken.tick,
                                  onPressed: () async {
                                    await SharedPreferencesService.instance
                                        .setInt('defaultThemeColor',
                                            tempColor.toARGB32());
                                    if (widget.updateThemeColor != null) {
                                      widget.updateThemeColor!(tempColor);
                                    }
                                    if (mounted) {
                                      Navigator.pop(context, tempColor);
                                    }
                                  },
                                  backgroundColor: widget.dominantColor,
                                  size: 40,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        });
  }

  Future<void> _showParticleColorPicker() async {
    Color tempColor = _particleBaseColor;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
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
                          _currentColor.withAlpha(30),
                          Colors.black.withAlpha(200),
                        ],
                      ),
                      border: Border.all(
                        color: _currentColor.withAlpha(100),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlowText(
                            'Particle Base Color',
                            glowColor: _currentColor.withAlpha(80),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color:
                                  Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ColorPicker(
                            pickerColor: tempColor,
                            onColorChanged: (color) {
                              setStateDialog(() => tempColor = color);
                            },
                            displayThumbColor: true,
                            enableAlpha: false,
                            labelTypes: const [],
                            pickerAreaHeightPercent: 0.7,
                            hexInputBar: true,
                            portraitOnly: true,
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              DynamicIconButton(
                                icon: Broken.refresh,
                                onPressed: () {
                                  setStateDialog(
                                      () => tempColor = Colors.white);
                                },
                                backgroundColor: _currentColor,
                                size: 40,
                              ),
                              DynamicIconButton(
                                icon: Broken.tick,
                                onPressed: () async {
                                  await _saveParticleBaseColor(tempColor);
                                  if (mounted) Navigator.pop(context);
                                },
                                backgroundColor: _currentColor,
                                size: 40,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsSwitch(
    BuildContext context, {
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final glowColor = _currentColor.withAlpha(60);
    final trackColor = _currentColor.withAlpha(30);
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        hoverColor: _currentColor.withAlpha(30),
        onTap: () => onChanged(!value),
        child: ListTile(
          title: GlowText(
            title,
            glowColor: glowColor,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          trailing: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                width: 60,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      trackColor,
                      trackColor.withAlpha(10),
                    ],
                  ),
                  border: Border.all(
                    color: _currentColor.withAlpha(value ? 100 : 40),
                    width: 1.5,
                  ),
                  boxShadow: [
                    if (value)
                      BoxShadow(
                        color: glowColor,
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _currentColor.withAlpha(200),
                          _currentColor.withAlpha(100),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: glowColor,
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      value ? Broken.tick : Broken.cross,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeekbarTypeSelector() {
    final textColor = _currentColor.computeLuminance() > 0.01
        ? _currentColor
        : Theme.of(context).textTheme.bodyLarge?.color;

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlowText(
              'Seekbar Style',
              glowColor: _currentColor.withAlpha(60),
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _currentColor.withAlpha(30),
                    Colors.black.withAlpha(80),
                  ],
                ),
                border: Border.all(
                  color: _currentColor.withAlpha(100),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _currentColor.withAlpha(40),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final optionWidth = constraints.maxWidth / 3;
                  return Stack(
                    children: [
                      // Animated background highlight
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        left: _seekbarType.index * optionWidth + 4,
                        child: Container(
                          width: optionWidth - 8,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _currentColor.withAlpha(100),
                                _currentColor.withAlpha(60),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _currentColor.withAlpha(80),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSeekbarOption(
                              'Waveform',
                              SeekbarType.waveform,
                              Broken.sound,
                            ),
                          ),
                          Expanded(
                            child: _buildSeekbarOption(
                              'Alt',
                              SeekbarType.alt,
                              Broken.slider_horizontal_1,
                            ),
                          ),
                          Expanded(
                            child: _buildSeekbarOption(
                              'Dynamic',
                              SeekbarType.dyn,
                              Broken.sound,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                'CDs always use the alt seekbar',
                style: TextStyle(
                  color: textColor!.withAlpha(150),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekbarOption(String label, SeekbarType type, IconData icon) {
    final isSelected = _seekbarType == type;
    final textColor = isSelected ? Colors.white : _currentColor;
    final glowColor = _currentColor.withAlpha(80);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _saveSeekbarType(type),
        borderRadius: BorderRadius.circular(12),
        splashColor: _currentColor.withAlpha(30),
        highlightColor: _currentColor.withAlpha(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isSelected
                  ? [
                      _currentColor,
                      _currentColor.withAlpha(220),
                    ]
                  : [
                      _currentColor.withAlpha(20),
                      Colors.transparent,
                    ],
            ),
            border: isSelected
                ? null
                : Border.all(
                    color: _currentColor.withAlpha(80),
                    width: 1.0,
                  ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: glowColor,
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GlowIcon(
                icon,
                color: textColor,
                glowColor: glowColor,
                blurRadius: 8,
                size: 20,
              ),
              const SizedBox(height: 6),
              GlowText(
                label,
                glowColor: glowColor,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsExpansionTile({
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: Icon(icon, color: _currentColor),
      title: GlowText(
        title,
        glowColor: _currentColor.withAlpha(60),
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyLarge?.color,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        Divider(color: _currentColor.withAlpha(80)),
        ...children,
        SizedBox(height: 16),
      ],
    );
  }

  Future<void> _clearPlaylistDatabase() async {
    await PlaylistOrderDatabase().clearAllPlaylists();
    ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
      backgroundColor: widget.dominantColor,
      content: 'Playlist database cleared',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final textColor = _currentColor.computeLuminance() > 0.01
        ? _currentColor
        : Theme.of(context).textTheme.bodyLarge?.color;
    final buttonTextColor = Theme.of(context).textTheme.bodyLarge?.color;

    return Theme(
        data: ThemeData(brightness: Brightness.dark),
        child: KeyboardListener(
          focusNode: _escapeNode,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.escape) {
                if (ModalRoute.of(context)?.isCurrent ?? false) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  Navigator.pop(context);
                }
              } else if (event.logicalKey == LogicalKeyboardKey.space &&
                  FocusScope.of(context).hasFocus &&
                  FocusScope.of(context).focusedChild is EditableText) {
                _togglePauseSong();
              }
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Broken.arrow_left)),
              title: GlowText(
                'Settings',
                glowColor: _currentColor.withValues(alpha: 0.3),
                style: TextStyle(
                  fontSize: 24,
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Colors.black,
              surfaceTintColor: _currentColor,
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.5,
                  colors: [_currentColor.withValues(alpha: 0.15), Colors.black],
                ),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        16.0, 16.0, 16.0, (_currentSong != null ? 80.0 : 0.0)),
                    child: ListView(
                      children: [
                        const SizedBox(height: 32),
                        _buildSettingsExpansionTile(
                          title: 'Music Library',
                          icon: Broken.folder,
                          children: [
                            // Music folder settings
                            GlowText(
                              'Music Folder',
                              glowColor: _currentColor.withValues(alpha: 0.2),
                              style: TextStyle(
                                fontSize: 28,
                                color: textColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _currentColor.withValues(alpha: 0.1),
                                    Colors.black.withValues(alpha: 0.3),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _currentColor.withValues(alpha: 0.2),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _musicFolderController,
                                style:
                                    TextStyle(color: textColor, fontSize: 16),
                                cursorColor:
                                    _currentColor.computeLuminance() > 0.01
                                        ? _currentColor
                                        : Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.color,
                                decoration: InputDecoration(
                                  hintText: 'Enter music folder path...',
                                  hintStyle: TextStyle(
                                    color: textColor?.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w300,
                                  ),
                                  prefixIcon: Icon(
                                    Broken.folder,
                                    color: textColor?.withValues(alpha: 0.8),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.transparent,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 18,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color:
                                          _currentColor.withValues(alpha: 0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.transparent,
                                    Colors.transparent,
                                  ],
                                ),
                                border: Border.all(
                                  color: _currentColor.withAlpha(100),
                                  width: 1.2,
                                  style: BorderStyle.solid,
                                  strokeAlign: BorderSide.strokeAlignOutside,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _currentColor.withAlpha(40),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  onTap: () async {
                                    final expandedPath = expandTilde(
                                        _musicFolderController.text);
                                    await SharedPreferencesService.instance
                                        .setString('musicFolder', expandedPath);
                                    final updater =
                                        await value_store.updateStore();
                                    await updater.setMusicFolder(
                                        folder: expandedPath);
                                    updater.apply();
                                    if (widget.onMusicFolderChanged != null) {
                                      await widget
                                          .onMusicFolderChanged!(expandedPath);
                                    }
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                    Navigator.pop(context, expandedPath);
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  splashColor: _currentColor.withAlpha(30),
                                  highlightColor: _currentColor.withAlpha(15),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16, horizontal: 24),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        GlowIcon(
                                          Broken.save_2,
                                          color: buttonTextColor,
                                          glowColor:
                                              _currentColor.withAlpha(80),
                                          blurRadius: 8,
                                        ),
                                        const SizedBox(width: 12),
                                        GlowText(
                                          'Save Music Folder',
                                          glowColor:
                                              _currentColor.withAlpha(60),
                                          style: TextStyle(
                                            color: buttonTextColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _buildActionButton(
                              icon: Broken.refresh,
                              label: 'Reload Music Library',
                              isLoading: _isReloadingLibrary,
                              onPressed: _reloadLibrary,
                            ),
                            _buildActionButton(
                              icon: Broken.text,
                              label: 'Manage Artist Separators',
                              isLoading: _isManagingSeparators,
                              onPressed: _showSeparatorManagementPopup,
                            ),
                            _buildActionButton(
                              icon: Broken.trash,
                              label: 'Clear Playlist Order Database',
                              isLoading: _isClearingDatabase,
                              onPressed: _clearPlaylistDatabase,
                            ),
                          ],
                        ),
                        _buildSettingsExpansionTile(
                          title: 'Playback',
                          icon: Broken.play_cricle,
                          children: [
                            _buildSettingsSwitch(context,
                                title: 'Music fade in on seek and song start',
                                value: _fadeIn,
                                onChanged: _saveFadeIn),
                            _buildSettingsSwitch(context,
                                title: 'Breathing animation on the album art',
                                value: _breathe,
                                onChanged: _saveBreathe),
                            _buildSettingsSwitch(context,
                                title: 'Alternate default for no album art',
                                value: _mSn,
                                onChanged: _saveMSn),
                            _buildSettingsSwitch(context,
                                title: 'Edge breathing effect',
                                value: _edgeBreathe,
                                onChanged: _saveEdgeBreathe),
                            _buildSeekbarTypeSelector(),
                          ],
                        ),
                        _buildSettingsExpansionTile(
                          title: 'Appearance',
                          icon: Broken.colorfilter,
                          children: [
                            _buildSettingsSwitch(context,
                                title: 'Use dominant colors from album art',
                                value: _useDominantColors,
                                onChanged: _saveUseDominantColors),
                            _buildSettingsSwitch(context,
                                title: 'Spinning Album Art',
                                value: _spinningAlbumArt,
                                onChanged: _saveSpinningAlbumArt),
                            _buildActionButton(
                              icon: Broken.colorfilter,
                              label: 'Default Theme Color',
                              isLoading: _isChangingColor,
                              onPressed: _showColorPicker,
                            ),
                            _buildActionButton(
                              icon: Broken.colors_square,
                              label: 'Particle base color',
                              isLoading: _isChangingParticleColor,
                              onPressed: _showParticleColorPicker,
                            ),
                          ],
                        ),
                        _buildSettingsExpansionTile(
                            title: 'Waveform & Particles',
                            icon: Broken.sound,
                            initiallyExpanded: false,
                            children: [
                              ListTile(
                                title: Text('Waveform Bars Count',
                                    style: TextStyle(color: textColor)),
                                subtitle: Text('Current: $_waveformBars',
                                    style: TextStyle(
                                        color: textColor?.withAlpha(150))),
                                trailing: SizedBox(
                                  width: 150,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _waveformBarsController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly
                                          ],
                                          decoration: InputDecoration(
                                            hintText: (SharedPreferencesService
                                                        .instance
                                                        .getInt(
                                                            'waveformBars') ??
                                                    1000)
                                                .toString(),
                                            border: OutlineInputBorder(),
                                            filled: true,
                                            fillColor:
                                                Colors.black.withAlpha(50),
                                          ),
                                          style: TextStyle(color: textColor),
                                          onSubmitted: (value) {
                                            if (value.isNotEmpty) {
                                              final intValue =
                                                  int.tryParse(value) ?? 1000;
                                              _saveWaveformBars(intValue);
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildResetButton(
                                        onPressed: () async {
                                          await _saveWaveformBars(1000);
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              ExpansionTile(
                                title: Text('Particle Settings',
                                    style: TextStyle(color: textColor)),
                                children: [
                                  _buildParticleSlider(
                                    label: 'Spawn Opacity',
                                    value: _particleSpawnOpacity,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: _saveParticleSpawnOpacity,
                                    defaultValue: 0.4,
                                  ),
                                  _buildParticleSlider(
                                    label: 'Opacity Change Rate',
                                    value: _particleOpacityChangeRate,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: _saveParticleOpacityChangeRate,
                                    defaultValue: 0.2,
                                  ),
                                  _buildParticleSlider(
                                    label: 'Min Opacity',
                                    value: _particleMinOpacity,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: _saveParticleMinOpacity,
                                    defaultValue: 0.1,
                                  ),
                                  _buildParticleSlider(
                                    label: 'Max Opacity',
                                    value: _particleMaxOpacity,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: _saveParticleMaxOpacity,
                                    defaultValue: 0.6,
                                  ),
                                  _buildParticleSlider(
                                    label: 'Min Radius',
                                    value: _particleMinRadius,
                                    min: 0.5,
                                    max: 10.0,
                                    onChanged: _saveParticleMinRadius,
                                    defaultValue: 2.0,
                                  ),
                                  _buildParticleSlider(
                                    label: 'Max Radius',
                                    value: _particleMaxRadius,
                                    min: 0.5,
                                    max: 10.0,
                                    onChanged: _saveParticleMaxRadius,
                                    defaultValue: 4.0,
                                  ),
                                  ListTile(
                                    title: Text('Particle Count',
                                        style: TextStyle(color: textColor)),
                                    subtitle: Text('Current: $_particleCount',
                                        style: TextStyle(
                                            color: textColor?.withAlpha(150))),
                                    trailing: SizedBox(
                                      width: 150,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller:
                                                  _particleCountController,
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly
                                              ],
                                              decoration: InputDecoration(
                                                hintText: (SharedPreferencesService
                                                            .instance
                                                            .getInt(
                                                                'particleCount') ??
                                                        50)
                                                    .toString(),
                                                border: OutlineInputBorder(),
                                                filled: true,
                                                fillColor:
                                                    Colors.black.withAlpha(50),
                                              ),
                                              style:
                                                  TextStyle(color: textColor),
                                              onSubmitted: (value) {
                                                if (value.isNotEmpty) {
                                                  final intValue =
                                                      int.tryParse(value) ?? 50;
                                                  _saveParticleCount(intValue);
                                                }
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _buildResetButton(
                                            onPressed: () async {
                                              await _saveParticleCount(50);
                                              setState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ]),
                        _buildSettingsExpansionTile(
                            title: 'Plugins',
                            icon: Broken.cpu,
                            children: [
                              _buildSettingsSwitch(
                                context,
                                title:
                                    'Enable Plugins (some changes may require restart)',
                                value: _enablePlugins,
                                onChanged: _saveEnablePlugins,
                              ),
                              SettingsTextField(
                                title: 'Plugin Directory',
                                initialValue: _pluginDir,
                                hintText: 'Enter plugin directory path...',
                                onChanged: _savePluginDir,
                                icon: Broken.folder,
                                dominantColor: _currentColor,
                              ),
                              SettingsTextField(
                                title:
                                    'Plugin R/W Directory (where can plugins read or write files/directories (this works through symlinks too))',
                                initialValue: _pluginRwDir,
                                hintText: 'Enter plugin r/w directory path...',
                                onChanged: _savePluginRwDir,
                                icon: Broken.folder,
                                dominantColor: _currentColor,
                              ),
                              _buildSettingsSwitch(context,
                                  title: 'Unsafe APIs',
                                  value: _unsafeAPIs,
                                  onChanged: _saveUnsafeAPIs),
                            ]),
                        _buildSettingsExpansionTile(
                          title: 'Keybindings',
                          icon: Broken.keyboard,
                          children: [
                            _buildSettingsSwitch(context,
                                title: 'Vim keybindings',
                                value: _vimKeybindings,
                                onChanged: _saveVimKeybindings),
                          ],
                        ),
                        _buildSettingsExpansionTile(
                          title: 'Download',
                          icon: Broken.document_download,
                          children: [
                            SettingsTextField(
                              title: 'spotdl Custom Flags',
                              initialValue: _spotdlFlags,
                              hintText: 'Enter custom flags for spotdl...',
                              onChanged: _saveSpotdlFlags,
                              icon: Broken.setting_4,
                              dominantColor: _currentColor,
                            ),
                          ],
                        ),
                        _buildSettingsExpansionTile(
                          title: 'Cache',
                          icon: Broken.trash,
                          children: [
                            _buildActionButton(
                              icon: Broken.trash,
                              label: 'Clear Cache',
                              isLoading: _isClearingCache,
                              onPressed: _clearCache,
                            ),
                            _buildSettingsSwitch(
                              context,
                              title: 'Clear MP3 cache with app cache',
                              value: _clearMp3Cache,
                              onChanged: _saveClearMp3Cache,
                            ),
                          ],
                        ),
                        _buildSettingsExpansionTile(
                            title: 'Misc',
                            icon: Broken.square,
                            children: [
                              _buildSettingsSwitch(context,
                                  title:
                                      'Auto Convert (converts certain files to a different format)',
                                  value: _autoConvert,
                                  onChanged: _saveAutoConvert),
                              _buildSettingsSwitch(context,
                                  title:
                                      'Auto Create Directories (auto creates certain directories if they do not exist)',
                                  value: _autoCreateDirs,
                                  onChanged: _saveAutoCreateDirs),
                            ])
                      ],
                    ),
                  ),
                  if (_currentSong != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: MiniPlayer(
                        onReloadLibrary: widget.onReloadLibrary,
                        musicFolder: widget.musicFolder,
                        key: _miniPlayerKey,
                        song: _currentSong!,
                        songList: widget.songs,
                        service: widget.service,
                        currentPlaylistName: widget.currentPlaylistName,
                        currentIndex: _currentIndex,
                        onClose: () => widget.onUpdateMiniPlayer?.call(
                          _currentSong!,
                          _currentIndex,
                          _currentColor,
                        ),
                        onUpdate: (newSong, newIndex, newColor) {
                          setState(() {
                            _currentSong = newSong;
                            _currentIndex = newIndex;
                            _currentColor = newColor;
                          });
                          widget.onUpdateMiniPlayer?.call(
                            newSong,
                            newIndex,
                            newColor,
                          );
                        },
                        dominantColor: _currentColor,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ));
  }

  Widget _buildResetButton({required VoidCallback onPressed}) {
    return IconButton(
      icon: GlowIcon(
        Broken.refresh,
        size: 20,
        color: _currentColor,
        glowColor: _currentColor.withAlpha(80),
      ),
      onPressed: onPressed,
    );
  }

  Widget _buildParticleSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required Function(double) onChanged,
    required double defaultValue,
  }) {
    final textColor = _currentColor.computeLuminance() > 0.01
        ? _currentColor
        : Theme.of(context).textTheme.bodyLarge?.color;
    return ListTile(
      title: Text(label, style: TextStyle(color: textColor)),
      subtitle: Slider(
        value: value,
        min: min,
        max: max,
        divisions: 20,
        activeColor: _currentColor,
        inactiveColor: Colors.grey,
        onChanged: (newValue) => onChanged(newValue),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value.toStringAsFixed(2), style: TextStyle(color: textColor)),
          const SizedBox(width: 8),
          _buildResetButton(
            onPressed: () => onChanged(defaultValue),
          ),
        ],
      ),
    );
  }

  Future<void> _showSeparatorManagementPopup() async {
    List<String> currentSeparators = await rust_api.getCurrentSeparators();
    final TextEditingController addController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
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
                          _currentColor.withAlpha(30),
                          Colors.black.withAlpha(200),
                        ],
                      ),
                      border: Border.all(
                        color: _currentColor.withAlpha(100),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GlowText(
                            'Artist Separators',
                            glowColor: _currentColor.withAlpha(80),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _currentColor,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Used to detect multiple artists in song metadata',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Form(
                            key: formKey,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    _currentColor.withAlpha(30),
                                    Colors.black.withAlpha(100),
                                  ],
                                ),
                              ),
                              child: TextFormField(
                                controller: addController,
                                style: TextStyle(color: Colors.white),
                                cursorColor:
                                    _currentColor.computeLuminance() > 0.01
                                        ? _currentColor
                                        : Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.color,
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  hintText: 'Add new separator...',
                                  hintStyle: TextStyle(color: Colors.white70),
                                  prefixIcon: GlowIcon(
                                    Broken.add_circle,
                                    color: _currentColor,
                                    size: 24,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  suffixIcon: Container(
                                    margin: const EdgeInsets.only(right: 8),
                                    child: DynamicIconButton(
                                      icon: Broken.tick,
                                      onPressed: () async {
                                        if (formKey.currentState!.validate()) {
                                          final newSep =
                                              addController.text.trim();
                                          if (newSep.isEmpty) return;

                                          if (currentSeparators
                                              .contains(newSep)) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(AdiSnackbar(
                                              backgroundColor: _currentColor,
                                              content:
                                                  'Separator "$newSep" already exists!',
                                            ));
                                            return;
                                          }

                                          try {
                                            rust_api.addSeparator(
                                                separator: newSep);
                                            final updatedSeparators =
                                                await rust_api
                                                    .getCurrentSeparators();
                                            await SharedPreferencesService
                                                .instance
                                                .setStringList('separators',
                                                    updatedSeparators);

                                            setStateDialog(() {
                                              currentSeparators =
                                                  updatedSeparators;
                                              addController.clear();
                                            });

                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(AdiSnackbar(
                                              backgroundColor: _currentColor,
                                              content:
                                                  'Added "$newSep" separator',
                                            ));
                                          } catch (e) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(AdiSnackbar(
                                              backgroundColor: Colors.redAccent,
                                              content:
                                                  'Failed to add separator: $e',
                                            ));
                                          }
                                        }
                                      },
                                      backgroundColor: _currentColor,
                                      size: 36,
                                    ),
                                  ),
                                ),
                                validator: (value) => value!.isEmpty
                                    ? 'Enter a separator character'
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Flexible(
                            child: currentSeparators.isEmpty
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Broken.grid_9,
                                        color: _currentColor.withAlpha(80),
                                        size: 48,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No custom separators\nAdd some to help identify multiple artists',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  )
                                : ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: currentSeparators.length,
                                    itemBuilder: (context, index) {
                                      final separator =
                                          currentSeparators[index];
                                      return Container(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          gradient: LinearGradient(
                                            colors: [
                                              _currentColor.withAlpha(30),
                                              Colors.black.withAlpha(50),
                                            ],
                                          ),
                                        ),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 16),
                                          leading: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: RadialGradient(
                                                colors: [
                                                  _currentColor.withAlpha(80),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                            child: Text(
                                              separator,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          title: Text(
                                            'Separator ${index + 1}',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          trailing: IconButton(
                                            icon: GlowIcon(
                                              Broken.trash,
                                              color: Colors.redAccent,
                                              size: 20,
                                            ),
                                            onPressed: () async {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  backgroundColor: Colors.black
                                                      .withAlpha(200),
                                                  title: Text(
                                                      'Delete Separator?',
                                                      style: TextStyle(
                                                          color: Colors.white)),
                                                  content: Text(
                                                      'Remove "$separator"?',
                                                      style: TextStyle(
                                                          color:
                                                              Colors.white70)),
                                                  actions: [
                                                    TextButton(
                                                      child: Text('Cancel',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .white70)),
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, false),
                                                    ),
                                                    TextButton(
                                                      child: Text('Delete',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .redAccent)),
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              ctx, true),
                                                    ),
                                                  ],
                                                ),
                                              );

                                              if (confirmed ?? false) {
                                                try {
                                                  rust_api.removeSeparator(
                                                      separator: separator);
                                                  final updatedSeparators =
                                                      await rust_api
                                                          .getCurrentSeparators();
                                                  await SharedPreferencesService
                                                      .instance
                                                      .setStringList(
                                                          'separators',
                                                          updatedSeparators);

                                                  setStateDialog(() =>
                                                      currentSeparators =
                                                          updatedSeparators);

                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(AdiSnackbar(
                                                    backgroundColor:
                                                        _currentColor,
                                                    content:
                                                        'Removed "$separator" separator',
                                                  ));
                                                } catch (e) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(AdiSnackbar(
                                                    backgroundColor:
                                                        Colors.redAccent,
                                                    content:
                                                        'Failed to remove separator: $e',
                                                  ));
                                                }
                                              }
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 16),
                          Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    backgroundColor:
                                        Colors.black.withAlpha(200),
                                    title: Text('Reset Separators?',
                                        style: TextStyle(color: Colors.white)),
                                    content: Text(
                                        'Restore to default separators? This cannot be undone.',
                                        style:
                                            TextStyle(color: Colors.white70)),
                                    actions: [
                                      TextButton(
                                        child: Text('Cancel',
                                            style: TextStyle(
                                                color: Colors.white70)),
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                      ),
                                      TextButton(
                                        child: Text('Reset',
                                            style: TextStyle(
                                                color: _currentColor)),
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmed ?? false) {
                                  try {
                                    rust_api.resetSeparators();
                                    final updatedSeparators =
                                        await rust_api.getCurrentSeparators();
                                    await SharedPreferencesService.instance
                                        .setStringList(
                                            'separators', updatedSeparators);

                                    setStateDialog(() =>
                                        currentSeparators = updatedSeparators);

                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(AdiSnackbar(
                                      backgroundColor: _currentColor,
                                      content: 'Restored default separators',
                                    ));
                                  } catch (e) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(AdiSnackbar(
                                      backgroundColor: Colors.redAccent,
                                      content: 'Failed to reset: $e',
                                    ));
                                  }
                                }
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 20),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _currentColor.withAlpha(100),
                                    width: 1.2,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      _currentColor.withAlpha(30),
                                      Colors.black.withAlpha(50),
                                    ],
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Broken.refresh, color: _currentColor),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Reset to Defaults',
                                      style: TextStyle(
                                        color: _currentColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    //final textColor =
    //    _currentColor.computeLuminance() > 0.01 ? Colors.white : Colors.black;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(15),
        splashColor: _currentColor.withValues(alpha: 0.1),
        highlightColor: _currentColor.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _currentColor.withValues(alpha: 0.3),
                      _currentColor.withValues(alpha: 0.1),
                    ],
                  ),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: textColor,
                        ),
                      )
                    : Icon(icon, color: textColor),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Broken.arrow_right,
                color: textColor!.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsTextField extends StatefulWidget {
  final String title;
  final String initialValue;
  final String hintText;
  final ValueChanged<String> onChanged;
  final IconData icon;
  final Color dominantColor;

  const SettingsTextField({
    super.key,
    required this.title,
    required this.initialValue,
    required this.hintText,
    required this.onChanged,
    required this.icon,
    required this.dominantColor,
  });

  @override
  State<SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(SettingsTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controller value if initialValue changes from parent
    if (oldWidget.initialValue != widget.initialValue && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.dominantColor.computeLuminance() > 0.01
        ? widget.dominantColor
        : Theme.of(context).textTheme.bodyLarge?.color;

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.dominantColor.withValues(alpha: 0.3),
                    widget.dominantColor.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Icon(widget.icon, color: textColor),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.dominantColor.withValues(alpha: 0.1),
                          Colors.black.withValues(alpha: 0.3),
                        ],
                      ),
                      border: Border.all(
                        color: widget.dominantColor.withValues(alpha: 0.2),
                        width: 1.0,
                      ),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      style: TextStyle(color: textColor, fontSize: 14),
                      cursorColor:
                          widget.dominantColor.computeLuminance() > 0.01
                              ? widget.dominantColor
                              : Theme.of(context).textTheme.bodyLarge?.color,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        hintText: widget.hintText,
                        hintStyle: TextStyle(
                          color: textColor!.withValues(alpha: 0.6),
                        ),
                        border: InputBorder.none,
                      ),
                      onChanged: widget.onChanged,
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
