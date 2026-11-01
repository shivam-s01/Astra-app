// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;

class AurumGlass extends StatelessWidget {
  final Widget child;
  final double sigma;
  final BorderRadius borderRadius;
  final bool isDark;

  final Color? tintColor;

  final bool useTintInGlass;

  const AurumGlass({
    super.key,
    required this.child,
    required this.sigma,
    required this.borderRadius,
    required this.isDark,
    this.tintColor,
    this.useTintInGlass = false,
  });

  @override
  Widget build(BuildContext context) {
    if (sigma <= 0) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Container(
          decoration: BoxDecoration(
            color: tintColor ??
                (isDark ? const Color(0xFF1B1927) : Colors.white),
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      );
    }

    final base = useTintInGlass
        ? (tintColor ?? (isDark ? Colors.black : Colors.white))
        : (isDark ? Colors.black : Colors.white);
    final blur = (sigma * 0.55).clamp(4.0, 10.0);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: TileMode.clamp,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                base.withValues(alpha: isDark ? 0.30 : 0.34),
                base.withValues(alpha: isDark ? 0.20 : 0.22),
              ],
            ),
          ),
          child: borderRadius == BorderRadius.zero
              ? child
              : CustomPaint(
                  foregroundPainter: _GlassRimPainter(
                    radius: borderRadius,
                    isDark: isDark,
                  ),
                  child: child,
                ),
        ),
      ),
    );
  }
}

class _GlassRimPainter extends CustomPainter {
  final BorderRadius radius;
  final bool isDark;
  const _GlassRimPainter({required this.radius, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const w = 0.7;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(w / 2);
    final hi = Colors.white.withValues(alpha: isDark ? 0.42 : 0.70);
    final lo = Colors.white.withValues(alpha: isDark ? 0.06 : 0.18);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [hi, lo, lo, hi.withValues(alpha: hi.a * 0.45)],
        stops: const [0.0, 0.42, 0.7, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) =>
      old.radius != radius || old.isDark != isDark;
}

class GlassSafeEnter extends StatelessWidget {
  final Animation<double> anim;
  final Widget child;
  const GlassSafeEnter({super.key, required this.anim, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
