// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user's custom profile photo on-device (one per account).
///
/// Every save writes a NEW file name, so Flutter's image cache can never show
/// a stale picture after the user changes their photo.
class ProfilePhotoService {
  ProfilePhotoService._();
  static final ProfilePhotoService instance = ProfilePhotoService._();

  static const String _prefix = 'custom_avatar_path_v1_';

  String _key(String uid) => '$_prefix$uid';

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/avatars');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Returns the saved photo path for [uid], or null if none / file missing.
  Future<String?> load(String uid) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final path = sp.getString(_key(uid));
      if (path == null || path.isEmpty) return null;
      if (!await File(path).exists()) {
        await sp.remove(_key(uid));
        return null;
      }
      return path;
    } catch (e) {
      if (kDebugMode) debugPrint('[ProfilePhoto] load failed: $e');
      return null;
    }
  }

  /// Saves [bytes] (PNG) as the new photo for [uid]. Returns the new path.
  Future<String?> save(String uid, Uint8List bytes) async {
    try {
      final dir = await _dir();
      final file = File(
          '${dir.path}/avatar_${uid.hashCode.abs()}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes, flush: true);

      final sp = await SharedPreferences.getInstance();
      final old = sp.getString(_key(uid));
      await sp.setString(_key(uid), file.path);

      if (old != null && old != file.path) {
        try {
          final f = File(old);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      return file.path;
    } catch (e) {
      if (kDebugMode) debugPrint('[ProfilePhoto] save failed: $e');
      return null;
    }
  }

  /// Removes the custom photo for [uid] (falls back to the Google photo).
  Future<void> clear(String uid) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final old = sp.getString(_key(uid));
      await sp.remove(_key(uid));
      if (old != null) {
        final f = File(old);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ProfilePhoto] clear failed: $e');
    }
  }
}
