// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../services/audio_prefs.dart';
import '../theme/aurum_theme.dart';
import 'aurum_motion.dart';

class _EdgeSwipeBack extends StatefulWidget {
  const _EdgeSwipeBack({
    required this.animationController,
    required this.child,
  });

  final AnimationController animationController;
  final Widget child;

  @override
  State<_EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<_EdgeSwipeBack> with WidgetsBindingObserver {
  static const double _edgeWidth = 24.0;
  double? _dragStartX;
  bool _dragging = false;

  static const Duration _staleDragTimeout = Duration(milliseconds: 120);
  DateTime? _lastDragUpdate;

  void _watchdogTick(Duration _) {
    if (!_dragging || _lastDragUpdate == null) return;
    if (DateTime.now().difference(_lastDragUpdate!) > _staleDragTimeout) {
      _dragging = false;
      widget.animationController.value = 1.0;
      return;
    }
    WidgetsBinding.instance.scheduleFrameCallback(_watchdogTick);
  }

  bool get _enabled =>
      AurumMotion.enabled && AudioPrefs.backAnimations;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.detached) &&
        _dragging) {
      _dragging = false;
      _lastDragUpdate = null;
      widget.animationController.value = 1.0;
    }
  }

  @override
  void dispose() {
    if (_dragging) {
      widget.animationController.value = 1.0;
    }
    _dragging = false;
    _lastDragUpdate = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    if (!_enabled) return;
    if (details.globalPosition.dx > _edgeWidth) return;
    if (!Navigator.of(context).canPop()) return;
    _dragStartX = details.globalPosition.dx;
    _dragging = true;
    _lastDragUpdate = DateTime.now();
    _dragWidth = MediaQuery.of(context).size.width;
    WidgetsBinding.instance.scheduleFrameCallback(_watchdogTick);
  }

  double? _dragWidth;

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _lastDragUpdate = DateTime.now();
    final width = _dragWidth;
    if (width == null || width <= 0) return;
    final dragFraction = (details.globalPosition.dx - _dragStartX!) / width;
    final newValue = (1.0 - dragFraction).clamp(0.0, 1.0);
    widget.animationController.value = newValue;
  }

  void _onDragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _lastDragUpdate = null;
    final remaining = 1.0 - widget.animationController.value;
    final settleMs = (AurumMotion.medium2.inMilliseconds * remaining)
        .clamp(80.0, AurumMotion.medium2.inMilliseconds.toDouble())
        .round();
    widget.animationController.animateTo(1.0,
        duration: Duration(milliseconds: settleMs),
        curve: AurumMotion.standard);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    _lastDragUpdate = null;
    final navigator = Navigator.of(context);
    final velocity = details.velocity.pixelsPerSecond.dx;
    final shouldPop = widget.animationController.value < 0.6 || velocity > 600;
    final remaining = shouldPop
        ? widget.animationController.value
        : (1.0 - widget.animationController.value);
    final settleMs = (AurumMotion.medium2.inMilliseconds * remaining)
        .clamp(80.0, AurumMotion.medium2.inMilliseconds.toDouble())
        .round();
    if (shouldPop) {
      widget.animationController
          .animateBack(0.0,
              duration: Duration(milliseconds: settleMs),
              curve: AurumMotion.standardReverse)
          .whenComplete(() {
        if (navigator.canPop()) navigator.pop();
      });
    } else {
      widget.animationController.animateTo(1.0,
          duration: Duration(milliseconds: settleMs),
          curve: AurumMotion.standard);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          () => HorizontalDragGestureRecognizer(),
          (instance) {
            instance
              ..onStart = _onDragStart
              ..onUpdate = _onDragUpdate
              ..onEnd = _onDragEnd
              ..onCancel = _onDragCancel;
          },
        ),
      },
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

class AurumPageRoute<T> extends PageRouteBuilder<T> {
  AurumPageRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
    bool enableEdgeSwipeBack = true,
  }) : super(
          settings: settings,
          fullscreenDialog: fullscreenDialog,
          opaque: true,
          transitionDuration: _animsOn()
              ? AurumMotion.medium2
              : Duration.zero,
          reverseTransitionDuration: _animsOn()
              ? AurumMotion.medium2
              : Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (!_animsOn()) return child;

            final curved = CurvedAnimation(
              parent: animation,
              curve: AurumMotion.standard,
              reverseCurve: AurumMotion.standardReverse,
            );

            final secondaryCurved = CurvedAnimation(
              parent: secondaryAnimation,
              curve: AurumMotion.standard,
            );

            final content = ColoredBox(
              color: AurumTheme.bgOf(context),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset.zero,
                    end: const Offset(-0.30, 0),
                  ).animate(secondaryCurved),
                  child: FadeTransition(
                    opacity: Tween<double>(begin: 1.0, end: 0.85)
                        .animate(secondaryCurved),
                    child: child,
                  ),
                ),
              ),
            );

            final routeController = ModalRoute.of(context)?.controller;
            if (routeController == null) return content;
            if (!enableEdgeSwipeBack) return content;
            return _EdgeSwipeBack(
              animationController: routeController,
              child: content,
            );
          },
        );

  static bool _animsOn() =>
      AurumMotion.enabled && AudioPrefs.backAnimations;

  static Future<T?> to<T extends Object?>(
    BuildContext context,
    Widget screen, {
    bool fullscreenDialog = false,
    bool enableEdgeSwipeBack = true,
  }) {
    return Navigator.of(context).push<T>(
      AurumPageRoute<T>(
        builder: (_) => screen,
        fullscreenDialog: fullscreenDialog,
        enableEdgeSwipeBack: enableEdgeSwipeBack,
      ),
    );
  }

  static Future<T?> replace<T extends Object?, TO extends Object?>(
    BuildContext context,
    Widget screen,
  ) {
    return Navigator.of(context).pushReplacement<T, TO>(
      AurumPageRoute<T>(builder: (_) => screen),
    );
  }
}

class AurumSlidePageRoute<T> extends PageRouteBuilder<T> {
  AurumSlidePageRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) : super(
          settings: settings,
          fullscreenDialog: fullscreenDialog,
          opaque: true,
          transitionDuration: _animsOn()
              ? AurumMotion.long1
              : Duration.zero,
          reverseTransitionDuration: _animsOn()
              ? AurumMotion.long1
              : Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (!_animsOn()) return child;

            final curved = CurvedAnimation(
              parent: animation,
              curve: AurumMotion.standard,
              reverseCurve: AurumMotion.standardReverse,
            );
            final secondaryCurved = CurvedAnimation(
              parent: secondaryAnimation,
              curve: AurumMotion.standard,
            );

            return ColoredBox(
              color: AurumTheme.bgOf(context),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset.zero,
                      end: const Offset(-0.06, 0),
                    ).animate(secondaryCurved),
                    child: FadeTransition(
                      opacity: Tween<double>(begin: 1.0, end: 0.92).animate(
                        secondaryCurved,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            );
          },
        );

  static bool _animsOn() =>
      AurumMotion.enabled && AudioPrefs.backAnimations;

  static Future<T?> to<T extends Object?>(
    BuildContext context,
    Widget screen, {
    bool fullscreenDialog = false,
  }) {
    return Navigator.of(context).push<T>(
      AurumSlidePageRoute<T>(
        builder: (_) => screen,
        fullscreenDialog: fullscreenDialog,
      ),
    );
  }
}

class AurumModalRoute<T> extends PageRouteBuilder<T> {
  AurumModalRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          opaque: true,
          transitionDuration: _animsOn()
              ? AurumMotion.long1
              : Duration.zero,
          reverseTransitionDuration: _animsOn()
              ? AurumMotion.long1
              : Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (!_animsOn()) return child;
            final curved = CurvedAnimation(
              parent: animation,
              curve: AurumMotion.standard,
              reverseCurve: AurumMotion.standardReverse,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );

  static bool _animsOn() =>
      AurumMotion.enabled && AudioPrefs.backAnimations;

  static Future<T?> to<T extends Object?>(BuildContext context, Widget screen) {
    return Navigator.of(context).push<T>(
      AurumModalRoute<T>(builder: (_) => screen),
    );
  }
}

class AurumDepthRoute<T> extends PageRouteBuilder<T> {
  AurumDepthRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) : super(
          settings: settings,
          fullscreenDialog: fullscreenDialog,
          opaque: true,
          transitionDuration: _animsOn()
              ? const Duration(milliseconds: 300)
              : Duration.zero,
          reverseTransitionDuration: _animsOn()
              ? const Duration(milliseconds: 300)
              : Duration.zero,
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (!_animsOn()) return child;

            final incomingFade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            final incomingSlide = Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ));

            final recedeFade = Tween<double>(begin: 1.0, end: 0.85).animate(
              CurvedAnimation(
                parent: secondaryAnimation,
                curve: Curves.easeInCubic,
              ),
            );

            return FadeTransition(
              opacity: recedeFade,
              child: FadeTransition(
                opacity: incomingFade,
                child: SlideTransition(
                  position: incomingSlide,
                  child: RepaintBoundary(child: child),
                ),
              ),
            );
          },
        );

  static bool _animsOn() =>
      AurumMotion.enabled && AudioPrefs.backAnimations;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final content = super.buildTransitions(
        context, animation, secondaryAnimation, child);
    if (!_animsOn()) return content;
    final routeController = controller;
    if (routeController == null) return content;
    return _EdgeSwipeBack(
      animationController: routeController,
      child: content,
    );
  }

  static Future<T?> to<T extends Object?>(
    BuildContext context,
    Widget screen, {
    bool fullscreenDialog = false,
  }) {
    return Navigator.of(context).push<T>(
      AurumDepthRoute<T>(
        builder: (_) => screen,
        fullscreenDialog: fullscreenDialog,
      ),
    );
  }
}
