// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'premium_gate.dart';
import '../services/feedback_service.dart';
import '../theme/aurum_theme.dart';
import 'aurum_focus_field.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_motion.dart';

Future<void> showFeedbackDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    barrierDismissible: false,
    builder: (_) => const _FeedbackDialog(),
  );
}

class _FeedbackDialog extends StatefulWidget {
  const _FeedbackDialog();

  @override
  State<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<_FeedbackDialog>
    with SingleTickerProviderStateMixin {
  int _rating = 0;
  final _controller = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;
  bool _spamWarn = false;

  late final AnimationController _iconCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_rating == 0 || _sending) return;
    FocusScope.of(context).unfocus();

    final problem = await FeedbackService.screen(_controller.text);
    if (!mounted) return;
    if (problem != null) {
      AurumHaptics.selection();
      setState(() => _error = problem);
      return;
    }

    final signedIn = await PremiumGate.ensureSignedIn(
      context,
      feature: 'Feedback',
      description:
          'Sign in with Google to send your feedback.\nIt takes just a moment.',
    );
    if (!mounted) return;
    if (!signedIn) return;

    final auth = context.read<AuthProvider>();
    setState(() {
      _error = null;
      _sending = true;
    });

    String? version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}

    final sendFuture = FeedbackService.submit(
      rating: _rating,
      userId: auth.userId,
      userEmail: auth.email,
      message: _controller.text,
      appVersion: version,
    );
    final results = await Future.wait<dynamic>([
      sendFuture,
      Future.delayed(const Duration(milliseconds: 600)),
    ]);

    if (!mounted) return;
    if (results.first != true) {
      setState(() {
        _sending = false;
        _error = 'Could not send. Check your connection and try again.';
      });
      return;
    }
    final warn = await FeedbackService.recordSendAndCheckSpam();
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = true;
      _spamWarn = warn;
    });

    await Future.delayed(Duration(milliseconds: warn ? 3200 : 1400));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxDialogHeight =
        MediaQuery.of(context).size.height - bottomInset - 48;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxDialogHeight > 0 ? maxDialogHeight : double.infinity,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white)
                    .withValues(alpha: isDark ? 0.55 : 0.85),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: AurumMotion.durationOrZero(AurumMotion.long1),
                    child: _sent ? _buildThankYou(context) : _buildForm(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      key: const ValueKey('form'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _AurumBrandMark(controller: _iconCtrl),
        const SizedBox(height: 18),
        Text(
          'Enjoying Astra?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your feedback helps us make it even better.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.65),
              ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final filled = i < _rating;
            return GestureDetector(
              onTap: () {
                AurumHaptics.selection();
                setState(() => _rating = i + 1);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('star_$i${filled}'),
                  tween: Tween(begin: filled ? 1.3 : 1.0, end: 1.0),
                  duration: AurumMotion.durationOrZero(AurumMotion.medium2),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 36,
                    color: filled
                        ? AurumTheme.accentOf(context)
                        : Theme.of(context)
                            .iconTheme
                            .color
                            ?.withValues(alpha: 0.3),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
        AurumFocusField(
          builder: (focusNode) => TextField(
            controller: _controller,
            focusNode: focusNode,
            maxLines: 3,
            minLines: 2,
            maxLength: FeedbackService.maxMessageLength,
            buildCounter: (_,
                    {required currentLength, required isFocused, maxLength}) =>
                null,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Tell us what\'s on your mind (optional)',
              hintStyle: TextStyle(
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.4),
                fontSize: 13,
              ),
              filled: true,
              fillColor: (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black)
                  .withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _rating == 0 || _sending ? null : _send,
            style: ElevatedButton.styleFrom(
              backgroundColor: AurumTheme.accentOf(context),
              disabledBackgroundColor:
                  AurumTheme.accentOf(context).withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _sending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Send Feedback',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Not now',
            style: TextStyle(
              color: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.color
                  ?.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThankYou(BuildContext context) {
    return Column(
      key: const ValueKey('thanks'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AurumTheme.accentOf(context).withValues(alpha: 0.95),
                AurumTheme.accentOf(context).withValues(alpha: 0.6),
              ],
            ),
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 20),
        Text(
          'Thank you!',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your feedback means a lot to us —\nwe\'re always working to improve\nyour experience.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.7),
                height: 1.4,
              ),
        ),
        if (_spamWarn) ...[
          const SizedBox(height: 14),
          const Text(
            FeedbackService.spamWarning,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _AurumBrandMark extends StatefulWidget {
  final AnimationController controller;
  const _AurumBrandMark({required this.controller});

  @override
  State<_AurumBrandMark> createState() => _AurumBrandMarkState();
}

class _AurumBrandMarkState extends State<_AurumBrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pop = CurvedAnimation(
      parent: widget.controller,
      curve: Curves.elasticOut,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([pop, _breathCtrl]),
      builder: (context, _) {
        final breath = 0.5 + (_breathCtrl.value * 0.5);
        return Transform.scale(
          scale: pop.value,
          child: SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AurumTheme.accentOf(context)
                            .withValues(alpha: 0.35 * breath),
                        blurRadius: 22,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AurumTheme.accentLightOf(context),
                        AurumTheme.accentOf(context),
                        AurumTheme.accentDarkOf(context),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
