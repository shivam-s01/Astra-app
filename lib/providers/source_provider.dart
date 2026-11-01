// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MusicSource { online, offline }

class SourceProvider extends ChangeNotifier {
  MusicSource _source = MusicSource.online;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _hasNetwork = true;
  bool _offlineModeEnabled = false;

  static const _offlineModePrefsKey = 'offline_mode_enabled';

  static const _reconnectDebounce = Duration(seconds: 2);
  Timer? _reconnectTimer;

  void Function()? onSourceChanged;

  bool Function()? isCurrentSongLocal;

  bool Function()? hasPlaybackBuffer;

  void Function()? onReconnected;

  MusicSource get source => _source;
  bool get isOnline => _source == MusicSource.online;
  bool get hasNetwork => _hasNetwork;
  bool get isOfflineModeEnabled => _offlineModeEnabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _offlineModeEnabled = prefs.getBool(_offlineModePrefsKey) ?? false;

    final initial = await Connectivity().checkConnectivity();
    _applyResult(initial, notify: false);

    _sub = Connectivity().onConnectivityChanged.listen(_applyResult);
  }

  Future<void> setOfflineMode(bool enabled) async {
    if (_offlineModeEnabled == enabled) return;
    _offlineModeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineModePrefsKey, enabled);

    if (enabled) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _setSource(MusicSource.offline, notify: true);
    } else {
      final current = await Connectivity().checkConnectivity();
      _applyResult(current, notify: true);
    }
  }

  void _applyResult(List<ConnectivityResult> results, {bool notify = true}) {
    final hasNetworkNow = results.any((r) => r != ConnectivityResult.none);
    _hasNetwork = hasNetworkNow;

    if (_offlineModeEnabled) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _setSource(MusicSource.offline, notify: notify);
      return;
    }

    if (!hasNetworkNow) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _setSource(MusicSource.offline, notify: notify);
      return;
    }

    if (_source == MusicSource.online) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDebounce, () {
      _reconnectTimer = null;
      if (!_hasNetwork) return;
      _setSource(MusicSource.online, notify: notify);
    });
  }

  void _setSource(MusicSource next, {required bool notify}) {
    if (next == _source) return;
    final previous = _source;
    _source = next;
    if (notify) {
      final currentIsLocal = isCurrentSongLocal?.call() ?? false;
      final stillBuffered = hasPlaybackBuffer?.call() ?? false;
      if (!currentIsLocal && !stillBuffered) {
        onSourceChanged?.call();
      }
      if (previous == MusicSource.offline && next == MusicSource.online) {
        onReconnected?.call();
      }
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _reconnectTimer?.cancel();
    super.dispose();
  }
}
