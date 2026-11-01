// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/material.dart';

class RouteDragDismiss {
  RouteDragDismiss(this.context);

  final BuildContext context;

  NavigatorState? _nav;
  AnimationController? _ctrl;
  bool _active = false;
  bool _lockHeld = false;
  AnimationStatusListener? _pending;

  bool get isActive => _active;

  double get _extent => MediaQuery.of(context).size.height;

  double get dragPx => _ctrl == null ? 0.0 : (1.0 - _ctrl!.value) * _extent;

  bool start() {
    if (_active) {
      _dropPending();
      return true;
    }
    final route = ModalRoute.of(context);
    // ignore: invalid_use_of_protected_member
    final ctrl = route?.controller;
    final nav = Navigator.maybeOf(context);
    if (route == null ||
        ctrl == null ||
        nav == null ||
        !route.isCurrent ||
        ctrl.status == AnimationStatus.reverse ||
        ctrl.status == AnimationStatus.dismissed) {
      return false;
    }
    _nav = nav;
    _ctrl = ctrl;
    _active = true;
    _lockHeld = true;
    nav.didStartUserGesture();
    return true;
  }

  void update(double deltaDown) {
    final c = _ctrl;
    if (!_active || c == null) return;
    c.value = (c.value - deltaDown / _extent).clamp(0.0, 1.0);
  }

  void end({
    required double velocityPxPerSec,
    required double dismissDistance,
    required double dismissVelocity,
  }) {
    final c = _ctrl;
    final nav = _nav;
    if (!_active || c == null || nav == null) return;
    _dropPending();

    final draggedPx = dragPx;
    final dismiss = draggedPx > dismissDistance ||
        (draggedPx > 24.0 && velocityPxPerSec > dismissVelocity);

    void onStatus(AnimationStatus s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        c.removeStatusListener(onStatus);
        if (identical(_pending, onStatus)) _pending = null;
        _stopLock();
        if (!dismiss) _finish();
      }
    }

    if (dismiss) {
      _pending = onStatus;
      c.addStatusListener(onStatus);
      _finish(keepLock: true);
      nav.pop();
    } else {
      final flingV = -velocityPxPerSec / _extent;
      if (c.isCompleted) {
        _stopLock();
        _finish();
        return;
      }
      _pending = onStatus;
      c.addStatusListener(onStatus);
      if (flingV > 0.05) {
        c.fling(velocity: flingV);
      } else {
        c.animateTo(1.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic);
      }
    }
  }

  void cancel() {
    _dropPending();
    final c = _ctrl;
    if (_active && c != null && !c.isCompleted &&
        c.status != AnimationStatus.reverse) {
      try {
        c.animateTo(1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic);
      } catch (_) {}
    }
    _stopLock();
    _finish();
  }

  void _dropPending() {
    final l = _pending;
    if (l != null) {
      _ctrl?.removeStatusListener(l);
      _pending = null;
    }
  }

  void _stopLock() {
    if (!_lockHeld) return;
    _lockHeld = false;
    _nav?.didStopUserGesture();
  }

  void _finish({bool keepLock = false}) {
    _active = false;
    if (!keepLock) {
      _nav = null;
      _ctrl = null;
    }
  }
}

Animation<double> routeDragCurve(
  BuildContext context,
  Animation<double> parent, {
  Curve curve = Curves.easeOutCubic,
}) {
  final nav = Navigator.maybeOf(context);
  return CurvedAnimation(
    parent: parent,
    curve: _LinearWhileGesture(nav, curve),
  );
}

class _LinearWhileGesture extends Curve {
  const _LinearWhileGesture(this._nav, this._curve);
  final NavigatorState? _nav;
  final Curve _curve;

  @override
  double transformInternal(double t) =>
      (_nav?.userGestureInProgress ?? false) ? t : _curve.transform(t);
}

class PullDismissScrollPhysics extends ClampingScrollPhysics {
  const PullDismissScrollPhysics({required this.isLocked, super.parent});

  final bool Function() isLocked;

  @override
  PullDismissScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      PullDismissScrollPhysics(
          isLocked: isLocked, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      isLocked() ? 0.0 : super.applyPhysicsToUserOffset(position, offset);
}

class PullDownDismissController {
  PullDownDismissController() {
    physics = PullDismissScrollPhysics(
      isLocked: () => active,
      parent: const AlwaysScrollableScrollPhysics(),
    );
  }

  bool active = false;

  late final ScrollPhysics physics;
}

class PullDownDismiss extends StatefulWidget {
  const PullDownDismiss({
    super.key,
    required this.controller,
    required this.scrollController,
    required this.child,
    this.dismissDistance = 120.0,
    this.dismissVelocity = 900.0,
  });

  final PullDownDismissController controller;
  final ScrollController scrollController;
  final Widget child;
  final double dismissDistance;
  final double dismissVelocity;

  static int ignorePointer = -1;

  @override
  State<PullDownDismiss> createState() => _PullDownDismissState();
}

class _PullDownDismissState extends State<PullDownDismiss> {
  late final RouteDragDismiss _dismiss;
  VelocityTracker? _tracker;
  int _pointer = -1;
  bool _ignored = false;
  bool _dead = false;
  double _ax = 0;
  double _ay = 0;

  static const double _slop = 8.0;

  @override
  void initState() {
    super.initState();
    _dismiss = RouteDragDismiss(context);
  }

  @override
  void dispose() {
    _dismiss.cancel();
    widget.controller.active = false;
    super.dispose();
  }

  bool get _atTop {
    final sc = widget.scrollController;
    return !sc.hasClients ||
        sc.position.pixels <= sc.position.minScrollExtent + 0.5;
  }

  void _reset() {
    _pointer = -1;
    _tracker = null;
    _ignored = false;
    _dead = false;
    _ax = 0;
    _ay = 0;
  }

  void _down(PointerDownEvent e) {
    if (_pointer != -1) return;
    _reset();
    _pointer = e.pointer;
    _ignored = PullDownDismiss.ignorePointer == e.pointer;
    _tracker = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _ignored) return;
    _tracker?.addPosition(e.timeStamp, e.position);
    final dy = e.delta.dy;

    if (_dismiss.isActive) {
      widget.controller.active = true;
      _dismiss.update(dy);
      return;
    }
    if (_dead) return;

    _ax += e.delta.dx.abs();
    if (!_atTop || dy < 0) {
      _ay = 0;
      return;
    }
    _ay += dy;
    if (_ax > 18 && _ax > _ay) {
      _dead = true;
      return;
    }
    if (_ay >= _slop && _ay > _ax * 1.5) {
      if (!_dismiss.start()) {
        _dead = true;
        return;
      }
      widget.controller.active = true;
      _dismiss.update(_ay);
    }
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    if (_dismiss.isActive) {
      final v = _tracker?.getVelocity().pixelsPerSecond.dy ?? 0.0;
      _dismiss.end(
        velocityPxPerSec: v,
        dismissDistance: widget.dismissDistance,
        dismissVelocity: widget.dismissVelocity,
      );
    }
    widget.controller.active = false;
    _reset();
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    if (_dismiss.isActive) _dismiss.cancel();
    widget.controller.active = false;
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: widget.child,
      ),
    );
  }
}
