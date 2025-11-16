import 'dart:async';
import 'package:flutter/material.dart';
import 'package:adiman/main.dart';
import 'package:flutter_glow/flutter_glow.dart';
import 'package:adiman/widgets/snackbar.dart';
import 'package:flutter/services.dart';
import 'package:adiman/widgets/icon_buttons.dart';
import 'package:adiman/services/playlist_order_service.dart';
import 'package:adiman/icons/broken_icons.dart';

class PlaylistReorderScreen extends StatefulWidget {
  final String playlistName;
  final String musicFolder;
  final List<Song> songs;

  const PlaylistReorderScreen({
    super.key,
    required this.playlistName,
    required this.musicFolder,
    required this.songs,
  });

  @override
  State<PlaylistReorderScreen> createState() => _PlaylistReorderScreenState();
}

class _PlaylistReorderScreenState extends State<PlaylistReorderScreen> {
  late List<Song> _reorderedSongs;
  late Color _dominantColor;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _reorderedSongs = List.from(widget.songs);
    _dominantColor = defaultThemeColorNotifier.value;
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _saveNewOrder() async {
    final orderedPaths = _reorderedSongs.map((song) => song.path).toList();
    await PlaylistOrderDatabase().updatePlaylistOrder(
      widget.playlistName,
      orderedPaths,
    );

    ScaffoldMessenger.of(context).showSnackBar(AdiSnackbar(
      backgroundColor: _dominantColor,
      content: 'Playlist order saved',
    ));

    Navigator.pop(context);
  }

  void _ensureFocus() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  Widget _buildSongItem(Song song, int index) {
    return Container(
      key: ValueKey(song.path),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _dominantColor.withAlpha(15),
            Colors.black.withAlpha(60),
          ],
        ),
        border: Border.all(
          color: _dominantColor.withAlpha(50),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: _dominantColor.withAlpha(20),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: ReorderableDragStartListener(
        index: index,
        child: GestureDetector(
          onTap: _ensureFocus,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Hero(
              tag: 'albumArt-${song.path}',
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _dominantColor.withAlpha(40),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: song.albumArt != null
                      ? Image.memory(
                          song.albumArt!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _dominantColor.withAlpha(60),
                                Colors.black.withAlpha(120),
                              ],
                            ),
                          ),
                          child: Icon(
                            Broken.musicnote,
                            color: Colors.white70,
                            size: 24,
                          ),
                        ),
                ),
              ),
            ),
            title: GlowText(
              song.title,
              glowColor: _dominantColor.withAlpha(40),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              song.artist,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(
              Broken.double_lines,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
        }
      },
      child: GestureDetector(
        onTap: _ensureFocus,
        child: Theme(
          data: ThemeData.dark().copyWith(
            // Remove drag highlight colors
            canvasColor: Colors.transparent,
            cardColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
          ),
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              leading: DynamicIconButton(
                icon: Broken.arrow_left,
                onPressed: () => Navigator.pop(context),
                backgroundColor: _dominantColor,
                size: 40,
              ),
              title: GlowText(
                'Reorder ${widget.playlistName}',
                glowColor: _dominantColor.withAlpha(60),
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              backgroundColor: Colors.black,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              actions: [
                DynamicIconButton(
                  icon: Broken.tick,
                  onPressed: _saveNewOrder,
                  backgroundColor: _dominantColor,
                  size: 40,
                ),
                const SizedBox(width: 12),
              ],
            ),
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    _dominantColor.withAlpha(15),
                  ],
                ),
              ),
              child: _reorderedSongs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GlowIcon(
                            Broken.music_playlist,
                            color: _dominantColor.withAlpha(80),
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          GlowText(
                            'No songs in playlist',
                            glowColor: _dominantColor.withAlpha(60),
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.all(16),
                      proxyDecorator: (child, index, animation) {
                        // Custom proxy decorator to remove highlight during drag
                        return Material(
                          color: Colors.transparent,
                          elevation: 0,
                          child: child,
                        );
                      },
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) {
                            newIndex -= 1;
                          }
                          final Song item = _reorderedSongs.removeAt(oldIndex);
                          _reorderedSongs.insert(newIndex, item);
                        });
                        // Re-request focus after reordering
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _ensureFocus();
                        });
                      },
                      children: [
                        for (int i = 0; i < _reorderedSongs.length; i++)
                          _buildSongItem(_reorderedSongs[i], i),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
