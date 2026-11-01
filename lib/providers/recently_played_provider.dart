// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../utils/constants.dart';
import '../services/api_service.dart';
import '../services/recommendation_engine.dart';
import '../services/audio_prefs.dart';
import '../services/sync_service.dart';

class RecentlyPlayedProvider extends ChangeNotifier {
  static const _boxName         = AppConstants.boxRecentlyPlayed;
  static const _kLastDecayDate  = 'aurum_rec_last_decay_date';

  Box<Map>? _box;
  final Completer<Box<Map>> _boxReady = Completer<Box<Map>>();
  List<Song>    _history = [];
  final Map<String, int> _playedAtById = {};

  List<Song> get history => List.unmodifiable(_history);

  Set<String> get playedIdSet => _playedAtById.keys.toSet();

  int? playedAtFor(String songId) => _playedAtById[songId];

  Future<void> init() async {
    if (_boxReady.isCompleted) return;
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;
    _boxReady.complete(box);
    final entries = box.values.map((m) {
      final map = Map<String, dynamic>.from(m);
      final playedAtMs = map['_playedAt'] as int?;
      return (
        song: Song.fromJson(map),
        playedAt: playedAtMs ?? 0,
      );
    }).toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    _history = entries.map((e) => e.song).toList();
    _playedAtById
      ..clear()
      ..addEntries(entries.map((e) => MapEntry(e.song.id, e.playedAt)));

    await RecommendationEngine.load();

    await _maybeApplyDecay();

    notifyListeners();

    for (final song in _history.take(5)) {
      ApiService.prewarmYtStream(song);
    }
  }

  Future<void> _writeQueue = Future.value();

  Future<void> addPlay(Song song) {
    final result = _writeQueue.then((_) => _addPlay(song));
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _addPlay(Song song) async {
    if (AudioPrefs.incognito) return;
    AnalyticsService.instance.logSongPlay(song);

    _history.removeWhere((s) => s.id == song.id);

    final entry = song.streamUrl == null
        ? song
        : Song(
            id:         song.id,
            title:      song.title,
            artist:     song.artist,
            album:      song.album,
            artworkUrl: song.artworkUrl,
            streamUrl:  null,
            duration:   song.duration,
            language:   song.language,
            year:       song.year,
            localPath:  song.localPath,
            source:     song.source,
          );

    _history.insert(0, entry);
    final playedAt = DateTime.now().millisecondsSinceEpoch;
    _playedAtById[entry.id] = playedAt;

    final p2 = await SharedPreferences.getInstance();
    final sliderVal = (p2.getInt('history_duration') ?? 50).clamp(0, 100);
    final maxHistory = (10 + (sliderVal / 100.0 * 190).round()).clamp(10, 200);
    if (_history.length > maxHistory) {
      _history = _history.sublist(0, maxHistory);
    }

    await _persistHistory();

    if (entry.source != SongSource.local) {
      unawaited(SyncService.instance.pushHistoryEntry(entry, playedAt));
    }

    RecommendationEngine.onSongStarted(song);

    notifyListeners();
  }

  Future<void> _persistHistory() async {
    final box = _box ?? await _boxReady.future;
    final keepIds = _history.map((s) => s.id).toSet();
    final staleKeys = box.keys.where((k) => !keepIds.contains(k)).toList();
    for (final key in staleKeys) {
      await box.delete(key);
    }
    for (final s in _history) {
      final json = s.toJson();
      json['_playedAt'] = _playedAtById[s.id] ?? DateTime.now().millisecondsSinceEpoch;
      await box.put(s.id, json);
    }
  }

  void notifyCompletion(Song song) {
    if (AudioPrefs.incognito) return;
    AnalyticsService.instance.logSongComplete(song);
    if (song.source == SongSource.local) return;
    RecommendationEngine.onSongCompleted(song);
  }

  void notifySkip(Song song) {
    if (AudioPrefs.incognito) return;
    AnalyticsService.instance.logSongSkip(song);
    if (song.source == SongSource.local) return;
    RecommendationEngine.onEarlySkip(song);
  }

  void notifyReplay(Song song) {
    if (AudioPrefs.incognito) return;
    AnalyticsService.instance.logSongReplay(song);
    if (song.source == SongSource.local) return;
    RecommendationEngine.onReplay(song);
  }

  void notifyFavorited(Song song) {
    if (AudioPrefs.incognito) return;
    if (song.source == SongSource.local) return;
    RecommendationEngine.onFavorited(song);
  }

  void notifyUnfavorited(Song song) {
    if (AudioPrefs.incognito) return;
    if (song.source == SongSource.local) return;
    RecommendationEngine.onUnfavorited(song);
  }

  Future<void> trimToLimit(int limit) {
    final result = _writeQueue.then((_) => _trimToLimit(limit));
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _trimToLimit(int limit) async {
    if (_history.length <= limit) return;
    _history = _history.sublist(0, limit);
    await _persistHistory();
    notifyListeners();
  }

  Future<void> clearHistory() {
    final result = _writeQueue.then((_) => _clearHistory());
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _clearHistory() async {
    _history.clear();
    _playedAtById.clear();
    final box = _box ?? await _boxReady.future;
    await box.clear();
    notifyListeners();
  }

  Future<void> upsertFromRemote(Song song, int playedAtMs) {
    final result = _writeQueue.then((_) => _upsertFromRemote(song, playedAtMs));
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _upsertFromRemote(Song song, int playedAtMs) async {
    final existingPlayedAt = _playedAtById[song.id];
    if (existingPlayedAt != null && existingPlayedAt >= playedAtMs) {
      return;
    }

    _history.removeWhere((s) => s.id == song.id);
    _history.insert(0, song);
    _playedAtById[song.id] = playedAtMs;
    _history.sort((a, b) =>
        (_playedAtById[b.id] ?? 0).compareTo(_playedAtById[a.id] ?? 0));

    final p2 = await SharedPreferences.getInstance();
    final sliderVal = (p2.getInt('history_duration') ?? 50).clamp(0, 100);
    final maxHistory = (10 + (sliderVal / 100.0 * 190).round()).clamp(10, 200);
    if (_history.length > maxHistory) {
      final dropped = _history.sublist(maxHistory);
      _history = _history.sublist(0, maxHistory);
      for (final d in dropped) {
        _playedAtById.remove(d.id);
      }
    }

    await _persistHistory();
    notifyListeners();
  }

  List<String> topArtists({int count = 2}) {
    if (_history.isEmpty) return [];
    return _rankedArtists().take(count).toList();
  }

  List<String> rotatingTopArtists({int count = 3, int? seed, int poolSize = 12}) {
    if (_history.isEmpty) return [];
    final pool = _rankedArtists().take(poolSize).toList();
    if (pool.length <= count) return pool;
    pool.shuffle(seed != null ? math.Random(seed) : math.Random());
    return pool.take(count).toList();
  }

  List<String> _rankedArtists() {
    if (_history.isEmpty) return [];

    const labelNames = {
      'unknown', 'unknown artist', 't-series', 'tseries', 't series',
      'zee music company', 'zee music', 'sony music', 'sony music india',
      'saregama', 'venus', 'venus music', 'tips', 'tips music',
      'yrf', 'yash raj films', 'eros now music', 'eros music',
      'speed records', 'white hill music', 'jjust music',
    };

    final freq = <String, int>{};
    for (final song in _history) {
      final artist = song.artist.trim();
      final key = artist.toLowerCase();
      if (artist.isEmpty || labelNames.contains(key)) continue;
      freq[artist] = (freq[artist] ?? 0) + 1;
    }

    final sorted = freq.keys.toList()
      ..sort((a, b) => freq[b]!.compareTo(freq[a]!));

    return sorted;
  }

  List<String> topAffinityArtists({int count = 5}) =>
      RecommendationEngine.topAffinityArtists(count: count);

  Future<void> _maybeApplyDecay() async {
    try {
      final p = await SharedPreferences.getInstance();
      final lastDecayStr = p.getString(_kLastDecayDate);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (lastDecayStr != today) {
        await RecommendationEngine.applyDecay();
        await p.setString(_kLastDecayDate, today);
      }
    } catch (_) {
    }
  }
}
