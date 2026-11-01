// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import 'user_region.dart';

enum SessionMood { romantic, sad, party, devotional, workout, chill, energetic, neutral }
enum SessionGenre { bollywood, punjabi, hiphop, english, lofi, devotional, bhojpuri, other }
enum SessionLanguage { hindi, punjabi, english, tamil, telugu, bengali, marathi, gujarati, malayalam, other }
enum TimeSlot { morning, afternoon, evening, night, lateNight }

class _SessionState {
  final SessionMood mood;
  final SessionGenre genre;
  final SessionLanguage language;
  final List<String> recentArtists;
  final List<String> recentIds;
  final List<String> recentTitles;
  final DateTime startedAt;

  _SessionState({
    required this.mood,
    required this.genre,
    required this.language,
    required this.recentArtists,
    required this.recentIds,
    required this.recentTitles,
    required this.startedAt,
  });

  factory _SessionState.fromJson(Map<String, dynamic> j) => _SessionState(
        mood: SessionMood.values.firstWhere(
            (e) => e.name == j['mood'], orElse: () => SessionMood.neutral),
        genre: SessionGenre.values.firstWhere(
            (e) => e.name == j['genre'], orElse: () => SessionGenre.other),
        language: SessionLanguage.values.firstWhere(
            (e) => e.name == j['language'], orElse: () => SessionLanguage.hindi),
        recentArtists: List<String>.from(j['recentArtists'] ?? []),
        recentIds: List<String>.from(j['recentIds'] ?? []),
        recentTitles: List<String>.from(j['recentTitles'] ?? []),
        startedAt: DateTime.tryParse(j['startedAt'] ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'mood': mood.name,
        'genre': genre.name,
        'language': language.name,
        'recentArtists': recentArtists,
        'recentIds': recentIds,
        'recentTitles': recentTitles,
        'startedAt': startedAt.toIso8601String(),
      };

  _SessionState copyWith({
    SessionMood? mood,
    SessionGenre? genre,
    SessionLanguage? language,
    List<String>? recentArtists,
    List<String>? recentIds,
    List<String>? recentTitles,
  }) =>
      _SessionState(
        mood: mood ?? this.mood,
        genre: genre ?? this.genre,
        language: language ?? this.language,
        recentArtists: recentArtists ?? this.recentArtists,
        recentIds: recentIds ?? this.recentIds,
        recentTitles: recentTitles ?? this.recentTitles,
        startedAt: startedAt,
      );
}

class RecommendationEngine {
  RecommendationEngine._();

  static const _kPlays     = 'aurum_rec_plays';
  static const _kCompletes = 'aurum_rec_completes';
  static const _kSkips     = 'aurum_rec_skips';
  static const _kReplays   = 'aurum_rec_replays';
  static const _kArtistW   = 'aurum_rec_artist_w';
  static const _kArtistDisplayName = 'aurum_rec_artist_display_name';
  static const _kPinnedArtists = 'aurum_rec_pinned_artists';
  static const _kGenreW    = 'aurum_rec_genre_w';
  static const _kLangW     = 'aurum_rec_lang_w';
  static const _kSession   = 'aurum_rec_session';
  static const _kHomeShown = 'aurum_rec_home_shown';
  static const _kAlbumPlays  = 'aurum_rec_album_plays';
  static const _kDecadeW     = 'aurum_rec_decade_w';
  static const _kLastPlayed  = 'aurum_rec_last_played_at';

  static Map<String, int>    _plays     = {};
  static Map<String, int>    _completes = {};
  static Map<String, int>    _skips     = {};
  static Map<String, int>    _replays   = {};
  static Map<String, double> _artistW   = {};
  static Map<String, String> _artistDisplayName = {};
  static List<String> _pinnedArtists = [];
  static const int _maxPinned = 30;
  static Map<String, double> _genreW    = {};
  static Map<String, double> _langW     = {};
  static _SessionState?      _session;
  static bool                _loaded    = false;
  static List<String>        _homeShown = [];
  static Map<String, int>    _albumPlays = {};
  static Map<String, double> _decadeW    = {};
  static Map<String, int>    _lastPlayedAt = {};

  static const double _decayFactor = 0.92;

  static const int _maxTrackedSongs = 500;

  static void _pruneTrackedSongs() {
    if (_plays.length <= _maxTrackedSongs) return;
    final ids = _plays.keys.toList()
      ..sort((a, b) =>
          (_lastPlayedAt[a] ?? 0).compareTo(_lastPlayedAt[b] ?? 0));
    final toDrop = ids.length - _maxTrackedSongs;
    if (toDrop <= 0) return;
    final dropIds = ids.take(toDrop).toSet();
    _plays.removeWhere((k, _) => dropIds.contains(k));
    _completes.removeWhere((k, _) => dropIds.contains(k));
    _skips.removeWhere((k, _) => dropIds.contains(k));
    _replays.removeWhere((k, _) => dropIds.contains(k));
    _lastPlayedAt.removeWhere((k, _) => dropIds.contains(k));
  }

  static int _queryRotation = 0;

  static Future<void> load() async {
    if (_loaded) return;
    await UserRegion.load();
    final p = await SharedPreferences.getInstance();

    _plays     = _loadIntMap(p, _kPlays);
    _completes = _loadIntMap(p, _kCompletes);
    _skips     = _loadIntMap(p, _kSkips);
    _replays   = _loadIntMap(p, _kReplays);
    _artistW   = _loadDoubleMap(p, _kArtistW);
    try {
      final raw = p.getString(_kArtistDisplayName);
      _artistDisplayName = raw == null
          ? {}
          : (jsonDecode(raw) as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      _artistDisplayName = {};
    }
    try {
      _pinnedArtists = List<String>.from(p.getStringList(_kPinnedArtists) ?? const []);
    } catch (_) {
      _pinnedArtists = [];
    }
    _genreW    = _loadDoubleMap(p, _kGenreW);
    _langW     = _loadDoubleMap(p, _kLangW);
    _albumPlays   = _loadIntMap(p, _kAlbumPlays);
    _decadeW      = _loadDoubleMap(p, _kDecadeW);
    _lastPlayedAt = _loadIntMap(p, _kLastPlayed);

    final sessionJson = p.getString(_kSession);
    if (sessionJson != null) {
      try {
        final decoded = jsonDecode(sessionJson) as Map<String, dynamic>;
        final candidate = _SessionState.fromJson(decoded);
        final age = DateTime.now().difference(candidate.startedAt);
        _session = age.inHours < 2 ? candidate : null;
      } catch (_) {
        _session = null;
      }
    }

    try {
      final raw = p.getStringList(_kHomeShown);
      _homeShown = raw ?? [];
    } catch (_) {
      _homeShown = [];
    }

    _loaded = true;
  }

  static Future<void> resetAll() async {
    _plays.clear();
    _completes.clear();
    _skips.clear();
    _replays.clear();
    _artistW.clear();
    _artistDisplayName.clear();
    _genreW.clear();
    _langW.clear();
    _session = null;
    _homeShown.clear();
    _albumPlays.clear();
    _decadeW.clear();
    _lastPlayedAt.clear();

    final p = await SharedPreferences.getInstance();
    await p.remove(_kPlays);
    await p.remove(_kCompletes);
    await p.remove(_kSkips);
    await p.remove(_kReplays);
    await p.remove(_kArtistW);
    await p.remove(_kArtistDisplayName);
    await p.remove(_kPinnedArtists);
    _pinnedArtists = [];
    await p.remove(_kGenreW);
    await p.remove(_kLangW);
    await p.remove(_kSession);
    await p.remove(_kHomeShown);
    await p.remove(_kAlbumPlays);
    await p.remove(_kDecadeW);
    await p.remove(_kLastPlayed);
  }

  static Map<String, int> _loadIntMap(SharedPreferences p, String key) {
    try {
      final raw = p.getString(key);
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  static Map<String, double> _loadDoubleMap(SharedPreferences p, String key) {
    try {
      final raw = p.getString(key);
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> onSongStarted(Song song) async {
    if (!_loaded) await load();
    if (song.isLocal) return;

    _plays[song.id] = (_plays[song.id] ?? 0) + 1;
    _lastPlayedAt[song.id] = DateTime.now().millisecondsSinceEpoch;

    _boostArtist(song.artist, delta: 0.06);
    _boostGenre(detectGenre(song), delta: 0.05);
    _boostLanguage(detectLanguage(song), delta: 0.04);

    _updateSession(song);

    _saveAll();
  }

  static Future<void> onSongCompleted(Song song) async {
    if (!_loaded) await load();
    if (song.isLocal) return;

    _completes[song.id] = (_completes[song.id] ?? 0) + 1;

    _boostArtist(song.artist, delta: 0.15);
    _boostGenre(detectGenre(song), delta: 0.10);
    _boostLanguage(detectLanguage(song), delta: 0.08);

    if (song.album.trim().isNotEmpty) {
      final albumKey = song.album.trim().toLowerCase();
      if (albumKey.isNotEmpty) {
        _albumPlays[albumKey] = (_albumPlays[albumKey] ?? 0) + 1;
      }
    }
    final decade = _songDecade(song);
    if (decade != null) _boostDecade(decade, delta: 0.10);

    _saveAll();
  }

  static Future<void> onEarlySkip(Song song) async {
    if (!_loaded) await load();
    if (song.isLocal) return;

    _skips[song.id] = (_skips[song.id] ?? 0) + 1;

    _boostArtist(song.artist, delta: -0.08);
    _boostGenre(detectGenre(song), delta: -0.05);
    _boostLanguage(detectLanguage(song), delta: -0.03);

    _saveAll();
  }

  static Future<void> onReplay(Song song) async {
    if (!_loaded) await load();
    if (song.isLocal) return;

    _replays[song.id] = (_replays[song.id] ?? 0) + 1;

    _boostArtist(song.artist, delta: 0.20);
    _boostGenre(detectGenre(song), delta: 0.15);
    _boostLanguage(detectLanguage(song), delta: 0.10);

    _saveAll();
  }

  static Future<void> onFavorited(Song song) async {
    if (!_loaded) await load();
    if (song.isLocal) return;

    _boostArtist(song.artist, delta: 0.35);
    _boostGenre(detectGenre(song), delta: 0.25);
    _boostLanguage(detectLanguage(song), delta: 0.15);

    _saveAll();
  }

  static Future<void> onUnfavorited(Song song) async {
    if (!_loaded) await load();
    if (song.isLocal) return;

    _boostArtist(song.artist, delta: -0.15);
    _boostGenre(detectGenre(song), delta: -0.10);

    _saveAll();
  }

  static Future<void> applyOnboardingGenrePreferences(List<String> genres) async {
    if (!_loaded) await load();
    for (final g in genres) {
      _boostGenre(g, delta: 0.35);
    }
    _saveAll();
  }

  static Future<void> applyOnboardingArtistPreferences(List<String> artists) async {
    if (!_loaded) await load();
    for (final a in artists) {
      final t = a.trim();
      if (t.isEmpty) continue;
      _boostArtist(t, delta: 0.35);
      final k = _normalizeKey(t);
      _pinnedArtists.removeWhere((x) => _normalizeKey(x) == k);
      _pinnedArtists.insert(0, t);
    }
    if (_pinnedArtists.length > _maxPinned) {
      _pinnedArtists = _pinnedArtists.take(_maxPinned).toList();
    }
    _saveAll();
  }

  static Future<void> setPinnedArtists(List<String> artists) async {
    if (!_loaded) await load();
    final next = <String>[];
    for (final a in artists) {
      final t = a.trim();
      if (t.isEmpty) continue;
      if (next.any((x) => _normalizeKey(x) == _normalizeKey(t))) continue;
      next.add(t);
    }
    final nextKeys = next.map(_normalizeKey).toSet();
    for (final old in _pinnedArtists) {
      final k = _normalizeKey(old);
      if (!nextKeys.contains(k) && (_artistW[k] ?? 0.5) > 0.5) {
        _artistW[k] = 0.5 + ((_artistW[k]! - 0.5) * 0.4);
      }
    }
    for (final a in next) {
      if (!_pinnedArtists.any((x) => _normalizeKey(x) == _normalizeKey(a))) {
        _boostArtist(a, delta: 0.35);
      }
    }
    _pinnedArtists = next.take(_maxPinned).toList();
    await _saveAll();
  }

  static List<String> get pinnedArtists => List.unmodifiable(_pinnedArtists);

  static void _boostArtist(String artist, {required double delta}) {
    final key = _normalizeKey(artist);
    if (key.isEmpty) return;
    final current = _artistW[key] ?? 0.5;
    _artistW[key] = (current + delta).clamp(0.0, 1.0);
    final trimmed = artist.trim();
    if (trimmed.isNotEmpty) {
      _artistDisplayName.putIfAbsent(key, () => trimmed);
    }
  }

  static void _boostGenre(String genre, {required double delta}) {
    final current = _genreW[genre] ?? 0.5;
    _genreW[genre] = (current + delta).clamp(0.0, 1.0);
  }

  static void _boostLanguage(String lang, {required double delta}) {
    final current = _langW[lang] ?? 0.5;
    _langW[lang] = (current + delta).clamp(0.0, 1.0);
  }

  static void _boostDecade(String decade, {required double delta}) {
    final current = _decadeW[decade] ?? 0.5;
    _decadeW[decade] = (current + delta).clamp(0.0, 1.0);
  }

  static void _updateSession(Song song) {
    final mood     = _detectMoodEnum(song);
    final genre    = _detectGenreEnum(song);
    final language = _detectLanguageEnum(song);

    if (_session == null) {
      _session = _SessionState(
        mood: mood,
        genre: genre,
        language: language,
        recentArtists: [song.artist],
        recentIds: [song.id],
        recentTitles: [_titleCore(song.title)],
        startedAt: DateTime.now(),
      );
      return;
    }

    final updatedMood = _blendMood(_session!.mood, mood);
    final updatedGenre = _blendGenre(_session!.genre, genre);
    final updatedLang = _blendLanguage(_session!.language, language);

    final artists = [song.artist, ..._session!.recentArtists]
        .toSet()
        .take(5)
        .toList();

    final ids = [song.id, ..._session!.recentIds].take(20).toList();

    final titles = [_titleCore(song.title), ..._session!.recentTitles]
        .toSet()
        .take(200)
        .toList();

    _session = _session!.copyWith(
      mood: updatedMood,
      genre: updatedGenre,
      language: updatedLang,
      recentArtists: artists,
      recentIds: ids,
      recentTitles: titles,
    );
  }

  static SessionMood _blendMood(SessionMood current, SessionMood incoming) {
    if (current == incoming) return current;
    const compatible = {
      SessionMood.romantic: {SessionMood.sad, SessionMood.chill},
      SessionMood.sad: {SessionMood.romantic, SessionMood.chill},
      SessionMood.party: {SessionMood.energetic, SessionMood.workout},
      SessionMood.workout: {SessionMood.party, SessionMood.energetic},
      SessionMood.energetic: {SessionMood.party, SessionMood.workout},
      SessionMood.chill: {SessionMood.romantic, SessionMood.sad},
      SessionMood.devotional: <SessionMood>{},
      SessionMood.neutral: {SessionMood.romantic, SessionMood.sad, SessionMood.party,
                             SessionMood.chill, SessionMood.energetic},
    };
    final compat = compatible[current] ?? {};
    return compat.contains(incoming) ? incoming : current;
  }

  static SessionGenre _blendGenre(SessionGenre current, SessionGenre incoming) =>
      incoming;

  static SessionLanguage _blendLanguage(SessionLanguage current, SessionLanguage incoming) =>
      incoming;

  static double scoreCandidate(Song candidate, {Song? currentSong}) {
    if (!_loaded) return 0.5;
    if (candidate.isLocal) return 0.3;

    double score = 0.0;

    final artistKey = _normalizeKey(candidate.artist);
    final genre     = detectGenre(candidate);
    final language  = detectLanguage(candidate);

    if (currentSong != null) {
      final refEra = _songDecade(currentSong);
      final candEra = _songDecade(candidate);
      if (refEra != null && candEra != null) {
        if (candEra == refEra) {
          score += 0.15;
        } else {
          score -= 0.10;
        }
      } else if (refEra != null && candEra == null) {
        score -= 0.05;
      }
    }

    score += (_artistW[artistKey] ?? 0.5) * 0.25;

    score += (_genreW[genre] ?? 0.5) * 0.20;

    score += (_langW[language] ?? 0.5) * 0.15;

    if (_session != null) {
      final songMood = _detectMoodEnum(candidate);
      if (songMood == _session!.mood) {
        score += 0.15;
      } else if (_moodCompatible(_session!.mood, songMood)) {
        score += 0.08;
      }
    } else {
      score += 0.075;
    }

    if (_session != null) {
      final songGenreEnum = _detectGenreEnum(candidate);
      if (songGenreEnum == _session!.genre) score += 0.10;
      else if (_session!.genre == SessionGenre.other) score += 0.05;
    } else {
      score += 0.05;
    }

    if (currentSong != null &&
        currentSong.album.isNotEmpty &&
        candidate.album.isNotEmpty &&
        _normalizeKey(candidate.album) == _normalizeKey(currentSong.album)) {
      score += 0.10;
    }

    final plays = _plays[candidate.id] ?? 0;
    if (plays > 0) {
      final completes = _completes[candidate.id] ?? 0;
      final rate = completes / plays;
      score += rate * 0.08;
    }

    final replays = _replays[candidate.id] ?? 0;
    if (replays > 0) score += math.min(replays * 0.02, 0.05);

    final skips = _skips[candidate.id] ?? 0;
    if (skips > 0) score -= math.min(skips * 0.07, 0.20);

    score += _timeSlotBonus(candidate) * 0.02;

    score += _freshnessBonus(candidate) * 0.06;

    score += _trendingBonus(candidate) * 0.05;

    return score.clamp(0.0, 1.0);
  }

  static const int _freshnessFullBonusDays = 30;
  static const int _freshnessFullDecayDays = 540;

  static double _freshnessBonus(Song song) {
    final year = int.tryParse(song.year ?? '') ?? 0;
    if (year <= 0) return 0.0;
    final releaseDate = DateTime(year, 1, 1);
    final ageDays = DateTime.now().difference(releaseDate).inDays;
    if (ageDays < 0) return 0.0;
    if (ageDays <= _freshnessFullBonusDays) return 1.0;
    if (ageDays >= _freshnessFullDecayDays) return 0.0;
    final span = _freshnessFullDecayDays - _freshnessFullBonusDays;
    final progress = (ageDays - _freshnessFullBonusDays) / span;
    return (1.0 - progress).clamp(0.0, 1.0);
  }

  static const int _trendingFloorViews = 500000;
  static const int _trendingCeilingViews = 50000000;

  static double _trendingBonus(Song song) {
    if (song.source != SongSource.youtube) return 0.0;
    final views = song.viewCount;
    if (views == null || views < _trendingFloorViews) return 0.0;
    if (views >= _trendingCeilingViews) return 1.0;
    final logFloor = math.log(_trendingFloorViews);
    final logCeil  = math.log(_trendingCeilingViews);
    final logViews = math.log(views);
    return ((logViews - logFloor) / (logCeil - logFloor)).clamp(0.0, 1.0);
  }

  static bool _moodCompatible(SessionMood session, SessionMood song) {
    const compat = {
      SessionMood.romantic: [SessionMood.sad, SessionMood.chill],
      SessionMood.sad: [SessionMood.romantic, SessionMood.chill],
      SessionMood.party: [SessionMood.energetic, SessionMood.workout],
      SessionMood.workout: [SessionMood.party, SessionMood.energetic],
      SessionMood.energetic: [SessionMood.party, SessionMood.workout],
      SessionMood.chill: [SessionMood.romantic, SessionMood.sad],
    };
    return (compat[session] ?? []).contains(song);
  }

  static double _timeSlotBonus(Song song) {
    final slot = currentTimeSlot();
    final genre = detectGenre(song);
    final mood  = _detectMoodEnum(song);

    switch (slot) {
      case TimeSlot.morning:
        if (mood == SessionMood.chill || mood == SessionMood.romantic) return 1.0;
        if (genre == 'lofi') return 0.8;
        return 0.3;
      case TimeSlot.afternoon:
        return 0.5;
      case TimeSlot.evening:
        if (mood == SessionMood.party || mood == SessionMood.energetic) return 0.9;
        return 0.5;
      case TimeSlot.night:
        if (mood == SessionMood.romantic || mood == SessionMood.chill) return 1.0;
        if (mood == SessionMood.sad) return 0.7;
        return 0.3;
      case TimeSlot.lateNight:
        if (genre == 'lofi' || mood == SessionMood.chill) return 1.0;
        if (mood == SessionMood.sad) return 0.8;
        return 0.2;
    }
  }

  static bool shouldBlock(Song song, {String? currentTitle}) {
    if (!_loaded) return false;

    if (_session != null && _session!.recentIds.contains(song.id)) return true;

    if (_session != null && _session!.recentArtists.length >= 2) {
      final lastTwo   = _session!.recentArtists.take(2).toList();
      final artistNorm = _normalizeKey(song.artist);
      if (lastTwo.every((a) => _normalizeKey(a) == artistNorm)) return true;
    }

    if (currentTitle != null) {
      if (_isVariant(song.title, currentTitle)) return true;
    }

    if (isInherentVariant(song.title)) return true;

    return false;
  }

  static bool _isVariant(String candidate, String original) {
    final candCore = _titleCore(candidate);
    final origCore = _titleCore(original);
    if (candCore.isEmpty || origCore.isEmpty) return false;
    if (candCore == origCore) return true;
    if (candCore.contains(origCore) && origCore.length >= 5) return true;
    if (origCore.contains(candCore) && candCore.length >= 5) return true;
    final prefixLen = origCore.length.clamp(0, 15);
    final prefix = origCore.substring(0, prefixLen);
    if (prefix.isNotEmpty && candCore.startsWith(prefix) && candCore != origCore) return true;
    if (isSameSongSmart(candidate, original)) return true;
    return false;
  }

  static final RegExp _titleSeparator =
      RegExp(r'\s*[|:\u2013\u2014(\[]\s*|\s-\s');

  static final RegExp _headNoisePattern = RegExp(
    r'\b(8k|4k|2k|hd|hq|fhd|uhd|\d{3,4}p|\d{2,4}\s*kbps|'
    r'with\s*lyrics|lyrics video|lyrics|duet|feat|ft|'
    r'official\s*(video|audio|music\s*video)?|full\s*(song|video|audio)|'
    r'audio|video|song)\b',
    caseSensitive: false,
  );

  static String titleHead(String rawTitle) {
    final firstPart = rawTitle.split(_titleSeparator).first;
    return _cleanSegment(firstPart);
  }

  static String _cleanSegment(String segment) {
    final nonLatinLetters = RegExp(r'[^\x00-\x7F]').allMatches(segment).length;
    final letterish =
        RegExp(r'[a-zA-Z\u00C0-\uFFFF]').allMatches(segment).length;
    if (letterish > 0 && nonLatinLetters / letterish > 0.3) return '';

    return segment
        .toLowerCase()
        .replaceAll(_headNoisePattern, '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isJunkSegment(String cleaned) =>
      cleaned.isEmpty || cleaned.length < 3;

  static bool _looksLikeDecorativeSuffix(String segment) {
    if (segment.isEmpty) return false;
    final words = segment.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length > 3) return false;
    final genericTokenPattern = RegExp(
      r'^(with|beats?|mix(?:ed)?|version|edit(?:ed)?|vol\.?|part|pt\.?|'
      r'v\d+|no\s?\d+|\d+|super|new|old|special|exclusive|ultra|super hd|'
      r'studio|live|original|classic|hits?|collection)$',
    );
    final genericCount = words.where((w) => genericTokenPattern.hasMatch(w)).length;
    return genericCount * 2 >= words.length;
  }

  static List<String> titleSegments(String rawTitle) {
    final parts = rawTitle.split(_titleSeparator);
    final segments = <String>[];
    for (final part in parts) {
      final cleaned = _cleanSegment(part);
      if (!_isJunkSegment(cleaned)) segments.add(cleaned);
    }
    final head = _cleanSegment(parts.first);
    if (head.isNotEmpty && !segments.contains(head)) {
      segments.insert(0, head);
    }
    return segments;
  }

  static bool isSameSongSmart(String rawA, String rawB) {
    final segmentsA = titleSegments(rawA);
    final segmentsB = titleSegments(rawB);
    if (segmentsA.isEmpty || segmentsB.isEmpty) return false;

    for (final headA in segmentsA) {
      for (final headB in segmentsB) {
        if (_segmentsMatch(headA, headB)) return true;
      }
    }

    final firstA = segmentsA.first;
    final firstB = segmentsB.first;
    if (_segmentsMatch(firstA, firstB)) {
      final extraSegments = segmentsA.length >= segmentsB.length
          ? segmentsA.skip(1)
          : segmentsB.skip(1);
      if (extraSegments.isEmpty ||
          extraSegments.every(_looksLikeDecorativeSuffix)) {
        return true;
      }
    }

    return false;
  }

  static bool _fuzzyTokenMatch(String a, String b) {
    if (a == b) return true;
    if (a.length < 5 || b.length < 5) return false;
    if ((a.length - b.length).abs() > 1) return false;
    return _levenshteinAtMost1(a, b);
  }

  static bool _levenshteinAtMost1(String a, String b) {
    if (a == b) return true;
    final lenDiff = a.length - b.length;
    if (lenDiff.abs() > 1) return false;

    if (lenDiff == 0) {
      var mismatches = 0;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          mismatches++;
          if (mismatches > 1) return false;
        }
      }
      return true;
    }

    final shorter = a.length < b.length ? a : b;
    final longer   = a.length < b.length ? b : a;
    var i = 0, j = 0;
    var skipped = false;
    while (i < shorter.length && j < longer.length) {
      if (shorter[i] == longer[j]) {
        i++;
        j++;
      } else {
        if (skipped) return false;
        skipped = true;
        j++;
      }
    }
    return true;
  }

  static bool _segmentsMatch(String headA, String headB) {
    if (headA.isEmpty || headB.isEmpty) return false;
    if (headA == headB) return true;

    final tokensA = headA.split(' ').where((t) => t.length >= 2).toList();
    final tokensB = headB.split(' ').where((t) => t.length >= 2).toList();
    if (tokensA.isEmpty || tokensB.isEmpty) return false;

    final List<String> shortTokens;
    final List<String> longTokens;
    if (tokensA.length <= tokensB.length) {
      shortTokens = tokensA;
      longTokens = tokensB;
    } else {
      shortTokens = tokensB;
      longTokens = tokensA;
    }

    final longSet = longTokens.toSet();
    bool tokenOverlaps(String t) =>
        longSet.contains(t) || longTokens.any((lt) => _fuzzyTokenMatch(t, lt));
    final overlap = shortTokens.where(tokenOverlaps).length;
    final overlapRatio = overlap / shortTokens.length;

    final minRatio = shortTokens.length <= 2 ? 1.0 : 0.8;
    if (overlapRatio < minRatio) return false;

    final matchedInShort = shortTokens.where(tokenOverlaps).toList();
    final longIndex = <String, int>{};
    for (var i = 0; i < longTokens.length; i++) {
      longIndex.putIfAbsent(longTokens[i], () => i);
    }
    var lastPos = -1;
    for (final t in matchedInShort) {
      final pos = longIndex[t];
      if (pos == null) continue;
      if (pos < lastPos) return false;
      lastPos = pos;
    }
    return true;
  }

  static bool isSameSongByTokens(String coreA, String coreB) =>
      isSameSongSmart(coreA, coreB);

  static bool isInherentVariant(String title) {
    return _variantPattern.hasMatch(title);
  }

  static final RegExp _variantPattern = RegExp(
    r'\b(remix|lofi|lo[- ]?fi|slowed|reverb|nightcore|cover|karaoke|'
    r'instrumental|bass[ -]?boost(?:ed)?|8d|sped[ -]?up|speed(?:ed)?[ -]?up|'
    r'reprise|mashup|tribute|remaster(?:ed)?|unplugged|acoustic version|'
    r'orchestra|choir|chillout|drill remix|female version|male version|'
    r'recreated|recreation|refix|redux|rework(?:ed)?|revamp(?:ed)?|'
    r'lounge mix|jukebox|jhankar(?:\s*beats)?|super\s*jhankar|'
    r'recreate|extended|flip|bootleg|'
    r'chill mix|punjabi mix|hindi mix|afro mix|tapori|dj |club mix|'
    r'the return|revisited|throwback mix|new version|duet(?:\s*version)?|'
    r'ringtone|bgm|background music|type beat|'
    r'\d\.\d)\b',
    caseSensitive: false,
  );

  static bool looksLikeChannelName(String artist) {
    return _channelNamePattern.hasMatch(artist);
  }

  static final RegExp _channelNamePattern = RegExp(
    r'\b(t-?series|vevo|records|music company|music official|'
    r'entertainment|studios?|productions?|films?|cinema|label|'
    r'official channel|music india|music bhojpuri|music hub|'
    r'sony music|zee music|saregama|tips (?:official|music)|'
    r'speed records|white hill|desi music|indie music|'
    r'top\s?(?:10|20)|now (?:playing|streaming)|jukebox)\b',
    caseSensitive: false,
  );

  static bool isLowQualityUpload(String title) {
    if (_hashtagSpamPattern.hasMatch(title)) return true;
    if (_handleMentionPattern.hasMatch(title)) return true;
    if (_descriptionStyleTitlePattern.hasMatch(title)) return true;
    return _junkUploadPattern.hasMatch(title);
  }

  static final RegExp _subscriberCountPattern =
      RegExp(r'\bsubscribers?\b', caseSensitive: false);
  static final RegExp _songCountPattern =
      RegExp(r'(\d[\d,]*)\s*songs?\b', caseSensitive: false);
  static const int _minPlaylistSongCount = 10;

  static bool isLowQualityPlaylistShelfItem(String subtitle) {
    if (subtitle.trim().isEmpty) return true;
    if (_subscriberCountPattern.hasMatch(subtitle)) return true;
    final match = _songCountPattern.firstMatch(subtitle);
    if (match == null) return true;
    final count = int.tryParse(match.group(1)!.replaceAll(',', '')) ?? 0;
    return count < _minPlaylistSongCount;
  }

  static final RegExp _handleMentionPattern = RegExp(r'@\w+');
  static final RegExp _descriptionStyleTitlePattern = RegExp(
    r'\b(is a song (?:from|by|of)|is a cover (?:of|by)|is sung by|'
    r'is the (?:title|first|debut) (?:song|track)|song is (?:from|by))\b',
    caseSensitive: false,
  );

  static final RegExp _junkUploadPattern = RegExp(
    r'\b(naya dhamaka|dhamaka 20\d\d|happy new year|nav varsh|'
    r'naye saal|det badhai|badhai ho|beet phone|bhaiya ji|'
    r'freestyle|panwadi|wedding dance|vivah geet|shaadi geet|'
    r'jukebox 20\d\d|mp3 song|whatsapp status|status video|'
    r'trending status|viral video song|dance video|'
    r'gana 20\d\d|new gana|superhit gana|bhojpuri gana|'
    r'full dance video|superb dance|dj remix song|trending bhojpuri|'
    r'reaction video|cover version|cover song|dance cover|'
    r'stage show|live show|orchestra|nonstop dj|nonstop mix)\b',
    caseSensitive: false,
  );

  static final RegExp _hashtagSpamPattern = RegExp(r'(#\S+\s*){2,}');

  static const int _minViewsForPremiumFeed = 100000;

  static const int _minViewsForUnofficialChannel = 500000;

  static const int _minDurationSeconds = 90;
  static const int _maxDurationSeconds = 1200;

  static const List<String> _officialChannelMarkers = [
    't-series', 'zee music', 'sony music', 'saregama', 'tips official',
    'tips music', 'speed records', 'desi music factory', 'shemaroo',
    'venus', 'eros now music', 'yrf', 'jjust music', 'white hill music',
    'times music', 'muzik one', 'goldmines', 'ultra music', 'divo',
    'universal music', 'sony music south', 'aditya music', 'lahari music',
    'think music', 'zee music south', 'wave music', 'atlantic records',
    'republic records', 'columbia records', 'interscope', 'def jam',
    'rca records', 'capitol records', 'warner records',
  ];

  static bool isKnownOfficialChannel(String channelName) {
    final c = channelName.toLowerCase();
    return _officialChannelMarkers.any((m) => c.contains(m));
  }

  static bool isPremiumQuality(Song song, {bool trustedRelatedGraph = false}) {
    if (song.source == SongSource.youtube) {
      if (song.viewCount == null) return false;
      final requiredViews = isKnownOfficialChannel(song.artist)
          ? _minViewsForPremiumFeed
          : _minViewsForUnofficialChannel;
      if (song.viewCount! < requiredViews) return false;
      if (song.duration == null &&
          !isKnownOfficialChannel(song.artist) &&
          !trustedRelatedGraph) {
        return false;
      }
    }
    if (song.duration != null) {
      if (song.duration! < _minDurationSeconds) return false;
      if (song.duration! > _maxDurationSeconds) return false;
    }
    return true;
  }

  static bool isSearchQuality(Song song) {
    if (song.duration != null) {
      if (song.duration! < _minDurationSeconds) return false;
      if (song.duration! > _maxDurationSeconds) return false;
    }
    return true;
  }

  static final RegExp _nonMusicTitlePattern = RegExp(
    r'\b(vs\.?\b|explained|exposed|breaking|debate|interview|podcast|'
    r'documentary|analysis|review|reaction|vlog|news|update|crisis|'
    r'scandal|controversy|drowning|flood|election|protest|war\b|'
    r'government|politics|political|'
    r'trailer|teaser|live (performance|concert|session|show)|concert\b|'
    r'behind the scenes|making of|studio session|awards? (show|night|'
    r'ceremony)|red carpet|press conference|first look|motion poster|'
    r'glimpse|promo\b|shorts?\b)\b',
    caseSensitive: false,
  );

  static final RegExp _questionHookPattern = RegExp(r'\?\s*\|?\s*$');

  static const Set<String> _labelOnlyChannels = {
    't-series', 'saregama', 'saregama music', 'sony music india',
    'zee music company', 'aditya music', 'tips official', 'venus',
    'speed records', 'white hill music',
  };

  static final RegExp _songStyleMarkerPattern = RegExp(
    r'[\-\|]|\((lyrics?|official( video| audio)?|full song|audio)\)',
    caseSensitive: false,
  );

  static bool isNonMusicContent(Song song) {
    if (song.source != SongSource.youtube) return false;
    final title = song.title;
    if (_nonMusicTitlePattern.hasMatch(title)) return true;
    if (_questionHookPattern.hasMatch(title)) return true;

    final channel = song.artist.trim().toLowerCase();
    if (_labelOnlyChannels.contains(channel) &&
        !_songStyleMarkerPattern.hasMatch(title)) {
      return true;
    }
    return false;
  }

  static String _titleCore(String title) {
    return title
        .toLowerCase()
        .replaceAll(_variantPattern, '')
        .replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<Song> rankAndFilter({
    required List<Song> pool,
    required Song currentSong,
    required Set<String> existingIds,
    bool allowVariants = false,
    int limit = 10,
  }) {
    final seenIds    = <String>{currentSong.id, ...existingIds};
    final currentCore = _titleCore(currentSong.title);
    final seenTitles = <String>{currentCore};
    seenTitles.addAll(sessionRecentTitles);
    final seenRawTitles = <String>[currentSong.title];

    final scored = <_ScoredSong>[];

    for (final song in pool) {
      if (seenIds.contains(song.id)) continue;

      if (isNonMusicContent(song)) continue;

      if (!allowVariants) {
        if (isInherentVariant(song.title)) continue;
        if (_isVariant(song.title, currentSong.title)) continue;
        final core = _titleCore(song.title);
        if (seenTitles.contains(core)) continue;
        final prefix = currentCore.substring(0, currentCore.length.clamp(0, 10));
        if (prefix.isNotEmpty && core.startsWith(prefix) && core != currentCore) continue;
        var isDupOfAccepted = false;
        for (final seenRaw in seenRawTitles) {
          if (isSameSongSmart(song.title, seenRaw)) {
            isDupOfAccepted = true;
            break;
          }
        }
        if (isDupOfAccepted) continue;
      }

      if (_session != null) {
        final recentTwo = _session!.recentArtists.take(2).toSet();
        if (recentTwo.contains(song.artist) && scored.length > 3) continue;
      }

      final score = scoreCandidate(song, currentSong: currentSong);
      if (score < 0.1) continue;

      seenIds.add(song.id);
      seenTitles.add(_titleCore(song.title));
      seenRawTitles.add(song.title);
      scored.add(_ScoredSong(song, score));
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    return _applyDiscoveryMix(scored, limit: limit);
  }

  static List<Song> _applyDiscoveryMix(List<_ScoredSong> sorted, {required int limit}) {
    if (sorted.isEmpty) return [];

    final core      = <Song>[];
    final related   = <Song>[];
    final discovery = <Song>[];

    final total = sorted.length;
    for (int i = 0; i < total; i++) {
      final ratio = i / total;
      if (ratio < 0.70)      core.add(sorted[i].song);
      else if (ratio < 0.90) related.add(sorted[i].song);
      else                   discovery.add(sorted[i].song);
    }

    final result = <Song>[];
    final coreCount      = (limit * 0.70).ceil();
    final relatedCount   = (limit * 0.20).ceil();
    final discoveryCount = (limit * 0.10).ceil();

    const maxPerArtist = 3;
    final artistCounts = <String, int>{};

    const maxPerAlbum = 2;
    final albumCounts = <String, int>{};

    bool underCap(Song s) {
      final artistKey = _normalizeKey(s.artist);
      final albumKey  = _normalizeKey(s.album);
      final artistN = artistCounts[artistKey] ?? 0;
      final albumN  = albumKey.isEmpty ? 0 : (albumCounts[albumKey] ?? 0);
      if (artistN >= maxPerArtist) return false;
      if (albumKey.isNotEmpty && albumN >= maxPerAlbum) return false;
      artistCounts[artistKey] = artistN + 1;
      if (albumKey.isNotEmpty) albumCounts[albumKey] = albumN + 1;
      return true;
    }

    result.addAll(core.where(underCap).take(coreCount));
    result.addAll(related.where(underCap).take(relatedCount));
    result.addAll(discovery.where(underCap).take(discoveryCount));

    if (result.length < limit) {
      final used = result.map((s) => s.id).toSet();
      final leftover = [...core, ...related, ...discovery]
          .where((s) => !used.contains(s.id))
          .toList();
      for (final s in leftover) {
        if (result.length >= limit) break;
        if (!underCap(s)) continue;
        result.add(s);
        used.add(s.id);
      }
      if (result.length < limit) {
        for (final s in leftover) {
          if (result.length >= limit) break;
          if (used.contains(s.id)) continue;
          result.add(s);
          used.add(s.id);
        }
      }
    }

    _shuffleTier(result, 0, math.min(coreCount, result.length));

    return _interleaveByArtist(result);
  }

  static const int _minArtistGap = 2;

  static List<Song> _interleaveByArtist(List<Song> songs) {
    if (songs.length < 3) return songs;

    final remaining = List<Song>.from(songs);
    final result = <Song>[];
    final lastSeenAt = <String, int>{};

    while (remaining.isNotEmpty) {
      final pos = result.length;
      int pickIndex = -1;

      for (var i = 0; i < remaining.length; i++) {
        final key = _normalizeKey(remaining[i].artist);
        final last = lastSeenAt[key];
        if (last == null || pos - last > _minArtistGap) {
          pickIndex = i;
          break;
        }
      }

      if (pickIndex == -1) pickIndex = 0;

      final chosen = remaining.removeAt(pickIndex);
      lastSeenAt[_normalizeKey(chosen.artist)] = pos;
      result.add(chosen);
    }

    return result;
  }

  static void _shuffleTier(List<Song> list, int start, int end) {
    if (end - start < 2) return;
    final rng = math.Random();
    for (int i = end - 1; i > start; i--) {
      final j = start + rng.nextInt(i - start + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  static List<AutoQueueQuery> generateQueries(Song currentSong) {
    final genre   = detectGenre(currentSong);
    final lang    = detectLanguage(currentSong);
    final mood    = _detectMoodEnum(currentSong);
    final era     = _eraLanguageQuery(currentSong);
    final activeMood = _session?.mood ?? mood;

    final decadeTok = _songDecade(currentSong);

    final rotation = _queryRotation++;

    if (!_loaded) {
      return [
        AutoQueueQuery('${currentSong.artist} songs', weight: 2),
        AutoQueueQuery(_moodLockedQuery(activeMood, lang, genre, era: decadeTok, rotation: rotation), weight: 2),
        AutoQueueQuery(_sessionMoodQuery(activeMood, lang, era: decadeTok, rotation: rotation), weight: 1),
        AutoQueueQuery(era, weight: 2),
      ];
    }

    final topArtistKeys = _artistW.entries
        .where((e) => e.value > 0.55)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topArtists = topArtistKeys.take(5).map((e) => e.key).toList();

    final q1 = AutoQueueQuery(
      '${currentSong.artist} songs',
      weight: 2,
    );

    final q2 = AutoQueueQuery(
      _moodLockedQuery(activeMood, lang, genre, era: decadeTok, rotation: rotation),
      weight: 2,
    );

    final similarArtist = _pickSimilarArtist(currentSong, topArtists, rotation);
    final q3 = AutoQueueQuery(
      '$similarArtist songs',
      weight: 1,
    );

    final q4 = AutoQueueQuery(
      decadeTok != null ? era : _sessionMoodQuery(activeMood, lang, rotation: rotation),
      weight: 2,
    );

    final exploreArtist = _pickSimilarArtist(currentSong, topArtists, rotation + 3);
    final q5 = AutoQueueQuery(
      '$exploreArtist hit songs',
      weight: 1,
    );

    return [q1, q2, q3, q4, q5];
  }

  static String _moodLockedQuery(SessionMood mood, String lang, String genre, {String? era, int rotation = 0}) {
    final moodWord = _moodSearchWord(mood, rotation);
    final erapfx = (era != null && era.isNotEmpty) ? '$era ' : '';
    if (genre == 'bhojpuri') return '$erapfx$moodWord bhojpuri songs';
    if (genre == 'punjabi')  return '$erapfx$moodWord punjabi songs';
    if (genre == 'english')  return '$erapfx$moodWord english songs';
    if (genre == 'hiphop')   return '$erapfx$moodWord hindi rap songs';
    if (genre == 'devotional') return 'bhakti devotional songs';
    if (genre == 'lofi')     return 'lofi chill songs hindi';
    if (genre == 'tamil')    return '$erapfx$moodWord tamil songs';
    if (genre == 'telugu')   return '$erapfx$moodWord telugu songs';
    return '$erapfx$moodWord bollywood hindi songs';
  }

  static String _moodSearchWord(SessionMood mood, [int rotation = 0]) {
    const variants = <SessionMood, List<String>>{
      SessionMood.romantic:   ['romantic love', 'love', 'romantic'],
      SessionMood.sad:        ['sad heartbreak dard', 'sad', 'emotional heartbreak'],
      SessionMood.party:      ['party dance', 'dance party', 'party'],
      SessionMood.workout:    ['energetic motivation', 'workout gym', 'motivation'],
      SessionMood.chill:      ['chill relax', 'relaxing', 'chill'],
      SessionMood.energetic:  ['energetic upbeat', 'upbeat', 'high energy'],
      SessionMood.devotional: ['bhakti devotional', 'devotional bhajan', 'bhakti'],
      SessionMood.neutral:    ['top hits', 'best songs', 'popular hits'],
    };
    final options = variants[mood] ?? const ['top hits'];
    return options[rotation.abs() % options.length];
  }

  static String _pickSimilarArtist(Song song, List<String> userTopArtists, [int rotation = 0]) {
    final genre = detectGenre(song);
    final pool  = _genreSimilarArtists[genre] ?? _genreSimilarArtists['bollywood']!;

    final currentNorm = _normalizeKey(song.artist);
    final candidates = pool.where((a) => !_normalizeKey(a).contains(currentNorm) &&
                                         !currentNorm.contains(_normalizeKey(a))).toList();
    if (candidates.isEmpty) return pool.first;

    final preferredMatches = <String>[];
    for (final preferred in userTopArtists) {
      final match = candidates.firstWhere(
        (a) => _normalizeKey(a) == _normalizeKey(preferred),
        orElse: () => '',
      );
      if (match.isNotEmpty) preferredMatches.add(match);
    }
    if (preferredMatches.isNotEmpty) {
      return preferredMatches[rotation.abs() % preferredMatches.length];
    }

    return candidates[rotation.abs() % candidates.length];
  }

  static String _sessionMoodQuery(SessionMood mood, String lang, {String? era, int rotation = 0}) {
    const variants = <SessionMood, List<String>>{
      SessionMood.romantic:   ['romantic love songs', 'love songs', 'romantic hits'],
      SessionMood.sad:        ['heartbreak sad songs', 'sad songs', 'emotional songs'],
      SessionMood.party:      ['party dance hits', 'dance hits', 'party songs'],
      SessionMood.devotional: ['bhakti devotional songs', 'devotional bhajan songs'],
      SessionMood.workout:    ['workout motivation energy songs', 'gym workout songs'],
      SessionMood.chill:      ['chill relax lofi songs', 'relaxing songs', 'chill songs'],
      SessionMood.energetic:  ['energetic upbeat hits', 'upbeat songs', 'high energy hits'],
      SessionMood.neutral:    ['top hits songs', 'best songs', 'popular songs'],
    };
    final options = variants[mood] ?? const ['top hits songs'];
    var base = options[rotation.abs() % options.length];
    if (era != null && era.isNotEmpty && mood != SessionMood.devotional) {
      base = '$era $base';
    }
    if (lang == 'hindi' || lang == 'punjabi') return '$base hindi';
    if (lang == 'english') return '$base english';
    return base;
  }

  static String? _songDecade(Song song) {
    final year = int.tryParse(song.year ?? '') ?? 0;
    if (year <= 0) return null;
    if (year < 2000) return '90s';
    if (year < 2010) return '2000s';
    if (year < 2020) return '2010s';
    final thisYear = DateTime.now().year;
    return 'new $thisYear ${thisYear - 1}';
  }

  static String _eraLanguageQuery(Song song) {
    final lang = detectLanguage(song);
    final era = _songDecade(song);
    if (era != null) return '$era $lang songs';
    return '$lang top hits';
  }

  static bool _mentionsArtist(String haystackLower, String artistLower) {
    final artistWords = artistLower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (artistWords.isEmpty) return false;
    final haystackWords = haystackLower.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
    if (artistWords.length == 1) return haystackWords.contains(artistWords.first);
    for (var i = 0; i + artistWords.length <= haystackWords.length; i++) {
      var matches = true;
      for (var j = 0; j < artistWords.length; j++) {
        if (haystackWords[i + j] != artistWords[j]) { matches = false; break; }
      }
      if (matches) return true;
    }
    return false;
  }

  static String detectGenre(Song song) {
    final text = '${song.title} ${song.artist} ${song.language ?? ""}'.toLowerCase();
    final langLow = (song.language ?? '').toLowerCase();
    final artistLow = song.artist.toLowerCase();

    if (langLow.contains('bhojpuri') || text.contains('bhojpuri') ||
        text.contains('pawan singh') || text.contains('khesari') ||
        text.contains('neelkamal singh') || text.contains('shilpi raj') ||
        text.contains('pramod premi') || text.contains('arvind akela') ||
        text.contains('nirhua') || text.contains('dinesh lal') ||
        text.contains('samar singh') || text.contains('ritesh pandey') ||
        text.contains('ankush raja') || text.contains('gunjan singh') ||
        text.contains('amrapali dubey') || text.contains('akshara singh')) return 'bhojpuri';

    if (text.contains('punjabi') || text.contains('bhangra') ||
        text.contains('diljit') || text.contains('sidhu') ||
        langLow == 'punjabi') return 'punjabi';
    if (text.contains('rap') || text.contains('hip hop') || text.contains('hiphop') ||
        text.contains('trap') || text.contains('divine') || text.contains('emiway') ||
        text.contains('kr\$na') || text.contains('mc stan') || text.contains('seedhe')) return 'hiphop';
    if (text.contains('lofi') || text.contains('lo-fi') ||
        text.contains('chill') || text.contains('study') || text.contains('sleep')) return 'lofi';

    if (langLow == 'english' || text.contains('english pop') || text.contains('pop hits') ||
        (_genreSimilarArtists['english'] ?? const []).any((a) => _mentionsArtist(artistLow, a))) {
      return 'english';
    }

    if (text.contains('tamil') || langLow == 'tamil') return 'tamil';
    if (text.contains('telugu') || langLow == 'telugu') return 'telugu';
    if (text.contains('bhajan') || text.contains('aarti') || text.contains('mantra') ||
        text.contains('kirtan') || text.contains('chalisa')) return 'devotional';
    return 'bollywood';
  }

  static String detectLanguage(Song song) {
    final lang = (song.language ?? '').toLowerCase();
    if (lang.contains('bhojpuri')) return 'bhojpuri';
    if (lang.contains('punjabi'))  return 'punjabi';
    if (lang.contains('english'))  return 'english';
    if (lang.contains('tamil'))    return 'tamil';
    if (lang.contains('telugu'))   return 'telugu';
    if (lang.contains('bengali'))  return 'bengali';
    if (lang.contains('marathi'))  return 'marathi';
    if (lang.contains('gujarati')) return 'gujarati';
    if (lang.contains('malayalam')) return 'malayalam';
    final a = song.artist.toLowerCase();
    if (a.contains('pawan singh') || a.contains('khesari') || a.contains('neelkamal') ||
        a.contains('shilpi raj') || a.contains('pramod premi') || a.contains('nirhua') ||
        a.contains('samar singh') || a.contains('ritesh pandey') || a.contains('ankush raja') ||
        a.contains('gunjan singh') || a.contains('amrapali') || a.contains('akshara singh')) return 'bhojpuri';
    if ((_genreSimilarArtists['english'] ?? const []).any((art) => _mentionsArtist(a, art))) {
      return 'english';
    }
    return 'hindi';
  }

  static SessionMood _detectMoodEnum(Song song) {
    final text = '${song.title} ${song.artist}'.toLowerCase();
    if (text.contains('sad') || text.contains('dard') || text.contains('rona') ||
        text.contains('toot') || text.contains('yaad') || text.contains('judai') ||
        text.contains('bewafa') || text.contains('akela') || text.contains('alvida') ||
        text.contains('broken') || text.contains('heartbreak') || text.contains('bheegi') ||
        text.contains('aansu') || text.contains('tadap')) return SessionMood.sad;
    if (text.contains('pyar') || text.contains('love') || text.contains('ishq') ||
        text.contains('mohabbat') || text.contains('romantic') || text.contains('sajde') ||
        text.contains('teri') || text.contains('tere bina') || text.contains('humsafar') ||
        text.contains('sunn') || text.contains('kesariya') || text.contains('raataan') ||
        text.contains('dil') && !text.contains('dildaar')) return SessionMood.romantic;
    if (text.contains('party') || text.contains('dance') || text.contains('naach') ||
        text.contains('bajao') || text.contains('dj') || text.contains('balle') ||
        text.contains('garmi') || text.contains('hookah bar') || text.contains('lungi') ||
        text.contains('kamariya') || text.contains('lachke') || text.contains('hila') ||
        text.contains('nathuniya') || text.contains('saiya') && text.contains('dance') ||
        text.contains('tohar') || text.contains('ghaghra')) return SessionMood.party;
    if (text.contains('workout') || text.contains('gym') || text.contains('motivation') ||
        text.contains('power') || text.contains('beast') || text.contains('fire') ||
        text.contains('thunder')) return SessionMood.workout;
    if (text.contains('lofi') || text.contains('lo-fi') || text.contains('chill') ||
        text.contains('night') || text.contains('rain') || text.contains('coffee') ||
        text.contains('study') || text.contains('sleep')) return SessionMood.chill;
    if (text.contains('bhajan') || text.contains('aarti') || text.contains('mantra') ||
        text.contains('chalisa') || text.contains('kirtan')) return SessionMood.devotional;
    if (text.contains('energy') || text.contains('run') || text.contains('speed') ||
        text.contains('race') || text.contains('fighter')) return SessionMood.energetic;
    return SessionMood.neutral;
  }

  static SessionGenre _detectGenreEnum(Song song) {
    final g = detectGenre(song);
    switch (g) {
      case 'bollywood':  return SessionGenre.bollywood;
      case 'punjabi':    return SessionGenre.punjabi;
      case 'hiphop':     return SessionGenre.hiphop;
      case 'english':    return SessionGenre.english;
      case 'lofi':       return SessionGenre.lofi;
      case 'devotional': return SessionGenre.devotional;
      case 'bhojpuri':   return SessionGenre.bhojpuri;
      default:           return SessionGenre.other;
    }
  }

  static SessionLanguage _detectLanguageEnum(Song song) {
    final l = detectLanguage(song);
    switch (l) {
      case 'hindi':     return SessionLanguage.hindi;
      case 'punjabi':   return SessionLanguage.punjabi;
      case 'english':   return SessionLanguage.english;
      case 'tamil':     return SessionLanguage.tamil;
      case 'telugu':    return SessionLanguage.telugu;
      case 'bengali':   return SessionLanguage.bengali;
      case 'marathi':   return SessionLanguage.marathi;
      case 'gujarati':  return SessionLanguage.gujarati;
      case 'malayalam': return SessionLanguage.malayalam;
      default:          return SessionLanguage.other;
    }
  }

  static List<String> topAffinityArtists({int count = 5}) {
    if (!_loaded) return [];
    final sorted = _artistW.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .where((e) => e.value > 0.5)
        .take(count)
        .map((e) => _artistDisplayName[e.key] ?? e.key)
        .toList();
  }

  static List<String> get _starterArtists => UserRegion.starterArtists();

  static List<String> rotatingAffinityArtists({int count = 4, int? seed}) {
    var real = _rotatingAffinityArtistsReal(count: count, seed: seed);
    if (_loaded && _pinnedArtists.isNotEmpty && count > 0) {
      final have = real.map(_normalizeKey).toSet();
      final pinPool = _pinnedArtists
          .where((a) => (_artistW[_normalizeKey(a)] ?? 0.5) >= 0.5)
          .toList();
      if (pinPool.isNotEmpty) {
        final want = count >= 3 ? 2 : 1;
        final start = ((seed ?? 0).abs()) % pinPool.length;
        final picks = <String>[];
        for (var i = 0; i < pinPool.length && picks.length < want; i++) {
          final a = pinPool[(start + i) % pinPool.length];
          if (!have.contains(_normalizeKey(a))) picks.add(a);
        }
        if (picks.isNotEmpty) {
          final merged = <String>[
            if (real.isNotEmpty) real.first,
            ...picks,
            ...real.skip(1),
          ];
          real = merged.take(count).toList();
        }
      }
    }
    if (real.length >= count) return real;
    final have = real.map((e) => _normalizeKey(e)).toSet();
    final start = ((seed ?? 0).abs()) % _starterArtists.length;
    final out = List<String>.from(real);
    for (var i = 0; i < _starterArtists.length && out.length < count; i++) {
      final a = _starterArtists[(start + i) % _starterArtists.length];
      if (have.add(_normalizeKey(a))) out.add(a);
    }
    return out;
  }

  static List<String> _rotatingAffinityArtistsReal({int count = 4, int? seed}) {
    if (!_loaded) return [];
    final sorted = _artistW.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    var pool = sorted
        .where((e) => e.value > 0.52)
        .take(12)
        .map((e) => _artistDisplayName[e.key] ?? e.key)
        .toList();
    final recentNow = sessionRecentArtists
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .toList();
    if (recentNow.isNotEmpty) {
      final lowPool = pool.map((e) => _normalizeKey(e)).toSet();
      final front = <String>[];
      for (final a in recentNow) {
        final k = _normalizeKey(a);
        if (k.isEmpty) continue;
        if ((_artistW[k] ?? 0.5) < 0.5) continue;
        if (front.any((f) => _normalizeKey(f) == k)) continue;
        front.add(_artistDisplayName[k] ?? a);
        lowPool.remove(k);
      }
      pool = [
        ...front.take(2),
        ...pool.where((e) => lowPool.contains(_normalizeKey(e))),
      ];
    }
    if (pool.length <= count && sorted.length > pool.length) {
      pool = sorted
          .where((e) => e.value != 0.5)
          .take(20)
          .map((e) => _artistDisplayName[e.key] ?? e.key)
          .toList();
    }
    if (pool.length <= count) return pool;
    final step = (seed ?? 0) % pool.length;
    final window = <String>[];
    for (var i = 0; i < count && i < pool.length; i++) {
      window.add(pool[(step + i) % pool.length]);
    }
    return window;
  }

  static List<String> topAffinityGenres({int count = 3}) {
    if (!_loaded) return [];
    final sorted = _genreW.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.where((e) => e.value > 0.5).take(count).map((e) => e.key).toList();
  }

  static List<String> rotatingAffinityGenres({int count = 3, int? seed}) {
    if (!_loaded) return [];
    final sorted = _genreW.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final pool = sorted.where((e) => e.value > 0.5).take(8).map((e) => e.key).toList();
    if (pool.length <= count) return pool;
    pool.shuffle(math.Random(seed));
    return pool.take(count).toList();
  }

  static List<String> topAffinityLanguages({int count = 2}) {
    if (!_loaded) return [];
    final sorted = _langW.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.where((e) => e.value > 0.5).take(count).map((e) => e.key).toList();
  }

  static List<String> topPlayedSongIds({int count = 20}) {
    if (!_loaded) return [];
    final sorted = _plays.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).map((e) => e.key).toList();
  }

  static List<String> topAlbumsByPlays({int count = 10}) {
    if (!_loaded) return [];
    final sorted = _albumPlays.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.where((e) => e.value > 0).take(count).map((e) => e.key).toList();
  }

  static List<String> topAffinityDecades({int count = 2}) {
    if (!_loaded) return [];
    final sorted = _decadeW.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.where((e) => e.value > 0.5).take(count).map((e) => e.key).toList();
  }

  static List<String> recentlyPlayedSongIds({
    int count = 15,
    Duration within = const Duration(hours: 48),
  }) {
    if (!_loaded) return [];
    final cutoff = DateTime.now().subtract(within).millisecondsSinceEpoch;
    final sorted = _lastPlayedAt.entries.where((e) => e.value >= cutoff).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).map((e) => e.key).toList();
  }

  static List<String> rediscoverCandidateIds({
    int count = 15,
    Duration olderThan = const Duration(days: 21),
  }) {
    if (!_loaded) return [];
    final cutoff = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
    final candidates = _plays.entries
        .where((e) => e.value >= 2 || (_completes[e.key] ?? 0) >= 1)
        .map((e) => e.key)
        .where((id) {
          final last = _lastPlayedAt[id];
          return last == null || last < cutoff;
        })
        .toList();
    candidates.sort((a, b) {
      final scoreA = (_plays[a] ?? 0) + 2 * (_completes[a] ?? 0);
      final scoreB = (_plays[b] ?? 0) + 2 * (_completes[b] ?? 0);
      return scoreB.compareTo(scoreA);
    });
    return candidates.take(count).toList();
  }

  static SessionMood? get currentMood => _session?.mood;

  static TimeSlot currentTimeSlot() {
    final hour = DateTime.now().hour;
    if (hour >= 5  && hour < 11) return TimeSlot.morning;
    if (hour >= 11 && hour < 17) return TimeSlot.afternoon;
    if (hour >= 17 && hour < 21) return TimeSlot.evening;
    if (hour >= 21 && hour < 24) return TimeSlot.night;
    return TimeSlot.lateNight;
  }

  static Set<String> get recentHomeShownIds => _homeShown.toSet();

  static const int _homeShownWindow = 2400;

  static Future<void> recordHomeShown(Iterable<String> ids) async {
    if (!_loaded) await load();
    _homeShown.addAll(ids);
    if (_homeShown.length > _homeShownWindow) {
      _homeShown = _homeShown.sublist(_homeShown.length - _homeShownWindow);
    }
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kHomeShown, _homeShown);
  }

  static Set<String> get heavilyPlayedIds {
    if (!_loaded) return {};
    return _plays.entries.where((e) => e.value >= 3).map((e) => e.key).toSet();
  }

  static Set<String> get sessionRecentIds =>
      _session?.recentIds.toSet() ?? {};

  static Set<String> get sessionRecentTitles =>
      _session?.recentTitles.toSet() ?? {};

  static List<String> get sessionRecentArtists =>
      _session?.recentArtists ?? [];

  static const Map<String, List<String>> _genreSimilarArtists = {
    'bollywood': [
      'arijit singh', 'atif aslam', 'armaan malik', 'jubin nautiyal',
      'sonu nigam', 'shaan', 'kk singer', 'mohit chauhan', 'vishal mishra',
      'darshan raval', 'stebin ben', 'yasser desai', 'ankit tiwari',
      'amaal mallik', 'javed ali', 'rahat fateh ali khan',
      'shreya ghoshal', 'neha kakkar', 'sunidhi chauhan', 'monali thakur',
      'palak muchhal', 'asees kaur', 'dhvani bhanushali', 'neeti mohan',
      'shilpa rao', 'jonita gandhi', 'kanika kapoor', 'akasa singh',
      'shashaa tirupati', 'nikhita gandhi',
      'lata mangeshkar', 'kishore kumar', 'mohd rafi', 'asha bhosle',
      'udit narayan', 'kumar sanu', 'alka yagnik', 'mukesh',
      'manna dey', 'hemant kumar', 'geeta dutt', 'mahendra kapoor',
      'a r rahman', 'pritam', 'vishal shekhar', 'shankar ehsaan loy',
      'anu malik', 'nadeem shravan', 'himesh reshammiya', 'amit trivedi',
      'sachin jigar', 'tanishk bagchi', 'vishal bhardwaj', 'ram sampath',
      'rd burman', 'laxmikant pyarelal',
    ],
    'english': [
      'the weeknd', 'ed sheeran', 'bruno mars', 'charlie puth',
      'post malone', 'dua lipa', 'taylor swift', 'ariana grande',
      'billie eilish', 'olivia rodrigo', 'shawn mendes', 'harry styles',
      'sam smith', 'adele', 'justin bieber', 'selena gomez',
      'rihanna', 'beyonce', 'lady gaga', 'katy perry', 'miley cyrus',
      'sia', 'khalid', 'zayn', 'niall horan', 'camila cabello',
      'doja cat', 'sza', 'the kid laroi', 'lewis capaldi',
      'coldplay', 'imagine dragons', 'onerepublic', 'maroon 5',
      'the chainsmokers', 'twenty one pilots', 'panic at the disco',
      'fall out boy', 'linkin park', 'the killers',
      'michael jackson', 'whitney houston', 'eminem', 'queen',
      'the beatles', 'elton john', 'celine dion', 'mariah carey',
      'george michael', 'phil collins', 'stevie wonder', 'abba',
    ],
    'punjabi': [
      'diljit dosanjh', 'ap dhillon', 'sidhu moosewala', 'guru randhawa',
      'badshah', 'hardy sandhu', 'b praak', 'jasleen royal',
      'parmish verma', 'ammy virk', 'karan aujla', 'shubh',
    ],
    'hiphop': [
      'divine', 'emiway bantai', 'kr\$na', 'mc stan', 'seedhe maut',
      'yo yo honey singh', 'badshah', 'raftar', 'naezy', 'ranveer',
    ],
    'lofi': [
      'lofi hip hop', 'chillhop music', 'lo-fi beats', 'study music',
      'calm music', 'sleep music', 'coffee shop music',
    ],
    'bhojpuri': [
      'pawan singh', 'khesari lal yadav', 'neelkamal singh', 'shilpi raj',
      'pramod premi yadav', 'ritesh pandey', 'samar singh', 'gunjan singh',
      'ankush raja', 'dinesh lal nirhua', 'arvind akela kallu',
      'awadhesh premi yadav', 'manoj tiwari', 'indu sonali',
    ],
    'devotional': [
      'lata mangeshkar bhajan', 'anuradha paudwal', 'narendra chanchal',
      'jagjit singh', 'gulshan kumar bhajan', 'shankar mahadevan bhajan',
    ],
    'tamil': [
      'ar rahman tamil', 'sid sriram', 'anirudh ravichander',
      'yuvan shankar raja', 'harris jayaraj', 'd imman',
    ],
    'telugu': [
      'dsp telugu', 'thaman s', 'ss thaman', 'mickey j meyer', 'anirudh telugu',
    ],
  };

  static Future<void> applyDecay() async {
    if (!_loaded) await load();
    double toNeutral(double v) =>
        (0.5 + (v - 0.5) * _decayFactor).clamp(0.0, 1.0);
    _artistW.updateAll((_, v) => toNeutral(v));
    _genreW.updateAll((_, v)  => toNeutral(v));
    _langW.updateAll((_, v)   => toNeutral(v));
    for (final a in _pinnedArtists) {
      final k = _normalizeKey(a);
      if (k.isEmpty) continue;
      if ((_artistW[k] ?? 0.5) < 0.75) _artistW[k] = 0.75;
    }
    final pinnedKeys = _pinnedArtists.map(_normalizeKey).toSet();
    _artistW.removeWhere(
        (k, v) => (v - 0.5).abs() < 0.02 && !pinnedKeys.contains(k));
    await _saveAll();
  }

  static Future<void> _saveAll() async {
    _pruneTrackedSongs();
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setString(_kPlays,     jsonEncode(_plays)),
      p.setString(_kCompletes, jsonEncode(_completes)),
      p.setString(_kSkips,     jsonEncode(_skips)),
      p.setString(_kReplays,   jsonEncode(_replays)),
      p.setString(_kArtistW,   jsonEncode(_artistW)),
      p.setString(_kArtistDisplayName, jsonEncode(_artistDisplayName)),
      p.setStringList(_kPinnedArtists, _pinnedArtists),
      p.setString(_kGenreW,    jsonEncode(_genreW)),
      p.setString(_kLangW,     jsonEncode(_langW)),
      p.setString(_kAlbumPlays, jsonEncode(_albumPlays)),
      p.setString(_kDecadeW,    jsonEncode(_decadeW)),
      p.setString(_kLastPlayed, jsonEncode(_lastPlayedAt)),
      if (_session != null)
        p.setString(_kSession, jsonEncode(_session!.toJson())),
    ]);
  }

  static String _normalizeKey(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
}

class _ScoredSong {
  final Song   song;
  final double score;
  _ScoredSong(this.song, this.score);
}

class AutoQueueQuery {
  final String query;
  final int    weight;
  AutoQueueQuery(this.query, {this.weight = 1});
}
