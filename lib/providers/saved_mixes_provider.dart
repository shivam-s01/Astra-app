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

class SavedMixesProvider extends ChangeNotifier {
  static const _boxName = 'aurum_saved_mixes';
  Box<String>? _box;
  bool _isLoading = true;
  final Completer<Box<String>> _boxReady = Completer<Box<String>>();

  bool get isLoading => _isLoading;

  List<Map<String, dynamic>> get saved => (_box?.values ?? const [])
      .map((raw) => Map<String, dynamic>.from(jsonDecode(raw) as Map))
      .toList()
      .reversed
      .toList();

  Future<void> init() async {
    if (_boxReady.isCompleted) return;
    _box = await Hive.openBox<String>(_boxName);
    _boxReady.complete(_box);
    _isLoading = false;
    notifyListeners();
  }

  bool isSaved(String mixId) => _box?.containsKey(mixId) ?? false;

  Future<void> toggleSave({
    required String mixId,
    required String name,
    required String artworkUrl,
    required String emoji,
    required List<Song> songs,
  }) async {
    final box = _box ?? await _boxReady.future;
    if (isSaved(mixId)) {
      await box.delete(mixId);
    } else {
      final data = {
        'id': mixId,
        'name': name,
        'artworkUrl': artworkUrl,
        'emoji': emoji,
        'songs': songs.map((s) => s.toJson()).toList(),
      };
      await box.put(mixId, jsonEncode(data));
    }
    notifyListeners();
  }

  List<Song> songsFor(String mixId) {
    final raw = _box?.get(mixId);
    if (raw == null) return [];
    final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final list = (data['songs'] as List?) ?? [];
    return list
        .map((j) => Song.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList();
  }

  Future<void> clearAll() async {
    final box = _box ?? await _boxReady.future;
    await box.clear();
    notifyListeners();
  }
}
