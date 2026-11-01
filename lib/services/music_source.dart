// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../models/song.dart';
import 'api_service.dart';

abstract class MusicSource {
  String get name;

  Future<List<Song>> search(String query, {int limit});

  Future<List<Song>> similarTo(Song seed, {int limit});
}

class SaavnSource implements MusicSource {
  const SaavnSource();

  @override
  String get name => 'saavn';

  @override
  Future<List<Song>> search(String query, {int limit = 30}) {
    return _withRetry(() => ApiService.searchSaavnRaw(query, limit: limit));
  }

  @override
  Future<List<Song>> similarTo(Song seed, {int limit = 20}) {
    return _withRetry(() => ApiService.similarFromSaavnRaw(seed, limit: limit));
  }

  Future<List<Song>> _withRetry(Future<List<Song>> Function() attempt) async {
    final first = await attempt();
    if (first.isNotEmpty) return first;
    await Future.delayed(const Duration(milliseconds: 600));
    return attempt();
  }
}

class YtSource implements MusicSource {
  const YtSource();

  @override
  String get name => 'youtube';

  @override
  Future<List<Song>> search(String query, {int limit = 30}) {
    return ApiService.searchYtRaw(query, limit: limit);
  }

  @override
  Future<List<Song>> similarTo(Song seed, {int limit = 20}) {
    return Future.value(const <Song>[]);
  }
}

class MusicCatalog {
  MusicCatalog._();

  static const MusicSource saavn = SaavnSource();
  static const MusicSource youtube = YtSource();

  static Future<List<Song>> search(
    String query, {
    int limit = 50,
    int minPrimaryResults = 8,
  }) async {
    final primary = await saavn.search(query, limit: limit);
    if (primary.length >= minPrimaryResults) return primary;

    final secondary = await youtube.search(query, limit: limit);
    final seenIds = {for (final s in primary) s.id};
    final topUp = secondary.where((s) => !seenIds.contains(s.id));
    return [...primary, ...topUp];
  }

  static Future<List<Song>> similarTo(
    Song seed, {
    int limit = 20,
    int minPrimaryResults = 8,
  }) async {
    final primary = await saavn.similarTo(seed, limit: limit);
    if (primary.length >= minPrimaryResults) return primary;

    final secondary = await youtube.similarTo(seed, limit: limit);
    final seenIds = {for (final s in primary) s.id};
    final topUp = secondary.where((s) => !seenIds.contains(s.id));
    return [...primary, ...topUp];
  }
}
