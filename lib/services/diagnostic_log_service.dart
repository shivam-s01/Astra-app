// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class DiagnosticLogService {
  DiagnosticLogService._();

  static const MethodChannel _channel = MethodChannel('com.aurum.music/media_store');

  static void logNetworkError(String context, String message) {
    _channel.invokeMethod('logNetworkError', {
      'context': context,
      'message': message,
    }).catchError((_) {
    });
  }

  static Future<String?> _logFilePath() async {
    try {
      return await _channel.invokeMethod<String>('getDiagnosticLogPath');
    } catch (_) {
      return null;
    }
  }

  static Future<String?> readLog() async {
    final path = await _logFilePath();
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> shareLog() async {
    final path = await _logFilePath();
    if (path == null) return false;
    final file = File(path);
    if (!await file.exists()) return false;
    try {
      await Share.shareXFiles(
        [XFile(path)],
        subject: 'Aurum Music — Diagnostic Log',
        text: 'Diagnostic log exported from Aurum Music.',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearLog() async {
    try {
      await _channel.invokeMethod('clearDiagnosticLog');
    } catch (_) {
    }
  }
}
