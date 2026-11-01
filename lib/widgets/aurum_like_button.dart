// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_motion.dart';

class AurumLikeButton extends StatefulWidget {
  const AurumLikeButton({
    super.key,
    required this.isLiked,
    required this.onTap,
    this.size = 20,
    this.likedColor = const Color(0xFFE1306C),
    this.unlikedColor,
    this.haptic = true,
  });

  final bool isLiked;
  final VoidCallback onTap;
  final double size;
  final Color likedColor;

  final Color? unlikedColor;

  final bool haptic;

  @override
  State<AurumLikeButton> createState() => _AurumLikeButtonState();
}

class _AurumLikeButtonState extends State<AurumLikeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static final List<_Sparkle> _sparkles = List.generate(6, (i) {
    final angle = (i / 6) * math.pi * 2 + 0.35;
    return _Sparkle(angle: angle, distance: 0.85 + (i.isEven ? 0.15 : 0.0));
  });

  bool _wasLiked = false;

  @override
  void initState() {
    super.initState();
    _wasLiked = widget.isLiked;
    _ctrl = AnimationController(
      vsync: this,
      duration: AurumMotion.durationOrZero(AurumMotion.long2),
    );
  }

  @override
  void didUpdateWidget(covariant AurumLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLiked != _wasLiked) {
      _wasLiked = widget.isLiked;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.haptic) {
      widget.isLiked
          ? AurumHaptics.selection()
          : AurumHaptics.medium();
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final unlikedColor = widget.unlikedColor ?? Colors.grey.withAlpha(150);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: SizedBox(
        width: widget.size * 2.2,
        height: widget.size * 2.2,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final liked = widget.isLiked;

            double scale;
            double wobble = 0;
            if (liked) {
              if (t < 0.35) {
                final p = t / 0.35;
                scale = 1.0 + (0.32 * Curves.easeOutBack.transform(p));
              } else {
                final p = (t - 0.35) / 0.65;
                scale = 1.32 - (0.32 * Curves.easeOutCubic.transform(p));
              }
            } else {
              if (t < 0.25) {
                final p = t / 0.25;
                scale = 1.0 - (0.18 * Curves.easeOut.transform(p));
              } else {
                final p = ((t - 0.25) / 0.75).clamp(0.0, 1.0);
                scale = 0.82 + (0.18 * Curves.easeOutCubic.transform(p));
              }
              if (t < 0.4) {
                wobble = math.sin(t * math.pi * 6) * (1 - t / 0.4) * 3;
              }
            }

            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (liked && t < 0.55)
                  CustomPaint(
                    size: Size(widget.size * 2.2, widget.size * 2.2),
                    painter: _SparklePainter(
                      progress: (t / 0.55).clamp(0.0, 1.0),
                      color: widget.likedColor,
                      sparkles: _sparkles,
                    ),
                  ),
                Transform.translate(
                  offset: Offset(wobble, 0),
                  child: Transform.scale(
                    scale: scale,
                    child: Icon(
                      liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: liked ? widget.likedColor : unlikedColor,
                      size: widget.size,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Sparkle {
  final double angle;
  final double distance;
  const _Sparkle({required this.angle, required this.distance});
}

class _SparklePainter extends CustomPainter {
  final double progress;
  final Color color;
  final List<_Sparkle> sparkles;

  _SparklePainter({
    required this.progress,
    required this.color,
    required this.sparkles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxTravel = size.width * 0.32;
    final travel = Curves.easeOutCubic.transform(progress) * maxTravel;
    final opacity = (1.0 - progress).clamp(0.0, 1.0);
    if (opacity <= 0) return;

    final paint = Paint()..color = color.withOpacity(opacity * 0.9);
    for (final s in sparkles) {
      final dx = math.cos(s.angle) * travel * s.distance;
      final dy = math.sin(s.angle) * travel * s.distance;
      final radius = 1.6 * (1.0 - progress * 0.4);
      canvas.drawCircle(center + Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) =>
      old.progress != progress || old.color != color;
}
