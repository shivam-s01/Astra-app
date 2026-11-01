// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';

class YtRelatedVideo {
  final String videoId;
  final String title;
  final String uploaderName;
  final int durationSecs;
  final int? viewCount;

  const YtRelatedVideo({
    required this.videoId,
    required this.title,
    required this.uploaderName,
    required this.durationSecs,
    this.viewCount,
  });
}

class NativeRelatedVideos {
  static const MethodChannel _channel = MethodChannel('com.aurum.music/related_videos');

  static Future<List<YtRelatedVideo>> getRelated(String videoId) async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        'getRelated',
        {'videoId': videoId},
      ).timeout(const Duration(seconds: 8), onTimeout: () => <Object?>[]);
      if (result == null) return [];
      return result
          .whereType<Map<Object?, Object?>>()
          .map((m) {
            final rawViews = (m['viewCount'] as num?)?.toInt();
            return YtRelatedVideo(
              videoId: m['videoId'] as String? ?? '',
              title: m['title'] as String? ?? '',
              uploaderName: m['uploaderName'] as String? ?? '',
              durationSecs: (m['durationSecs'] as num?)?.toInt() ?? 0,
              viewCount: (rawViews != null && rawViews >= 0) ? rawViews : null,
            );
          })
          .where((v) => v.videoId.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
