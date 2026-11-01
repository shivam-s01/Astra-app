// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, AppLifecycleState;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/recommendation_engine.dart';
import '../services/sync_service.dart';
import 'download_provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../main.dart' show navigatorKey;
import '../services/auth_service.dart';
import '../widgets/premium_gate.dart';

class FavoritesProvider extends ChangeNotifier {
  static const _boxName = 'aurum_favorites';
  Box<Map>? _box;
  final Completer<Box<Map>> _boxReady = Completer<Box<Map>>();
  List<Song> _favorites = [];
  bool _isLoading = true;

  DownloadProvider? downloadProvider;

  List<Song> get favorites   => List.unmodifiable(_favorites);
  bool get isLoading         => _isLoading;
  bool isFavorite(String id) => _favorites.any((s) => s.id == id);

  Future<void> init() async {
    if (_boxReady.isCompleted) return;
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;
    _boxReady.complete(box);
    _favorites = box.values
        .map((m) => Song.fromJson(Map<String, dynamic>.from(m)))
        .toList()
        .reversed
        .toList();
    _isLoading = false;
    notifyListeners();

    for (final song in _favorites.take(5)) {
      ApiService.prewarmYtStream(song);
    }
  }

  bool _loginPromptOpen = false;

  Future<bool> _ensureSignedInToLike() async {
    bool signedIn;
    try {
      signedIn = AuthService.instance.isSignedIn;
    } catch (_) {
      signedIn = false;
    }
    if (signedIn) return true;

    if (_loginPromptOpen) return false;

    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return false;

    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null || !ctx.mounted) return false;

    _loginPromptOpen = true;
    try {
      final l10n = AppLocalizations.of(ctx);
      return await PremiumGate.ensureSignedIn(
        ctx,
        feature: l10n?.fpLikeSongsFeature ?? 'Like Songs',
        description: l10n?.fpLikeSongsSignIn ??
            'Sign in with Google to save songs to your library.',
      );
    } finally {
      _loginPromptOpen = false;
    }
  }

  Future<void> toggleFavorite(Song song) async {
    if (!isFavorite(song.id)) {
      if (!await _ensureSignedInToLike()) return;
      if (isFavorite(song.id)) return;
    }
    if (isFavorite(song.id)) {
      await _remove(song.id);
      AnalyticsService.instance.logFavorite(song, false);
      if (song.source != SongSource.local) {
        RecommendationEngine.onUnfavorited(song);
      }
    } else {
      await _add(song);
      AnalyticsService.instance.logFavorite(song, true);
      if (song.source != SongSource.local) {
        RecommendationEngine.onFavorited(song);
      }
      final p = await SharedPreferences.getInstance();
      if (p.getBool('auto_download_liked') == true &&
          song.source != SongSource.local) {
        downloadProvider?.download(song);
      }
    }
  }

  Future<void> _add(Song song) async {
    final box = _box ?? await _boxReady.future;
    await box.put(song.id, song.toJson());
    _favorites.insert(0, song);
    unawaited(SyncService.instance.pushFavorite(song));
    notifyListeners();
  }

  Future<void> _remove(String id) async {
    final box = _box ?? await _boxReady.future;
    await box.delete(id);
    _favorites.removeWhere((s) => s.id == id);
    unawaited(SyncService.instance.pushUnfavorite(id));
    notifyListeners();
  }

  Future<void> addFromRemote(Map<String, dynamic> data) async {
    final song = Song.fromJson(data);
    if (!isFavorite(song.id)) {
      final box = _box ?? await _boxReady.future;
      await box.put(song.id, song.toJson());
      _favorites.insert(0, song);
      notifyListeners();
    }
  }

  Future<void> removeMany(Iterable<String> ids) async {
    final box = _box ?? await _boxReady.future;
    for (final id in ids) {
      await box.delete(id);
      unawaited(SyncService.instance.pushUnfavorite(id));
    }
    final idSet = ids.toSet();
    _favorites.removeWhere((s) => idSet.contains(s.id));
    notifyListeners();
  }

  Future<void> clearAll() async {
    final box = _box ?? await _boxReady.future;
    await box.clear();
    _favorites = [];
    notifyListeners();
  }
}
