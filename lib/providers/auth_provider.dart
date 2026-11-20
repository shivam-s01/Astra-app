// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/native_engine_bridge.dart';
import '../services/profile_photo_service.dart';

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

  String? _customAvatarPath;
  String? _customAvatarUid;

  /// Photo to show in the UI: the user's own picked photo if set, otherwise
  /// the Google account photo. May be a local file path (starts with '/') or
  /// a network URL. Use [avatarUrl] when a shareable URL is needed (e.g. Jam).
  String? get displayAvatar {
    if (isSignedIn && _customAvatarUid == userId && _customAvatarPath != null) {
      return _customAvatarPath;
    }
    return avatarUrl;
  }

  bool get hasCustomAvatar =>
      isSignedIn && _customAvatarUid == userId && _customAvatarPath != null;

  Future<void> _loadCustomAvatar() async {
    final uid = userId;
    if (uid == null) {
      if (_customAvatarPath != null || _customAvatarUid != null) {
        _customAvatarPath = null;
        _customAvatarUid = null;
        notifyListeners();
      }
      return;
    }
    if (_customAvatarUid == uid && _customAvatarPath != null) return;
    final path = await ProfilePhotoService.instance.load(uid);
    if (userId != uid) return;
    _customAvatarUid = uid;
    if (_customAvatarPath != path) {
      _customAvatarPath = path;
      notifyListeners();
    }
  }

  /// Saves a cropped PNG as the user's profile photo.
  Future<bool> setCustomAvatar(Uint8List pngBytes) async {
    final uid = userId;
    if (uid == null) return false;
    final path = await ProfilePhotoService.instance.save(uid, pngBytes);
    if (path == null) return false;
    _customAvatarUid = uid;
    _customAvatarPath = path;
    notifyListeners();
    return true;
  }

  /// Removes the custom photo and falls back to the Google photo.
  Future<void> removeCustomAvatar() async {
    final uid = userId;
    if (uid == null) return;
    await ProfilePhotoService.instance.clear(uid);
    _customAvatarPath = null;
    _customAvatarUid = uid;
    notifyListeners();
  }

  void init() {
    _engineBridge.autoSleepGuardSetSignedIn(isSignedIn);
    _loadCustomAvatar();
    _sub = AuthService.instance.authStateChanges.listen((_) {
      _engineBridge.autoSleepGuardSetSignedIn(isSignedIn);
      _loadCustomAvatar();
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
    if (error == null) {
      AnalyticsService.instance.logLogin();
      await _loadCustomAvatar();
    }
    notifyListeners();
    return error == null;
  }

  Future<void> signOut() async {
    AnalyticsService.instance.logLogout();
    await AuthService.instance.signOut();
    _customAvatarPath = null;
    _customAvatarUid = null;
    _engineBridge.autoSleepGuardSetSignedIn(false);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
