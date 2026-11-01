// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

class LyricLine {
  final Duration time;
  final String text;

  const LyricLine({required this.time, required this.text});
}

class LyricsResult {
  final List<LyricLine>? synced;

  final String? plain;

  const LyricsResult({this.synced, this.plain});

  bool get hasSynced => synced != null && synced!.isNotEmpty;
  bool get hasAny => hasSynced || (plain != null && plain!.trim().isNotEmpty);

  static const Duration kHighlightLead = Duration(milliseconds: 250);

  int activeIndexFor(Duration position) {
    if (!hasSynced) return -1;
    position += kHighlightLead;
    int lo = 0, hi = synced!.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (synced![mid].time <= position) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  static List<LyricLine> parseLrc(String lrc) {
    final tagPattern = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\]');
    final lines = <LyricLine>[];
    final offMatch =
        RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false)
            .firstMatch(lrc);
    final offsetMs = int.tryParse(offMatch?.group(1) ?? '') ?? 0;
    for (final rawLine in lrc.split('\n')) {
      final matches = tagPattern.allMatches(rawLine).toList();
      if (matches.isEmpty) continue;
      final text = rawLine.replaceAll(tagPattern, '').trim();
      for (final m in matches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        final fracStr = m.group(3) ?? '0';
        final millis = int.parse(fracStr.padRight(3, '0').substring(0, 3));
        final ms = (minutes * 60 + seconds) * 1000 + millis - offsetMs;
        lines.add(LyricLine(
          time: Duration(milliseconds: ms < 0 ? 0 : ms),
          text: text,
        ));
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }
}
