// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'song.dart';

enum DownloadStatus { queued, downloading, paused, completed, failed, cancelled }

class DownloadItem {
  final Song song;
  final DownloadStatus status;
  final double progress;
  final String? localPath;
  final int? fileSizeBytes;
  final DateTime addedAt;
  final String? resolvedUrl;
  final int bytesDownloaded;

  DownloadItem({
    required this.song,
    required this.status,
    this.progress = 0.0,
    this.localPath,
    this.fileSizeBytes,
    this.resolvedUrl,
    this.bytesDownloaded = 0,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  bool get isCompleted => status == DownloadStatus.completed;
  bool get isDownloading => status == DownloadStatus.downloading || status == DownloadStatus.queued;
  bool get isPaused => status == DownloadStatus.paused;
  bool get isFailed => status == DownloadStatus.failed;

  DownloadItem copyWith({
    DownloadStatus? status,
    double? progress,
    String? localPath,
    int? fileSizeBytes,
    String? resolvedUrl,
    int? bytesDownloaded,
  }) {
    return DownloadItem(
      song: song,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      localPath: localPath ?? this.localPath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      resolvedUrl: resolvedUrl ?? this.resolvedUrl,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'song': song.toJson(),
    'status': status.name,
    'progress': progress,
    'localPath': localPath,
    'fileSizeBytes': fileSizeBytes,
    'resolvedUrl': resolvedUrl,
    'bytesDownloaded': bytesDownloaded,
    'addedAt': addedAt.toIso8601String(),
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status']?.toString();
    final status = DownloadStatus.values.firstWhere(
      (s) => s.name == statusStr,
      orElse: () => DownloadStatus.failed,
    );
    return DownloadItem(
      song: Song.fromJson(Map<String, dynamic>.from(json['song'])),
      status: status,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      localPath: json['localPath'],
      fileSizeBytes: json['fileSizeBytes'],
      resolvedUrl: json['resolvedUrl'],
      bytesDownloaded: (json['bytesDownloaded'] as num?)?.toInt() ?? 0,
      addedAt: json['addedAt'] != null
          ? DateTime.tryParse(json['addedAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
