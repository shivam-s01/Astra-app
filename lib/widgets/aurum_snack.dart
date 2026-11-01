// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/aurum_theme.dart';

class AurumSnack {
  AurumSnack._();

  static final Map<ScaffoldMessengerState, (String, DateTime)> _lastShown = {};

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
    Duration dedupeWindow = const Duration(milliseconds: 800),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    final last = _lastShown[messenger];
    if (last != null &&
        last.$1 == message &&
        now.difference(last.$2) < dedupeWindow) {
      return;
    }
    _lastShown[messenger] = (message, now);

    final surface = AurumTheme.bgElevatedOf(context);
    final textColor = AurumTheme.textPrimaryOf(context);

    final hasAction = actionLabel != null && onAction != null;
    if (hasAction) messenger.hideCurrentSnackBar();

    final controller = messenger.showSnackBar(SnackBar(
      content: Text(
        message,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: surface,
      elevation: 6,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AurumTheme.dividerOf(context), width: 0.6),
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: duration,
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(
              label: actionLabel,
              textColor: AurumTheme.accentOf(context),
              onPressed: onAction,
            )
          : null,
    ));

    if (hasAction) {
      var closed = false;
      unawaited(controller.closed.then((_) => closed = true));
      Timer(duration, () {
        if (!closed) controller.close();
      });
    }
  }
}
