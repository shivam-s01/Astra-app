// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import 'mini_player.dart';
import 'aurum_glass.dart';
import '../utils/aurum_motion.dart';

class MiniPlayerSlot extends StatelessWidget {
  const MiniPlayerSlot({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      child: RepaintBoundary(
        child: SafeArea(
          top: false,
          child: Selector<PlayerProvider, bool>(
            selector: (_, p) => p.miniPlayerVisible,
            builder: (context, visible, __) => AnimatedSwitcher(
              duration: AurumMotion.durationOrZero(AurumMotion.medium1),
              switchInCurve: AurumMotion.standard,
              switchOutCurve: AurumMotion.standardReverse,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              transitionBuilder: (child, anim) => GlassSafeEnter(
                anim: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.12),
                    end: Offset.zero,
                  ).animate(anim),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.97, end: 1.0).animate(anim),
                    alignment: Alignment.bottomCenter,
                    child: child,
                  ),
                ),
              ),
              child: visible
                  ? const MiniPlayer(key: ValueKey('mini_player_visible'))
                  : const SizedBox.shrink(key: ValueKey('mini_player_hidden')),
            ),
          ),
        ),
      ),
    );
  }
}
