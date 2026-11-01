// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/aurum_theme.dart';
import '../services/audio_prefs.dart';

class SplashScreen extends StatefulWidget {
  final Widget child;
  const SplashScreen({super.key, required this.child});

  static final ValueNotifier<bool> finishedNotifier = ValueNotifier<bool>(false);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static bool _played = false;

  bool _showSplash = false;
  bool _controllerCreated = false;

  late final AnimationController _timeline;
  late final AnimationController _fadeController;
  late final List<_Particle> _particles;

  static const _timelineDuration = Duration(milliseconds: 3200);
  static const _fadeOutDuration = Duration(milliseconds: 420);

  static const _cyan = Color(0xFF4FE8D8);
  static const _violet = Color(0xFFA47BFF);
  static const _paleCyan = Color(0xFF8FF6E9);
  static const _paleViolet = Color(0xFFC9A6FF);
  static const _musicTextColorDark = Color(0xFFDEDCE6);
  static const _musicTextColorLight = Color(0xFF2A2733);

  @override
  void initState() {
    super.initState();
    if (_played || !AudioPrefs.enableAnimationsNotifier.value) {
      _played = true;
      SplashScreen.finishedNotifier.value = true;
      return;
    }
    _showSplash = true;
    _played = true;
    _controllerCreated = true;

    _timeline = AnimationController(vsync: this, duration: _timelineDuration)
      ..forward();
    _fadeController = AnimationController(
      vsync: this,
      duration: _fadeOutDuration,
    );

    final rng = math.Random();
    _particles = List.generate(22, (i) {
      const colors = [_paleCyan, _cyan, _violet, _paleViolet];
      return _Particle(
        startX: rng.nextDouble(),
        startYFactor: 0.35 + rng.nextDouble() * 0.6,
        size: 1.0 + rng.nextDouble() * 2.2,
        dx: (rng.nextDouble() - 0.5) * 30,
        maxOpacity: 0.15 + rng.nextDouble() * 0.35,
        duration: 7 + rng.nextDouble() * 9,
        delay: rng.nextDouble() * 3.5,
        color: colors[rng.nextInt(colors.length)],
      );
    });

    _timeline.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  void _finish() {
    if (!mounted || !_showSplash) return;
    if (_fadeController.status == AnimationStatus.forward ||
        _fadeController.status == AnimationStatus.completed) {
      return;
    }
    _fadeController.forward().whenComplete(() {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _showSplash = false);
          SplashScreen.finishedNotifier.value = true;
        });
      });
    });
  }

  @override
  void dispose() {
    if (_controllerCreated) {
      _timeline.dispose();
      _fadeController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (_showSplash) _buildOverlay(context),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final handoffBg = AurumTheme.bgOf(context);
    final musicTextColor = ThemeData.estimateBrightnessForColor(handoffBg) ==
            Brightness.dark
        ? _musicTextColorDark
        : _musicTextColorLight;
    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, _) {
        return Opacity(
          opacity: 1.0 - _fadeController.value,
          child: IgnorePointer(
            child: Container(
              color: handoffBg,
              width: double.infinity,
              height: double.infinity,
              child: _SplashContent(
                timeline: _timeline,
                particles: _particles,
                screenSize: size,
                cyan: _cyan,
                violet: _violet,
                paleCyan: _paleCyan,
                paleViolet: _paleViolet,
                musicColor: musicTextColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Particle {
  final double startX;
  final double startYFactor;
  final double size;
  final double dx;
  final double maxOpacity;
  final double duration;
  final double delay;
  final Color color;

  _Particle({
    required this.startX,
    required this.startYFactor,
    required this.size,
    required this.dx,
    required this.maxOpacity,
    required this.duration,
    required this.delay,
    required this.color,
  });
}

class _SplashContent extends StatelessWidget {
  final AnimationController timeline;
  final List<_Particle> particles;
  final Size screenSize;
  final Color cyan;
  final Color violet;
  final Color paleCyan;
  final Color paleViolet;
  final Color musicColor;

  const _SplashContent({
    required this.timeline,
    required this.particles,
    required this.screenSize,
    required this.cyan,
    required this.violet,
    required this.paleCyan,
    required this.paleViolet,
    required this.musicColor,
  });

  static double _t(double v, double start, double end) {
    if (end <= start) return v >= end ? 1.0 : 0.0;
    return ((v - start) / (end - start)).clamp(0.0, 1.0);
  }

  static double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();

  @override
  Widget build(BuildContext context) {
    final wordmarkWidth = math.min(screenSize.width * 0.74, 340.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: timeline,
              builder: (context, _) {
                final elapsedS = timeline.value * 3.2;
                return CustomPaint(
                  painter: _ParticlePainter(
                    particles: particles,
                    elapsedSeconds: elapsedS,
                  ),
                );
              },
            ),
          ),
        ),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: timeline,
            builder: (context, _) {
              final v = timeline.value;
              final glowT = _easeOutCubic(_t(v, 0.123 / 3.2, 2.338 / 3.2));
              return Opacity(
                opacity: glowT,
                child: Transform.scale(
                  scale: 1.0 + glowT * 0.05,
                  child: Container(
                    width: 460,
                    height: 460,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          cyan.withOpacity(0.07),
                          violet.withOpacity(0.035),
                          violet.withOpacity(0.012),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.38, 0.62, 0.78],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: timeline,
            builder: (context, _) {
              final v = timeline.value;
              final drawT = _easeOutCubic(_t(v, 0.185 / 3.2, 1.846 / 3.2));
              final fillT = _t(v, 1.538 / 3.2, 2.154 / 3.2);
              final sheenT = _t(v, 1.908 / 3.2, 3.2 / 3.2);
              final subtitleT = _easeOutCubic(_t(v, 1.662 / 3.2, 2.40 / 3.2));
              final underlineT = _easeOutCubic(_t(v, 2.092 / 3.2, 2.954 / 3.2));

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: wordmarkWidth,
                    height: wordmarkWidth * (160 / 620),
                    child: CustomPaint(
                      painter: _WordmarkPainter(
                        drawT: drawT,
                        fillT: fillT,
                        sheenT: sheenT,
                        cyan: cyan,
                        violet: violet,
                        paleCyan: paleCyan,
                        paleViolet: paleViolet,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Opacity(
                    opacity: subtitleT,
                    child: Transform.translate(
                      offset: Offset(0, (1 - subtitleT) * 24),
                      child: Text(
                        'MUSIC',
                        style: TextStyle(
                          fontSize: math.min(screenSize.width * 0.064, 27),
                          fontWeight: FontWeight.w400,
                          letterSpacing: 8,
                          color: musicColor.withOpacity(0.85),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.center,
                      widthFactor: underlineT,
                      child: Container(
                        width: 120,
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [cyan, violet]),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WordmarkPainter extends CustomPainter {
  final double drawT;
  final double fillT;
  final double sheenT;
  final Color cyan;
  final Color violet;
  final Color paleCyan;
  final Color paleViolet;

  static double? _cachedFontSize;
  static TextPainter? _cachedMeasureTp;
  static TextPainter? _cachedStrokeTp;
  static TextPainter? _cachedFillTp;
  static Shader? _cachedShader;
  static Rect? _cachedTextRect;
  static Offset? _cachedOffset;

  _WordmarkPainter({
    required this.drawT,
    required this.fillT,
    required this.sheenT,
    required this.cyan,
    required this.violet,
    required this.paleCyan,
    required this.paleViolet,
  });

  void _ensureLayout(Size size) {
    final fontSize = size.height * (118 / 160);
    if (_cachedFontSize == fontSize && _cachedMeasureTp != null) {
      return;
    }
    const text = 'ASTRA';
    final gradient = LinearGradient(
      colors: [paleCyan, cyan, violet, paleViolet],
      stops: const [0.0, 0.40, 0.75, 1.0],
    );
    final baseStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 2,
    );

    final measureTp = TextPainter(
      text: TextSpan(text: text, style: baseStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(
      (size.width - measureTp.width) / 2,
      (size.height - measureTp.height) / 2,
    );
    final textRect = offset & measureTp.size;
    final shader = gradient.createShader(textRect);

    final strokeStyle = baseStyle.copyWith(
      foreground: Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final strokeTp = TextPainter(
      text: TextSpan(text: text, style: strokeStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    final fillStyle = baseStyle.copyWith(
      foreground: Paint()
        ..shader = shader
        ..style = PaintingStyle.fill,
    );
    final fillTp = TextPainter(
      text: TextSpan(text: text, style: fillStyle),
      textDirection: TextDirection.ltr,
    )..layout();

    _cachedFontSize = fontSize;
    _cachedMeasureTp = measureTp;
    _cachedStrokeTp = strokeTp;
    _cachedFillTp = fillTp;
    _cachedShader = shader;
    _cachedTextRect = textRect;
    _cachedOffset = offset;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _ensureLayout(size);
    final offset = _cachedOffset!;
    final textRect = _cachedTextRect!;

    if (drawT > 0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
        textRect.left,
        textRect.top - 20,
        textRect.width * drawT,
        textRect.height + 40,
      ));
      _cachedStrokeTp!.paint(canvas, offset);
      canvas.restore();
    }

    if (fillT > 0) {
      canvas.saveLayer(
        textRect.inflate(20),
        Paint()..color = Colors.white.withOpacity(fillT),
      );
      _cachedFillTp!.paint(canvas, offset);
      canvas.restore();
    }

    if (sheenT > 0 && sheenT < 1 && fillT > 0.99) {
      canvas.save();
      canvas.clipRect(textRect);
      final sweepX = textRect.left - 140 + (textRect.width + 280) * sheenT;
      final sheenOpacity = sheenT < 0.15
          ? (sheenT / 0.15) * 0.9
          : sheenT > 0.55
              ? ((1 - sheenT) / 0.45) * 0.9
              : 0.9;
      final sheenPaint = Paint()
        ..color = Colors.white.withOpacity(sheenOpacity.clamp(0.0, 0.9))
        ..style = PaintingStyle.fill;
      canvas.save();
      canvas.translate(sweepX, textRect.center.dy);
      canvas.rotate(-20 * math.pi / 180);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 60, height: 220),
        sheenPaint,
      );
      canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WordmarkPainter old) {
    return old.drawT != drawT || old.fillT != fillT || old.sheenT != sheenT;
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double elapsedSeconds;

  _ParticlePainter({required this.particles, required this.elapsedSeconds});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final localT = elapsedSeconds - p.delay;
      if (localT <= 0) continue;
      final fadeT = (localT / 1.2).clamp(0.0, 1.0);
      final driftT = (localT % p.duration) / p.duration;
      final opacity = p.maxOpacity * fadeT;
      if (opacity <= 0.001) continue;

      final startX = p.startX * size.width;
      final startY = p.startYFactor * size.height;
      final x = startX + p.dx * driftT;
      final y = startY - 70 * driftT;

      final paint = Paint()
        ..color = p.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.elapsedSeconds != elapsedSeconds;
}
