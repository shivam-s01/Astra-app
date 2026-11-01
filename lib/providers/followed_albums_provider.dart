// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';
import '../services/sync_service.dart';

class FollowedAlbumsProvider extends ChangeNotifier {
  static const _boxName = 'aurum_followed_albums';
  Box<Map>? _box;
  bool _isLoading = true;
  final Completer<Box<Map>> _boxReady = Completer<Box<Map>>();

  bool get isLoading => _isLoading;

  List<Map<String, dynamic>> get followed => (_box?.values ?? const [])
      .map((m) => Map<String, dynamic>.from(m))
      .toList()
      .reversed
      .toList();

  Future<void> init() async {
    if (_boxReady.isCompleted) return;
    _box = await Hive.openBox<Map>(_boxName);
    _boxReady.complete(_box);
    _isLoading = false;
    notifyListeners();
  }

  bool isFollowing(String albumId) => _box?.containsKey(albumId) ?? false;

  Future<void> toggleFollow({
    required String albumId,
    required String name,
    required String artworkUrl,
    bool isMix = false,
    List<Song> songs = const [],
  }) async {
    final box = _box ?? await _boxReady.future;
    if (isFollowing(albumId)) {
      await box.delete(albumId);
      if (!isMix) {
        unawaited(SyncService.instance.pushUnfollowedAlbum(albumId));
      }
    } else {
      final data = {
        'id': albumId,
        'name': name,
        'artworkUrl': artworkUrl,
        'isMix': isMix,
        if (isMix) 'songs': jsonEncode(songs.map((s) => s.toJson()).toList()),
      };
      await box.put(albumId, data);
      if (!isMix) {
        unawaited(SyncService.instance.pushFollowedAlbum(data));
      }
    }
    notifyListeners();
  }

  List<Song> songsFor(String albumId) {
    final raw = _box?.get(albumId);
    if (raw == null) return [];
    final data = Map<String, dynamic>.from(raw);
    if (data['isMix'] != true) return [];
    final encoded = data['songs'];
    if (encoded is! String) return [];
    final list = (jsonDecode(encoded) as List?) ?? [];
    return list
        .map((j) => Song.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  Future<void> followFromRemote({
    required String albumId,
    required String name,
    required String artworkUrl,
  }) async {
    if (isFollowing(albumId)) return;
    final box = _box ?? await _boxReady.future;
    await box.put(albumId, {
      'id': albumId,
      'name': name,
      'artworkUrl': artworkUrl,
    });
    notifyListeners();
  }

  Future<void> clearAll() async {
    final box = _box ?? await _boxReady.future;
    await box.clear();
    notifyListeners();
  }
}
