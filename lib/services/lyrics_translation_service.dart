// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TranslationLang {
  final String code;
  final String name;
  final String native;
  const TranslationLang(this.code, this.name, this.native);
}

// NOTE: these are *scripts*, not meaning-translations.
//  'en' → Hinglish (Hindi written in English letters: pyaar stays pyaar)
//  'hi' → Hindi in Devanagari
const List<TranslationLang> kTranslationLanguages = [
  TranslationLang('en', 'English letters · pyaar, tum', 'Hinglish'),
  TranslationLang('hi', 'Hindi script · प्यार, तुम', 'हिन्दी'),
];

TranslationLang? translationLangFor(String? code) {
  if (code == null) return null;
  for (final l in kTranslationLanguages) {
    if (l.code == code) return l;
  }
  return null;
}

enum TranslationDisplay { both, translationOnly }

class LyricsTranslation {
  final String target;

  /// Aligned 1:1 with the source lines. Empty source line → empty string.
  final List<String> lines;

  final String? sourceLang;

  /// True when the lyrics were romanised (Hinglish etc.) and were converted
  /// to the native script before translating.
  final bool transliterated;

  /// True when the lyrics are already in the target language.
  final bool sameLanguage;

  const LyricsTranslation({
    required this.target,
    required this.lines,
    this.sourceLang,
    this.transliterated = false,
    this.sameLanguage = false,
  });

  Map<String, dynamic> toJson() => {
        't': target,
        'l': lines,
        's': sourceLang,
        'x': transliterated,
        'e': sameLanguage,
      };

  static LyricsTranslation? fromJson(Map<String, dynamic> j) {
    try {
      return LyricsTranslation(
        target: j['t'] as String,
        lines: (j['l'] as List).cast<String>(),
        sourceLang: j['s'] as String?,
        transliterated: j['x'] as bool? ?? false,
        sameLanguage: j['e'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persisted user choices (sticky across songs and app restarts).
class LyricsTranslatePrefs {
  LyricsTranslatePrefs._();

  static const _kTarget = 'lyr_tr_target';
  static const _kMode = 'lyr_tr_mode';

  /// null = translation off.
  static final ValueNotifier<String?> targetNotifier =
      ValueNotifier<String?>(null);
  static final ValueNotifier<TranslationDisplay> modeNotifier =
      ValueNotifier<TranslationDisplay>(TranslationDisplay.both);

  static bool _loaded = false;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= () async {
      try {
        final p = await SharedPreferences.getInstance();
        final t = p.getString(_kTarget);
        if (t != null && translationLangFor(t) != null) {
          targetNotifier.value = t;
        }
        final m = p.getInt(_kMode);
        if (m != null && m >= 0 && m < TranslationDisplay.values.length) {
          modeNotifier.value = TranslationDisplay.values[m];
        }
      } catch (_) {}
      _loaded = true;
    }();
  }

  static Future<void> setTarget(String? code) async {
    targetNotifier.value = code;
    try {
      final p = await SharedPreferences.getInstance();
      if (code == null) {
        await p.remove(_kTarget);
      } else {
        await p.setString(_kTarget, code);
      }
    } catch (_) {}
  }

  static Future<void> setMode(TranslationDisplay m) async {
    modeNotifier.value = m;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kMode, m.index);
    } catch (_) {}
  }
}

class LyricsTranslationService {
  LyricsTranslationService._();

  static const _cacheVersion = 'v3';
  static const _kDiskCache = 'lyr_tr_cache_v2';
  static const _kDiskOrder = 'lyr_tr_cache_order_v2';
  static const int _diskMax = 40;
  static const int _memMax = 60;

  static final Map<String, LyricsTranslation> _mem = {};
  static final Map<String, Future<LyricsTranslation?>> _inflight = {};

  // Failure memory (this app session only). A song that could not be
  // converted is never retried, and after two failures in a row the network
  // is left alone for a while, so a bad connection costs nothing.
  static final Set<String> _failedKeys = {};
  static int _failStreak = 0;
  static DateTime? _cooldownUntil;
  static const Duration _cooldown = Duration(minutes: 3);

  static bool get coolingDown =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  /// Lyrics count as "already in English letters" only when practically no
  /// other script is left (a few Devanagari lines still get converted).
  static const double _romanSame = 0.985;

  static const Map<String, String> _hintToIndic = {
    'hindi': 'hi',
    'punjabi': 'pa',
    'urdu': 'ur',
    'bengali': 'bn',
    'bangla': 'bn',
    'marathi': 'mr',
    'gujarati': 'gu',
    'tamil': 'ta',
    'telugu': 'te',
    'kannada': 'kn',
    'malayalam': 'ml',
    'haryanvi': 'hi',
    'bhojpuri': 'hi',
    'rajasthani': 'hi',
  };

  static const Set<String> _indicCodes = {
    'hi', 'pa', 'ur', 'bn', 'mr', 'gu', 'ta', 'te', 'kn', 'ml', 'ne',
  };

  // Common romanised Hindi / Punjabi / Urdu words (Hinglish detector).
  static const Set<String> _romanIndicWords = {
    'hai', 'hain', 'tu', 'tum', 'tumhe', 'tumhari', 'tera', 'teri', 'tere',
    'mera', 'meri', 'mere', 'mujhe', 'mujh', 'main', 'mein', 'hum', 'humein',
    'aur', 'bhi', 'woh', 'wo', 'yeh', 'ye', 'jo', 'kya', 'kyun', 'kyu', 'nahi',
    'nahin', 'na', 'ko', 'se', 'ke', 'ki', 'ka', 'ho', 'hoon', 'hu', 'tha',
    'thi', 'the', 'raha', 'rahi', 'rahe', 'kar', 'karna', 'kiya', 'karo',
    'dil', 'ishq', 'pyar', 'pyaar', 'mohabbat', 'zindagi', 'duniya', 'jaan',
    'saath', 'sath', 'yaar', 'yaad', 'khwab', 'khuda', 'rab', 'raat', 'din',
    'aaj', 'kal', 'abhi', 'phir', 'bas', 'sirf', 'mat', 'ab', 'jab', 'tab',
    'koi', 'kuch', 'sab', 'apna', 'apni', 'apne', 'sang', 'bin', 'bina',
    'chal', 'chala', 'aa', 'aaja', 'ja', 'jaa', 'de', 'diya', 'le', 'liya',
    'bol', 'bolo', 'sun', 'suno', 'dekh', 'dekho', 'ek', 'do', 'teen',
    'nu', 'di', 'da', 'ne', 'oye', 'kithe', 'kitna', 'kaun', 'kab', 'kahan',
    'sanam', 'sajna', 'mahi', 've', 'vi', 'hor', 'menu', 'tenu', 'assi',
    'tussi', 'kudi', 'munda', 'balle', 'jee', 'ji', 'wala', 'wali', 'lagda',
    'lagta', 'lagti', 'bhula', 'bhoola', 'tujhe', 'tujh', 'tujhse', 'tumse',
    'humse', 'hamesha', 'kabhi', 'sabse', 'pehle', 'baad', 'liye', 'wajah',
  };

  static const Set<String> _englishWords = {
    'the', 'and', 'you', 'i', 'to', 'a', 'my', 'me', 'it', 'in', 'of', 'is',
    'that', 'on', 'for', 'with', 'your', 'this', 'be', 'just', 'but', 'so',
    'we', 'like', 'all', 'know', 'baby', 'love', 'oh', 'yeah', 'got', 'dont',
    "don't", "i'm", "it's", 'im', 'are', 'was', 'can', 'what', 'when', 'up',
  };

  // ───────────────────────── public API ─────────────────────────

  static LyricsTranslation? peek(String cacheKey, String target) =>
      _mem['$cacheKey|$target|$_cacheVersion'];

  /// Synchronous shortcut: Hinglish ('en') never changes lyrics that are
  /// already in English letters, so those can be shown instantly with no
  /// network and no waiting.
  static bool isAlreadyRoman(List<String> lines) {
    final text = lines.map((l) => l.trim()).where((l) => l.isNotEmpty).join(' ');
    return text.isNotEmpty && _latinRatio(text) > _romanSame;
  }

  /// Translates [lines] (empty lines allowed and preserved). Returns null on
  /// failure. Never throws.
  static Future<LyricsTranslation?> translate({
    required String cacheKey,
    required List<String> lines,
    required String target,
    String? songLanguageHint,
  }) {
    final key = '$cacheKey|$target|$_cacheVersion';
    final hit = _mem[key];
    if (hit != null && hit.lines.length == lines.length) {
      return Future.value(hit);
    }
    return _inflight[key] ??= () async {
      try {
        final disk = await _readDisk(key);
        if (disk != null && disk.lines.length == lines.length) {
          _remember(key, disk);
          return disk;
        }
        if (_failedKeys.contains(key) || coolingDown) return null;
        final r = await _run(lines, target, songLanguageHint);
        if (r != null) {
          _failStreak = 0;
          _remember(key, r);
          unawaited(_writeDisk(key, r));
        } else {
          _failedKeys.add(key);
          if (++_failStreak >= 2) {
            _cooldownUntil = DateTime.now().add(_cooldown);
          }
        }
        return r;
      } catch (e) {
        if (kDebugMode) debugPrint('[lyrics-translate] failed: $e');
        return null;
      } finally {
        _inflight.remove(key);
      }
    }();
  }

  // ───────────────────────── pipeline ─────────────────────────

  static Future<LyricsTranslation?> _run(
      List<String> lines, String target, String? hint) async {
    final idx = <int>[];
    final src = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.isNotEmpty) {
        idx.add(i);
        src.add(t);
      }
    }
    if (src.isEmpty) return null;

    final isLatin = _latinRatio(src.join(' ')) > 0.85;
    final same = LyricsTranslation(
      target: target,
      lines: List<String>.of(lines),
      sameLanguage: true,
    );

    List<String>? converted;
    var transliterated = true;
    String? sourceLang;

    if (target == 'en') {
      // Hinglish: only change the SCRIPT, never the meaning.
      if (_latinRatio(src.join(' ')) > _romanSame) return same;
      converted = await _romanise(src);
      sourceLang = 'hi';
    } else {
      if (isLatin) {
        final indic = _romanIndicLang(src, hint);
        if (indic != null) {
          // Hinglish → Devanagari, word meaning untouched.
          converted = await _transliterate(src, 'hi');
          sourceLang = indic;
        } else {
          // Genuine English lyrics → Hindi meaning.
          final res = await _translateAll(src, 'hi', null);
          converted = res?.lines;
          transliterated = false;
          sourceLang = res?.detected ?? 'en';
        }
      } else {
        final dev = _devanagariRatio(src.join(' '));
        if (dev > 0.7) return same;
        final res = await _translateAll(src, 'hi', null);
        converted = res?.lines;
        transliterated = false;
        sourceLang = res?.detected;
      }
    }
    if (converted == null) return null;

    // Identical source lines (chorus) share one result.
    final firstFor = <String, String>{};
    final out = List<String>.filled(lines.length, '');
    for (var k = 0; k < idx.length; k++) {
      final norm = src[k]
          .toLowerCase()
          .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
          .trim();
      var tr = converted[k].trim();
      if (norm.isNotEmpty) tr = firstFor.putIfAbsent(norm, () => tr);
      out[idx[k]] = tr;
    }

    return LyricsTranslation(
      target: target,
      lines: out,
      sourceLang: sourceLang,
      transliterated: transliterated,
    );
  }

  static double _devanagariRatio(String s) {
    var dev = 0, letters = 0;
    for (final r in s.runes) {
      if (r >= 0x0900 && r <= 0x097F) {
        dev++;
        letters++;
      } else if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || r > 0x2FF) {
        letters++;
      }
    }
    return letters == 0 ? 0 : dev / letters;
  }

  /// Devanagari / other Indic script → English letters, line by line, using
  /// Google's own source-transliteration (so "प्यार" → "pyaar", not "love").
  static Future<List<String>?> _romanise(List<String> lines) async {
    var okCount = 0, badCount = 0;
    final out = await _pool<String?>(lines.length, 6, (i) async {
      final l = lines[i];
      if (_latinRatio(l) > 0.85) return l;
      // Nothing has worked after several tries: stop hammering the network.
      if (badCount >= 4 && okCount == 0) return null;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final uri = Uri.parse(
              'https://translate.googleapis.com/translate_a/single'
              '?client=gtx&sl=auto&tl=en&dt=t&dt=rm');
          final r = await http
              .post(uri, body: {'q': l})
              .timeout(const Duration(seconds: 10));
          if (r.statusCode != 200) {
            await Future.delayed(const Duration(milliseconds: 300));
            continue;
          }
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          final parts = <String>[];
          for (final seg in (j[0] as List)) {
            if (seg is List && seg.length >= 4 && seg[3] is String) {
              final t = (seg[3] as String).trim();
              if (t.isNotEmpty) parts.add(t);
            }
          }
          if (parts.isEmpty) continue;
          okCount++;
          return _tidyRoman(parts.join(' '));
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }
      badCount++;
      return null;
    });
    final ok = out.where((e) => e != null).length;
    if (ok < (lines.length * 0.7)) return null;
    return [for (var i = 0; i < lines.length; i++) out[i] ?? lines[i]];
  }

  static String _tidyRoman(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }

  // ───────────────────── romanised-Indic detection ─────────────────────

  static double _latinRatio(String s) {
    var latin = 0, letters = 0;
    for (final r in s.runes) {
      final isLatin = (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) ||
          (r >= 0xC0 && r <= 0x24F);
      if (isLatin) {
        latin++;
        letters++;
      } else if (r > 0x2FF) {
        letters++;
      }
    }
    return letters == 0 ? 0 : latin / letters;
  }

  static String? _romanIndicLang(List<String> lines, String? hint) {
    final text = lines.join(' ');
    if (_latinRatio(text) < 0.85) return null;
    final toks = text
        .toLowerCase()
        .split(RegExp(r"[^a-z']+"))
        .where((w) => w.isNotEmpty)
        .toList();
    if (toks.length < 4) return null;
    var indicHits = 0, enHits = 0;
    for (final w in toks) {
      if (_romanIndicWords.contains(w)) indicHits++;
      if (_englishWords.contains(w)) enHits++;
    }
    final indicScore = indicHits / toks.length;
    final enScore = enHits / toks.length;

    final h = (hint ?? '').toLowerCase().trim();
    final hinted = _hintToIndic[h];
    if (hinted != null) {
      // Trust the hint unless the text clearly is English.
      if (enScore > 0.28 && indicScore < 0.05) return null;
      return hinted;
    }
    if (h == 'english') return null;
    if (indicScore >= 0.14 && indicScore > enScore * 0.7) return 'hi';
    return null;
  }

  // ───────────────────────── transliteration ─────────────────────────

  static Future<List<String>?> _transliterate(
      List<String> lines, String lang) async {
    final out = await _pool<String?>(lines.length, 6, (i) async {
      if (_latinRatio(lines[i]) < 0.5) return lines[i];
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final uri = Uri.https('inputtools.google.com', '/request', {
            'text': lines[i],
            'itc': '$lang-t-i0-und',
            'num': '1',
            'cp': '0',
            'cs': '1',
            'ie': 'utf-8',
            'oe': 'utf-8',
            'app': 'demopage',
          });
          final r = await http.get(uri).timeout(const Duration(seconds: 8));
          if (r.statusCode != 200) continue;
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          if (j is List && j.isNotEmpty && j[0] == 'SUCCESS') {
            final cand = j[1][0][1][0] as String;
            if (cand.trim().isNotEmpty) return cand.trim();
          }
        } catch (_) {}
      }
      return null;
    });
    final ok = out.where((e) => e != null).length;
    if (ok < (lines.length * 0.7)) return null;
    return [for (var i = 0; i < lines.length; i++) out[i] ?? lines[i]];
  }

  // ───────────────────────── translation ─────────────────────────

  static Future<_Translated?> _translateAll(
      List<String> lines, String target, String? forcedSource) async {
    final chunks = <List<int>>[];
    var cur = <int>[];
    var len = 0;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].length + 1;
      if (cur.isNotEmpty && len + l > 3200) {
        chunks.add(cur);
        cur = <int>[];
        len = 0;
      }
      cur.add(i);
      len += l;
    }
    if (cur.isNotEmpty) chunks.add(cur);

    final out = List<String>.filled(lines.length, '');
    String? detected = forcedSource;
    var failed = 0;

    final results = await _pool<_Translated?>(chunks.length, 3, (c) async {
      final ids = chunks[c];
      final part = [for (final i in ids) lines[i]];
      return _translateBlock(part, target, forcedSource);
    });

    for (var c = 0; c < chunks.length; c++) {
      final r = results[c];
      if (r == null) {
        failed++;
        continue;
      }
      detected ??= r.detected;
      for (var k = 0; k < chunks[c].length; k++) {
        out[chunks[c][k]] = r.lines[k];
      }
    }
    if (failed == chunks.length) return null;
    if (failed > 0) {
      // Fill gaps with the source text so alignment is never broken.
      for (var c = 0; c < chunks.length; c++) {
        if (results[c] == null) {
          for (final i in chunks[c]) {
            out[i] = lines[i];
          }
        }
      }
    }
    return _Translated(out, detected);
  }

  static Future<_Translated?> _translateBlock(
      List<String> part, String target, String? forcedSource) async {
    final joined = part.join('\n');
    final whole = await _gtx(joined, target, forcedSource);
    if (whole != null) {
      final split = whole.text.split('\n');
      if (split.length == part.length) {
        return _Translated(split.map((s) => s.trim()).toList(), whole.detected);
      }
    }
    // Line count drifted → translate line by line (keeps alignment exact).
    String? detected = whole?.detected ?? forcedSource;
    final per = await _pool<String?>(part.length, 5, (i) async {
      final r = await _gtx(part[i], target, forcedSource ?? detected) ??
          await _fallbackLine(part[i], target, forcedSource ?? detected);
      return r?.text.replaceAll('\n', ' ').trim();
    });
    if (per.every((e) => e == null)) return null;
    return _Translated(
        [for (var i = 0; i < part.length; i++) per[i] ?? part[i]], detected);
  }

  static Future<_Gtx?> _gtx(String text, String target, String? source) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
          'client': 'gtx',
          'sl': source ?? 'auto',
          'tl': target,
          'dt': 't',
        });
        final r = await http
            .post(uri, body: {'q': text})
            .timeout(const Duration(seconds: 14));
        if (r.statusCode != 200) {
          await Future.delayed(const Duration(milliseconds: 350));
          continue;
        }
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final segs = j[0] as List;
        final sb = StringBuffer();
        for (final s in segs) {
          if (s is List && s.isNotEmpty && s[0] is String) sb.write(s[0]);
        }
        final det = (j.length > 2 && j[2] is String) ? j[2] as String : null;
        final t = sb.toString();
        if (t.trim().isEmpty) return null;
        return _Gtx(t, det);
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 350));
      }
    }
    return null;
  }

  static Future<_Gtx?> _fallbackLine(
      String text, String target, String? source) async {
    try {
      final uri = Uri.https('clients5.google.com', '/translate_a/t', {
        'client': 'dict-chrome-ex',
        'sl': source ?? 'auto',
        'tl': target,
        'q': text,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is List && j.isNotEmpty) {
        final first = j[0];
        if (first is List && first.isNotEmpty && first[0] is String) {
          return _Gtx(first[0] as String, first.length > 1 ? first[1] as String? : null);
        }
        if (first is String) return _Gtx(first, null);
      }
    } catch (_) {}
    return null;
  }

  // ───────────────────────── helpers ─────────────────────────

  static Future<List<T>> _pool<T>(
      int n, int concurrency, Future<T> Function(int) job) async {
    final res = List<T?>.filled(n, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= n) return;
        res[i] = await job(i);
      }
    }

    final workers = n == 0 ? 1 : (concurrency < n ? concurrency : n);
    await Future.wait(List.generate(workers, (_) => worker()));
    return res.cast<T>();
  }

  static void _remember(String key, LyricsTranslation v) {
    if (_mem.length >= _memMax) _mem.remove(_mem.keys.first);
    _mem[key] = v;
  }

  static Future<LyricsTranslation?> _readDisk(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kDiskCache);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final e = m[key];
      if (e is Map<String, dynamic>) return LyricsTranslation.fromJson(e);
    } catch (_) {}
    return null;
  }

  static Future<void> _writeDisk(String key, LyricsTranslation v) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kDiskCache);
      final m = raw == null
          ? <String, dynamic>{}
          : (jsonDecode(raw) as Map<String, dynamic>);
      final order = List<String>.from(p.getStringList(_kDiskOrder) ?? const []);
      order.remove(key);
      order.add(key);
      m[key] = v.toJson();
      while (order.length > _diskMax) {
        m.remove(order.removeAt(0));
      }
      await p.setString(_kDiskCache, jsonEncode(m));
      await p.setStringList(_kDiskOrder, order);
    } catch (_) {}
  }
}

class _Gtx {
  final String text;
  final String? detected;
  const _Gtx(this.text, this.detected);
}

class _Translated {
  final List<String> lines;
  final String? detected;
  const _Translated(this.lines, this.detected);
}
