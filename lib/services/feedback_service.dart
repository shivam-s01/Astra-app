// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/profanity_filter.dart';

class FeedbackService {
  FeedbackService._();

  static const _endpoint = 'https://formspree.io/f/xnjeagol';

  static const _kSongsSincePrompt = 'feedback_songs_since_prompt';
  static const _kLastPromptAt = 'feedback_last_prompt_at_ms';
  static const _kLastPromptedVersionShown = 'feedback_ever_shown';

  static const _cooldown = Duration(hours: 12);
  static const _songsBeforePrompt = 2;
  static const int maxMessageLength = 500;

  static const _kAbuseLog = 'feedback_abuse_attempts_ms';
  static const _kSendLog = 'feedback_recent_sends_ms';
  static const _abuseWindow = Duration(hours: 24);
  static const _sendWindow = Duration(minutes: 10);
  static const _abuseStrikesForWarning = 2;
  static const _sendsBeforeWarning = 2;

  static const String abuseMessage =
      'Please keep your feedback respectful — abusive language is not allowed.';
  static const String spamWarning =
      "Don't spam or abuse. Your ID and device may be blocked.";

  static Future<List<int>> _recent(
      SharedPreferences prefs, String key, Duration window) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return (prefs.getStringList(key) ?? [])
        .map(int.tryParse)
        .whereType<int>()
        .where((t) => now - t < window.inMilliseconds)
        .toList();
  }

  static Future<String?> screen(String? message) async {
    final problem = validate(message);
    if (problem == null) return null;
    if (problem != abuseMessage) return problem;
    try {
      final prefs = await SharedPreferences.getInstance();
      final log = await _recent(prefs, _kAbuseLog, _abuseWindow);
      log.add(DateTime.now().millisecondsSinceEpoch);
      await prefs.setStringList(_kAbuseLog, log.map((e) => '$e').toList());
      if (log.length >= _abuseStrikesForWarning) return spamWarning;
    } catch (_) {}
    return problem;
  }

  static Future<bool> recordSendAndCheckSpam() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final log = await _recent(prefs, _kSendLog, _sendWindow);
      log.add(DateTime.now().millisecondsSinceEpoch);
      await prefs.setStringList(_kSendLog, log.map((e) => '$e').toList());
      return log.length > _sendsBeforeWarning;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> onSongPlayed() async {
    final prefs = await SharedPreferences.getInstance();

    final lastPromptMs = prefs.getInt(_kLastPromptAt) ?? 0;
    final sinceLast = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastPromptMs),
    );
    if (lastPromptMs != 0 && sinceLast < _cooldown) {
      return false;
    }

    final songCount = (prefs.getInt(_kSongsSincePrompt) ?? 0) + 1;

    if (songCount >= _songsBeforePrompt) {
      await prefs.setInt(_kSongsSincePrompt, 0);
      await prefs.setInt(_kLastPromptAt, DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool(_kLastPromptedVersionShown, true);
      return true;
    }

    await prefs.setInt(_kSongsSincePrompt, songCount);
    return false;
  }

  static String? validate(String? message) {
    final msg = (message ?? '').trim();
    if (msg.length > maxMessageLength) {
      return 'Message is too long (max $maxMessageLength characters).';
    }
    if (ProfanityFilter.containsProfanity(msg)) {
      return abuseMessage;
    }
    return null;
  }

  static Future<bool> submit({
    required int rating,
    String? userId,
    String? userEmail,
    String? message,
    String? appVersion,
  }) async {
    if (validate(message) != null) return false;
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'rating': '$rating / 5',
              'message': (message == null || message.trim().isEmpty)
                  ? '(no additional comments)'
                  : message.trim(),
              'app_version': appVersion ?? 'unknown',
              'user_id': userId ?? 'unknown',
              'user_email': userEmail ?? 'unknown',
              'subject': 'Aurum Feedback — $rating★',
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200 || response.statusCode == 202;
    } catch (_) {
      return false;
    }
  }
}
