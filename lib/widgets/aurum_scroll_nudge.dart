// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../utils/aurum_motion.dart';

class AurumScrollDeltaScope extends InheritedNotifier<ValueNotifier<double>> {
  const AurumScrollDeltaScope({
    super.key,
    required ValueNotifier<double> notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ValueNotifier<double>? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AurumScrollDeltaScope>()
        ?.notifier;
  }
}

class AurumScrollDelta {
  final ValueNotifier<double> notifier = ValueNotifier<double>(0);
  ScrollController? _controller;
  double _lastPixels = 0;

  void attach(ScrollController controller) {
    _controller = controller;
    _lastPixels = controller.hasClients ? controller.position.pixels : 0;
    controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!AurumMotion.enabled) return;
    final c = _controller;
    if (c == null || !c.hasClients) return;
    final pixels = c.position.pixels;
    notifier.value = pixels - _lastPixels;
    _lastPixels = pixels;
  }

  void dispose() {
    _controller?.removeListener(_onScroll);
    notifier.dispose();
  }
}

class AurumScrollNudge extends StatelessWidget {
  final Widget child;
  const AurumScrollNudge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!AurumMotion.enabled) return child;
    final notifier = AurumScrollDeltaScope.of(context);
    if (notifier == null) return child;
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: notifier,
        builder: (_, dy, cachedChild) {
          final dir = dy.sign;
          final offset = dir * 4.0;
          final opacity = dy == 0 ? 1.0 : 0.92;
          return Transform.translate(
            offset: Offset(0, offset),
            child: Opacity(opacity: opacity, child: cachedChild),
          );
        },
        child: child,
      ),
    );
  }
}
