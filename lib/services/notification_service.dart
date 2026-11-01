// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'com.aurum.music.channel.downloads';
  static const String _channelName = 'Downloads';
  static const String _channelDesc = 'Shows progress while songs are downloading';

  static const String _updateChannelId = 'com.aurum.music.channel.updates';
  static const String _updateChannelName = 'App Updates';
  static const String _updateChannelDesc = 'Notifies you when a new Aurum update is available';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  void Function()? onNotificationTapped;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.id == _updateNotificationId) {
          onUpdateNotificationTapped?.call();
          return;
        }
        if (response.id == _jamRequestId || response.id == _jamSuggestionId) {
          onJamNotificationTapped?.call();
          return;
        }
        onNotificationTapped?.call();
      },
    );

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.low,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      const updateChannel = AndroidNotificationChannel(
        _updateChannelId,
        _updateChannelName,
        description: _updateChannelDesc,
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(updateChannel);

      const jamChannel = AndroidNotificationChannel(
        _jamChannelId,
        _jamChannelName,
        description: _jamChannelDesc,
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(jamChannel);
    }

    _initialized = true;
  }

  static const String _jamChannelId = 'com.aurum.music.channel.jam';
  static const String _jamChannelName = 'Astra Jam';
  static const String _jamChannelDesc = 'Join requests and song suggestions in your Jam';
  static const int _jamRequestId = 0x7FFFFFF0;
  static const int _jamSuggestionId = 0x7FFFFFF1;

  void Function()? onJamNotificationTapped;

  Future<void> showJamRequest(String username) async {
    if (!_initialized) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _jamChannelId,
        _jamChannelName,
        channelDescription: _jamChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        autoCancel: true,
      ),
    );
    try {
      await _plugin.show(_jamRequestId, 'Astra Jam', '$username wants to join your Jam', details);
    } catch (_) {}
  }

  Future<void> showJamSuggestion(String username, String songTitle) async {
    if (!_initialized) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _jamChannelId,
        _jamChannelName,
        channelDescription: _jamChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        autoCancel: true,
      ),
    );
    try {
      await _plugin.show(_jamSuggestionId, 'Astra Jam', '$username suggested "$songTitle"', details);
    } catch (_) {}
  }

  static const int _updateNotificationId = 0x7FFFFFFD;

  void Function()? onUpdateNotificationTapped;

  Future<void> showUpdateAvailable({
    required String title,
    required String body,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _updateChannelId,
        _updateChannelName,
        channelDescription: _updateChannelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        autoCancel: true,
      ),
    );
    await _plugin.show(_updateNotificationId, title, body, details);
  }

  int _idFor(String songId) => songId.hashCode & 0x7FFFFFFF;

  static const int _batchId = 0x7FFFFFFE;

  static const int _maxIndividualNotifications = 2;

  Future<void> showProgress({
    required String songId,
    required String title,
    required int percent,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: 100,
        progress: percent,
        icon: '@mipmap/ic_launcher',
        ongoing: percent < 100,
        autoCancel: false,
        category: AndroidNotificationCategory.progress,
      ),
    );

    await _plugin.show(
      _idFor(songId),
      'Downloading',
      '$title • $percent%',
      details,
    );
  }

  Future<void> showBatchProgress({
    required int completed,
    required int total,
  }) async {
    if (total <= 0) return;
    final percent = ((completed / total) * 100).clamp(0, 100).round();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.low,
        priority: Priority.low,
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: total,
        progress: completed,
        icon: '@mipmap/ic_launcher',
        ongoing: completed < total,
        autoCancel: false,
        category: AndroidNotificationCategory.progress,
      ),
    );

    await _plugin.show(
      _batchId,
      'Downloading songs',
      '$completed of $total • $percent%',
      details,
    );
  }

  Future<void> cancelBatchProgress() async {
    await _plugin.cancel(_batchId);
  }

  bool shouldUseBatchNotification(int activeCount) =>
      activeCount > _maxIndividualNotifications;

  Future<void> showCompleted({
    required String songId,
    required String title,
  }) async {
    await _plugin.cancel(_idFor(songId));

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
        autoCancel: true,
      ),
    );

    await _plugin.show(
      _idFor(songId) + 1,
      'Download complete',
      title,
      details,
    );
  }

  Future<void> showFailed({
    required String songId,
    required String title,
  }) async {
    await _plugin.cancel(_idFor(songId));

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
        autoCancel: true,
      ),
    );

    await _plugin.show(
      _idFor(songId) + 1,
      'Download failed',
      title,
      details,
    );
  }

  Future<void> cancelProgress(String songId) async {
    await _plugin.cancel(_idFor(songId));
  }
}
