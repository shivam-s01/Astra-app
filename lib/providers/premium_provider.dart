// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/audio_prefs.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/payment_service.dart';

class PremiumProvider extends ChangeNotifier {
  static const _kCachedPremium = 'aurum_is_premium_cached';
  static const _kPremiumPlan = 'aurum_premium_plan';

  bool _isPremium = false;
  bool _isChecking = false;
  String? _activePlanId;

  bool get isPremium => _isPremium;
  bool get isChecking => _isChecking;
  String? get activePlanId => _activePlanId;

  void Function()? onSlowNetwork;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<AuthState>? _authSub;
  static const _slowNetworkTimeout = Duration(seconds: 6);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isPremium = prefs.getBool(_kCachedPremium) ?? false;
    _activePlanId = prefs.getString(_kPremiumPlan);
    notifyListeners();

    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (AudioPrefs.dataSaverActiveNotifier.value &&
          (state.event == AuthChangeEvent.initialSession ||
              state.event == AuthChangeEvent.tokenRefreshed)) {
        return;
      }
      _refresh();
    });

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        _refresh();
      }
    });

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastLive = prefs.getInt('premium_last_live_check_ms') ?? 0;
    final liveDue = !AudioPrefs.dataSaverActiveNotifier.value ||
        nowMs - lastLive > 24 * 60 * 60 * 1000;
    if (liveDue) await prefs.setInt('premium_last_live_check_ms', nowMs);
    await _refresh(live: liveDue);
    AnalyticsService.instance.setPremium(_isPremium);
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  int _refreshSession = 0;

  Future<void> _refresh({bool live = true}) async {
    final mySession = ++_refreshSession;
    _isChecking = true;
    notifyListeners();

    var sawSlowNetwork = false;
    void reportSlow() {
      if (!sawSlowNetwork) {
        sawSlowNetwork = true;
        onSlowNetwork?.call();
      }
    }

    try {
      User? user;
      try {
        if (!live) {
          throw StateError('cold-start: use cached session');
        }
        final resp = await Supabase.instance.client.auth
            .getUser()
            .timeout(_slowNetworkTimeout, onTimeout: () {
          reportSlow();
          throw TimeoutException('getUser timed out');
        });
        user = resp.user;
      } on TimeoutException {
        user = Supabase.instance.client.auth.currentUser;
      } catch (_) {
        user = Supabase.instance.client.auth.currentUser;
      }

      if (mySession != _refreshSession) return;

      bool fromAdmin = false;
      if (user != null) {
        final meta = user.userMetadata ?? {};
        final fromMeta = meta['is_premium'] == true;
        final appMeta = user.appMetadata;
        final fromApp = appMeta['is_premium'] == true;
        fromAdmin = fromMeta || fromApp;
      }

      final hasValidPayment = await PaymentService.hasValidLocalGrant();
      if (mySession != _refreshSession) return;

      final hasLegacyPaymentGrant = fromAdmin || hasValidPayment;

      String? planId;
      if (hasValidPayment) {
        planId = await PaymentService.currentPlanId();
        if (mySession != _refreshSession) return;
      } else if (fromAdmin) {
        planId = null;
      }
      _activePlanId = planId;

      _setPremium(hasLegacyPaymentGrant);
    } catch (e) {
      if (kDebugMode) debugPrint('[PremiumProvider] _refresh error: $e');
    } finally {
      if (mySession == _refreshSession) {
        _isChecking = false;
        notifyListeners();
      }
    }
  }

  void _setPremium(bool value) async {
    _isPremium = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCachedPremium, value);
    notifyListeners();
  }

  Future<void> refresh() => _refresh();

  void markPremiumGranted(String planId) {
    _isPremium = true;
    _activePlanId = planId;
    AnalyticsService.instance.logPremium(planId);
    AnalyticsService.instance.setPremium(true);
    notifyListeners();
    _refresh();
  }

  void devToggle() {
    assert(() {
      _setPremium(!_isPremium);
      return true;
    }());
  }
}
