// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:expressive_loading_indicator/expressive_loading_indicator.dart';
import '../providers/theme_provider.dart';

const Color kAurumMorphBlue = Color(0xFFA855F7);

class AurumMorphLoader extends StatelessWidget {
  const AurumMorphLoader({
    super.key,
    this.size = 40.0,
    this.color,
    this.contained = false,
    this.containerColor,
    this.morphDuration = const Duration(milliseconds: 650),
    this.rotateDuration = const Duration(milliseconds: 4000),
  });

  final double size;

  final Color? color;

  final bool contained;

  final Color? containerColor;

  final Duration morphDuration;
  final Duration rotateDuration;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ??
        (context.select<ThemeProvider, Color>((tp) => tp.accentColor));

    final indicator = ExpressiveLoadingIndicator(
      color: resolvedColor,
      constraints: BoxConstraints(
        minWidth: size,
        minHeight: size,
        maxWidth: size,
        maxHeight: size,
      ),
    );

    if (!contained) {
      return RepaintBoundary(child: indicator);
    }

    final containerSize = size / (38 / 48);
    return RepaintBoundary(
      child: Container(
        width: containerSize,
        height: containerSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: containerColor ?? resolvedColor.withOpacity(0.16),
        ),
        alignment: Alignment.center,
        child: indicator,
      ),
    );
  }
}
