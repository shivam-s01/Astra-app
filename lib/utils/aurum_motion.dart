// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/animation.dart';
import '../services/audio_prefs.dart';

class AurumMotion {
  AurumMotion._();

  static const short1 = Duration(milliseconds: 100);
  static const short2 = Duration(milliseconds: 150);

  static const medium1 = Duration(milliseconds: 220);
  static const medium2 = Duration(milliseconds: 280);

  static const long1 = Duration(milliseconds: 350);
  static const long2 = Duration(milliseconds: 420);

  static const extraLong1 = Duration(milliseconds: 600);

  static const standard = Curves.easeOutCubic;

  static const standardReverse = Curves.easeOutCubic;

  static const emphasized = Curves.easeOutBack;

  static bool get enabled =>
      AudioPrefs.enableAnimationsNotifier.value &&
      !AudioPrefs.batterySaverActiveNotifier.value;

  static Duration durationOrZero(Duration duration) =>
      enabled ? duration : Duration.zero;
}
