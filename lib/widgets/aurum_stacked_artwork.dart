// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/aurum_theme.dart';
import 'aurum_artwork.dart';
import 'aurum_equalizer_bars.dart';

class AurumStackedArtwork extends StatelessWidget {
  final String url;
  final double size;
  final double borderRadius;
  final bool circular;
  final bool showNowPlaying;
  final bool isPlaying;
  final Color? stackColor;

  const AurumStackedArtwork({
    super.key,
    required this.url,
    required this.size,
    this.borderRadius = 8,
    this.circular = false,
    this.showNowPlaying = false,
    this.isPlaying = false,
    this.stackColor,
  });

  @override
  Widget build(BuildContext context) {
    final tint = stackColor ?? AurumTheme.textPrimaryOf(context);
    final stackRadius = circular ? size / 2 : borderRadius;

    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (circular) ...[
            Transform.translate(
              offset: const Offset(0, -4),
              child: Container(
                width: size - 3,
                height: size - 3,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(stackRadius),
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -2.5),
              child: Container(
                width: size - 1.5,
                height: size - 1.5,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(stackRadius),
                ),
              ),
            ),
          ],
          circular
              ? ClipOval(
                  child: AurumArtwork(url: url, size: size, borderRadius: 0),
                )
              : AurumArtwork(url: url, size: size, borderRadius: borderRadius),

          if (showNowPlaying)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(stackRadius),
              ),
              alignment: Alignment.center,
              child: AurumEqualizerBars(
                playing: isPlaying,
                color: Colors.white,
                size: size * 0.36,
              ),
            ),
        ],
      ),
    );
  }
}
