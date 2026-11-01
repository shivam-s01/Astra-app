// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import '../models/song.dart';

class StreamQualityStore extends ChangeNotifier {
  StreamQualityStore._();
  static final StreamQualityStore instance = StreamQualityStore._();

  String? codecFor(Song song) {
    if (song.isLocal) return _codecForPath(song.localPath);
    switch (song.source) {
      case SongSource.saavn:
        return 'AAC';
      case SongSource.youtube:
        return 'OPUS';
      case SongSource.local:
        return _codecForPath(song.localPath);
    }
  }

  bool showFallback(Song song) => codecFor(song) == null;

  static String? _codecForPath(String? path) {
    if (path == null) return null;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    switch (path.substring(dot + 1).toLowerCase()) {
      case 'opus':
        return 'OPUS';
      case 'm4a':
      case 'aac':
        return 'AAC';
      case 'mp3':
        return 'MP3';
      default:
        return null;
    }
  }
}
