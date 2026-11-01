// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'audio_prefs.dart';
import 'native_engine_bridge.dart';

class DataSaverController {
  DataSaverController._();
  static final DataSaverController instance = DataSaverController._();

  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    AudioPrefs.dataSaverActiveNotifier.addListener(_pushToNative);
    _pushToNative();
  }

  void _pushToNative() {
    unawaited(
      NativeAudioEngine()
          .setDataSaverActive(AudioPrefs.dataSaverActiveNotifier.value)
          .catchError((_) {}),
    );
  }

  void dispose() {
    _started = false;
    AudioPrefs.dataSaverActiveNotifier.removeListener(_pushToNative);
  }
}
