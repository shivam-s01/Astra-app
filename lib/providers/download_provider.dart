// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/download_item.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';
import '../services/audio_prefs.dart';
import '../services/native_engine_bridge.dart';

class DownloadProvider extends ChangeNotifier {
  static const _boxName = 'aurum_downloads';

  static const _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

  static final Dio _downloadClient = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': _browserUserAgent,
        'Accept-Encoding': 'identity',
      },
    ),
  )..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient()
          ..maxConnectionsPerHost = 6
          ..autoUncompress = false;
        return client;
      },
    );

  final NativeAudioEngine _engine;
  DownloadProvider(this._engine);

  Box<Map>? _box;
  final Completer<Box<Map>> _boxReady = Completer<Box<Map>>();
  final Map<String, DownloadItem> _items = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Set<String> _pausedTokens = {};

  bool _initialized = false;

  final Set<String> _activePlaylistDownloads = {};

  bool isPlaylistDownloading(String playlistId) =>
      _activePlaylistDownloads.contains(playlistId);

  (int, int) playlistDownloadProgress(List<Song> songs) {
    final total = songs.length;
    final done = songs.where((s) => isDownloaded(s.id)).length;
    return (done, total);
  }

  Future<void> downloadPlaylist({
    required String playlistId,
    required List<Song> songs,
    int maxConcurrent = 4,
  }) async {
    if (songs.isEmpty) return;
    if (_activePlaylistDownloads.contains(playlistId)) return;

    _activePlaylistDownloads.add(playlistId);
    notifyListeners();

    try {
      final pending = songs.where((s) => !isDownloaded(s.id)).toList();
      if (pending.isEmpty) return;

      final queue = List<Song>.from(pending);
      final workerCount = pending.length < maxConcurrent
          ? pending.length
          : maxConcurrent;

      Future<void> worker() async {
        while (queue.isNotEmpty) {
          if (!_activePlaylistDownloads.contains(playlistId)) return;
          final song = queue.removeAt(0);
          try {
            await download(song);
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[Aurum] downloadPlaylist: ${song.id} failed: $e');
            }
          }
        }
      }

      await Future.wait(List.generate(workerCount, (_) => worker()));
    } finally {
      _activePlaylistDownloads.remove(playlistId);
      notifyListeners();
    }
  }

  void cancelPlaylistDownload(String playlistId, List<Song> songs) {
    _activePlaylistDownloads.remove(playlistId);
    for (final song in songs) {
      if (isDownloading(song.id)) cancelDownload(song.id);
    }
    notifyListeners();
  }

  List<DownloadItem> get items =>
      _items.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  List<DownloadItem> get completed =>
      items.where((d) => d.status == DownloadStatus.completed).toList();

  List<DownloadItem> get inProgress =>
      items.where((d) => d.isDownloading || d.isPaused).toList();

  List<DownloadItem> get failed =>
      items.where((d) => d.isFailed).toList();

  bool isDownloaded(String songId) =>
      _items[songId]?.status == DownloadStatus.completed;

  bool isDownloading(String songId) => _items[songId]?.isDownloading ?? false;

  bool isPaused(String songId) => _items[songId]?.isPaused ?? false;

  DownloadItem? statusOf(String songId) => _items[songId];

  Song? offlineSongFor(String songId) {
    final item = _items[songId];
    if (item != null && item.isCompleted && item.localPath != null) {
      return item.song.copyWith(localPath: item.localPath);
    }
    return null;
  }

  Future<void> init() async {
    if (_initialized) return;
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;
    _boxReady.complete(box);

    for (final raw in box.values) {
      try {
        final item = DownloadItem.fromJson(Map<String, dynamic>.from(raw));
        final fixed = item.status == DownloadStatus.downloading ||
                item.status == DownloadStatus.queued
            ? item.copyWith(status: DownloadStatus.failed)
            : item;
        _items[fixed.song.id] = fixed;
      } catch (_) {
      }
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> _persist(DownloadItem item) async {
    _items[item.song.id] = item;
    try {
      final box = _box ?? await _boxReady.future;
      await box.put(item.song.id, item.toJson());
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Aurum] DownloadProvider: failed to persist ${item.song.id}: $e');
      }
    }
    notifyListeners();
  }

  int get _activeDownloadCount => _cancelTokens.length;

  Future<void> _notifyProgress({
    required String songId,
    required String title,
    required int percent,
  }) async {
    final active = _activeDownloadCount;
    if (NotificationService.instance.shouldUseBatchNotification(active)) {
      await NotificationService.instance.cancelProgress(songId);
      final completed = _items.values
          .where((d) => d.status == DownloadStatus.completed)
          .length;
      await NotificationService.instance.showBatchProgress(
        completed: completed,
        total: completed + active,
      );
    } else {
      await NotificationService.instance.showProgress(
        songId: songId,
        title: title,
        percent: percent,
      );
    }
  }

  Future<Directory> _downloadsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _safeFileName(Song song) {
    final safe = '${song.title}_${song.artist}'
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return '${safe.isEmpty ? song.id : safe}.mp3';
  }

  Future<bool> download(Song song) async {
    if (isDownloaded(song.id) || isDownloading(song.id)) return true;
    if (song.isLocal) return false;
    AnalyticsService.instance.logDownload(song);
    return _runDownload(song);
  }

  Future<bool> resumeDownload(Song song) async {
    final item = _items[song.id];
    if (item == null || !item.isPaused) return download(song);

    final dir = await _downloadsDir();
    final filePath = '${dir.path}/${_safeFileName(song)}';
    final tempFile = File('$filePath.part');
    final hasPartialFile =
        await tempFile.exists() && item.bytesDownloaded > 0;

    return _runDownload(
      song,
      resumeFromBytes: hasPartialFile ? item.bytesDownloaded : 0,
      knownUrl: item.resolvedUrl,
    );
  }

  Future<void> pauseDownload(String songId) async {
    final item = _items[songId];
    if (item == null || !item.isDownloading) return;
    final token = _cancelTokens[songId];
    if (token == null) return;
    _pausedTokens.add(songId);
    token.cancel('paused');
  }

  Future<bool> _runDownload(
    Song song, {
    int resumeFromBytes = 0,
    String? knownUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final wifiOnly = prefs.getBool('download_wifi_only') ?? true;
    if (wifiOnly) {
      final result = await Connectivity().checkConnectivity();
      final onWifi = result.contains(ConnectivityResult.wifi);
      if (!onWifi) return false;
    }

    final rawQuality = prefs.getString('download_quality') ?? '320kbps';
    final List<String> qualityOrder;
    switch (rawQuality) {
      case '160kbps':
        qualityOrder = const ['160kbps', '320kbps'];
        break;
      case '320kbps':
      default:
        qualityOrder = const ['320kbps', '160kbps'];
    }

    await _persist(DownloadItem(
      song: song,
      status: DownloadStatus.queued,
      progress: resumeFromBytes > 0
          ? (_items[song.id]?.progress ?? 0.0)
          : 0.0,
      resolvedUrl: knownUrl,
      bytesDownloaded: resumeFromBytes,
    ));
    try {
      await _notifyProgress(
        songId: song.id,
        title: song.title,
        percent: (resumeFromBytes > 0
                ? ((_items[song.id]?.progress ?? 0.0) * 100)
                : 0)
            .round(),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Aurum] DownloadProvider: initial showProgress failed for ${song.id} (continuing anyway): $e');
      }
    }

    String? url = knownUrl ?? (song.source == SongSource.saavn ? null : song.streamUrl);
    if (url == null || url.isEmpty || !url.startsWith('http')) {
      try {
        if (song.source == SongSource.youtube) {
          for (var attempt = 0; attempt < 3 && url == null; attempt++) {
            if (attempt > 0) {
              await Future.delayed(Duration(milliseconds: 800 * attempt));
            }
            url = await _engine.resolveForDownload(song);
          }
        }
        for (var attempt = 0; attempt < 2 && (url == null || url.isEmpty); attempt++) {
          if (attempt > 0) {
            await Future.delayed(const Duration(milliseconds: 1000));
          }
          url = await ApiService.resolveDownloadUrl(song, qualityOrder: qualityOrder);
        }
      } catch (_) {
        url = null;
      }

      if (song.source == SongSource.saavn &&
          url != null &&
          AudioPrefs.lastResolvedKbps != null &&
          AudioPrefs.lastResolvedKbps! < 160) {
        url = null;
      }
    }

    if (url == null || url.isEmpty) {
      await _persist(_items[song.id]!.copyWith(status: DownloadStatus.failed));
      try {
        await NotificationService.instance.showFailed(
          songId: song.id,
          title: song.title,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Aurum] DownloadProvider: showFailed notification failed for ${song.id}: $e');
        }
      }
      return false;
    }

    final cancelToken = CancelToken();
    _cancelTokens[song.id] = cancelToken;

    String? tempPath;

    try {
      final dir = await _downloadsDir();
      final filePath = '${dir.path}/${_safeFileName(song)}';
      tempPath = '$filePath.part';

      await _persist(
        _items[song.id]!.copyWith(
          status: DownloadStatus.downloading,
          resolvedUrl: url,
        ),
      );

      int lastNotifiedPercent = -1;
      final isResume = resumeFromBytes > 0;
      final tempFile = File(tempPath);
      final finalFile = File(filePath);

      if (isResume) {
        final response = await _downloadClient.get<ResponseBody>(
          url,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(seconds: 60),
            headers: {
              'Range': 'bytes=$resumeFromBytes-',
              if (song.source == SongSource.youtube)
                'Referer': 'https://www.youtube.com/',
            },
          ),
        );

        final isPartialContent = response.statusCode == 206;
        final sink = await tempFile.open(
          mode: isPartialContent ? FileMode.append : FileMode.write,
        );
        var received = isPartialContent ? resumeFromBytes : 0;
        final contentLength = response.data?.contentLength ?? -1;
        final total = isPartialContent && contentLength > 0
            ? resumeFromBytes + contentLength
            : contentLength;

        try {
          int lastPersistedBytes = resumeFromBytes;
          await for (final chunk in response.data!.stream) {
            await sink.writeFrom(chunk);
            received += chunk.length;

            final hasTotal = total > 0;
            final progress = hasTotal ? received / total : null;
            final percent = hasTotal ? (progress! * 100).round() : null;

            final shouldPersist = hasTotal
                ? percent != lastNotifiedPercent
                : (received - lastPersistedBytes) >= 262144;

            if (!shouldPersist) continue;

            final current = _items[song.id];
            if (current == null) continue;
            await _persist(current.copyWith(
              progress: progress ?? current.progress,
              bytesDownloaded: received,
            ));
            lastPersistedBytes = received;

            if (hasTotal && percent != lastNotifiedPercent) {
              lastNotifiedPercent = percent!;
              try {
                await _notifyProgress(
                  songId: song.id,
                  title: song.title,
                  percent: percent,
                );
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[Aurum] DownloadProvider: showProgress notification failed for ${song.id} at $percent% (transfer continues): $e');
                }
              }
            }
          }
        } finally {
          await sink.close();
        }
      } else {
        await _downloadClient.download(
          url,
          tempPath,
          cancelToken: cancelToken,
          deleteOnError: true,
          options: Options(
            receiveTimeout: const Duration(seconds: 60),
            headers: song.source == SongSource.youtube
                ? {'Referer': 'https://www.youtube.com/'}
                : null,
          ),
          onReceiveProgress: (received, total) async {
            if (total <= 0) return;
            final progress = received / total;
            final percent = (progress * 100).round();

            if (percent == lastNotifiedPercent) return;

            final current = _items[song.id];
            if (current == null) return;

            await _persist(current.copyWith(
              progress: progress,
              bytesDownloaded: received,
            ));

            if (percent != lastNotifiedPercent) {
              lastNotifiedPercent = percent;
              try {
                await _notifyProgress(
                  songId: song.id,
                  title: song.title,
                  percent: percent,
                );
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('[Aurum] DownloadProvider: showProgress notification failed for ${song.id} at $percent% (transfer continues): $e');
                }
              }
            }
          },
        );
      }

      if (await finalFile.exists()) await finalFile.delete();
      await tempFile.rename(filePath);

      final size = await finalFile.length();

      final String finalLocalPath = filePath;

      await _persist(_items[song.id]!.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        localPath: finalLocalPath,
        fileSizeBytes: size,
      ));

      try {
        await NotificationService.instance.showCompleted(
          songId: song.id,
          title: song.title,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Aurum] DownloadProvider: showCompleted notification failed for ${song.id} (download itself succeeded and is saved): $e');
        }
      }
      return true;
    } catch (e) {
      final wasPaused = _pausedTokens.remove(song.id);
      if (wasPaused && cancelToken.isCancelled) {
        final partial = File(tempPath!);
        final bytesOnDisk = await partial.exists() ? await partial.length() : 0;
        await _persist(_items[song.id]!.copyWith(
          status: DownloadStatus.paused,
          bytesDownloaded: bytesOnDisk,
        ));
        try {
          await NotificationService.instance.cancelProgress(song.id);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Aurum] DownloadProvider: cancelProgress notification failed for ${song.id}: $e');
          }
        }
        return false;
      }

      if (tempPath != null) {
        try {
          final leftover = File(tempPath);
          if (await leftover.exists()) await leftover.delete();
        } catch (_) {}
      }

      if (cancelToken.isCancelled) {
        await _persist(_items[song.id]!.copyWith(status: DownloadStatus.cancelled));
        try {
          await NotificationService.instance.cancelProgress(song.id);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Aurum] DownloadProvider: cancelProgress notification failed for ${song.id}: $e');
          }
        }
        return false;
      } else {
        await _persist(_items[song.id]!.copyWith(status: DownloadStatus.failed));
        try {
          await NotificationService.instance.showFailed(
            songId: song.id,
            title: song.title,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[Aurum] DownloadProvider: showFailed notification failed for ${song.id}: $e');
          }
        }
        return false;
      }
    } finally {
      _cancelTokens.remove(song.id);
      if (!NotificationService.instance.shouldUseBatchNotification(_activeDownloadCount)) {
        try {
          await NotificationService.instance.cancelBatchProgress();
        } catch (_) {}
      }
    }
  }

  Future<void> cancelDownload(String songId) async {
    final item = _items[songId];
    if (item != null && item.isPaused) {
      final dir = await _downloadsDir();
      final tempPath = '${dir.path}/${_safeFileName(item.song)}.part';
      try {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      } catch (_) {}
      await _persist(item.copyWith(status: DownloadStatus.cancelled));
      try {
        await NotificationService.instance.cancelProgress(songId);
      } catch (_) {}
      return;
    }
    _cancelTokens[songId]?.cancel();
  }

  Future<void> dismissFailed(String songId) async {
    final item = _items[songId];
    if (item == null || !item.isFailed) return;
    _items.remove(songId);
    notifyListeners();
    final box = _box ?? await _boxReady.future;
    await box.delete(songId);
  }

  Future<void> retry(Song song) async {
    _items.remove(song.id);
    final box = _box ?? await _boxReady.future;
    await box.delete(song.id);
    await download(song);
  }

  Future<bool> deleteDownload(String songId) async {
    final item = _items[songId];
    if (item?.localPath != null && item!.localPath!.isNotEmpty) {
      final deleted = await _engine.deletePublicDownload(item.localPath!);
      if (!deleted) {
        if (kDebugMode) {
          debugPrint('[Aurum] DownloadProvider: failed to delete file for $songId at ${item.localPath} — keeping list entry so the orphaned file stays visible/retryable');
        }
        return false;
      }
    }
    if (item != null && item.isPaused) {
      final dir = await _downloadsDir();
      final tempPath = '${dir.path}/${_safeFileName(item.song)}.part';
      try {
        final leftover = File(tempPath);
        if (await leftover.exists()) await leftover.delete();
      } catch (_) {}
    }
    _items.remove(songId);
    final box = _box ?? await _boxReady.future;
    await box.delete(songId);
    await NotificationService.instance.cancelProgress(songId);
    notifyListeners();
    return true;
  }

  int get totalBytesUsed => completed.fold(0, (sum, d) => sum + (d.fileSizeBytes ?? 0));
}
