// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/artist.dart';
import 'api_service.dart';
import 'audio_prefs.dart';

List<SongSection> _decodeSections(String raw) {
  final decoded = jsonDecode(raw) as List;
  return decoded
      .map((e) => SongSection.fromJson(e as Map<String, dynamic>))
      .where((s) => s.songs.isNotEmpty)
      .toList();
}

const int _computeThresholdBytes = 40 * 1024;

String _encodeSections(List<Map<String, dynamic>> sectionsJson) =>
    jsonEncode(sectionsJson);

List<ArtistSimple> _decodeArtists(String raw) {
  final decoded = jsonDecode(raw) as List;
  return decoded
      .map((e) => ArtistSimple(
            id: e['id'] as String,
            name: e['name'] as String,
            imageUrl: e['imageUrl'] as String,
          ))
      .toList();
}

class RefreshStage {
  final bool quickPicks;
  final bool shelves;
  final bool similarArtistRows;
  final bool similarSongRows;

  const RefreshStage({
    required this.quickPicks,
    required this.shelves,
    required this.similarArtistRows,
    required this.similarSongRows,
  });

  factory RefreshStage.forPosition(int position) {
    final slot = position % 3;
    return RefreshStage(
      quickPicks: true,
      shelves: slot == 1,
      similarArtistRows: slot == 2,
      similarSongRows: slot == 0,
    );
  }
}

class HomeFeedCache {
  static Future<void> invalidateForRegionChange() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [
        _savedAtKey,
        _artistsSavedAtKey,
        _quickPicksSavedAtKey,
        _similarArtistRowsSavedAtKey,
        _similarSongRowsSavedAtKey,
        _homeShelvesSavedAtKey,
      ]) {
        await prefs.remove(k);
      }
      for (final k in prefs.getKeys().toList()) {
        if (k.contains('playlists_saved_at') ||
            k.contains('albums_saved_at') ||
            k.contains('SavedAt')) {
          await prefs.remove(k);
        }
      }
    } catch (_) {}
  }

  static const _sectionsKey = 'home_feed_cache_sections_v1';
  static const _artistsKey = 'home_feed_cache_artists_v3';
  static const _savedAtKey = 'home_feed_cache_saved_at_ms';
  static const _artistsSavedAtKey = 'home_feed_cache_artists_saved_at_ms_v3';

  static const Duration _maxFreshAge = Duration(hours: 6);
  static const Duration _maxFreshAgeDataSaver = Duration(hours: 24);

  static bool _isRecent(int? savedAtMs) {
    if (savedAtMs == null) return false;
    if (AudioPrefs.dataSaverActiveNotifier.value) return true;
    final age = DateTime.now().millisecondsSinceEpoch - savedAtMs;
    return age >= 0 && age < _maxFreshAge.inMilliseconds;
  }

  static Future<bool> coldAttemptedRecently(String key) async {
    if (!AudioPrefs.dataSaverActiveNotifier.value) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getInt('cold_attempt_$key') ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - t;
      return age >= 0 && age < const Duration(hours: 24).inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markColdAttempt(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'cold_attempt_$key', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<void> clearColdAttempt(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cold_attempt_$key');
    } catch (_) {}
  }

  static Future<bool> isFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _isRecent(prefs.getInt(_savedAtKey));
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isArtistsFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _isRecent(prefs.getInt(_artistsSavedAtKey));
    } catch (_) {
      return false;
    }
  }

  static Future<void> saveSections(List<SongSection> sections) async {
    if (sections.isEmpty) return;
    final usable = sections.where((s) => s.songs.isNotEmpty).toList();
    if (usable.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final sectionsJson = usable.map((s) => s.toJson()).toList();
      final approxSongCount =
          usable.fold<int>(0, (sum, s) => sum + s.songs.length);
      final encoded = approxSongCount > 200
          ? await compute(_encodeSections, sectionsJson)
          : _encodeSections(sectionsJson);
      await prefs.setString(_sectionsKey, encoded);
      await prefs.setInt(_savedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
    }
  }

  static Future<List<SongSection>> loadSections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAtMs = prefs.getInt(_savedAtKey);
      if (savedAtMs == null) return [];
      final raw = prefs.getString(_sectionsKey);
      if (raw == null || raw.isEmpty) return [];
      if (raw.length < _computeThresholdBytes) {
        return _decodeSections(raw);
      }
      return compute(_decodeSections, raw);
    } catch (_) {
      return [];
    }
  }

  static Future<List<SongSection>> loadBundledSnapshot() async {
    try {
      final raw = await rootBundle.loadString('assets/data/home_snapshot.json');
      if (raw.isEmpty) return [];
      if (raw.length < _computeThresholdBytes) {
        return _decodeSections(raw);
      }
      return compute(_decodeSections, raw);
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveArtists(List<ArtistSimple> artists) async {
    if (artists.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(artists
          .map((a) => {'id': a.id, 'name': a.name, 'imageUrl': a.imageUrl})
          .toList());
      await prefs.setString(_artistsKey, encoded);
      await prefs.setInt(
          _artistsSavedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
    }
  }

  static Future<List<ArtistSimple>> loadArtists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAtMs = prefs.getInt(_artistsSavedAtKey);
      if (savedAtMs == null) return [];
      final raw = prefs.getString(_artistsKey);
      if (raw == null || raw.isEmpty) return [];
      if (raw.length < _computeThresholdBytes) {
        return _decodeArtists(raw);
      }
      return compute(_decodeArtists, raw);
    } catch (_) {
      return [];
    }
  }

  static String _playlistsKey(String mood) => 'home_playlist_cards_v1_$mood';
  static String _playlistsSavedAtKey(String mood) =>
      'home_playlist_cards_saved_at_ms_$mood';

  static Future<void> savePlaylistCards(
      String mood, List<YtHomePlaylistCard> cards) async {
    if (cards.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(cards.map((c) => c.toJson()).toList());
      await prefs.setString(_playlistsKey(mood), encoded);
      await prefs.setInt(
          _playlistsSavedAtKey(mood), DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<YtHomePlaylistCard>> loadPlaylistCards(
      String mood) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAtMs = prefs.getInt(_playlistsSavedAtKey(mood));
      if (savedAtMs == null) return [];
      final raw = prefs.getString(_playlistsKey(mood));
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) =>
              YtHomePlaylistCard.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isPlaylistsFresh(String mood) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _isRecent(prefs.getInt(_playlistsSavedAtKey(mood)));
    } catch (_) {
      return false;
    }
  }

  static String _albumsKey(String mood) => 'home_album_cards_v1_$mood';
  static String _albumsSavedAtKey(String mood) =>
      'home_album_cards_saved_at_ms_$mood';

  static Future<void> saveAlbumCards(
      String mood, List<HomeAlbumCard> cards) async {
    if (cards.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(cards.map((c) => c.toJson()).toList());
      await prefs.setString(_albumsKey(mood), encoded);
      await prefs.setInt(
          _albumsSavedAtKey(mood), DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<HomeAlbumCard>> loadAlbumCards(String mood) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAtMs = prefs.getInt(_albumsSavedAtKey(mood));
      if (savedAtMs == null) return [];
      final raw = prefs.getString(_albumsKey(mood));
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => HomeAlbumCard.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isAlbumsFresh(String mood) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _isRecent(prefs.getInt(_albumsSavedAtKey(mood)));
    } catch (_) {
      return false;
    }
  }

  static const _quickPicksKey = 'home_quick_picks_v1';
  static const _quickPicksSavedAtKey = 'home_quick_picks_saved_at_ms';

  static Future<void> saveQuickPicks(List<Song> songs,
      {bool touch = true}) async {
    if (songs.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(songs.map((s) => s.toJson()).toList());
      await prefs.setString(_quickPicksKey, encoded);
      if (touch) {
        await prefs.setInt(
            _quickPicksSavedAtKey, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (_) {}
  }

  static Future<List<Song>> loadQuickPicks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAtMs = prefs.getInt(_quickPicksSavedAtKey);
      if (savedAtMs == null) return [];
      final raw = prefs.getString(_quickPicksKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isQuickPicksFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _isRecent(prefs.getInt(_quickPicksSavedAtKey));
    } catch (_) {
      return false;
    }
  }

  static const _similarArtistRowsKey = 'home_similar_artist_rows_v2';
  static const _similarArtistRowsSavedAtKey =
      'home_similar_artist_rows_saved_at_ms';

  static Future<void> saveSimilarArtistRows(
      List<({String artistName, String? artistImageUrl, RelatedArtist? relatedArtist, List<ArtistAlbum> albums})> rows) async {
    if (rows.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(rows
          .map((r) => {
                'artistName': r.artistName,
                'artistImageUrl': r.artistImageUrl,
                'relatedArtist': r.relatedArtist?.toJson(),
                'albums': r.albums.map((a) => a.toJson()).toList(),
              })
          .toList());
      await prefs.setString(_similarArtistRowsKey, encoded);
      await prefs.setInt(_similarArtistRowsSavedAtKey,
          DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<({String artistName, String? artistImageUrl, RelatedArtist? relatedArtist, List<ArtistAlbum> albums})>>
      loadSimilarArtistRows() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAtMs = prefs.getInt(_similarArtistRowsSavedAtKey);
      if (savedAtMs == null) return [];
      final raw = prefs.getString(_similarArtistRowsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final relatedJson = m['relatedArtist'];
        return (
          artistName: (m['artistName'] ?? '').toString(),
          artistImageUrl: m['artistImageUrl']?.toString(),
          relatedArtist: relatedJson is Map
              ? RelatedArtist.fromJson(Map<String, dynamic>.from(relatedJson))
              : null,
          albums: ((m['albums'] as List?) ?? const [])
              .whereType<Map>()
              .map((a) => ArtistAlbum.fromJson(Map<String, dynamic>.from(a)))
              .toList(),
        );
      }).where((r) => r.artistName.isNotEmpty && r.albums.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isSimilarArtistRowsFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _isRecent(prefs.getInt(_similarArtistRowsSavedAtKey));
    } catch (_) {
      return false;
    }
  }

  static const _similarSongRowsKey = 'home_similar_song_rows_v1';
  static const _similarSongRowsSavedAtKey =
      'home_similar_song_rows_saved_at_ms';

  static Future<void> saveSimilarSongRows(
      List<({Song seedSong, List<Song> related})> rows) async {
    if (rows.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(rows
          .map((r) => {
                'seedSong': r.seedSong.toJson(),
                'related': r.related.map((s) => s.toJson()).toList(),
              })
          .toList());
      await prefs.setString(_similarSongRowsKey, encoded);
      await prefs.setInt(
          _similarSongRowsSavedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<({Song seedSong, List<Song> related})>>
      loadSimilarSongRows() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAtMs = prefs.getInt(_similarSongRowsSavedAtKey);
      if (savedAtMs == null) return [];
      final raw = prefs.getString(_similarSongRowsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final seedJson = m['seedSong'];
        final related = ((m['related'] as List?) ?? const [])
            .whereType<Map>()
            .map((s) => Song.fromJson(Map<String, dynamic>.from(s)))
            .toList();
        return (
          seedSong: seedJson is Map
              ? Song.fromJson(Map<String, dynamic>.from(seedJson))
              : Song(id: '', title: '', artist: '', album: '', artworkUrl: ''),
          related: related,
        );
      }).where((r) => r.seedSong.id.isNotEmpty && r.related.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isSimilarSongRowsFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _isRecent(prefs.getInt(_similarSongRowsSavedAtKey));
    } catch (_) {
      return false;
    }
  }

  static const _homeShelvesKey = 'home_real_shelves_v1';
  static const _homeShelvesSavedAtKey = 'home_real_shelves_saved_at_ms';

  static Future<void> saveHomeShelves(List<HomeShelf> shelves) async {
    if (shelves.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(shelves.map((s) => s.toJson()).toList());
      await prefs.setString(_homeShelvesKey, encoded);
      await prefs.setInt(
          _homeShelvesSavedAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<HomeShelf>> loadHomeShelves() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedAtMs = prefs.getInt(_homeShelvesSavedAtKey);
      if (savedAtMs == null) return [];
      final raw = prefs.getString(_homeShelvesKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map((e) => HomeShelf.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.items.isNotEmpty || s.songs.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> isHomeShelvesFresh() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _isRecent(prefs.getInt(_homeShelvesSavedAtKey));
    } catch (_) {
      return false;
    }
  }

  static const _pullRefreshCountKey = 'home_pull_refresh_count';

  static const int fullRefreshEvery = 10;

  static Future<int> bumpPullRefreshAndGetPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = (prefs.getInt(_pullRefreshCountKey) ?? 0) + 1;
      await prefs.setInt(_pullRefreshCountKey, next);
      final pos = ((next - 1) % fullRefreshEvery) + 1;
      return pos;
    } catch (_) {
      return 1;
    }
  }
}
