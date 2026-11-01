// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AurumFocusField extends StatefulWidget {
  final Widget Function(FocusNode focusNode) builder;
  final Object? refocusSignal;

  const AurumFocusField({
    super.key,
    required this.builder,
    this.refocusSignal,
  });

  @override
  State<AurumFocusField> createState() => _AurumFocusFieldState();
}

class _AurumFocusFieldState extends State<AurumFocusField> {
  final _focusNode = FocusNode();
  bool _didInitialFocus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleInitialFocus());
  }

  void _scheduleInitialFocus() {
    if (!mounted || _didInitialFocus) return;
    final route = ModalRoute.of(context);
    final animation = route?.animation;

    if (animation == null || animation.status == AnimationStatus.completed) {
      _requestFocusAndShowKeyboard();
      return;
    }

    void onStatusChange(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(onStatusChange);
        _requestFocusAndShowKeyboard();
      }
    }

    animation.addStatusListener(onStatusChange);

    Future.delayed(const Duration(milliseconds: 500), () {
      animation.removeStatusListener(onStatusChange);
      if (mounted && !_didInitialFocus) _requestFocusAndShowKeyboard();
    });
  }

  void _requestFocusAndShowKeyboard() {
    if (!mounted) return;
    _didInitialFocus = true;
    _focusNode.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      }
    });
  }

  @override
  void didUpdateWidget(AurumFocusField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refocusSignal != oldWidget.refocusSignal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNode.requestFocus();
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_focusNode);
}
