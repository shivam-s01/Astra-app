// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/aurum_image_cache.dart';
import '../services/audio_prefs.dart';
import '../theme/aurum_theme.dart';
import '../utils/aurum_motion.dart';

class AurumArtwork extends StatelessWidget {
  final String url;
  final double size;
  final double borderRadius;

  final bool fadeIn;

  final bool isBlurredBackground;

  final bool suppressWhiteShimmer;

  final bool decodeToScreenWidth;

  const AurumArtwork({
    super.key,
    required this.url,
    required this.size,
    this.borderRadius = 8,
    this.fadeIn = true,
    this.isBlurredBackground = false,
    this.suppressWhiteShimmer = false,
    this.decodeToScreenWidth = false,
  });

  static int screenDecodeWidth(BuildContext context) {
    final px = MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context) *
        1.05;
    return px.ceil().clamp(480, 1200);
  }

  static String upgradeForFullPlayer(String url) {
    if (url.isEmpty) return url;
    if (AudioPrefs.dataSaverActiveNotifier.value) {
      if (url.contains('-l60-rj')) {
        return url.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w300-h300');
      }
      return url;
    }
    final m = RegExp(r'=w(\d+)-h(\d+)').firstMatch(url);
    if (m != null && int.parse(m.group(1)!) <= 300) {
      return url.replaceFirst(m.group(0)!, '=w600-h600');
    }
    if (url.contains('150x150')) {
      return url.replaceAll('150x150', '500x500');
    }
    return url;
  }

  int? _cacheSizeFor(BuildContext context) {
    if (!size.isFinite) {
      if (isBlurredBackground) return 220;
      return decodeToScreenWidth ? screenDecodeWidth(context) : 1200;
    }
    if (size <= 0) return null;
    return (size * 2).toInt();
  }

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return isBlurredBackground ? const SizedBox.expand() : _placeholder(context);
    }

    if (url.startsWith('content://')) {
      return _ContentUriImage(
        uri: url,
        size: size,
        borderRadius: borderRadius,
        placeholder: _placeholder(context),
        fadeIn: fadeIn,
        isBlurredBackground: isBlurredBackground,
        suppressWhiteShimmer: suppressWhiteShimmer,
      );
    }

    if (url.startsWith('/') || url.startsWith('file://')) {
      final path =
          url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
      final fileImage = Image.file(
        File(path),
        key: ValueKey(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: _cacheSizeFor(context),
        errorBuilder: (_, __, ___) =>
            isBlurredBackground ? const SizedBox.expand() : _placeholder(context),
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: fadeIn ? _FadeInImage(child: fileImage) : fileImage,
      );
    }

    return _clipped(
      _RetryableNetworkImage(
        url: url,
        size: size,
        cacheSize: _cacheSizeFor(context),
        fadeIn: fadeIn,
        placeholder: _shimmer(context, suppressWhiteShimmer),
        errorWidget:
            isBlurredBackground ? const SizedBox.expand() : _placeholder(context),
      ),
    );
  }

  Widget _clipped(Widget child) => borderRadius <= 0
      ? child
      : ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: child,
        );

  static const Color _placeholderBase = Color(0xFF1A1714);

  Widget _placeholder(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_placeholderBase, Color(0xFF0F0D0B)],
          ),
        ),
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: 0.35),
          size: size * 0.38,
        ),
      );

  Widget _shimmer(BuildContext context, [bool suppress = false]) {
    if (isBlurredBackground) return const SizedBox.expand();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _placeholderBase,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class _RetryableNetworkImage extends StatefulWidget {
  final String url;
  final double size;
  final int? cacheSize;
  final bool fadeIn;
  final Widget placeholder;
  final Widget errorWidget;

  const _RetryableNetworkImage({
    required this.url,
    required this.size,
    required this.cacheSize,
    required this.fadeIn,
    required this.placeholder,
    required this.errorWidget,
  });

  @override
  State<_RetryableNetworkImage> createState() =>
      _RetryableNetworkImageState();
}

class _RetryableNetworkImageState extends State<_RetryableNetworkImage> {
  static final RegExp _maxResPattern =
      RegExp(r'/maxresdefault\.jpg$');

  late String _activeUrl = widget.url;
  bool _triedFallback = false;

  @override
  void didUpdateWidget(_RetryableNetworkImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _activeUrl = widget.url;
      _triedFallback = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      key: ValueKey(widget.url),
      imageUrl: _activeUrl,
      cacheManager: AurumImageCache(),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      memCacheWidth: widget.cacheSize,
      fadeInDuration:
          widget.fadeIn ? const Duration(milliseconds: 280) : Duration.zero,
      fadeInCurve: Curves.easeOut,
      fadeOutDuration:
          widget.fadeIn ? const Duration(milliseconds: 120) : Duration.zero,
      fadeOutCurve: Curves.easeIn,
      placeholder: (_, __) => widget.placeholder,
      errorWidget: (_, __, ___) {
        if (!_triedFallback && _maxResPattern.hasMatch(_activeUrl)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _triedFallback = true;
                _activeUrl =
                    _activeUrl.replaceFirst(_maxResPattern, '/hqdefault.jpg');
              });
            }
          });
          return widget.placeholder;
        }
        return widget.errorWidget;
      },
    );
  }
}

class _FadeInImage extends StatelessWidget {
  final Widget child;

  const _FadeInImage({required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AurumMotion.durationOrZero(AurumMotion.medium1),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: child,
    );
  }
}

class _ContentUriImage extends StatefulWidget {
  final String uri;
  final double size;
  final double borderRadius;
  final Widget placeholder;
  final bool fadeIn;
  final bool isBlurredBackground;
  final bool suppressWhiteShimmer;

  const _ContentUriImage({
    required this.uri,
    required this.size,
    required this.borderRadius,
    required this.placeholder,
    this.fadeIn = true,
    this.isBlurredBackground = false,
    this.suppressWhiteShimmer = false,
  });

  @override
  State<_ContentUriImage> createState() => _ContentUriImageState();
}

class _ContentUriImageState extends State<_ContentUriImage> {
  static const int _maxEntries = 60;
  static final Map<String, Uint8List?> _cache = {};

  static void _cachePut(String uri, Uint8List? bytes) {
    if (_cache.length >= _maxEntries && !_cache.containsKey(uri)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[uri] = bytes;
  }

  static const _channel = MethodChannel('com.aurum.music/media_store');

  Uint8List? _bytes;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ContentUriImage old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) {
      setState(() {
        _loaded = false;
        _bytes = null;
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (_cache.containsKey(widget.uri)) {
      if (mounted) {
        setState(() {
          _bytes = _cache[widget.uri];
          _loaded = true;
        });
      }
      return;
    }

    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'getAlbumArt',
        {'uri': widget.uri},
      );
      _cachePut(widget.uri, result);
      if (mounted) setState(() { _bytes = result; _loaded = true; });
    } catch (_) {
      _cachePut(widget.uri, null);
      if (mounted) setState(() { _bytes = null; _loaded = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      if (widget.isBlurredBackground) {
        return const SizedBox.expand();
      }
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: AurumArtwork._placeholderBase,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      );
    }

    if (_bytes == null || _bytes!.isEmpty) {
      return widget.isBlurredBackground
          ? const SizedBox.expand()
          : widget.placeholder;
    }

    final memImage = Image.memory(
      _bytes!,
      key: ValueKey(widget.uri),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      cacheWidth: (widget.size.isFinite && widget.size > 0)
          ? (widget.size * 2).toInt()
          : null,
      errorBuilder: (_, __, ___) => widget.placeholder,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: widget.fadeIn ? _FadeInImage(child: memImage) : memImage,
    );
  }
}
