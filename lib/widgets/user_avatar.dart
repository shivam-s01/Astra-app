// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/aurum_image_cache.dart';

class UserAvatar extends StatelessWidget {
  final String? url;
  final Widget fallback;
  final int memCache;

  const UserAvatar({
    super.key,
    required this.url,
    required this.fallback,
    this.memCache = 260,
  });

  static bool isLocal(String? v) => v != null && v.startsWith('/');

  @override
  Widget build(BuildContext context) {
    final v = url;
    if (v == null || v.isEmpty) return fallback;

    if (isLocal(v)) {
      return Image.file(
        File(v),
        key: ValueKey(v),
        fit: BoxFit.cover,
        cacheWidth: memCache,
        cacheHeight: memCache,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return CachedNetworkImage(
      imageUrl: v,
      cacheManager: AurumImageCache(),
      fit: BoxFit.cover,
      memCacheWidth: memCache,
      memCacheHeight: memCache,
      placeholder: (_, __) => fallback,
      errorWidget: (_, __, ___) => fallback,
    );
  }
}
