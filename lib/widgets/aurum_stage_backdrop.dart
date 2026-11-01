// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/aurum_image_cache.dart';
import '../providers/player_provider.dart';
import '../theme/aurum_theme.dart';

class AurumStageBackdrop extends StatelessWidget {
  final double height;

  final ScrollController? scrollController;
  const AurumStageBackdrop({
    super.key,
    this.height = 260,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final song = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final pageBg = AurumTheme.bgOf(context);

    final glowOpacity = isLight ? 0.06 : 0.14;
    final glowStops = isLight
        ? const [0.0, 0.22, 0.48, 0.72, 1.0]
        : const [0.0, 0.30, 0.58, 0.80, 1.0];

    final stage = RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AurumTheme.accentOf(context).withOpacity(glowOpacity),
                    AurumTheme.accentOf(context)
                        .withOpacity(glowOpacity * 0.55),
                    AurumTheme.accentOf(context)
                        .withOpacity(glowOpacity * 0.22),
                    AurumTheme.accentOf(context)
                        .withOpacity(glowOpacity * 0.06),
                    pageBg,
                  ],
                  stops: glowStops,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.9, -1.2),
                  radius: 1.15,
                  colors: [
                    AurumTheme.accentOf(context)
                        .withOpacity(isLight ? 0.13 : 0.24),
                    AurumTheme.accentOf(context).withOpacity(0.0),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(1.0, -1.1),
                  radius: 0.95,
                  colors: [
                    AurumTheme.accentLightOf(context)
                        .withOpacity(isLight ? 0.10 : 0.14),
                    AurumTheme.accentLightOf(context).withOpacity(0.0),
                  ],
                ),
              ),
            ),
            if (song != null && song.artworkUrl.isNotEmpty)
              Opacity(
                opacity: isLight ? 0.34 : 0.92,
                child: _BakedBlurStage(
                  key: ValueKey('${song.id}_${song.artworkUrl}'),
                  song: song,
                  isLight: isLight,
                ),
              ),
            if (!isLight) const _GrainOverlay(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    pageBg.withOpacity(0.18),
                    pageBg.withOpacity(0.45),
                    pageBg.withOpacity(0.78),
                    pageBg,
                  ],
                  stops: isLight
                      ? const [0.0, 0.40, 0.62, 0.82, 1.0]
                      : const [0.0, 0.55, 0.72, 0.86, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final ctrl = scrollController;
    if (ctrl == null) return stage;
    return AnimatedBuilder(
      animation: ctrl,
      child: stage,
      builder: (context, child) {
        var dy = 0.0;
        if (ctrl.hasClients) {
          dy = -ctrl.position.pixels.clamp(0.0, height);
        }
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
    );
  }
}

class _BakedBlurStage extends StatefulWidget {
  final Song song;
  final bool isLight;
  const _BakedBlurStage({super.key, required this.song, required this.isLight});

  @override
  State<_BakedBlurStage> createState() => _BakedBlurStageState();
}

class _BakedBlurStageState extends State<_BakedBlurStage> {
  final GlobalKey _repaintKey = GlobalKey();
  ui.Image? _snapshot;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
  }

  @override
  void dispose() {
    _snapshot?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_capturing || !mounted) return;
    _capturing = true;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      _capturing = false;
      return;
    }
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) {
        _capturing = false;
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
        }
        return;
      }
      final image = await boundary.toImage(pixelRatio: 1.0);
      if (!mounted) {
        image.dispose();
        _capturing = false;
        return;
      }
      final old = _snapshot;
      setState(() => _snapshot = image);
      old?.dispose();
    } catch (_) {
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [...previousChildren, if (currentChild != null) currentChild],
        ),
        child: snapshot != null
            ? SizedBox.expand(
                key: const ValueKey('baked'),
                child: RawImage(image: snapshot, fit: BoxFit.cover),
              )
            : RepaintBoundary(
                key: _repaintKey,
                child: _LiveBlur(song: widget.song, isLight: widget.isLight),
              ),
      ),
    );
  }
}

class _LiveBlur extends StatelessWidget {
  final Song song;
  final bool isLight;
  const _LiveBlur({required this.song, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1.6,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: isLight ? 26 : 30,
          sigmaY: isLight ? 26 : 30,
          tileMode: TileMode.mirror,
        ),
        child: ShaderMask(
          shaderCallback: (rect) => const RadialGradient(
            radius: 0.85,
            colors: [Colors.white, Colors.transparent],
            stops: [0.55, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: _ArtworkFill(url: song.artworkUrl),
        ),
      ),
    );
  }
}

class _ArtworkFill extends StatelessWidget {
  final String url;
  const _ArtworkFill({required this.url});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 200,
          height: 200,
          child: _NoFadeArtwork(url: url),
        ),
      ),
    );
  }
}

class _NoFadeArtwork extends StatelessWidget {
  final String url;
  const _NoFadeArtwork({required this.url});

  @override
  Widget build(BuildContext context) {
    return Image(
      image: resolveAurumImageProvider(url),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const SizedBox.expand(),
    );
  }
}

ImageProvider resolveAurumImageProvider(String url) {
  if (url.startsWith('http')) {
    return CachedNetworkImageProvider(url, cacheManager: AurumImageCache());
  }
  if (url.startsWith('file://')) {
    return FileImage(_fileFromUri(url));
  }
  if (url.startsWith('/')) {
    return FileImage(_fileFromUri(url));
  }
  return MemoryImage(_kTransparentPixel);
}

File _fileFromUri(String url) =>
    File(url.startsWith('file://') ? url.replaceFirst('file://', '') : url);

final Uint8List _kTransparentPixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _GrainOverlay extends StatelessWidget {
  const _GrainOverlay();

  static ui.Image? _cached;
  static Future<ui.Image>? _pending;

  static Future<ui.Image> _generate() {
    if (_cached != null) return Future.value(_cached);
    return _pending ??= _build().then((img) {
      _cached = img;
      return img;
    });
  }

  static Future<ui.Image> _build() async {
    const size = 64;
    final rnd = math.Random(7);
    final bytes = Uint8List(size * size * 4);
    for (var i = 0; i < size * size; i++) {
      final v = rnd.nextInt(256);
      bytes[i * 4] = v;
      bytes[i * 4 + 1] = v;
      bytes[i * 4 + 2] = v;
      bytes[i * 4 + 3] = 255;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _generate(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return Opacity(
          opacity: 0.035,
          child: SizedBox.expand(
            child: CustomPaint(
              painter: _GrainPainter(snap.data!),
            ),
          ),
        );
      },
    );
  }
}

class _GrainPainter extends CustomPainter {
  final ui.Image tile;
  const _GrainPainter(this.tile);

  @override
  void paint(Canvas canvas, Size size) {
    final shader = ImageShader(
      tile,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.identity().storage,
    );
    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.overlay;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GrainPainter old) => old.tile != tile;
}
