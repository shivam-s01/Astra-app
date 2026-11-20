// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/aurum_theme.dart';
import '../utils/aurum_haptics.dart';
import '../widgets/aurum_pressable.dart';

/// Full-screen "Move and scale" circular crop, Spotify style.
/// Pops with the cropped square PNG bytes (512x512) or null if cancelled.
class ProfilePhotoCropScreen extends StatefulWidget {
  final String path;
  const ProfilePhotoCropScreen({super.key, required this.path});

  @override
  State<ProfilePhotoCropScreen> createState() => _ProfilePhotoCropScreenState();
}

class _ProfilePhotoCropScreenState extends State<ProfilePhotoCropScreen> {
  static const double _maxZoom = 6.0;
  static const int _outSize = 512;

  ui.Image? _img;
  bool _failed = false;
  bool _exporting = false;

  double _zoom = 1.0;
  Offset _offset = Offset.zero;

  double _startZoom = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  double _cropD = 0; // diameter of the crop circle (logical px)
  bool _dragging = false;

  bool get _hi => Localizations.localeOf(context).languageCode == 'hi';
  String _t(String en, String hi) => _hi ? hi : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _img?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _img = frame.image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  // Size of the image when zoom == 1 (it exactly covers the crop circle).
  Size _baseSize() {
    final img = _img!;
    final base = _cropD / math.min(img.width, img.height);
    return Size(img.width * base, img.height * base);
  }

  Offset _clamp(Offset o, double zoom) {
    final b = _baseSize();
    final maxDx = math.max(0.0, (b.width * zoom - _cropD) / 2);
    final maxDy = math.max(0.0, (b.height * zoom - _cropD) / 2);
    return Offset(
      o.dx.clamp(-maxDx, maxDx).toDouble(),
      o.dy.clamp(-maxDy, maxDy).toDouble(),
    );
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startZoom = _zoom;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
    setState(() => _dragging = true);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_img == null || _cropD <= 0) return;
    final z = (_startZoom * d.scale).clamp(1.0, _maxZoom).toDouble();
    final ratio = z / _startZoom;
    final o = _startOffset * ratio + (d.localFocalPoint - _startFocal);
    setState(() {
      _zoom = z;
      _offset = _clamp(o, z);
    });
  }

  void _onScaleEnd(ScaleEndDetails d) => setState(() => _dragging = false);

  void _reset() {
    AurumHaptics.selection();
    setState(() {
      _zoom = 1.0;
      _offset = Offset.zero;
    });
  }

  Future<void> _confirm() async {
    if (_img == null || _exporting || _cropD <= 0) return;
    AurumHaptics.medium();
    setState(() => _exporting = true);
    try {
      final img = _img!;
      final b = _baseSize();
      final dispW = b.width * _zoom;
      final dispH = b.height * _zoom;
      final k = _outSize / _cropD;

      final dest = Rect.fromCenter(
        center: Offset(_cropD / 2 + _offset.dx, _cropD / 2 + _offset.dy) * k,
        width: dispW * k,
        height: dispH * k,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, _outSize.toDouble(), _outSize.toDouble()),
      );
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dest,
        Paint()
          ..filterQuality = FilterQuality.high
          ..isAntiAlias = true,
      );
      final out = await recorder.endRecording().toImage(_outSize, _outSize);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (!mounted) return;
      if (data == null) {
        setState(() => _exporting = false);
        return;
      }
      Navigator.of(context).pop<Uint8List>(data.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AurumTheme.accentOf(context);
    final bottom = MediaQuery.of(context).padding.bottom;
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          SizedBox(
            height: top + 64,
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, top + 8, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed:
                        _exporting ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 26),
                  ),
                  Expanded(
                    child: Text(
                      _t('Move and scale', 'खिसकाएँ और ज़ूम करें'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _t('Reset', 'रीसेट'),
                    onPressed: (_exporting || (_zoom == 1.0 && _offset == Offset.zero))
                        ? null
                        : _reset,
                    icon: Icon(
                      Icons.restart_alt_rounded,
                      color: (_zoom == 1.0 && _offset == Offset.zero)
                          ? Colors.white24
                          : Colors.white,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final d = math.max(
                    120.0, math.min(c.maxWidth - 48, c.maxHeight - 24));
                if ((d - _cropD).abs() > 0.5) {
                  _cropD = d;
                  if (_img != null) _offset = _clamp(_offset, _zoom);
                }

                if (_failed) {
                  return Center(
                    child: Text(
                      _t('Could not open this photo', 'यह फ़ोटो नहीं खुल सकी'),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  );
                }
                if (_img == null) {
                  return const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.6, color: Colors.white70),
                    ),
                  );
                }

                final b = _baseSize();
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: Transform.translate(
                            offset: _offset,
                            child: Transform.scale(
                              scale: _zoom,
                              child: SizedBox(
                                width: b.width,
                                height: b.height,
                                child: RawImage(
                                  image: _img,
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _CropOverlayPainter(
                              diameter: d,
                              ringColor: accent,
                              showGrid: _dragging,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(24, 14, 24, bottom + 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _t('Pinch to zoom · drag to reposition',
                      'ज़ूम के लिए पिंच करें · जगह बदलने के लिए खींचें'),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AurumPressable(
                        onTap: _exporting
                            ? null
                            : () => Navigator.of(context).pop(),
                        scaleAmount: 0.97,
                        haptic: false,
                        child: Container(
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white38, width: 1.2),
                          ),
                          child: Text(
                            _t('Cancel', 'रद्द करें'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: AurumPressable(
                        onTap: (_img == null || _exporting) ? null : _confirm,
                        scaleAmount: 0.97,
                        haptic: false,
                        child: Opacity(
                          opacity: _img == null ? 0.5 : 1,
                          child: Container(
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: AurumTheme.accentGradientOf(context),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: _exporting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      valueColor:
                                          AlwaysStoppedAnimation(Colors.black),
                                    ),
                                  )
                                : Text(
                                    _t('Choose photo', 'फ़ोटो चुनें'),
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final double diameter;
  final Color ringColor;
  final bool showGrid;

  _CropOverlayPainter({
    required this.diameter,
    required this.ringColor,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = diameter / 2;

    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: r));
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.68));

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    if (showGrid) {
      final g = Paint()
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.28);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: r)));
      final left = center.dx - r;
      final topY = center.dy - r;
      for (var i = 1; i < 3; i++) {
        final x = left + diameter * i / 3;
        final y = topY + diameter * i / 3;
        canvas.drawLine(Offset(x, topY), Offset(x, topY + diameter), g);
        canvas.drawLine(Offset(left, y), Offset(left + diameter, y), g);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter old) =>
      old.diameter != diameter ||
      old.ringColor != ringColor ||
      old.showGrid != showGrid;
}
