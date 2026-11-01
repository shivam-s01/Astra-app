// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class FadedHorizontalList extends StatefulWidget {
  final Widget child;
  final double height;

  final double fadeWidth;

  final bool fadeLeft;

  final ScrollController? controller;

  const FadedHorizontalList({
    super.key,
    required this.child,
    required this.height,
    this.fadeWidth = 20,
    this.fadeLeft = true,
    this.controller,
  });

  @override
  State<FadedHorizontalList> createState() => _FadedHorizontalListState();
}

class _FadedHorizontalListState extends State<FadedHorizontalList> {
  bool _showLeft = false;
  bool _showRight = false;
  ScrollController? _ownedController;

  ScrollController get _controller =>
      widget.controller ?? (_ownedController ??= ScrollController());

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      widget.controller!.addListener(_onScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
    } else {
      _showLeft = widget.fadeLeft;
      _showRight = true;
    }
  }

  void _onScroll() {
    if (!mounted) return;
    final c = widget.controller!;
    if (!c.hasClients) return;
    const noScrollThreshold = 4.0;
    final hasRoomToScroll =
        c.position.maxScrollExtent > noScrollThreshold;
    final atStart = c.offset <= c.position.minScrollExtent + 0.5;
    final atEnd = !hasRoomToScroll ||
        c.offset >= c.position.maxScrollExtent - 0.5;
    final newLeft = widget.fadeLeft && hasRoomToScroll && !atStart;
    final newRight = hasRoomToScroll && !atEnd;
    if (newLeft != _showLeft || newRight != _showRight) {
      setState(() {
        _showLeft = newLeft;
        _showRight = newRight;
      });
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onScroll);
    _ownedController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: widget.height, child: widget.child);
  }
}
