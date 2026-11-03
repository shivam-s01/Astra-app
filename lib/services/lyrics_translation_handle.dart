// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/lyrics.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import 'api_service.dart';
import 'lyrics_translation_service.dart';

/// One per lyrics surface (lyrics page, front strip, Spotify card …).
/// Follows the user's saved script choice, converts the given lyrics and
/// notifies listeners. The heavy work + caching lives in
/// [LyricsTranslationService], so several handles for the same song share
/// one network round-trip.
class LyricsTranslationHandle extends ChangeNotifier {
  LyricsTranslationHandle() {
    LyricsTranslatePrefs.targetNotifier.addListener(_onPrefs);
    LyricsTranslatePrefs.modeNotifier.addListener(_onMode);
    LyricsTranslatePrefs.ensureLoaded().then((_) {
      if (!_disposed) _run();
    });
  }

  Song? _song;
  LyricsResult? _result;
  LyricsTranslation? _tr;
  bool _loading = false;
  bool _failed = false;
  int _gen = 0;
  bool _disposed = false;
  bool _timedOut = false;
  Timer? _holdTimer;
  List<LyricLine>? _convertedSynced;

  /// How long a surface may hold its lyrics back while the conversion is
  /// still being fetched, so the original script never flashes first.
  static const Duration _holdMax = Duration(seconds: 5);

  /// The conversion to show, or null when off / not ready / already in the
  /// chosen script.
  LyricsTranslation? get active =>
      (_tr != null && !_tr!.sameLanguage) ? _tr : null;

  bool get loading => _loading;

  /// True while a conversion is wanted but not decided yet. Surfaces keep
  /// the lyrics hidden (spinner) during this window instead of showing the
  /// original and swapping a moment later. Never longer than [_holdMax].
  bool get pending =>
      target != null && _result != null && _tr == null && !_failed && !_timedOut;

  bool get failed => _failed;
  String? get target => LyricsTranslatePrefs.targetNotifier.value;
  TranslationDisplay get mode => LyricsTranslatePrefs.modeNotifier.value;
  bool get onlyConverted => mode == TranslationDisplay.translationOnly;

  /// Synced lines with the converted text swapped in (same timestamps).
  /// Identity-stable until the conversion changes.
  List<LyricLine>? convertedSynced(List<LyricLine> raw) {
    final tr = active;
    if (tr == null) return null;
    return _convertedSynced ??= [
      for (var i = 0; i < raw.length; i++)
        LyricLine(
          time: raw[i].time,
          text: (i < tr.lines.length && tr.lines[i].trim().isNotEmpty)
              ? tr.lines[i].trim()
              : raw[i].text,
        ),
    ];
  }

  /// Converted text for source line [i], or null.
  String? lineAt(int i) {
    final tr = active;
    if (tr == null || i < 0 || i >= tr.lines.length) return null;
    final t = tr.lines[i].trim();
    return t.isEmpty ? null : t;
  }

  /// Call whenever the song or its fetched lyrics change.
  void update({required Song? song, required LyricsResult? result}) {
    if (_disposed) return;
    if (identical(result, _result) && song?.id == _song?.id) return;
    final sameSong = song?.id == _song?.id;
    _song = song;
    _result = result;
    if (!sameSong && (_tr != null || _convertedSynced != null)) {
      _tr = null;
      _convertedSynced = null;
      notifyListeners();
    }
    _run();
  }

  void retry() {
    if (!_disposed) _run();
  }

  void _onPrefs() {
    if (!_disposed) _run();
  }

  void _onMode() {
    if (!_disposed) notifyListeners();
  }

  static List<String> sourceLines(LyricsResult r) {
    if (r.hasSynced) return [for (final l in r.synced!) l.text];
    return (r.plain ?? '').split('\n');
  }

  static String cacheKeyFor(Song song, LyricsResult r) =>
      '${song.id}|${r.hasSynced ? 's' : 'p'}';

  Future<void> _run() async {
    final gen = ++_gen;
    final tgt = target;
    final result = _result;
    final song = _song;
    _holdTimer?.cancel();
    _timedOut = false;

    if (tgt == null || result == null || song == null || !result.hasAny) {
      if (_tr != null || _loading || _failed) {
        _tr = null;
        _loading = false;
        _failed = false;
        _convertedSynced = null;
        notifyListeners();
      }
      return;
    }

    final src = sourceLines(result);
    final key = cacheKeyFor(song, result);

    // English-letter lyrics + Hinglish: nothing to convert, decide instantly.
    if (tgt == 'en' && LyricsTranslationService.isAlreadyRoman(src)) {
      _tr = LyricsTranslation(target: tgt, lines: src, sameLanguage: true);
      _loading = false;
      _failed = false;
      _convertedSynced = null;
      notifyListeners();
      return;
    }
    final cached = LyricsTranslationService.peek(key, tgt);
    if (cached != null && cached.lines.length == src.length) {
      _tr = cached;
      _loading = false;
      _failed = false;
      _convertedSynced = null;
      notifyListeners();
      return;
    }

    // A conversion in another script must not linger: surfaces hold their
    // lyrics (pending) until the chosen script is ready.
    if (_tr != null && _tr!.target != tgt) {
      _tr = null;
      _convertedSynced = null;
    }
    _loading = true;
    _failed = false;
    _holdTimer = Timer(_holdMax, () {
      if (_disposed || gen != _gen || !_loading) return;
      _timedOut = true;
      notifyListeners();
    });
    notifyListeners();

    final r = await LyricsTranslationService.translate(
      cacheKey: key,
      lines: src,
      target: tgt,
      songLanguageHint: song.language,
    );
    if (_disposed || gen != _gen) return;
    _holdTimer?.cancel();
    _loading = false;
    _tr = r;
    _failed = r == null;
    _convertedSynced = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _holdTimer?.cancel();
    LyricsTranslatePrefs.targetNotifier.removeListener(_onPrefs);
    LyricsTranslatePrefs.modeNotifier.removeListener(_onMode);
    super.dispose();
  }
}


/// App-wide warm-up. Runs while the app is open (not tied to any screen):
/// converts the current song's lyrics as soon as the song changes or the user
/// picks a script, so every lyrics surface finds the result already cached
/// and shows it on its very first frame.
class LyricsTranslationPrefetcher {
  LyricsTranslationPrefetcher._();

  static PlayerProvider? _player;
  static String? _lastSongId;
  static int _gen = 0;

  static void attach(PlayerProvider player) {
    if (identical(_player, player)) return;
    detach();
    _player = player;
    player.addListener(_onPlayer);
    LyricsTranslatePrefs.targetNotifier.addListener(_warm);
    LyricsTranslatePrefs.ensureLoaded().then((_) => _warm());
  }

  static void detach() {
    _player?.removeListener(_onPlayer);
    LyricsTranslatePrefs.targetNotifier.removeListener(_warm);
    _player = null;
    _lastSongId = null;
    _gen++;
  }

  static void _onPlayer() {
    final id = _player?.currentSong?.id;
    if (id == _lastSongId) return;
    _warm();
  }

  static Future<void> _warm() async {
    final song = _player?.currentSong;
    _lastSongId = song?.id;
    final target = LyricsTranslatePrefs.targetNotifier.value;
    final gen = ++_gen;
    if (song == null || target == null) return;
    await _warmSong(song, target, gen);
    // Then the next song in the queue, so skipping is instant too.
    final next = _nextSong(song);
    if (next != null && gen == _gen) await _warmSong(next, target, gen);
  }

  static Song? _nextSong(Song current) {
    final p = _player;
    if (p == null) return null;
    final q = p.queue;
    final i = p.currentIndex;
    if (i < 0 || i + 1 >= q.length || q[i].id != current.id) return null;
    return q[i + 1];
  }

  static Future<void> _warmSong(Song song, String target, int gen) async {
    try {
      final result = await ApiService.fetchSyncedLyrics(song);
      if (gen != _gen || !result.hasAny) return;
      final lines = LyricsTranslationHandle.sourceLines(result);
      if (target == 'en' && LyricsTranslationService.isAlreadyRoman(lines)) {
        return;
      }
      await LyricsTranslationService.translate(
        cacheKey: LyricsTranslationHandle.cacheKeyFor(song, result),
        lines: lines,
        target: target,
        songLanguageHint: song.language,
      );
    } catch (_) {}
  }
}
