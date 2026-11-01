// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/sync_service.dart';

class FollowedArtistsProvider extends ChangeNotifier {
  static const _boxName = 'aurum_followed_artists';
  Box<Map>? _box;
  bool _isLoading = true;

  bool get isLoading => _isLoading;

  List<Map<String, dynamic>> get followed => (_box?.values ?? const [])
      .map((m) => Map<String, dynamic>.from(m))
      .toList()
      .reversed
      .toList();

  final Completer<Box<Map>> _boxReady = Completer<Box<Map>>();

  Future<void> init() async {
    if (_boxReady.isCompleted) return;
    try {
      _box = await Hive.openBox<Map>(_boxName);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FollowedArtists] openBox failed, deleting and '
            'retrying once: $e');
      }
      try {
        await Hive.deleteBoxFromDisk(_boxName);
        _box = await Hive.openBox<Map>(_boxName);
      } catch (e2) {
        if (kDebugMode) {
          debugPrint('[FollowedArtists] retry also failed: $e2');
        }
      }
    }
    if (!_boxReady.isCompleted) {
      if (_box != null) {
        _boxReady.complete(_box);
      } else {
        _boxReady.completeError('FollowedArtistsProvider box unavailable');
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  bool isFollowing(String artistId) {
    final key = artistId.trim();
    if (key.isEmpty) return false;
    return _box?.containsKey(key) ?? false;
  }

  Future<void> toggleFollow({
    required String artistId,
    required String name,
    required String imageUrl,
  }) async {
    final key = artistId.trim();
    if (key.isEmpty) return;
    Box<Map>? box;
    try {
      box = _box ?? await _boxReady.future;
    } catch (_) {
      return;
    }
    if (box.containsKey(key)) {
      await box.delete(key);
      if (kDebugMode) {
        debugPrint('[FollowedArtists] UNFOLLOWED id=$key name=$name '
            '— box now has ${box.length} artist(s)');
      }
      unawaited(SyncService.instance.pushUnfollowedArtist(key));
    } else {
      final data = {
        'id': key,
        'name': name,
        'imageUrl': imageUrl,
      };
      await box.put(key, data);
      final saved = box.containsKey(key);
      if (kDebugMode) {
        debugPrint('[FollowedArtists] FOLLOWED id=$key name=$name '
            'saved=$saved — box now has ${box.length} artist(s): '
            '${box.values.map((m) => m['name']).toList()}');
      }
      unawaited(SyncService.instance.pushFollowedArtist(data));
    }
    notifyListeners();
  }

  Future<void> followFromRemote({
    required String artistId,
    required String name,
    required String imageUrl,
  }) async {
    final key = artistId.trim();
    if (key.isEmpty) return;
    if (isFollowing(key)) return;
    Box<Map>? box;
    try {
      box = _box ?? await _boxReady.future;
    } catch (_) {
      return;
    }
    await box.put(key, {
      'id': key,
      'name': name,
      'imageUrl': imageUrl,
    });
    notifyListeners();
  }

  Future<void> unfollowMany(Iterable<String> artistIds) async {
    Box<Map>? box;
    try {
      box = _box ?? await _boxReady.future;
    } catch (_) {
      return;
    }
    for (final rawId in artistIds) {
      final key = rawId.trim();
      if (key.isEmpty) continue;
      await box.delete(key);
      unawaited(SyncService.instance.pushUnfollowedArtist(key));
    }
    notifyListeners();
  }

  Future<void> clearAll() async {
    Box<Map>? box;
    try {
      box = _box ?? await _boxReady.future;
    } catch (_) {
      return;
    }
    await box.clear();
    notifyListeners();
  }
}
