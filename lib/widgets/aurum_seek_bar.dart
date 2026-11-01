// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../providers/theme_provider.dart';
import '../services/waveform_service.dart';

class AurumSeekBar extends StatefulWidget {
  final PlayerProvider player;
  final double hPad;
  final Color activeColor;
  final Color inactiveColor;
  final Color timeColor;

  final Widget? centerLabel;

  const AurumSeekBar({
    super.key,
    required this.player,
    required this.hPad,
    required this.activeColor,
    required this.inactiveColor,
    required this.timeColor,
    this.centerLabel,
  });

  @override
  State<AurumSeekBar> createState() => _AurumSeekBarState();
}

class _AurumSeekBarState extends State<AurumSeekBar> {
  bool _dragging = false;
  double? _dragValue;
  List<double>? _waveform;
  String? _waveformFor;

  Future<void> _loadWaveform() async {
    final song = widget.player.currentSong;
    if (song == null) return;
    final key = song.localPath ?? song.streamUrl ?? song.id;
    if (_waveformFor == key) return;
    _waveformFor = key;
    final isLocal = song.isLocal;
    final path = song.localPath ?? song.streamUrl ?? '';
    if (path.isEmpty) return;
    final wf = await WaveformService.getWaveform(path, isLocal: isLocal);
    if (mounted && _waveformFor == key) {
      setState(() => _waveform = wf);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, (double, int, int, String, String, String?, bool)>(
      selector: (_, player) => (
        player.progress,
        player.duration.inMilliseconds,
        player.buffered.inMilliseconds,
        player.positionString,
        player.durationString,
        player.currentSong?.id,
        player.isPlaying,
      ),
      builder: (context, data, __) => _buildSeekBar(context),
    );
  }

  Widget _buildSeekBar(BuildContext context) {
    final sliderStyle = context.watch<ThemeProvider>().playerSliderStyle;
    final double baseTrackHeight;
    final double thumbRadius;
    switch (sliderStyle) {
      case 'Slim':
        baseTrackHeight = 1.5;
        thumbRadius = 4.5;
        break;
      case 'Thick':
        baseTrackHeight = 6.0;
        thumbRadius = 7.0;
        break;
      case 'Waveform':
        baseTrackHeight = 0;
        thumbRadius = 0;
        break;
      case 'Rounded':
      default:
        baseTrackHeight = 3.0;
        thumbRadius = 5.5;
    }

    if (sliderStyle == 'Waveform') {
      _loadWaveform();
      return _WaveformSeekBar(
        player: widget.player,
        hPad: widget.hPad,
        waveform: _waveform,
        activeColor: widget.activeColor,
        inactiveColor: widget.inactiveColor,
        timeColor: widget.timeColor,
        dragging: _dragging,
        dragValue: _dragValue,
        centerLabel: widget.centerLabel,
        onDragStart: () => setState(() => _dragging = true),
        onDrag: (v) => setState(() => _dragValue = v),
        onDragEnd: (v) {
          widget.player.seek(v);
          setState(() {
            _dragging = false;
            _dragValue = null;
          });
        },
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.hPad - 4),
      child: Column(children: [
        SizedBox(
          height: 32,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: _dragging ? baseTrackHeight + 1 : baseTrackHeight,
              thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: _dragging ? thumbRadius + 2 : thumbRadius,
                  elevation: _dragging ? 4 : 1,
                  pressedElevation: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: widget.activeColor,
              inactiveTrackColor: widget.inactiveColor,
              thumbColor: widget.activeColor,
              overlayColor: widget.activeColor.withAlpha(22),
              trackShape: const _BufferedTrackShape(),
            ),
            child: Slider(
              value: _dragValue ?? widget.player.progress,
              secondaryTrackValue: widget.player.duration.inMilliseconds > 0
                  ? (widget.player.buffered.inMilliseconds /
                          widget.player.duration.inMilliseconds)
                      .clamp(0.0, 1.0)
                  : 0.0,
              onChangeStart: (v) => setState(() {
                _dragging = true;
                _dragValue = v;
              }),
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                widget.player.seek(v);
                setState(() {
                  _dragging = false;
                  _dragValue = null;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.player.positionString,
                  style: TextStyle(
                      color: widget.timeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3)),
              if (widget.centerLabel != null) widget.centerLabel!,
              Text(widget.player.durationString,
                  style: TextStyle(
                      color: widget.timeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3)),
            ],
          ),
        ),
      ]),
    );
  }
}

class _WaveformSeekBar extends StatefulWidget {
  final PlayerProvider player;
  final double hPad;
  final List<double>? waveform;
  final Color activeColor;
  final Color inactiveColor;
  final Color timeColor;
  final bool dragging;
  final double? dragValue;
  final Widget? centerLabel;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;

  const _WaveformSeekBar({
    required this.player,
    required this.hPad,
    required this.waveform,
    required this.activeColor,
    required this.inactiveColor,
    required this.timeColor,
    required this.dragging,
    required this.dragValue,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    this.centerLabel,
  });

  @override
  State<_WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<_WaveformSeekBar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _ampAnim = 0.0;
  double _thumbFraction = 0.0;
  Duration _lastElapsed = Duration.zero;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);

  static const double _wavelength = 24;
  static const double _waveSpeed = 18;

  double _phase = 0;

  double _visMs = 0;
  double _visFrac = 0;
  int _lastReportedMs = -1;
  double _reportedAtMs = 0;
  final Stopwatch _clock = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.player.isPlaying && !widget.dragging) _ticker.start();
    _thumbFraction = widget.dragging ? 1.0 : 0.0;
    _visMs = widget.player.position.inMilliseconds.toDouble();
    _visFrac = widget.player.progress;
    _lastReportedMs = widget.player.position.inMilliseconds;
  }

  @override
  void didUpdateWidget(_WaveformSeekBar old) {
    super.didUpdateWidget(old);
    if (old.dragging && !widget.dragging) {
      _visMs = widget.player.position.inMilliseconds.toDouble();
      _visFrac = widget.player.progress;
      _lastReportedMs = widget.player.position.inMilliseconds;
      _reportedAtMs = _clock.elapsedMicroseconds / 1000.0;
    }
    _syncTickerToPlaybackState();
  }

  void _syncTickerToPlaybackState() {
    final settled = _ampAnim <= 0.001 &&
        (_thumbFraction - (widget.dragging ? 1.0 : 0.0)).abs() <= 0.001;
    final shouldRun =
        (widget.player.isPlaying && !widget.dragging) || widget.dragging || !settled;
    if (shouldRun && !_ticker.isTicking) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    } else if (!shouldRun && _ticker.isTicking) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dtUs = (elapsed - _lastElapsed).inMicroseconds;
    _lastElapsed = elapsed;
    if (dtUs <= 0) return;
    final dt = (dtUs / 1e6).clamp(0.0, 0.05);

    final player = widget.player;
    final playing = player.isPlaying && !widget.dragging;

    if (playing || _ampAnim > 0.001) {
      _phase = (_phase + dt * _waveSpeed) % _wavelength;
    }

    if (!widget.dragging) {
      final durMs = player.duration.inMilliseconds;
      final nowMs = _clock.elapsedMicroseconds / 1000.0;
      final repMs = player.position.inMilliseconds;
      if (repMs != _lastReportedMs) {
        _lastReportedMs = repMs;
        _reportedAtMs = nowMs;
      }
      if (durMs > 0) {
        var posTarget = repMs.toDouble();
        if (playing) posTarget += (nowMs - _reportedAtMs).clamp(0.0, 600.0);
        posTarget = posTarget.clamp(0.0, durMs.toDouble());
        final err = posTarget - _visMs;
        if (err.abs() > 1500) {
          _visMs = posTarget;
        } else {
          _visMs += err * (1 - math.exp(-dt * 12));
        }
        _visFrac = (_visMs / durMs).clamp(0.0, 1.0);
      } else {
        _visMs = 0;
        _visFrac = 0;
      }
    }

    final ampTarget = playing ? 1.0 : 0.0;
    final nextAmp = _ampAnim + (ampTarget - _ampAnim) * (1 - math.exp(-dt * 6));

    final thumbTarget = widget.dragging ? 1.0 : 0.0;
    final nextThumb =
        _thumbFraction + (thumbTarget - _thumbFraction) * (1 - math.exp(-dt * 12));

    final ampSettled = (nextAmp - ampTarget).abs() <= 0.002 && !playing;
    final thumbSettled = (nextThumb - thumbTarget).abs() <= 0.002;

    if (playing || !ampSettled || !thumbSettled) {
      _ampAnim = nextAmp;
      _thumbFraction = nextThumb;
      _frame.value++;
    } else if (_ticker.isTicking) {
      _ampAnim = ampTarget;
      _thumbFraction = thumbTarget;
      _frame.value++;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncTickerToPlaybackState();
    final progress =
        widget.dragging ? (widget.dragValue ?? widget.player.progress) : widget.player.progress;
    if (!_ticker.isTicking && !widget.dragging) {
      _visFrac = widget.player.progress;
      _visMs = widget.player.position.inMilliseconds.toDouble();
      _lastReportedMs = widget.player.position.inMilliseconds;
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.hPad - 4),
      child: Column(children: [
        SizedBox(
          height: 32,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              void handleUpdate(Offset local) {
                final v = (local.dx / width).clamp(0.0, 1.0);
                widget.onDrag(v);
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
                  widget.onDragStart();
                  widget.onDrag(v);
                  widget.onDragEnd(v);
                },
                onHorizontalDragStart: (d) {
                  widget.onDragStart();
                  handleUpdate(d.localPosition);
                },
                onHorizontalDragUpdate: (d) => handleUpdate(d.localPosition),
                onHorizontalDragEnd: (_) => widget.onDragEnd(widget.dragValue ?? progress),
                onHorizontalDragCancel: () => widget.onDragEnd(widget.dragValue ?? progress),
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(width, 32),
                    painter: _WaveformPainter(
                      repaint: _frame,
                      live: () => (_phase, _ampAnim, _thumbFraction, _visFrac),
                      progress: progress,
                      activeColor: widget.activeColor,
                      inactiveColor: widget.inactiveColor,
                      wavelength: _wavelength,
                      dragging: widget.dragging,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.player.positionString,
                  style: TextStyle(
                      color: widget.timeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3)),
              if (widget.centerLabel != null) widget.centerLabel!,
              Text(widget.player.durationString,
                  style: TextStyle(
                      color: widget.timeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3)),
            ],
          ),
        ),
      ]),
    );
  }
}

const double _thumbAmpScale = 0.6;

class _WaveformPainter extends CustomPainter {
  final (double, double, double, double) Function() live;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double wavelength;
  final bool dragging;

  _WaveformPainter({
    required Listenable repaint,
    required this.live,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.wavelength,
    required this.dragging,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final (scrollX, ampAnim, thumbInteractionFraction, visProgress) = live();
    final centerY = size.height / 2;
    final shownProgress = dragging ? progress : visProgress;
    final progressX = (size.width * shownProgress).clamp(0.0, size.width);
    final maxAmp = size.height * 0.125;
    final k = (2 * math.pi) / wavelength;
    final f = thumbInteractionFraction;

    final idleGap = 5.0;
    final draggingGap = 11.0 + (maxAmp * ampAnim);
    final gap = idleGap + (draggingGap - idleGap) * f;

    final idleThumbSize = 8.0;
    final draggingThumbWidth = 4.0;
    final draggingThumbHeight = 20.0;
    final thumbWidth = idleThumbSize + (draggingThumbWidth - idleThumbSize) * f;
    final thumbHeight = idleThumbSize + (draggingThumbHeight - idleThumbSize) * f;

    final fadeZone = wavelength * 0.85;
    final waveEndX = (progressX - gap / 2).clamp(0.0, size.width);

    double edgeFadeAt(double x) {
      final t = ((progressX - x) / fadeZone).clamp(0.0, 1.0);
      return _thumbAmpScale + (1.0 - _thumbAmpScale) * t;
    }

    final activePath = Path();
    bool started = false;
    double yAt(double x) {
      final amp = maxAmp * ampAnim * edgeFadeAt(x) * (1.0 - f);
      return centerY + math.sin(k * (x - scrollX)) * amp;
    }

    double lastX = 0;
    for (double x = 0; x < waveEndX; x += 2) {
      final y = yAt(x);
      if (!started) {
        activePath.moveTo(x, y);
        started = true;
      } else {
        activePath.lineTo(x, y);
      }
      lastX = x;
    }
    if (waveEndX > 0 || started) {
      final yEnd = yAt(waveEndX);
      if (!started) {
        activePath.moveTo(waveEndX, yEnd);
        started = true;
      } else if (waveEndX > lastX) {
        activePath.lineTo(waveEndX, yEnd);
      }
    }

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (started) canvas.drawPath(activePath, activePaint);

    final trackStartX = (progressX + gap / 2).clamp(0.0, size.width);
    if (trackStartX + 4 < size.width) {
      final trackPaint = Paint()
        ..color = inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(trackStartX, centerY),
        Offset(size.width - 6, centerY),
        trackPaint,
      );
      canvas.drawCircle(
        Offset(size.width - 2, centerY),
        2.0,
        Paint()..color = inactiveColor,
      );
    }

    final waveHeadY = centerY +
        math.sin(k * (progressX - scrollX)) *
            (maxAmp * ampAnim * _thumbAmpScale * (1.0 - f));
    final headY = waveHeadY * (1.0 - f) + centerY * f;

    final thumbPaint = Paint()..color = activeColor;
    final rect = Rect.fromCenter(
      center: Offset(progressX, headY),
      width: thumbWidth,
      height: thumbHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(thumbWidth / 2)),
      thumbPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.dragging != dragging;
}

class _BufferedTrackShape extends RoundedRectSliderTrackShape {
  const _BufferedTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(context, offset,
        parentBox: parentBox,
        sliderTheme: sliderTheme,
        enableAnimation: enableAnimation,
        textDirection: textDirection,
        thumbCenter: thumbCenter,
        secondaryOffset: secondaryOffset,
        isDiscrete: isDiscrete,
        isEnabled: isEnabled,
        additionalActiveTrackHeight: additionalActiveTrackHeight);

    if (secondaryOffset != null) {
      final trackRect = getPreferredRect(
          parentBox: parentBox,
          offset: offset,
          sliderTheme: sliderTheme,
          isEnabled: isEnabled,
          isDiscrete: isDiscrete);
      final paint = Paint()
        ..color = Colors.white.withAlpha(40)
        ..style = PaintingStyle.fill;
      final bufferedRect = Rect.fromLTRB(
          trackRect.left, trackRect.top, secondaryOffset.dx, trackRect.bottom);
      context.canvas.drawRRect(
          RRect.fromRectAndRadius(bufferedRect, const Radius.circular(2)),
          paint);
    }
  }
}
