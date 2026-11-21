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

class _CropState {
  final double zoom;
  final Offset offset;
  final bool dragging;
  const _CropState(this.zoom, this.offset, this.dragging);

  bool get isDefault => zoom == 1.0 && offset == Offset.zero;
}

class ProfilePhotoCropScreen extends StatefulWidget {
  final String path;
  const ProfilePhotoCropScreen({super.key, required this.path});

  @override
  State<ProfilePhotoCropScreen> createState() => _ProfilePhotoCropScreenState();
}

class _ProfilePhotoCropScreenState extends State<ProfilePhotoCropScreen> {
  static const double _maxZoom = 6.0;
  static const int _outSize = 512;

  final ValueNotifier<_CropState> _state =
      ValueNotifier<_CropState>(const _CropState(1.0, Offset.zero, false));

  ui.Image? _img;
  bool _failed = false;
  bool _exporting = false;
  double _cropD = 0;

  double _startZoom = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  bool get _hi => Localizations.localeOf(context).languageCode == 'hi';
  String _t(String en, String hi) => _hi ? hi : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _state.dispose();
    _img?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _img = frame.image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

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
    final s = _state.value;
    _startZoom = s.zoom;
    _startOffset = s.offset;
    _startFocal = d.localFocalPoint;
    _state.value = _CropState(s.zoom, s.offset, true);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_img == null || _cropD <= 0) return;
    final z = (_startZoom * d.scale).clamp(1.0, _maxZoom).toDouble();
    final o = _startOffset * (z / _startZoom) + (d.localFocalPoint - _startFocal);
    _state.value = _CropState(z, _clamp(o, z), true);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final s = _state.value;
    _state.value = _CropState(s.zoom, s.offset, false);
  }

  void _reset() {
    AurumHaptics.selection();
    _state.value = const _CropState(1.0, Offset.zero, false);
  }

  Future<void> _confirm() async {
    if (_img == null || _exporting || _cropD <= 0) return;
    AurumHaptics.medium();
    setState(() => _exporting = true);
    try {
      final img = _img!;
      final s = _state.value;
      final b = _baseSize();
      final k = _outSize / _cropD;

      final dest = Rect.fromCenter(
        center: Offset(_cropD / 2 + s.offset.dx, _cropD / 2 + s.offset.dy) * k,
        width: b.width * s.zoom * k,
        height: b.height * s.zoom * k,
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
      final picture = recorder.endRecording();
      final out = await picture.toImage(_outSize, _outSize);
      picture.dispose();
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

  Widget _canvas(double d) {
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
    final accent = AurumTheme.accentOf(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onScaleEnd: _onScaleEnd,
      child: ClipRect(
        child: ValueListenableBuilder<_CropState>(
          valueListenable: _state,
          builder: (context, s, _) => Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Transform.translate(
                  offset: s.offset,
                  child: Transform.scale(
                    scale: s.zoom,
                    child: SizedBox(
                      width: b.width,
                      height: b.height,
                      child: RawImage(
                        image: _img,
                        fit: BoxFit.fill,
                        filterQuality: s.dragging
                            ? FilterQuality.low
                            : FilterQuality.medium,
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
                    showGrid: s.dragging,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
                  ValueListenableBuilder<_CropState>(
                    valueListenable: _state,
                    builder: (context, s, _) {
                      final enabled = !_exporting && !s.isDefault;
                      return IconButton(
                        tooltip: _t('Reset', 'रीसेट'),
                        onPressed: enabled ? _reset : null,
                        icon: Icon(
                          Icons.restart_alt_rounded,
                          color: enabled ? Colors.white : Colors.white24,
                          size: 24,
                        ),
                      );
                    },
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
                  if (_img != null) {
                    final s = _state.value;
                    _state.value =
                        _CropState(s.zoom, _clamp(s.offset, s.zoom), s.dragging);
                  }
                }
                return _canvas(d);
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
                            border:
                                Border.all(color: Colors.white38, width: 1.2),
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
                                  color: accent.withValues(alpha: 0.3),
                                  blurRadius: 14,
                                  offset: const Offset(0, 5),
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

  const _CropOverlayPainter({
    required this.diameter,
    required this.ringColor,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = diameter / 2;
    final circle = Rect.fromCircle(center: center, radius: r);

    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(circle);
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
      canvas.clipPath(Path()..addOval(circle));
      for (var i = 1; i < 3; i++) {
        final x = circle.left + diameter * i / 3;
        final y = circle.top + diameter * i / 3;
        canvas.drawLine(Offset(x, circle.top), Offset(x, circle.bottom), g);
        canvas.drawLine(Offset(circle.left, y), Offset(circle.right, y), g);
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
