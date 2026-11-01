// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'aurum_artwork.dart';

class AurumWideThumb extends StatelessWidget {
  final String url;
  final double width;
  final double height;
  final double borderRadius;

  const AurumWideThumb({
    super.key,
    required this.url,
    this.width = 80,
    this.height = 45,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final src = width * 1.4;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: src,
            height: src,
            child: AurumArtwork(url: url, size: src, borderRadius: 0),
          ),
        ),
      ),
    );
  }
}
