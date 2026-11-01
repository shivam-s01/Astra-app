// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AurumHaptics {
  AurumHaptics._();

  static const MethodChannel _channel =
      MethodChannel('com.aurum.music/media_store');

  static String _intensity = 'light';
  static bool _loaded = false;

  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _intensity = p.getString('haptic_intensity') ?? 'light';
    _loaded = true;
  }

  static Future<void> setIntensity(String value) async {
    _intensity = value;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    await p.setString('haptic_intensity', value);
  }

  static String get intensity => _intensity;

  static void _fire({
    required VoidCallback lightFallback,
    required int strongAmplitude,
    required int strongDurationMs,
  }) {
    if (!_loaded) {
      lightFallback();
      return;
    }
    switch (_intensity) {
      case 'off':
        return;
      case 'strong':
        _channel.invokeMethod('vibrateHaptic', {
          'amplitude': strongAmplitude,
          'durationMs': strongDurationMs,
        }).catchError((_) {});
        return;
      case 'light':
      default:
        lightFallback();
        return;
    }
  }

  static void selection() => _fire(
        lightFallback: HapticFeedback.selectionClick,
        strongAmplitude: 90,
        strongDurationMs: 8,
      );

  static void light() => _fire(
        lightFallback: HapticFeedback.lightImpact,
        strongAmplitude: 130,
        strongDurationMs: 10,
      );

  static void medium() => _fire(
        lightFallback: HapticFeedback.mediumImpact,
        strongAmplitude: 190,
        strongDurationMs: 14,
      );

  static void heavy() => _fire(
        lightFallback: HapticFeedback.heavyImpact,
        strongAmplitude: 255,
        strongDurationMs: 18,
      );

  static void vibrate() => _fire(
        lightFallback: HapticFeedback.vibrate,
        strongAmplitude: 200,
        strongDurationMs: 16,
      );
}
