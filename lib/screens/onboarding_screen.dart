// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/api_service.dart';
import '../services/recommendation_engine.dart';
import '../theme/aurum_theme.dart';
import '../utils/aurum_haptics.dart';
import '../config/region_catalog.dart';
import '../services/user_region.dart';
import '../services/artist_picker_loader.dart';
import '../services/aurum_image_cache.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  Country? _selectedCountry;
  final Set<String> _selectedGenres = {};
  final Set<String> _selectedArtists = {};

  bool _detectedAutomatically = false;
  bool _detecting = false;
  bool _detectionFailed = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _runDetection() async {
    setState(() {
      _detecting = true;
      _detectionFailed = false;
    });
    final detected = await detectCountryReal();
    if (!mounted) return;
    setState(() {
      _detecting = false;
      if (detected != null) {
        _selectedCountry = detected;
        _detectedAutomatically = true;
      } else {
        _detectionFailed = true;
      }
    });
  }

  void _goToStep(int step) {
    AurumHaptics.medium();
    setState(() => _step = step);
  }

  Future<void> _finish() async {
    try {
      if (_selectedGenres.isNotEmpty) {
        await RecommendationEngine.applyOnboardingGenrePreferences(
          _selectedGenres.toList(),
        );
      }
      if (_selectedArtists.isNotEmpty) {
        await RecommendationEngine.applyOnboardingArtistPreferences(
          _selectedArtists.toList(),
        );
      }
    } catch (_) {
    }

    var confirmed = false;
    for (var attempt = 0; attempt < 3 && !confirmed; attempt++) {
      try {
        final p = await SharedPreferences.getInstance();
        if (_selectedCountry != null) {
          await p.setString('onboarding_country_code', _selectedCountry!.code);
          await p.setString('onboarding_country_name', _selectedCountry!.name);
          UserRegion.update(_selectedCountry!.code, _selectedCountry!.name);
        }
        await p.setBool('onboarding_complete', true);
        confirmed = p.getBool('onboarding_complete') == true;
      } catch (_) {
        confirmed = false;
      }
      if (!confirmed && attempt < 2) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: switch (_step) {
            0 => _CountryStep(
                key: const ValueKey('country'),
                selected: _selectedCountry,
                autoDetected: _detectedAutomatically && _selectedCountry != null,
                detecting: _detecting,
                detectionFailed: _detectionFailed,
                onAutoDetect: _runDetection,
                onSelect: (c) => setState(() {
                  _selectedCountry = c;
                  _detectedAutomatically = false;
                  _detecting = false;
                  _detectionFailed = false;
                }),
                onNext: () => _goToStep(1),
              ),
            1 => _GenreStep(
                key: const ValueKey('genres'),
                country: _selectedCountry,
                selected: _selectedGenres,
                onToggle: (key) => setState(() {
                  if (!_selectedGenres.remove(key)) _selectedGenres.add(key);
                }),
                onBack: () => _goToStep(0),
                onNext: () => _goToStep(2),
              ),
            _ => _ArtistStep(
                key: const ValueKey('artists'),
                country: _selectedCountry,
                genres: _selectedGenres,
                selected: _selectedArtists,
                onToggle: (name) => setState(() {
                  if (!_selectedArtists.remove(name)) _selectedArtists.add(name);
                }),
                onBack: () => _goToStep(1),
                onFinish: _finish,
              ),
          },
        ),
      ),
    );
  }
}

class _CountryStep extends StatefulWidget {
  final Country? selected;
  final bool autoDetected;
  final bool detecting;
  final bool detectionFailed;
  final VoidCallback onAutoDetect;
  final ValueChanged<Country> onSelect;
  final VoidCallback onNext;

  const _CountryStep({
    super.key,
    required this.selected,
    required this.autoDetected,
    required this.detecting,
    required this.detectionFailed,
    required this.onAutoDetect,
    required this.onSelect,
    required this.onNext,
  });

  @override
  State<_CountryStep> createState() => _CountryStepState();
}

class _CountryStepState extends State<_CountryStep> {
  String _query = '';
  bool _showManualList = false;

  @override
  void didUpdateWidget(covariant _CountryStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justFinishedDetecting = oldWidget.detecting && !widget.detecting;
    if (justFinishedDetecting && widget.detectionFailed) {
      _showManualList = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AurumTheme.accentOf(context);
    final filtered = _query.isEmpty
        ? kCountries
        : kCountries
            .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final showDetectedBanner = widget.autoDetected && widget.selected != null && !_showManualList;
    final showScanning = widget.detecting && !_showManualList;
    final showChoice = !showScanning && !showDetectedBanner && !_showManualList;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepDots(activeIndex: 0, total: 3),
          const SizedBox(height: 20),
          Text(
            'Where are you\nlistening from?',
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.5,
              color: AurumTheme.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Helps us pick the right genres, charts and artists for you.',
            style: TextStyle(
              fontSize: 14,
              color: AurumTheme.textMutedOf(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          if (showChoice) ...[
            Expanded(
              child: _CountryChoiceView(
                accent: accent,
                onAutoDetect: widget.onAutoDetect,
                onSearchManually: () => setState(() => _showManualList = true),
              ),
            ),
          ] else if (showScanning) ...[
            _ScanningLocationCard(
              accent: accent,
              onChooseManually: () => setState(() => _showManualList = true),
            ),
            const Spacer(),
          ] else if (showDetectedBanner) ...[
            _DetectedCountryCard(
              country: widget.selected!,
              accent: accent,
              onChangeTap: () => setState(() => _showManualList = true),
            ),
            const Spacer(),
          ] else ...[
            if (widget.detectionFailed) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AurumTheme.bgCardOf(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AurumTheme.dividerOf(context)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: AurumTheme.textMutedOf(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Couldn't detect automatically — pick your country below.",
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AurumTheme.textMutedOf(context),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            _SearchField(
              hint: 'Search countries',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No countries match "$_query"',
                        style: TextStyle(color: AurumTheme.textMutedOf(context)),
                      ),
                    )
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        thickness: 0.5,
                        color: AurumTheme.dividerOf(context),
                      ),
                      itemBuilder: (context, i) {
                        final country = filtered[i];
                        final isSelected = widget.selected?.code == country.code;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              AurumHaptics.selection();
                              widget.onSelect(country);
                            },
                            splashFactory: NoSplash.splashFactory,
                            highlightColor: accent.withValues(alpha: 0.06),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 12),
                              child: Row(
                                children: [
                                  Text(country.flag,
                                      style: const TextStyle(fontSize: 24)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      country.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? accent
                                            : AurumTheme.textPrimaryOf(context),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(Icons.check_circle_rounded,
                                        color: accent, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
          const SizedBox(height: 12),
          if (!showChoice)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: showScanning ? null : widget.onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: accent.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  showScanning
                      ? 'Detecting...'
                      : widget.selected == null
                          ? 'Skip for now'
                          : 'Continue',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CountryChoiceView extends StatelessWidget {
  final Color accent;
  final VoidCallback onAutoDetect;
  final VoidCallback onSearchManually;

  const _CountryChoiceView({
    required this.accent,
    required this.onAutoDetect,
    required this.onSearchManually,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.public_rounded, color: accent.withValues(alpha: 0.7), size: 56),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () {
              AurumHaptics.medium();
              onAutoDetect();
            },
            icon: const Icon(Icons.my_location_rounded, size: 20),
            label: const Text(
              'Auto-Detect My Country',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Takes 1-3 seconds — uses your network,\nnot GPS.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: AurumTheme.textMutedOf(context),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: AurumTheme.dividerOf(context))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'OR',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AurumTheme.textMutedOf(context),
                ),
              ),
            ),
            Expanded(child: Divider(color: AurumTheme.dividerOf(context))),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton.icon(
            onPressed: () {
              AurumHaptics.selection();
              onSearchManually();
            },
            icon: Icon(Icons.search_rounded, size: 20, color: AurumTheme.textPrimaryOf(context)),
            label: Text(
              'Search Manually',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: AurumTheme.textPrimaryOf(context),
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AurumTheme.dividerOf(context)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanningLocationCard extends StatefulWidget {
  final Color accent;
  final VoidCallback onChooseManually;

  const _ScanningLocationCard({
    required this.accent,
    required this.onChooseManually,
  });

  @override
  State<_ScanningLocationCard> createState() => _ScanningLocationCardState();
}

class _ScanningLocationCardState extends State<_ScanningLocationCard>
    with TickerProviderStateMixin {
  late final AnimationController _sweep;
  late final AnimationController _pulse;
  late final AnimationController _entrance;
  late final AnimationController _progress;
  late final AnimationController _shimmer;

  static const List<String> _statusMessages = [
    'Scanning your network...',
    'Pinpointing your region...',
    'Almost there...',
  ];
  int _statusIndex = 0;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _progress = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    )..forward();

    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _statusTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (!mounted) return;
      setState(() => _statusIndex = (_statusIndex + 1) % _statusMessages.length);
    });
  }

  @override
  void dispose() {
    _sweep.dispose();
    _pulse.dispose();
    _entrance.dispose();
    _progress.dispose();
    _shimmer.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = AurumTheme.bgCardOf(context);
    final border = AurumTheme.dividerOf(context);

    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_entrance.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: 1),
        ),
        child: Column(
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: AnimatedBuilder(
                animation: Listenable.merge([_sweep, _pulse]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _RadarPainter(
                      sweepAngle: _sweep.value * 2 * 3.14159265,
                      pulseValue: _pulse.value,
                      accent: widget.accent,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.location_on_rounded,
                        color: widget.accent,
                        size: 28,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                _statusMessages[_statusIndex],
                key: ValueKey(_statusIndex),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AurumTheme.textPrimaryOf(context),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Finding the country closest to your\nactual network for accurate results.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: AurumTheme.textMutedOf(context),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 6,
              child: AnimatedBuilder(
                animation: Listenable.merge([_progress, _shimmer]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _LoadingBarPainter(
                      fill: Curves.easeOutCubic.transform(_progress.value) * 0.92,
                      shimmer: _shimmer.value,
                      accent: widget.accent,
                      track: border,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: widget.onChooseManually,
              style: TextButton.styleFrom(
                foregroundColor: widget.accent,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: const Text(
                'Choose manually instead',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBarPainter extends CustomPainter {
  final double fill;
  final double shimmer;
  final Color accent;
  final Color track;

  _LoadingBarPainter({
    required this.fill,
    required this.shimmer,
    required this.accent,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);

    final trackPaint = Paint()..color = track.withValues(alpha: 0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      trackPaint,
    );

    final fillWidth = size.width * fill.clamp(0.0, 1.0);
    if (fillWidth <= 0) return;

    final fillRect = Rect.fromLTWH(0, 0, fillWidth, size.height);
    final fillRRect = RRect.fromRectAndRadius(fillRect, radius);

    canvas.save();
    canvas.clipRRect(fillRRect);
    canvas.drawRect(fillRect, Paint()..color = accent.withValues(alpha: 0.85));

    final shimmerCenter = fillWidth * shimmer;
    final shimmerWidth = size.width * 0.35;
    final shimmerRect = Rect.fromLTWH(
      shimmerCenter - shimmerWidth / 2,
      0,
      shimmerWidth,
      size.height,
    );
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.55),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(shimmerRect);
    canvas.drawRect(shimmerRect, shimmerPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LoadingBarPainter oldDelegate) {
    return oldDelegate.fill != fill ||
        oldDelegate.shimmer != shimmer ||
        oldDelegate.accent != accent ||
        oldDelegate.track != track;
  }
}

class _RadarPainter extends CustomPainter {
  final double sweepAngle;
  final double pulseValue;
  final Color accent;

  _RadarPainter({
    required this.sweepAngle,
    required this.pulseValue,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final ringPaint = Paint()
      ..color = accent.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(center, maxRadius * 0.98, ringPaint);
    canvas.drawCircle(center, maxRadius * 0.66, ringPaint);
    canvas.drawCircle(center, maxRadius * 0.34, ringPaint);

    for (final offset in [0.0, 0.5]) {
      final progress = (pulseValue + offset) % 1.0;
      final radius = maxRadius * (0.25 + progress * 0.75);
      final opacity = (1.0 - progress).clamp(0.0, 1.0) * 0.35;
      final pulsePaint = Paint()
        ..color = accent.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, pulsePaint);
    }

    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 3.14159265 / 2,
        colors: [
          accent.withValues(alpha: 0.0),
          accent.withValues(alpha: 0.35),
        ],
        transform: GradientRotation(sweepAngle),
      ).createShader(sweepRect);
    canvas.drawCircle(center, maxRadius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.accent != accent;
  }
}

class _DetectedCountryCard extends StatefulWidget {
  final Country country;
  final Color accent;
  final VoidCallback onChangeTap;

  const _DetectedCountryCard({
    required this.country,
    required this.accent,
    required this.onChangeTap,
  });

  @override
  State<_DetectedCountryCard> createState() => _DetectedCountryCardState();
}

class _DetectedCountryCardState extends State<_DetectedCountryCard>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _ping;

  late final Animation<double> _cardFade;
  late final Animation<double> _cardSlide;
  late final Animation<double> _cardScale;
  late final Animation<double> _flagScale;
  late final Animation<double> _labelFade;
  late final Animation<double> _labelSlide;
  late final Animation<double> _nameFade;
  late final Animation<double> _nameSlide;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _cardFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _cardSlide = Tween<double>(begin: 18, end: 0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
      ),
    );
    _cardScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _flagScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.25, 0.85, curve: Curves.elasticOut),
      ),
    );

    _labelFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.35, 0.7, curve: Curves.easeOut),
    );
    _labelSlide = Tween<double>(begin: -8, end: 0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.35, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _nameFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
    );
    _nameSlide = Tween<double>(begin: 10, end: 0).animate(
      CurvedAnimation(
        parent: _entrance,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOutCubic),
      ),
    );

    _ping = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _entrance.forward();
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _ping.forward();
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entrance,
      builder: (context, child) {
        return Opacity(
          opacity: _cardFade.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, _cardSlide.value),
            child: Transform.scale(
              scale: _cardScale.value,
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: widget.accent.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, _) => Opacity(
                opacity: _labelFade.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(_labelSlide.value, 0),
                  child: Row(
                    children: [
                      Icon(Icons.my_location_rounded, color: widget.accent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'DETECTED AUTOMATICALLY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: widget.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _ping,
                        builder: (context, _) {
                          final t = _ping.value;
                          if (t == 0.0 || t == 1.0) return const SizedBox.shrink();
                          return Container(
                            width: 48 * (0.6 + t * 0.8),
                            height: 48 * (0.6 + t * 0.8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.accent
                                    .withValues(alpha: (1.0 - t) * 0.5),
                                width: 1.4,
                              ),
                            ),
                          );
                        },
                      ),
                      AnimatedBuilder(
                        animation: _entrance,
                        builder: (context, _) => Transform.scale(
                          scale: _flagScale.value,
                          child: Text(widget.country.flag,
                              style: const TextStyle(fontSize: 36)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: AnimatedBuilder(
                    animation: _entrance,
                    builder: (context, _) => Opacity(
                      opacity: _nameFade.value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(_nameSlide.value, 0),
                        child: Text(
                          widget.country.name,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AurumTheme.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onChangeTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AurumTheme.textPrimaryOf(context),
                  side: BorderSide(color: AurumTheme.dividerOf(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Not you? Choose manually',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreStep extends StatefulWidget {
  final Country? country;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _GenreStep({
    super.key,
    required this.country,
    required this.selected,
    required this.onToggle,
    required this.onBack,
    required this.onNext,
  });

  @override
  State<_GenreStep> createState() => _GenreStepState();
}

class _GenreStepState extends State<_GenreStep> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final accent = AurumTheme.accentOf(context);
    final ordered = genreOrderFor(widget.country?.code);
    final filtered = _query.isEmpty
        ? ordered
        : ordered
            .where((g) => g.label.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: Icon(Icons.arrow_back_rounded,
                    color: AurumTheme.textPrimaryOf(context)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const Spacer(),
              const _StepDots(activeIndex: 1, total: 3),
              const Spacer(),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'What do you like\nlistening to?',
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.5,
              color: AurumTheme.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.country != null
                ? 'Pick a few — sorted for ${widget.country!.name}.'
                : 'Pick a few — we\'ll shape your Home feed around them.',
            style: TextStyle(
              fontSize: 14,
              color: AurumTheme.textMutedOf(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _SearchField(
            hint: 'Search genres',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No genres match "$_query"',
                      style: TextStyle(color: AurumTheme.textMutedOf(context)),
                    ),
                  )
                : GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: filtered.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 2.4,
                    ),
                    itemBuilder: (context, i) {
                      final genre = filtered[i];
                      final isSelected = widget.selected.contains(genre.key);
                      return _PillChip(
                        label: genre.label,
                        icon: genre.icon,
                        selected: isSelected,
                        accent: accent,
                        onTap: () {
                          AurumHaptics.selection();
                          widget.onToggle(genre.key);
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: widget.onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: Text(
                widget.selected.isEmpty ? 'Skip for now' : 'Continue',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtistStep extends StatefulWidget {
  final Country? country;
  final Set<String> genres;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onBack;
  final Future<void> Function() onFinish;

  const _ArtistStep({
    super.key,
    required this.country,
    required this.genres,
    required this.selected,
    required this.onToggle,
    required this.onBack,
    required this.onFinish,
  });

  @override
  State<_ArtistStep> createState() => _ArtistStepState();
}

class _ArtistStepState extends State<_ArtistStep> {
  List<ArtistSimple>? _artists;
  bool _saving = false;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  List<ArtistSimple>? _searchResults;
  bool _searching = false;
  int _searchToken = 0;
  final Map<String, ArtistSimple> _known = {};

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    final q = v.trim();
    if (q.length < 2) {
      setState(() {
        _searchResults = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 380), () async {
      final token = ++_searchToken;
      final res = await ArtistPickerLoader.search(q);
      if (!mounted || token != _searchToken) return;
      for (final a in res) {
        _known.putIfAbsent(a.name, () => a);
      }
      setState(() {
        _searchResults = res;
        _searching = false;
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _loadArtists();
  }

  Future<void> _loadArtists() async {
    try {
      final genreList = widget.genres.isNotEmpty
          ? kOnboardingGenres.where((g) => widget.genres.contains(g.key)).toList()
          : genreOrderFor(widget.country?.code).take(4).toList();

      final countryName = widget.country?.name;
      final countryCode = widget.country?.code;
      final isIndiaOrUnset = countryCode == null || countryCode == 'IN';

      final queries = genreList.map((g) {
        final seed = buildArtistSearchSeed(
          genreSeed: g.searchSeed,
          countryName: countryName,
        );
        return ApiService.searchArtistsRegionScoped(seed,
                limit: 16, includeSaavn: isIndiaOrUnset)
            .timeout(const Duration(seconds: 3))
            .catchError((_) => <ArtistSimple>[])
            .then((list) => MapEntry(g.key, list));
      }).toList();

      final earlyIndiaTopUp = isIndiaOrUnset
          ? ApiService.fetchHomeArtists()
              .timeout(const Duration(seconds: 3))
              .catchError((_) => <ArtistSimple>[])
          : null;

      final results = await Future.wait(queries).timeout(
        const Duration(seconds: 5),
        onTimeout: () => <MapEntry<String, List<ArtistSimple>>>[],
      );

      final merged = await ArtistPickerLoader.buildInitialList(
        genreBuckets: results.map((e) => e.value).toList(),
        includeSaavn: isIndiaOrUnset,
      );
      final seenNames = <String>{for (final m in merged) m.name.toLowerCase()};
      for (final m in merged) {
        _known.putIfAbsent(m.name, () => m);
      }

      if (merged.length < 40 && isIndiaOrUnset) {
        try {
          final topUp = await (earlyIndiaTopUp ?? ApiService.fetchHomeArtists()
              .timeout(const Duration(seconds: 3)));
          for (final a in topUp) {
            if (merged.length >= 40) break;
            if (a.name.isEmpty) continue;
            if (seenNames.add(a.name.toLowerCase())) merged.add(a);
          }
        } catch (_) {}
      }

      if (merged.length < 40 && !isIndiaOrUnset) {
        try {
          final triedKeys = genreList.map((g) => g.key).toSet();
          final extraGenres = genreOrderFor(countryCode)
              .where((g) => !triedKeys.contains(g.key))
              .take(4)
              .toList();

          final extraQueries = extraGenres.map((g) {
            final seed = buildArtistSearchSeed(
              genreSeed: g.searchSeed,
              countryName: countryName,
            );
            return ApiService.searchArtistsRegionScoped(seed,
                    limit: 16, includeSaavn: isIndiaOrUnset)
                .timeout(const Duration(seconds: 3))
                .catchError((_) => <ArtistSimple>[]);
          }).toList();

          final extraResults = await Future.wait(extraQueries).timeout(
            const Duration(seconds: 5),
            onTimeout: () => <List<ArtistSimple>>[],
          );

          for (final list in extraResults) {
            for (final a in list) {
              if (merged.length >= 40) break;
              if (a.name.isEmpty) continue;
              if (seenNames.add(a.name.toLowerCase())) merged.add(a);
            }
          }
        } catch (_) {}
      }

      if (merged.length < 6) {
        try {
          final fallback = await (earlyIndiaTopUp ?? ApiService.fetchHomeArtists()
              .timeout(const Duration(seconds: 3)));
          for (final a in fallback) {
            if (a.name.isEmpty) continue;
            if (seenNames.add(a.name.toLowerCase())) merged.add(a);
          }
        } catch (_) {}
      }

      if (mounted) setState(() => _artists = merged);
    } catch (_) {
      if (mounted) setState(() => _artists = const []);
    }
  }

  Future<void> _handleFinish() async {
    if (_saving) return;
    setState(() => _saving = true);
    AurumHaptics.medium();
    await widget.onFinish();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AurumTheme.accentOf(context);
    final loading = _artists == null;
    final hasArtists = _artists != null && _artists!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onBack,
                icon: Icon(Icons.arrow_back_rounded,
                    color: AurumTheme.textPrimaryOf(context)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const Spacer(),
              const _StepDots(activeIndex: 2, total: 3),
              const Spacer(),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Follow a few\nartists?',
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: -0.5,
              color: AurumTheme.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasArtists
                ? 'Pick your favourites or search any artist —\nyour feed will be built around them.'
                : loading
                    ? 'Finding artists picked for you...'
                    : 'We couldn\'t load artist picks right now — no\nworries, you can skip this step.',
            style: TextStyle(
              fontSize: 14,
              color: AurumTheme.textMutedOf(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (!loading)
            _SearchField(
              hint: 'Search any artist',
              onChanged: _onSearchChanged,
            ),
          if (widget.selected.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.selected.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final name = widget.selected.elementAt(i);
                  return GestureDetector(
                    onTap: () {
                      AurumHaptics.selection();
                      widget.onToggle(name);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(19),
                        border: Border.all(color: accent, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              style: TextStyle(
                                  color: accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          Icon(Icons.close_rounded, size: 15, color: accent),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : (_searchResults != null || _searching)
                    ? (_searching && (_searchResults ?? const []).isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : (_searchResults ?? const []).isEmpty
                            ? Center(
                                child: Text('No artists found',
                                    style: TextStyle(
                                        color: AurumTheme.textMutedOf(context))))
                            : GridView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: _searchResults!.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.78,
                                ),
                                itemBuilder: (context, i) {
                                  final artist = _searchResults![i];
                                  return _ArtistCard(
                                    artist: artist,
                                    selected:
                                        widget.selected.contains(artist.name),
                                    accent: accent,
                                    onTap: () {
                                      AurumHaptics.selection();
                                      widget.onToggle(artist.name);
                                    },
                                  );
                                },
                              ))
                : hasArtists
                    ? GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: _artists!.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemBuilder: (context, i) {
                          final artist = _artists![i];
                          final isSelected = widget.selected.contains(artist.name);
                          return _ArtistCard(
                            artist: artist,
                            selected: isSelected,
                            accent: accent,
                            onTap: () {
                              AurumHaptics.selection();
                              widget.onToggle(artist.name);
                            },
                          );
                        },
                      )
                    : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _handleFinish,
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(Colors.black),
                      ),
                    )
                  : Text(
                      widget.selected.isEmpty ? 'Skip & Start Listening' : 'Start Listening',
                      style:
                          const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: TextField(
        onChanged: onChanged,
        style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AurumTheme.textMutedOf(context)),
          prefixIcon: Icon(Icons.search_rounded,
              color: AurumTheme.textMutedOf(context), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  final int activeIndex;
  final int total;
  const _StepDots({required this.activeIndex, required this.total});

  @override
  Widget build(BuildContext context) {
    final accent = AurumTheme.accentOf(context);
    final muted = AurumTheme.dividerOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final active = i == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? accent : muted,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

class _PillChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _PillChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? accent : AurumTheme.dividerOf(context);
    final bgColor =
        selected ? accent.withValues(alpha: 0.14) : AurumTheme.bgCardOf(context);
    final fgColor = selected ? accent : AurumTheme.textPrimaryOf(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashFactory: NoSplash.splashFactory,
        highlightColor: accent.withValues(alpha: 0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 1.4 : 0.8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(icon, color: fgColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final ArtistSimple artist;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ArtistCard({
    required this.artist,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? accent : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: ClipOval(
                  child: artist.imageUrl.isEmpty
                      ? Container(
                          color: AurumTheme.bgCardOf(context),
                          child: Icon(Icons.person_rounded,
                              color: AurumTheme.textMutedOf(context)),
                        )
                      : CachedNetworkImage(
                          cacheManager: AurumImageCache(),
                          imageUrl: artist.imageUrl,
                          memCacheWidth: 256,
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: AurumTheme.bgCardOf(context)),
                          errorWidget: (_, __, ___) => Container(
                            color: AurumTheme.bgCardOf(context),
                            child: Icon(Icons.person_rounded,
                                color: AurumTheme.textMutedOf(context)),
                          ),
                        ),
                ),
              ),
              if (selected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AurumTheme.bgOf(context),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_circle_rounded,
                        color: accent, size: 20),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AurumTheme.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
