// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/aurum_motion.dart';

class AurumEqualizerBars extends StatefulWidget {
  final bool playing;
  final Color color;
  final double size;
  final int barCount;

  const AurumEqualizerBars({
    super.key,
    required this.playing,
    required this.color,
    this.size = 18,
    this.barCount = 3,
  });

  @override
  State<AurumEqualizerBars> createState() => _AurumEqualizerBarsState();
}

class _AurumEqualizerBarsState extends State<AurumEqualizerBars>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _heights;
  final _rand = Random();

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.barCount, (i) {
      final controller = AnimationController(
        vsync: this,
        duration: _randomDuration(),
      );
      controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          controller.duration = _randomDuration();
          controller.reverse();
        } else if (status == AnimationStatus.dismissed) {
          controller.duration = _randomDuration();
          controller.forward();
        }
      });
      return controller;
    });

    _heights = _controllers
        .map((c) => Tween<double>(begin: 0.25, end: 1.0).animate(
              CurvedAnimation(parent: c, curve: Curves.easeInOut),
            ))
        .toList();

    if (widget.playing) _startAll();
  }

  Duration _randomDuration() =>
      Duration(milliseconds: 260 + _rand.nextInt(260));

  void _startAll() {
    for (var i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 90), () {
        if (mounted && widget.playing) _controllers[i].forward();
      });
    }
  }

  void _stopAll() {
    for (final c in _controllers) {
      c.stop();
      c.animateTo(0.18, duration: AurumMotion.durationOrZero(AurumMotion.medium1), curve: Curves.easeOut);
    }
  }

  @override
  void didUpdateWidget(covariant AurumEqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) {
      widget.playing ? _startAll() : _stopAll();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(widget.barCount, (i) {
          return AnimatedBuilder(
            animation: _heights[i],
            builder: (_, __) {
              return Container(
                width: widget.size / (widget.barCount * 1.8),
                height: widget.size * _heights[i].value,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
