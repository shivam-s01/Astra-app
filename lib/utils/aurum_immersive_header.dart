// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/aurum_theme.dart';
import '../widgets/aurum_glass.dart';
import 'artwork_palette_cache.dart';

Future<Color?> extractImmersiveColor(
  String artworkUrl, {
  Color fallback = const Color(0xFF1A1630),
}) async {
  if (artworkUrl.isEmpty) return null;

  final cached = ArtworkPaletteCache.peek(artworkUrl);
  if (cached != null) return _pickMuted(cached);

  final accurateFuture = ArtworkPaletteCache.get(artworkUrl);
  final fast = await ArtworkPaletteCache.getFast(artworkUrl);
  if (fast != null) return _pickMuted(fast);

  final accurate = await accurateFuture;
  return _pickMuted(accurate);
}

Color _pickMuted(ArtworkPalette p) => p.darkMuted;

BoxDecoration immersiveHeaderScrim(Color glow) {
  final textSafeBottom = Color.alphaBlend(
    glow.withOpacity(0.55),
    const Color(0xFF0A0810),
  );
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        glow.withOpacity(0.10),
        glow.withOpacity(0.35),
        glow.withOpacity(0.70),
        textSafeBottom,
      ],
      stops: const [0.0, 0.45, 0.80, 1.0],
    ),
  );
}

Color immersiveScaffoldBg(BuildContext context, Color? glow) {
  if (glow == null) return AurumTheme.bgOf(context);
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final hsl = HSLColor.fromColor(glow);

  final Color tinted;
  final double blendOpacity;
  if (isDark) {
    tinted = hsl
        .withLightness((hsl.lightness * 0.45).clamp(0.09, 0.22))
        .withSaturation((hsl.saturation * 0.55).clamp(0.0, 0.45))
        .toColor();
    blendOpacity = 0.92;
  } else {
    tinted = hsl
        .withLightness((0.90 + hsl.lightness * 0.08).clamp(0.90, 0.97))
        .withSaturation((hsl.saturation * 0.35).clamp(0.0, 0.22))
        .toColor();
    blendOpacity = 0.55;
  }

  return Color.alphaBlend(
    tinted.withOpacity(blendOpacity),
    AurumTheme.bgOf(context),
  );
}

class AurumGlassCollapseBar extends StatelessWidget {
  final Color glow;
  final double expandRatio;
  final double barHeight;

  const AurumGlassCollapseBar({
    super.key,
    required this.glow,
    required this.expandRatio,
    this.barHeight = kToolbarHeight,
  });

  static const double _minStrength = 0.0;

  @override
  Widget build(BuildContext context) {
    final collapseRaw = (1.0 - expandRatio).clamp(0.0, 1.0);
    final strength = _minStrength + (1.0 - _minStrength) * collapseRaw;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Opacity(
        opacity: strength,
        child: AurumGlass(
          sigma: 18 * strength,
          borderRadius: BorderRadius.zero,
          isDark: isDark,
          tintColor: glow,
          child: SizedBox(
            height: barHeight + MediaQuery.of(context).padding.top,
            width: double.infinity,
          ),
        ),
      ),
    );
  }
}
