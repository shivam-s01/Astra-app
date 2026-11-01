// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/favorites_provider.dart';
import '../theme/aurum_theme.dart';
import '../services/api_service.dart';
import 'aurum_like_button.dart';
import 'aurum_stacked_artwork.dart';
import '../utils/aurum_haptics.dart';
import 'aurum_song_options_sheet.dart';
import 'aurum_wide_thumb.dart';
import 'aurum_equalizer_bars.dart';

class SongTile extends StatefulWidget {
  final Song song;
  final List<Song>? queue;
  final int? index;
  final bool showIndex;
  final int? displayIndex;
  final bool curatedQueue;

  final VoidCallback? onLongPressOverride;

  final bool ytStyle;

  const SongTile({
    super.key,
    required this.song,
    this.queue,
    this.index,
    this.showIndex = false,
    this.displayIndex,
    this.curatedQueue = false,
    this.onLongPressOverride,
    this.ytStyle = false,
  });

  @override
  State<SongTile> createState() => _SongTileState();
}

class _SongTileState extends State<SongTile> {
  bool _isTapping = false;

  Timer? _prewarmTimer;

  @override
  void initState() {
    super.initState();
    if (widget.song.source == SongSource.youtube) {
      final delayMs = 120 + (widget.song.id.hashCode.abs() % 280);
      _prewarmTimer = Timer(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        ApiService.prewarmYtStream(widget.song);
      });
    }
  }

  @override
  void dispose() {
    _prewarmTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleTap(BuildContext context) async {
    if (_isTapping) return;
    _isTapping = true;
    AurumHaptics.light();
    try {
      context.read<PlayerProvider>().playSong(
            widget.song,
            queue: widget.queue ?? [widget.song],
            index: widget.index ?? 0,
            curatedQueue: widget.curatedQueue,
          ).catchError((e) {
        debugPrint('[SongTile] playSong error: $e');
      });
    } finally {
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) _isTapping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLiked = widget.ytStyle
        ? false
        : context.select<FavoritesProvider, bool>(
            (fav) => fav.isFavorite(widget.song.id),
          );
    final isCurrentSong = context.select<PlayerProvider, bool>(
      (p) => p.currentSong?.id == widget.song.id,
    );
    final isActuallyPlaying = context.select<PlayerProvider, bool>(
      (p) => p.currentSong?.id == widget.song.id && p.isPlaying,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (widget.ytStyle) {
      return _buildYtStyle(context, isCurrentSong, isActuallyPlaying, isDark);
    }
    return RepaintBoundary(
      child: InkWell(
      onTap: () => _handleTap(context),
      onLongPress: widget.onLongPressOverride ?? () => _showOptions(context),
      borderRadius: BorderRadius.circular(8),
      splashColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
      highlightColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (widget.showIndex) ...[
              SizedBox(
                width: 28,
                child: isCurrentSong
                    ? const SizedBox.shrink()
                    : Text(
                        '${widget.displayIndex ?? (widget.index ?? 0) + 1}',
                        style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 8),
            ],
            AurumStackedArtwork(
              url: widget.song.artworkUrl,
              size: 58,
              borderRadius: 10,
              showNowPlaying: isCurrentSong,
              isPlaying: isActuallyPlaying,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.song.title,
                    style: TextStyle(
                      color: isCurrentSong ? AurumTheme.accentOf(context) : AurumTheme.textPrimaryOf(context),
                      fontSize: 16,
                      fontWeight: isCurrentSong ? FontWeight.w700 : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.song.artist,
                    style: TextStyle(color: AurumTheme.textSecondaryOf(context), fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            AurumLikeButton(
              isLiked: isLiked,
              size: 19,
              unlikedColor: AurumTheme.textMutedOf(context),
              onTap: () => context.read<FavoritesProvider>().toggleFavorite(widget.song),
            ),
            const SizedBox(width: 4),
            if (widget.song.durationString.isNotEmpty)
              Text(
                widget.song.durationString,
                style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12),
              ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _showOptions(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.more_vert_rounded, color: AurumTheme.textMutedOf(context), size: 18),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildYtStyle(
    BuildContext context,
    bool isCurrentSong,
    bool isPlaying,
    bool isDark,
  ) {
    final accent = AurumTheme.accentOf(context);
    final dividerColor =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    return RepaintBoundary(
      child: InkWell(
        onTap: () => _handleTap(context),
        onLongPress: widget.onLongPressOverride ?? () => _showOptions(context),
        splashColor:
            (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        highlightColor:
            (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 9, 4, 9),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      AurumWideThumb(
                        url: widget.song.artworkUrl,
                        width: 80,
                        height: 45,
                        borderRadius: 6,
                      ),
                      if (isCurrentSong)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: AurumEqualizerBars(
                                playing: isPlaying,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrentSong
                                ? accent
                                : AurumTheme.textPrimaryOf(context),
                            fontSize: 16,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AurumTheme.textSecondaryOf(context),
                            fontSize: 13.5,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showOptions(context),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.more_vert_rounded,
                        size: 22,
                        color: AurumTheme.textSecondaryOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 114, right: 16),
              child: Divider(height: 1, thickness: 0.6, color: dividerColor),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showAurumSongOptions(context, widget.song, compact: widget.ytStyle);
  }
}
