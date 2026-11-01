// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:characters/characters.dart';

class DevanagariTransliterator {
  DevanagariTransliterator._();

  static const Map<String, String> _vowels = {
    'अ': 'a', 'आ': 'aa', 'इ': 'i', 'ई': 'ee', 'उ': 'u', 'ऊ': 'oo',
    'ऋ': 'ri', 'ए': 'e', 'ऐ': 'ai', 'ओ': 'o', 'औ': 'au',
    'ां': 'an', 'ऑ': 'o',
  };

  static const Map<String, String> _matras = {
    'ा': 'aa', 'ि': 'i', 'ी': 'ee', 'ु': 'u', 'ू': 'oo',
    'ृ': 'ri', 'े': 'e', 'ै': 'ai', 'ो': 'o', 'ौ': 'au',
    'ं': 'n', 'ँ': 'n', 'ः': 'h', '़': '',
  };

  static const Map<String, String> _consonants = {
    'क': 'k', 'ख': 'kh', 'ग': 'g', 'घ': 'gh', 'ङ': 'ng',
    'च': 'ch', 'छ': 'chh', 'ज': 'j', 'झ': 'jh', 'ञ': 'ny',
    'ट': 't', 'ठ': 'th', 'ड': 'd', 'ढ': 'dh', 'ण': 'n',
    'त': 't', 'थ': 'th', 'द': 'd', 'ध': 'dh', 'न': 'n',
    'प': 'p', 'फ': 'f', 'ब': 'b', 'भ': 'bh', 'म': 'm',
    'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 'sh',
    'ष': 'sh', 'स': 's', 'ह': 'h', 'क्ष': 'ksh', 'त्र': 'tr',
    'ज्ञ': 'gy', 'ड़': 'r', 'ढ़': 'rh',
  };

  static const String _virama = '्';
  static const Map<String, String> _digits = {
    '०': '0', '१': '1', '२': '2', '३': '3', '४': '4',
    '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
  };

  static bool containsDevanagari(String text) {
    for (final rune in text.runes) {
      if (rune >= 0x0900 && rune <= 0x097F) return true;
    }
    return false;
  }

  static String transliterate(String text) {
    if (text.isEmpty || !containsDevanagari(text)) return text;

    final buffer = StringBuffer();
    final chars = text.characters.toList();
    var i = 0;

    while (i < chars.length) {
      final ch = chars[i];

      String? multiMatch;
      for (final cluster in ['क्ष', 'त्र', 'ज्ञ']) {
        if (i + cluster.characters.length <= chars.length &&
            chars.sublist(i, i + cluster.characters.length).join() == cluster) {
          multiMatch = cluster;
          break;
        }
      }

      if (multiMatch != null) {
        buffer.write(_consonants[multiMatch]);
        i += multiMatch.characters.length;
        i = _handleFollowing(chars, i, buffer);
        continue;
      }

      if (_consonants.containsKey(ch)) {
        buffer.write(_consonants[ch]);
        i++;
        i = _handleFollowing(chars, i, buffer);
        continue;
      }

      if (_vowels.containsKey(ch)) {
        buffer.write(_vowels[ch]);
        i++;
        continue;
      }

      if (_digits.containsKey(ch)) {
        buffer.write(_digits[ch]);
        i++;
        continue;
      }

      if (ch == _virama) {
        i++;
        continue;
      }

      if (ch == '।' || ch == '॥') {
        buffer.write('.');
        i++;
        continue;
      }

      buffer.write(ch);
      i++;
    }

    return buffer.toString();
  }

  static int _handleFollowing(List<String> chars, int i, StringBuffer buffer) {
    if (i >= chars.length) {
      return i;
    }

    final next = chars[i];

    if (next == _virama) {
      return i + 1;
    }

    if (_matras.containsKey(next)) {
      buffer.write(_matras[next]);
      return i + 1;
    }

    buffer.write('a');
    return i;
  }
}
