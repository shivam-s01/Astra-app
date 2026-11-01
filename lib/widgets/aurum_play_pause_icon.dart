// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class AurumPlayPauseIcon extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double size;
  final Duration duration;

  const AurumPlayPauseIcon({
    super.key,
    required this.isPlaying,
    required this.color,
    this.size = 36,
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<AurumPlayPauseIcon> createState() => _AurumPlayPauseIconState();
}

class _AurumPlayPauseIconState extends State<AurumPlayPauseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.isPlaying ? 1.0 : 0.0,
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.fastOutSlowIn);
  }

  @override
  void didUpdateWidget(AurumPlayPauseIcon old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying != old.isPlaying) {
      if (widget.isPlaying) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final t = _curve.value;
        final half = (t * 2).clamp(0.0, 2.0);
        final scale = half <= 1.0
            ? 1.0 + 0.25 * half
            : 1.0 + 0.25 * (2.0 - half);
        final rotationTurns = t * 0.25;
        return Transform.rotate(
          angle: rotationTurns * 3.14159265358979 * 2,
          child: Transform.scale(
            scale: scale,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _PlayPausePainter(t: t, color: widget.color),
            ),
          ),
        );
      },
    );
  }
}

class _PlayPausePainter extends CustomPainter {
  final double t;
  final Color color;
  const _PlayPausePainter({required this.t, required this.color});

  static const List<String> _cmdSeq = [
    'M', 'L', 'Q', 'Q', 'L', 'Q', 'Q', 'L', 'Q', 'Q', 'Q', 'Q', 'Q', 'Q',
    'M', 'L', 'Q', 'Q', 'L', 'Q', 'Q', 'L', 'Q', 'Q', 'Q', 'Q', 'Q', 'Q',
  ];

  static const List<Offset> _playPoints = [
    Offset(0.381250, 0.758333),
    Offset(0.750000, 0.522917),
    Offset(0.757292, 0.517708),
    Offset(0.760938, 0.511458),
    Offset(0.764583, 0.505208),
    Offset(0.764583, 0.496875),
    Offset(0.620833, 0.496131),
    Offset(0.548958, 0.495759),
    Offset(0.477083, 0.495386),
    Offset(0.405208, 0.495015),
    Offset(0.333333, 0.494643),
    Offset(0.333333, 0.731250),
    Offset(0.333333, 0.731250),
    Offset(0.333333, 0.731250),
    Offset(0.333333, 0.745833),
    Offset(0.342708, 0.754167),
    Offset(0.352083, 0.762500),
    Offset(0.364583, 0.762500),
    Offset(0.368750, 0.762500),
    Offset(0.372917, 0.761458),
    Offset(0.375000, 0.760938),
    Offset(0.377083, 0.760156),
    Offset(0.379167, 0.759375),
    Offset(0.381250, 0.758333),
    Offset(0.333333, 0.494643),
    Offset(0.764583, 0.496875),
    Offset(0.764583, 0.488542),
    Offset(0.760938, 0.482292),
    Offset(0.757292, 0.476042),
    Offset(0.750000, 0.470833),
    Offset(0.657813, 0.411979),
    Offset(0.611719, 0.382552),
    Offset(0.565625, 0.353125),
    Offset(0.519531, 0.323698),
    Offset(0.473438, 0.294271),
    Offset(0.381250, 0.235417),
    Offset(0.377083, 0.233333),
    Offset(0.372917, 0.232292),
    Offset(0.368750, 0.231250),
    Offset(0.364583, 0.231250),
    Offset(0.352083, 0.231250),
    Offset(0.342708, 0.239583),
    Offset(0.333333, 0.247917),
    Offset(0.333333, 0.262500),
    Offset(0.333333, 0.320535),
    Offset(0.333333, 0.378572),
    Offset(0.333333, 0.436607),
    Offset(0.333333, 0.494643),
  ];

  static const List<Offset> _pausePoints = [
    Offset(0.270833, 0.760417),
    Offset(0.729167, 0.760417),
    Offset(0.754938, 0.760427),
    Offset(0.773302, 0.742062),
    Offset(0.791667, 0.723698),
    Offset(0.791667, 0.697917),
    Offset(0.791667, 0.640625),
    Offset(0.791677, 0.614854),
    Offset(0.773312, 0.596490),
    Offset(0.754948, 0.578125),
    Offset(0.729167, 0.578125),
    Offset(0.270833, 0.578125),
    Offset(0.245062, 0.578115),
    Offset(0.226698, 0.596479),
    Offset(0.208333, 0.614844),
    Offset(0.208333, 0.640625),
    Offset(0.208333, 0.640625),
    Offset(0.208333, 0.640625),
    Offset(0.208333, 0.669271),
    Offset(0.208333, 0.697917),
    Offset(0.208323, 0.723688),
    Offset(0.226688, 0.742052),
    Offset(0.245052, 0.760417),
    Offset(0.270833, 0.760417),
    Offset(0.270833, 0.421875),
    Offset(0.729167, 0.421875),
    Offset(0.754938, 0.421885),
    Offset(0.773302, 0.403521),
    Offset(0.791667, 0.385156),
    Offset(0.791667, 0.359375),
    Offset(0.791667, 0.302083),
    Offset(0.791677, 0.276313),
    Offset(0.773312, 0.257948),
    Offset(0.754948, 0.239583),
    Offset(0.729167, 0.239583),
    Offset(0.270833, 0.239583),
    Offset(0.245062, 0.239573),
    Offset(0.226698, 0.257937),
    Offset(0.208333, 0.276302),
    Offset(0.208333, 0.302083),
    Offset(0.208333, 0.302083),
    Offset(0.208333, 0.302083),
    Offset(0.208333, 0.330729),
    Offset(0.208333, 0.359375),
    Offset(0.208323, 0.385146),
    Offset(0.226688, 0.403510),
    Offset(0.245052, 0.421875),
    Offset(0.270833, 0.421875),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final path = Path();
    int i = 0;
    Offset lerpAt(int idx) => Offset.lerp(_playPoints[idx], _pausePoints[idx], t)!;

    bool hasOpenContour = false;
    for (final cmd in _cmdSeq) {
      switch (cmd) {
        case 'M':
          if (hasOpenContour) path.close();
          final p = lerpAt(i);
          path.moveTo(p.dx * size.width, p.dy * size.height);
          hasOpenContour = true;
          i += 1;
          break;
        case 'L':
          final p = lerpAt(i);
          path.lineTo(p.dx * size.width, p.dy * size.height);
          i += 1;
          break;
        case 'Q':
          final c = lerpAt(i);
          final e = lerpAt(i + 1);
          path.quadraticBezierTo(
            c.dx * size.width, c.dy * size.height,
            e.dx * size.width, e.dy * size.height,
          );
          i += 2;
          break;
      }
    }
    if (hasOpenContour) path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _PlayPausePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}
