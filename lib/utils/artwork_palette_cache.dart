// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'player_color_extractor.dart';
import '../services/aurum_image_cache.dart';

const MethodChannel _mediaStoreChannel =
    MethodChannel('com.aurum.music/media_store');

const int _kContentArtCacheCap = 60;
final Map<String, Uint8List?> _contentArtCache = {};

Future<Uint8List?> _loadContentUriBytes(String uri) async {
  if (_contentArtCache.containsKey(uri)) return _contentArtCache[uri];
  Uint8List? bytes;
  try {
    bytes = await _mediaStoreChannel
        .invokeMethod<Uint8List>('getAlbumArt', {'uri': uri});
  } catch (_) {
    bytes = null;
  }
  if (_contentArtCache.length >= _kContentArtCacheCap &&
      !_contentArtCache.containsKey(uri)) {
    _contentArtCache.remove(_contentArtCache.keys.first);
  }
  _contentArtCache[uri] = bytes;
  return bytes;
}

Future<ImageProvider?> _resolveArtworkProvider(String url) async {
  if (url.startsWith('content://')) {
    final bytes = await _loadContentUriBytes(url);
    if (bytes == null || bytes.isEmpty) return null;
    return MemoryImage(bytes);
  }
  if (url.startsWith('/') || url.startsWith('file://')) {
    final path =
        url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
    if (!File(path).existsSync()) return null;
    return FileImage(File(path));
  }
  if (url.startsWith('http')) {
    return CachedNetworkImageProvider(url, cacheManager: AurumImageCache());
  }
  return null;
}

class ArtworkPalette {
  final Color vibrant;
  final Color dominant;
  final Color darkMuted;
  final Color lightVibrant;

  final List<Color> gradientColors;

  const ArtworkPalette({
    required this.vibrant,
    required this.dominant,
    required this.darkMuted,
    required this.lightVibrant,
    this.gradientColors = const [],
  });
}

Color ensureContrastSafe(Color c, {required bool isLight}) {
  final luma = c.computeLuminance();
  if (isLight) {
    const minLuma = 0.55;
    if (luma >= minLuma) return c;
    final t = ((minLuma - luma) / (1 - luma)).clamp(0.0, 0.85);
    return Color.lerp(c, Colors.white, t)!;
  } else {
    const maxLuma = 0.22;
    if (luma <= maxLuma) return c;
    return Color.lerp(c, Colors.black, ((luma - maxLuma) / luma).clamp(0.0, 1.0))!;
  }
}

class ArtworkPaletteCache {
  ArtworkPaletteCache._();

  static const int _maxEntries = 60;
  static final Map<String, ArtworkPalette> _cache = {};

  static final Map<String, Future<ArtworkPalette>> _inFlight = {};

  static ArtworkPalette? peek(String url) => _cache[url];

  static final Map<String, Future<ArtworkPalette?>> _fastInFlight = {};

  static const int _maxConcurrent = 3;
  static int _activeCount = 0;
  static final List<Completer<void>> _waitQueue = [];

  static Future<void> _acquireSlot() {
    if (_activeCount < _maxConcurrent) {
      _activeCount++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  static void _releaseSlot() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      next.complete();
    } else {
      _activeCount--;
    }
  }

  static Future<ArtworkPalette?> getFast(String url) {
    if (url.isEmpty) return Future.value(null);
    final existing = _fastInFlight[url];
    if (existing != null) return existing;

    final future = _extractFast(url).whenComplete(() {
      _fastInFlight.remove(url);
    });
    _fastInFlight[url] = future;
    return future;
  }

  static Future<ArtworkPalette?> _extractFast(String url) async {
    await _acquireSlot();
    try {
      final provider = await _resolveArtworkProvider(url);
      if (provider == null) return null;
      final pg = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(16, 16),
        maximumColorCount: 1,
      ).timeout(const Duration(milliseconds: 600));
      final avg = pg.dominantColor?.color ??
          pg.vibrantColor?.color ??
          pg.mutedColor?.color;
      if (avg == null) return null;
      return ArtworkPalette(
        vibrant: avg,
        dominant: avg,
        darkMuted: avg,
        lightVibrant: avg,
      );
    } catch (_) {
      return null;
    } finally {
      _releaseSlot();
    }
  }

  static Future<ArtworkPalette> get(String url) {
    final cached = _cache[url];
    if (cached != null) return Future.value(cached);

    final existing = _inFlight[url];
    if (existing != null) return existing;

    final future = _extract(url).then((palette) {
      _inFlight.remove(url);
      if (palette == null) return const ArtworkPalette(
        vibrant: Color(0xFF1A1630),
        dominant: Color(0xFF120F24),
        darkMuted: Color(0xFF080810),
        lightVibrant: Color(0xFF1A1630),
      );
      _put(url, palette);
      return palette;
    });
    _inFlight[url] = future;
    return future;
  }

  static void warm(String url) {
    if (url.isEmpty || _cache.containsKey(url) || _inFlight.containsKey(url)) {
      return;
    }
    get(url);
  }

  static void _put(String url, ArtworkPalette palette) {
    if (_cache.length >= _maxEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = palette;
  }

  static Future<ArtworkPalette?> _extract(String url) async {
    if (url.isEmpty) return null;
    await _acquireSlot();
    try {
      final provider = await _resolveArtworkProvider(url);
      if (provider == null) return null;
      final pg = await PaletteGenerator.fromImageProvider(
        provider,
        size: const Size(40, 40),
        maximumColorCount: 12,
      ).timeout(const Duration(milliseconds: 1200));

      final gradientColors = PlayerColorExtractor.extractGradientColors(
        pg,
        fallbackColor: const Color(0xFF1A1630),
      );
      final ranked = gradientColors.isNotEmpty
          ? gradientColors
          : const [Color(0xFF1A1630)];

      return ArtworkPalette(
        vibrant: pg.vibrantColor?.color ??
            pg.lightVibrantColor?.color ??
            pg.dominantColor?.color ??
            const Color(0xFF1A1630),
        dominant: pg.dominantColor?.color ??
            pg.mutedColor?.color ??
            const Color(0xFF120F24),
        darkMuted: pg.darkMutedColor?.color ??
            pg.mutedColor?.color ??
            const Color(0xFF080810),
        lightVibrant: pg.lightVibrantColor?.color ??
            pg.vibrantColor?.color ??
            pg.lightMutedColor?.color ??
            const Color(0xFF1A1630),
        gradientColors: ranked,
      );
    } catch (_) {
      return null;
    } finally {
      _releaseSlot();
    }
  }
}
