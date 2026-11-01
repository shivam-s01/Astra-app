// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/native_engine_bridge.dart';

class AuthProvider extends ChangeNotifier {
  StreamSubscription<AuthState>? _sub;
  bool _isSigningIn = false;
  String? _lastError;

  final NativeAudioEngine _engineBridge = NativeAudioEngine();

  bool get isSignedIn => AuthService.instance.isSignedIn;
  bool get isSigningIn => _isSigningIn;
  String? get lastError => _lastError;
  String? get displayName => AuthService.instance.displayName;
  String? get email => AuthService.instance.email;
  String? get avatarUrl => AuthService.instance.avatarUrl;
  String? get userId => AuthService.instance.currentUser?.id;

  void init() {
    _engineBridge.autoSleepGuardSetSignedIn(isSignedIn);
    _sub = AuthService.instance.authStateChanges.listen((_) {
      _engineBridge.autoSleepGuardSetSignedIn(isSignedIn);
      notifyListeners();
    });
  }

  Future<bool> signInWithGoogle() async {
    _isSigningIn = true;
    _lastError = null;
    notifyListeners();

    final error = await AuthService.instance.signInWithGoogle();

    _isSigningIn = false;
    if (error != null && error != 'cancelled') {
      _lastError = error;
    }
    _engineBridge.autoSleepGuardSetSignedIn(isSignedIn);
    if (error == null) AnalyticsService.instance.logLogin();
    notifyListeners();
    return error == null;
  }

  Future<void> signOut() async {
    AnalyticsService.instance.logLogout();
    await AuthService.instance.signOut();
    _engineBridge.autoSleepGuardSetSignedIn(false);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
