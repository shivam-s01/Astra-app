// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../services/stream_quality_store.dart';

class AurumStreamQualityChip extends StatelessWidget {
  const AurumStreamQualityChip({super.key, required this.player});
  final PlayerProvider player;

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, String?>(
      selector: (_, p) => p.currentSong?.id,
      builder: (context, _, __) {
        final song = player.currentSong;
        final store = StreamQualityStore.instance;
        final codec = song == null ? null : store.codecFor(song);
        final label = codec ??
            ((song != null && store.showFallback(song)) ? 'Astra' : null);
        final base = Colors.white.withOpacity(0.85);

        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  size: 14,
                  color: base,
                ),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: base,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
