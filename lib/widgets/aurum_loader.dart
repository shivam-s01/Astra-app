// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aurum_music/widgets/aurum_morph_loader.dart';
import 'package:aurum_music/providers/theme_provider.dart';
import 'package:aurum_music/theme/aurum_theme.dart';
export 'package:aurum_music/widgets/aurum_morph_loader.dart';

Color _ensureContrast(Color color, Color surface) {
  final colorLum = color.computeLuminance();
  final surfaceLum = surface.computeLuminance();
  if ((colorLum - surfaceLum).abs() > 0.25) return color;
  final target = surfaceLum > 0.5 ? Colors.black : Colors.white;
  return Color.lerp(color, target, 0.45)!;
}

class AurumM3Loader extends StatefulWidget {
  const AurumM3Loader({
    super.key,
    this.width,
    this.height = 3.0,
    this.borderRadius = 99.0,
  });

  final double? width;
  final double  height;
  final double  borderRadius;

  @override
  State<AurumM3Loader> createState() => _AurumM3LoaderState();
}

class _AurumM3LoaderState extends State<AurumM3Loader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static final _s1s = CurveTween(curve: const Interval(0.0,  0.70, curve: Curves.easeIn));
  static final _s1e = CurveTween(curve: const Interval(0.10, 0.90, curve: Curves.fastOutSlowIn));
  static final _s2s = CurveTween(curve: const Interval(0.40, 0.98, curve: Curves.easeIn));
  static final _s2e = CurveTween(curve: const Interval(0.50, 1.00, curve: Curves.fastOutSlowIn));

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final rawAccent = context.select<ThemeProvider, Color>((tp) => tp.accentColor);
    final surface = AurumTheme.bgCardOf(context);
    final accent = _ensureContrast(rawAccent, surface);
    final accentLight = Color.lerp(accent, Colors.white, 0.30)!;
    final accentDark = Color.lerp(accent, Colors.black, 0.35)!;

    final painter = AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _M3Painter(
          s1s: _s1s.evaluate(_ctrl),
          s1e: _s1e.evaluate(_ctrl),
          s2s: _s2s.evaluate(_ctrl),
          s2e: _s2e.evaluate(_ctrl),
          h: widget.height,
          r: widget.borderRadius,
          base: accent,
          light: accentLight,
          dark: accentDark,
        ),
      ),
    );

    if (widget.width != null) {
      return RepaintBoundary(
        child: SizedBox(width: widget.width, height: widget.height, child: painter),
      );
    }

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : (constraints.biggest.width.isFinite
                  ? constraints.biggest.width
                  : MediaQuery.sizeOf(context).width);
          return SizedBox(width: w, height: widget.height, child: painter);
        },
      ),
    );
  }
}

class _M3Painter extends CustomPainter {
  const _M3Painter({
    required this.s1s, required this.s1e,
    required this.s2s, required this.s2e,
    required this.h,   required this.r,
    required this.base, required this.light, required this.dark,
  });

  final double s1s, s1e, s2s, s2e, h, r;
  final Color base, light, dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w  = size.width;
    final br = math.min(r, h / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(br)),
      Paint()..color = base.withOpacity(0.10),
    );

    void seg(double normStart, double normEnd) {
      if (normEnd <= normStart) return;
      final left  = (normStart * w).clamp(0.0, w);
      final right = (normEnd   * w).clamp(0.0, w);
      if (right - left < 0.5) return;

      final rect  = Rect.fromLTWH(left, 0, right - left, h);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(br));

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(h), Radius.circular(br + h)),
        Paint()
          ..color      = light.withOpacity(0.18)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 2),
      );

      canvas.drawRRect(rrect, Paint()
        ..shader = ui.Gradient.linear(
          Offset(left, 0), Offset(right, 0),
          [dark, base, light],
          [0.0, 0.5, 1.0],
        ));

      final headW = math.min(h * 3, right - left);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(right - headW, 0, headW, h),
          Radius.circular(br),
        ),
        Paint()..shader = ui.Gradient.linear(
          Offset(right - headW, 0), Offset(right, 0),
          [Colors.transparent, Colors.white.withOpacity(0.55)],
        ),
      );
    }

    seg(s1s, s1e);
    seg(s2s, s2e);
  }

  @override
  bool shouldRepaint(covariant _M3Painter o) =>
      o.s1s != s1s || o.s1e != s1e || o.s2s != s2s || o.s2e != s2e ||
      o.base != base || o.light != light || o.dark != dark;
}

class AurumM3Spinner extends StatelessWidget {
  const AurumM3Spinner({super.key, this.size = 28.0});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: Center(child: AurumM3Loader(width: size, height: 2.5)),
  );
}

class AurumLoaderScreen extends StatelessWidget {
  const AurumLoaderScreen({super.key, this.onCompleted});
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: const Center(
        child: AurumMorphLoader(size: 56, contained: true),
      ),
    );
  }
}
