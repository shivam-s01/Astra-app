// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/services.dart';
import 'audio_prefs.dart';
import 'native_engine_bridge.dart';

class BatterySaverController {
  BatterySaverController._();
  static final BatterySaverController instance = BatterySaverController._();

  static const EventChannel _channel = EventChannel('com.aurum.music/battery');

  StreamSubscription<dynamic>? _sub;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    AudioPrefs.registerBatterySaverReevaluateHook(reevaluateNow);
    AudioPrefs.batterySaverActiveNotifier.addListener(_pushToNative);
    _pushToNative();
    try {
      _sub = _channel.receiveBroadcastStream().listen(
        _onBatteryLevel,
        onError: (_) {
        },
        cancelOnError: false,
      );
    } catch (_) {
    }
  }

  void _onBatteryLevel(dynamic level) {
    if (level is! int) return;
    AudioPrefs.batteryLevelNotifier.value = level;

    final shouldBeActive = AudioPrefs.batterySaverEnabledNotifier.value &&
        level <= AudioPrefs.batterySaverThresholdNotifier.value;

    if (AudioPrefs.batterySaverActiveNotifier.value != shouldBeActive) {
      AudioPrefs.batterySaverActiveNotifier.value = shouldBeActive;
    }
  }

  void reevaluateNow() {
    final level = AudioPrefs.batteryLevelNotifier.value;
    if (level == null) return;
    _onBatteryLevel(level);
  }

  void _pushToNative() {
    unawaited(
      NativeAudioEngine()
          .setBatterySaverActive(AudioPrefs.batterySaverActiveNotifier.value)
          .catchError((_) {}),
    );
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
    AudioPrefs.batterySaverActiveNotifier.removeListener(_pushToNative);
  }
}
