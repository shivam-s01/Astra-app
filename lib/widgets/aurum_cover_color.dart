// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/aurum_theme.dart';
import '../utils/artwork_palette_cache.dart';
import '../utils/aurum_motion.dart';

class PlaylistColorCover extends StatefulWidget {
  final String artworkUrl;
  final double size;
  final double borderRadius;
  final double? iconSize;

  const PlaylistColorCover({
    super.key,
    required this.artworkUrl,
    required this.size,
    this.borderRadius = 12,
    this.iconSize,
  });

  static const Color _fallbackA = AurumTheme.accent;
  static const Color _fallbackB = Color(0xFF3A2F5C);

  @override
  State<PlaylistColorCover> createState() => _PlaylistColorCoverState();
}

class _PlaylistColorCoverState extends State<PlaylistColorCover> {
  List<Color>? _colors;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PlaylistColorCover old) {
    super.didUpdateWidget(old);
    if (old.artworkUrl != widget.artworkUrl) {
      _colors = null;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.artworkUrl;
    if (url.isEmpty) return;

    final fast = ArtworkPaletteCache.peek(url) ?? await ArtworkPaletteCache.getFast(url);
    if (fast != null && mounted) {
      setState(() => _colors = [fast.vibrant, fast.darkMuted]);
    }

    final accurate = await ArtworkPaletteCache.get(url);
    if (mounted) {
      setState(() => _colors = [accurate.vibrant, accurate.darkMuted]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _colors ??
        const [
          PlaylistColorCover._fallbackA,
          PlaylistColorCover._fallbackB,
        ];
    final hasFiniteSize = widget.size.isFinite;
    final shadowBlur = hasFiniteSize ? widget.size * 0.18 : 24.0;
    final shadowOffsetY = hasFiniteSize ? widget.size * 0.06 : 8.0;
    return AnimatedContainer(
      duration: AurumMotion.durationOrZero(AurumMotion.long1),
      curve: Curves.easeOutCubic,
      width: widget.size.isFinite ? widget.size : null,
      height: widget.size.isFinite ? widget.size : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withOpacity(0.35),
            blurRadius: shadowBlur,
            offset: Offset(0, shadowOffsetY),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.16),
                      Colors.white.withOpacity(0.0),
                      Colors.black.withOpacity(0.10),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Icon(
            Icons.queue_music_rounded,
            color: Colors.white.withOpacity(0.92),
            size: widget.iconSize ?? widget.size * 0.4,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: widget.size * 0.06,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
