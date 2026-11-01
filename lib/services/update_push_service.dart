// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_prefs.dart';
import 'notification_service.dart';

class UpdatePushService {
  UpdatePushService._();
  static final UpdatePushService instance = UpdatePushService._();

  static const String _updatesTopic = 'updates';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();

      final messaging = FirebaseMessaging.instance;
      final sp = await SharedPreferences.getInstance();
      if (!AudioPrefs.dataSaverActiveNotifier.value ||
          sp.getBool('fcm_topic_subscribed_v1') != true) {
        await messaging.subscribeToTopic(_updatesTopic);
        await sp.setBool('fcm_topic_subscribed_v1', true);
      }

      FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title ?? 'Update available';
        final body = message.notification?.body ??
            'A new version of Aurum is ready to install.';
        NotificationService.instance.showUpdateAvailable(title: title, body: body);
      });

      _initialized = true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Aurum] UpdatePushService: init failed (push notifications disabled this session): $e');
      }
    }
  }
}
