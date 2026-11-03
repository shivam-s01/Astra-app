// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import '../widgets/aurum_seek_bar.dart';
import '../widgets/aurum_loader.dart';
import '../widgets/aurum_morph_loader.dart';
import '../main.dart' show aurumRouteObserver;
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:ui' as ui show Image;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/route_drag_dismiss.dart';
import '../utils/artwork_palette_cache.dart';
import '../utils/aurum_transitions.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:share_plus/share_plus.dart';
import '../providers/player_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/premium_provider.dart';
import '../providers/theme_provider.dart';
import '../models/song.dart';
import '../models/lyrics.dart';
import '../theme/aurum_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/audio_prefs.dart';
import '../services/lyrics_translation_service.dart';
import '../widgets/aurum_artwork.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/aurum_like_button.dart';
import '../widgets/aurum_snack.dart';
import '../widgets/aurum_play_pause_icon.dart';
import '../widgets/constellation_lyrics.dart';
import '../widgets/premium_gate.dart';
import '../widgets/audio_output_sheet.dart';
import '../widgets/cast_button.dart';
import 'settings_player_screen.dart' show SleepTimerService, SleepTimerSheet;
import '../utils/aurum_haptics.dart';
import '../utils/aurum_sheet.dart';
import '../widgets/aurum_song_options_sheet.dart';
import '../services/aurum_image_cache.dart';

class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  late final AnimationController _staggerCtrl;
  late final Animation<double> _infoStagger;
  late final Animation<double> _seekStagger;
  late final Animation<double> _ctrlStagger;

  late final AnimationController _titleChangeCtrl;
  late final Animation<double> _titleFadeAnim;
  late final Animation<Offset> _titleSlideAnim;

  late final AnimationController _artworkCtrl;
  late final Animation<double> _artworkAnim;

  late final AnimationController _playBtnCtrl;
  late final Animation<double> _playBtnAnim;

  late final AnimationController _bgColorCtrl;
  Color _targetBg1 = const Color(0xFF0D0D18);
  Color _targetBg2 = const Color(0xFF060608);
  Color _targetBg3 = const Color(0xFF030305);
  Color _targetBg4 = const Color(0xFF0A0A14);
  Color _currentBg1 = const Color(0xFF0D0D18);
  Color _currentBg2 = const Color(0xFF060608);
  Color _currentBg3 = const Color(0xFF030305);
  Color _currentBg4 = const Color(0xFF0A0A14);

  late final RouteDragDismiss _routeDrag;
  static const double _routeDismissDistance = 120.0;
  static const double _routeDismissVelocity = 900.0;
  final ValueNotifier<double> _dragYNotifier = ValueNotifier(0.0);
  double get _dragY => _dragYNotifier.value;
  set _dragY(double v) => _dragYNotifier.value = v;
  bool _isDragging = false;
  bool _dragIsUpward = false;
  bool _bgFullscreenRevealed = false;
  Offset? _bgTapDownPos;

  void _toggleBgFullscreenReveal() {
    if (!AudioPrefs.showBlurredBgNotifier.value) return;
    AurumHaptics.selection();
    setState(() => _bgFullscreenRevealed = !_bgFullscreenRevealed);
  }
  double _upwardDragDistance = 0;

  late final AnimationController _springBackCtrl;
  bool _springBackIsDismissing = false;

  String? _lastArtUrl;
  String? _lastSongId;
  bool? _lastIsLight;
  bool _isFirstBuild = true;

  int _artGen = 0;
  int _titleGen = 0;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('Full Player');
    _routeDrag = RouteDragDismiss(context);
    WidgetsBinding.instance.addObserver(this);

    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _infoStagger = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _staggerCtrl,
            curve: const Interval(0.18, 0.75, curve: Curves.easeOutCubic)));
    _seekStagger = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _staggerCtrl,
            curve: const Interval(0.30, 0.85, curve: Curves.easeOutCubic)));
    _ctrlStagger = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _staggerCtrl,
            curve: const Interval(0.42, 1.0, curve: Curves.easeOutCubic)));
    _staggerCtrl.forward();

    _titleChangeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _titleFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _titleChangeCtrl, curve: Curves.easeOut));
    _titleSlideAnim = Tween<Offset>(
            begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _titleChangeCtrl, curve: Curves.easeOutCubic));
    _titleChangeCtrl.value = 1.0;

    _artworkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _artworkAnim = Tween<double>(begin: 0.94, end: 1.0)
        .animate(CurvedAnimation(parent: _artworkCtrl, curve: Curves.easeOutCubic));
    _artworkCtrl.value = 1.0;

    _playBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
    _playBtnAnim = Tween<double>(begin: 1.0, end: 0.87)
        .animate(CurvedAnimation(parent: _playBtnCtrl, curve: Curves.easeInOut));

    _bgColorCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _springBackCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final url = context.read<PlayerProvider>().currentSong?.artworkUrl;
      if (url != null &&
          url.isNotEmpty &&
          !url.startsWith('content://') &&
          !url.startsWith('/') &&
          !url.startsWith('file://')) {
        precacheImage(
          CachedNetworkImageProvider(url, maxWidth: 220, cacheManager: AurumImageCache()),
          context,
        ).catchError((_) {});
      }
      if (_immersiveLyricsOpen) {
        _pauseAmbientAnims();
      }
    });
  }

  @override
  void dispose() {
    aurumRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _staggerCtrl.dispose();
    _titleChangeCtrl.dispose();
    _artworkCtrl.dispose();
    _playBtnCtrl.dispose();
    _bgColorCtrl.dispose();
    _immersiveCtrl.dispose();
    _routeDrag.cancel();
    _springBackCtrl.dispose();
    _dragYNotifier.dispose();
    super.dispose();
  }

  void _springBackDrag([double velocity = 0]) {
    final start = _dragY;
    if (start == 0) return;
    var durationMs = (start.abs() / 2).clamp(180, 420).round();
    final speed = velocity.abs();
    if (speed > 0) {
      final velocityMs = (start.abs() / speed * 1000).clamp(120, 420);
      durationMs = velocityMs.round();
    }
    _springBackCtrl.duration = Duration(milliseconds: durationMs);
    _springBackCtrl.reset();
    final anim = Tween<double>(begin: start, end: 0.0).animate(
      CurvedAnimation(parent: _springBackCtrl, curve: Curves.easeOutCubic),
    );
    void listener() {
      if (!mounted) return;
      _dragY = anim.value;
    }

    anim.addListener(listener);
    _springBackCtrl.forward().whenCompleteOrCancel(() {
      anim.removeListener(listener);
      if (mounted) _dragY = 0;
      _springBackCtrl.duration = const Duration(milliseconds: 320);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_panelOpen) _resumeAmbientAnims();
    } else {
      _pauseAmbientAnims();
    }

    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.detached) &&
        mounted &&
        (_isDragging ||
            (_dragY != 0 && !_springBackIsDismissing) ||
            (_springBackCtrl.isAnimating && !_springBackIsDismissing))) {
      if (_springBackCtrl.isAnimating) _springBackCtrl.stop();
      _dragIsUpward = false;
      _upwardDragDistance = 0;
      _dragY = 0;
      _routeDrag.cancel();
      if (_isDragging) setState(() => _isDragging = false);
    }
  }

  bool _didSeedInitialPalette = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    aurumRouteObserver.subscribe(this, ModalRoute.of(context)!);

    if (!_didSeedInitialPalette) {
      _didSeedInitialPalette = true;
      if (context.read<PlayerProvider>().immersiveLyricsWasOpen) {
        _immersiveLyricsOpen = true;
        _immersiveCtrl.value = 1.0;
      }
      final currentSong = context.read<PlayerProvider>().currentSong;
      final url = currentSong?.artworkUrl ?? '';
      if (url.isNotEmpty && currentSong != null) {
        final cached = ArtworkPaletteCache.peek(url);
        if (cached != null) {
          final isLight = !context.read<ThemeProvider>().isDarkOf(context);
          final c1 = cached.vibrant;
          final c2 = cached.dominant;
          final c3 = cached.darkMuted;
          final c4 = cached.lightVibrant;
          const lightLift = 0.16;
          final seeded1 = isLight
              ? ensureContrastSafe(Color.lerp(
                  ensureContrastSafe(Color.lerp(c1, Colors.black, 0.22)!, isLight: false),
                  Colors.white, lightLift)!, isLight: true)
              : ensureContrastSafe(Color.lerp(c1, Colors.black, 0.22)!, isLight: false);
          final seeded2 = isLight
              ? ensureContrastSafe(Color.lerp(
                  ensureContrastSafe(Color.lerp(c2, Colors.black, 0.48)!, isLight: false),
                  Colors.white, lightLift)!, isLight: true)
              : ensureContrastSafe(Color.lerp(c2, Colors.black, 0.48)!, isLight: false);
          final seeded3 = isLight
              ? ensureContrastSafe(Color.lerp(
                  ensureContrastSafe(Color.lerp(c3, Colors.black, 0.70)!, isLight: false),
                  Colors.white, lightLift)!, isLight: true)
              : ensureContrastSafe(Color.lerp(c3, Colors.black, 0.70)!, isLight: false);
          final seeded4 = isLight
              ? ensureContrastSafe(Color.lerp(
                  ensureContrastSafe(Color.lerp(c4, Colors.black, 0.30)!, isLight: false),
                  Colors.white, lightLift)!, isLight: true)
              : ensureContrastSafe(Color.lerp(c4, Colors.black, 0.30)!, isLight: false);
          _currentBg1 = seeded1;
          _currentBg2 = seeded2;
          _currentBg3 = seeded3;
          _currentBg4 = seeded4;
          _targetBg1 = seeded1;
          _targetBg2 = seeded2;
          _targetBg3 = seeded3;
          _targetBg4 = seeded4;
          _lastSongId = currentSong.id;
          _lastIsLight = isLight;
          _lastArtUrl = url;
          _isFirstBuild = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _warmNextInQueue();
          });
        } else {
          final isLight = !context.read<ThemeProvider>().isDarkOf(context);
          final gen = ++_artGen;
          _lastArtUrl = url;
          _lastSongId = currentSong.id;
          _lastIsLight = isLight;
          _isFirstBuild = false;
          unawaited(ArtworkPaletteCache.getFast(url).then((fast) {
            if (fast == null || gen != _artGen || !mounted) return;
            if (ArtworkPaletteCache.peek(url) != null) return;
            _applyPalette(fast, gen: gen, isLight: isLight, instant: true);
          }));
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _extractColorForce(url, isLight: isLight);
            _warmNextInQueue();
          });
        }
      }
    }
  }

  @override
  void didPushNext() {
    _pauseAmbientAnims();
  }

  @override
  void didPopNext() {
    if (!_panelOpen) _resumeAmbientAnims();
  }

  bool _panelOpen = false;

  final GlobalKey<_StaticBlurArtworkState> _kenBurnsKey = GlobalKey();

  void _pauseAmbientAnims() {
    _kenBurnsKey.currentState?.pause();
  }

  void _resumeAmbientAnims() {
    _kenBurnsKey.currentState?.resume();
  }

  bool _immersiveLyricsOpen = false;
  late final AnimationController _immersiveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
    reverseDuration: const Duration(milliseconds: 420),
  );
  double _immersiveDragY = 0.0;
  bool _immersiveDragging = false;

  void _openImmersiveLyrics() {
    if (_immersiveLyricsOpen) {
      _closeImmersiveLyrics();
      return;
    }
    AurumHaptics.medium();
    setState(() => _immersiveLyricsOpen = true);
    context.read<PlayerProvider>().immersiveLyricsWasOpen = true;
    _pauseAmbientAnims();
    _immersiveCtrl.forward(from: 0.0);
  }

  void _closeImmersiveLyrics() {
    if (!_immersiveLyricsOpen) return;
    AurumHaptics.light();
    context.read<PlayerProvider>().immersiveLyricsWasOpen = false;
    _immersiveDragY = 0.0;
    _immersiveCtrl.reverse(from: _immersiveCtrl.value).whenComplete(() {
      if (!mounted) return;
      setState(() => _immersiveLyricsOpen = false);
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _resumeAmbientAnims();
      }
    });
  }

  Future<void> _extractColor(String url, {bool isLight = false}) async {
    if (url.isEmpty || url == _lastArtUrl) return;
    _lastArtUrl = url;
    final gen = ++_artGen;

    final cached = ArtworkPaletteCache.peek(url);
    if (cached != null) {
      _applyPalette(cached, gen: gen, isLight: isLight);
      return;
    }

    unawaited(ArtworkPaletteCache.getFast(url).then((fast) {
      if (fast == null || gen != _artGen || !mounted) return;
      if (ArtworkPaletteCache.peek(url) != null) return;
      _applyPalette(fast, gen: gen, isLight: isLight, instant: true);
    }));

    try {
      final palette = await ArtworkPaletteCache.get(url);
      if (gen != _artGen || !mounted) return;
      _applyPalette(palette, gen: gen, isLight: isLight);
    } catch (_) {}
  }

  Future<void> _extractColorForce(String url, {required bool isLight}) async {
    if (url.isEmpty) return;
    final gen = ++_artGen;
    final cached = ArtworkPaletteCache.peek(url);
    if (cached != null) {
      _applyPalette(cached, gen: gen, isLight: isLight);
      return;
    }
    try {
      final palette = await ArtworkPaletteCache.get(url);
      if (gen != _artGen || !mounted) return;
      _applyPalette(palette, gen: gen, isLight: isLight);
    } catch (_) {}
  }

  void _applyPalette(ArtworkPalette p, {required int gen, required bool isLight, bool instant = false}) {
    if (gen != _artGen || !mounted) return;
    final c1 = p.vibrant;
    final c2 = p.dominant;
    final c3 = p.darkMuted;
    final c4 = p.lightVibrant;

    final t = _bgColorCtrl.value;
    _currentBg1 = Color.lerp(_currentBg1, _targetBg1, t) ?? _currentBg1;
    _currentBg2 = Color.lerp(_currentBg2, _targetBg2, t) ?? _currentBg2;
    _currentBg3 = Color.lerp(_currentBg3, _targetBg3, t) ?? _currentBg3;
    _currentBg4 = Color.lerp(_currentBg4, _targetBg4, t) ?? _currentBg4;

    if (isLight) {
      const lightLift = 0.16;
      final darkBg1 = ensureContrastSafe(Color.lerp(c1, Colors.black, 0.22)!, isLight: false);
      final darkBg2 = ensureContrastSafe(Color.lerp(c2, Colors.black, 0.48)!, isLight: false);
      final darkBg3 = ensureContrastSafe(Color.lerp(c3, Colors.black, 0.70)!, isLight: false);
      final darkBg4 = ensureContrastSafe(Color.lerp(c4, Colors.black, 0.30)!, isLight: false);
      _targetBg1 = ensureContrastSafe(Color.lerp(darkBg1, Colors.white, lightLift)!, isLight: true);
      _targetBg2 = ensureContrastSafe(Color.lerp(darkBg2, Colors.white, lightLift)!, isLight: true);
      _targetBg3 = ensureContrastSafe(Color.lerp(darkBg3, Colors.white, lightLift)!, isLight: true);
      _targetBg4 = ensureContrastSafe(Color.lerp(darkBg4, Colors.white, lightLift)!, isLight: true);
    } else {
      _targetBg1 = ensureContrastSafe(Color.lerp(c1, Colors.black, 0.22)!, isLight: false);
      _targetBg2 = ensureContrastSafe(Color.lerp(c2, Colors.black, 0.48)!, isLight: false);
      _targetBg3 = ensureContrastSafe(Color.lerp(c3, Colors.black, 0.70)!, isLight: false);
      _targetBg4 = ensureContrastSafe(Color.lerp(c4, Colors.black, 0.30)!, isLight: false);
    }

    if (instant) {
      _currentBg1 = _targetBg1;
      _currentBg2 = _targetBg2;
      _currentBg3 = _targetBg3;
      _currentBg4 = _targetBg4;
      _bgColorCtrl.value = 1.0;
      if (mounted) setState(() {});
      return;
    }

    _bgColorCtrl.forward(from: 0.0);
  }

  void _warmNextInQueue() {
    final player = context.read<PlayerProvider>();
    final queue = player.queue;
    final idx = player.currentIndex;
    if (queue.isEmpty || idx < 0 || idx + 1 >= queue.length) return;
    final next = queue[idx + 1];
    if (next.artworkUrl.isNotEmpty) {
      ArtworkPaletteCache.warm(next.artworkUrl);
      _precacheHeroArtwork(next.artworkUrl);
    }
  }

  void _precacheHeroArtwork(String url) {
    if (url.isEmpty ||
        url.startsWith('content://') ||
        url.startsWith('/') ||
        url.startsWith('file://')) {
      return;
    }
    if (!mounted) return;
    precacheImage(
      CachedNetworkImageProvider(url, maxWidth: 220, cacheManager: AurumImageCache()),
      context,
    ).catchError((_) {
    });
  }

  void _triggerArtworkAnimation() {
    if (mounted) {
      _artworkCtrl.forward(from: 0.0);
    }
    if (mounted) {
      final gen = ++_titleGen;
      _titleChangeCtrl.reverse(from: 1.0).then((_) {
        if (mounted && gen == _titleGen) _titleChangeCtrl.forward();
      });
    }
  }

  void _close() {
    if (!mounted) return;
    AurumHaptics.light();
    if (_springBackIsDismissing) return;
    if (_dragY != 0) _dragY = 0;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _completeDismissDrag() {
    if (!mounted) return;
    if (_springBackIsDismissing) {
      return;
    }
    AurumHaptics.light();
    _springBackIsDismissing = true;
    final screenH = MediaQuery.of(context).size.height;
    final start = _dragY;
    _springBackCtrl.reset();
    final remaining = (screenH - start).clamp(1.0, screenH);
    final ms = (140 + (remaining / screenH) * 160).round();
    _springBackCtrl.duration = Duration(milliseconds: ms);
    final anim = Tween<double>(begin: start, end: screenH).animate(
      CurvedAnimation(parent: _springBackCtrl, curve: Curves.easeIn),
    );
    void listener() {
      if (!mounted) return;
      _dragY = anim.value;
    }

    anim.addListener(listener);
    _springBackCtrl.forward().whenCompleteOrCancel(() {
      anim.removeListener(listener);
      _springBackCtrl.duration = const Duration(milliseconds: 320);
      _springBackIsDismissing = false;
      if (!mounted) {
        return;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        if (mounted) {
          setState(() => _dragY = 0);
        }
      }
    });
  }

  Future<void> _onPlayTap(PlayerProvider player) async {
    AurumHaptics.heavy();
    unawaited(player.togglePlay());
    unawaited(_playBtnCtrl.forward().then((_) => _playBtnCtrl.reverse()));
  }

  void _openPanel({int initialTab = 0}) {
    AurumHaptics.medium();
    _panelOpen = true;
    _pauseAmbientAnims();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(165),
      useSafeArea: false,
      enableDrag: false,
      builder: (_) => _PremiumContentPanel(
        bg1: _currentBg1,
        bg2: _currentBg2,
        bg3: _currentBg3,
        initialTab: initialTab,
      ),
    ).whenComplete(() {
      _panelOpen = false;
      if (mounted &&
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) {
        _resumeAmbientAnims();
      }
    });
  }

  void _showOptions(BuildContext context) {
    final player = context.read<PlayerProvider>();
    final song = player.currentSong;
    if (song == null) return;
    showAurumSongOptions(context, song, showPlayerTools: true);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, (String?, bool, bool, LoopMode, bool, int)>(
      selector: (_, player) => (
        player.currentSong?.id,
        player.isPlaying,
        player.isLoading,
        player.loopMode,
        player.shuffle,
        player.queue.length,
      ),
      builder: (context, _, __) {
        final player = context.read<PlayerProvider>();
        final song = player.currentSong;
        if (song == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }

        final isLight = !context.watch<ThemeProvider>().isDarkOf(context);
        final themeChanged = isLight != _lastIsLight;
        _lastIsLight = isLight;
        if (song.id != _lastSongId || themeChanged) {
          final songChanged = song.id != _lastSongId;
          _lastSongId = song.id;
          final isFirstBuild = _isFirstBuild;
          _isFirstBuild = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (songChanged && !isFirstBuild) _triggerArtworkAnimation();
            if (song.artworkUrl.isNotEmpty) {
              if (songChanged) {
                _extractColor(song.artworkUrl, isLight: isLight);
              } else {
                _extractColorForce(song.artworkUrl, isLight: isLight);
              }
            }
            if (songChanged) _warmNextInQueue();
          });
        }

        return GestureDetector(
              onVerticalDragStart: (_) {
                _dragIsUpward = false;
                _upwardDragDistance = 0;
                setState(() => _isDragging = true);
              },
              onVerticalDragUpdate: (d) {
                if (_panelOpen) return;
                if (_routeDrag.isActive ||
                    (d.delta.dy > 0 && !_dragIsUpward)) {
                  if (!_routeDrag.isActive && !_routeDrag.start()) return;
                  _routeDrag.update(d.delta.dy);
                } else if (d.delta.dy < 0 || _dragIsUpward) {
                  _dragIsUpward = true;
                  _upwardDragDistance += d.delta.dy;
                }
              },
              onVerticalDragEnd: (d) {
                setState(() => _isDragging = false);
                final velocity = d.primaryVelocity ?? 0;

                if (_routeDrag.isActive) {
                  _routeDrag.end(
                    velocityPxPerSec: velocity,
                    dismissDistance: _routeDismissDistance,
                    dismissVelocity: _routeDismissVelocity,
                  );
                } else if (_dragIsUpward &&
                    (_upwardDragDistance < -20 || velocity < -400)) {
                  _openPanel();
                }
                _dragIsUpward = false;
              },
              onVerticalDragCancel: () {
                if (_isDragging && mounted) setState(() => _isDragging = false);
                _dragIsUpward = false;
                _upwardDragDistance = 0;
                _routeDrag.cancel();
              },
              child: _DragTransform(
                dragYListenable: _dragYNotifier,
                child: PopScope(
                  canPop: true,
                  onPopInvokedWithResult: (didPop, _) {},
                  child: Scaffold(
                      backgroundColor: Colors.black,
                      body: Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Colors.black),
                          RepaintBoundary(
                            child: _BgLayer(
                              song: song,
                              bgCtrl: _bgColorCtrl,
                              kenBurnsKey: _kenBurnsKey,
                              startBg1: _currentBg1,
                              startBg2: _currentBg2,
                              startBg3: _currentBg3,
                              startBg4: _currentBg4,
                              targetBg1: _targetBg1,
                              targetBg2: _targetBg2,
                              targetBg3: _targetBg3,
                              targetBg4: _targetBg4,
                              isDragging: _isDragging,
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: _bgFullscreenRevealed ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: IgnorePointer(
                              ignoring: _bgFullscreenRevealed,
                              child: SafeArea(
                                child: RepaintBoundary(
                                  child: _buildBody(context, player, song),
                                ),
                              ),
                            ),
                          ),
                          if (_bgFullscreenRevealed)
                            Positioned.fill(
                              child: Listener(
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (e) => _bgTapDownPos = e.position,
                                onPointerCancel: (_) => _bgTapDownPos = null,
                                onPointerUp: (e) {
                                  final start = _bgTapDownPos;
                                  _bgTapDownPos = null;
                                  if (start == null) return;
                                  if (_immersiveLyricsOpen ||
                                      _immersiveCtrl.value > 0) {
                                    return;
                                  }
                                  if ((e.position - start).distance <= 18) {
                                    _toggleBgFullscreenReveal();
                                  }
                                },
                              ),
                            ),
                          if (_immersiveLyricsOpen || _immersiveCtrl.value > 0)
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: _ImmersiveGlowLayer(controller: _immersiveCtrl),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, PlayerProvider player, Song song) {
    return LayoutBuilder(builder: (context, constraints) {
      final h = constraints.maxHeight;
      final w = constraints.maxWidth;
      final isCompact = h < 640;
      final isTablet = w > 600;

      final vGapSm = isCompact ? 8.0 : 16.0;
      final vGapMd = isCompact ? 12.0 : 20.0;
      final hPad = isTablet ? w * 0.16 : 28.0;

      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DragHandle(isDragging: _isDragging),
            ValueListenableBuilder<LyricsViewMode>(
              valueListenable: AudioPrefs.lyricsViewModeNotifier,
              builder: (context, viewMode, _) => TopBarWithCastBanner(
                song: song,
                bgLuma: _currentBg2.computeLuminance(),
                onMore: () => _showOptions(context),
                showLyricsTrigger: viewMode == LyricsViewMode.fullscreen,
                lyricsTriggerActive: _immersiveLyricsOpen,
                onLyricsTrigger: _openImmersiveLyrics,
              ),
            ),
            SizedBox(height: (vGapMd - 15).clamp(0.0, vGapMd)),
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => _bgTapDownPos = e.position,
              onPointerCancel: (_) => _bgTapDownPos = null,
              onPointerUp: (e) {
                final start = _bgTapDownPos;
                _bgTapDownPos = null;
                if (start == null) return;
                if (_immersiveLyricsOpen || _immersiveCtrl.value > 0) return;
                if ((e.position - start).distance <= 18) {
                  _toggleBgFullscreenReveal();
                }
              },
              child: _Artwork(
              song: song,
              player: player,
              hPad: hPad,
              h: h,
              w: w,
              bgLuma: _currentBg2.computeLuminance(),
              artworkAnim: _artworkAnim,
              immersiveOpen: _immersiveLyricsOpen,
              immersiveCtrl: _immersiveCtrl,
              immersiveDragY: _immersiveDragY,
              immersiveDragging: _immersiveDragging,
              onCloseImmersive: _closeImmersiveLyrics,
              onImmersiveDragStart: () =>
                  setState(() => _immersiveDragging = true),
              onImmersiveDragUpdate: (dy) =>
                  setState(() => _immersiveDragY = dy),
              onImmersiveDragEnd: (shouldClose) {
                setState(() => _immersiveDragging = false);
                if (shouldClose) {
                  _closeImmersiveLyrics();
                } else {
                  setState(() => _immersiveDragY = 0.0);
                }
              },
              bg1: _currentBg1,
              bg2: _currentBg2,
              bg3: _currentBg3,
              bg4: _currentBg4,
              ),
            ),
            SizedBox(height: vGapMd),
            ValueListenableBuilder<bool>(
              valueListenable: AudioPrefs.showLyricsOnPlayerNotifier,
              builder: (context, show, _) {
                return ValueListenableBuilder<LyricsViewMode>(
                  valueListenable: AudioPrefs.lyricsViewModeNotifier,
                  builder: (context, viewMode, __) {
                    if (!show ||
                        _immersiveLyricsOpen ||
                        viewMode == LyricsViewMode.fullscreen) {
                      return const SizedBox.shrink();
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: _InlineLyricsStrip(
                            hPad: hPad,
                            bgLuma: _currentBg2.computeLuminance(),
                            onTap: _openImmersiveLyrics,
                          ),
                        ),
                        SizedBox(width: hPad * 0.5),
                      ],
                    );
                  },
                );
              },
            ),
            SizedBox(height: vGapSm * 0.6),
            FadeTransition(
              opacity: _infoStagger,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.06), end: Offset.zero)
                    .animate(CurvedAnimation(
                        parent: _staggerCtrl,
                        curve: const Interval(0.18, 0.75, curve: Curves.easeOutCubic))),
                child: FadeTransition(
                  opacity: _titleFadeAnim,
                  child: SlideTransition(
                    position: _titleSlideAnim,
                    child: _SongInfo(
                      song: song,
                      hPad: hPad,
                      isTablet: isTablet,
                      bgLuma: _currentBg2.computeLuminance(),
                      isFav: context.watch<FavoritesProvider>().isFavorite(song.id),
                      onLyricsTap: _openImmersiveLyrics,
                      onFavTap: () {
                        PremiumGate.guard(
                          context,
                          feature: AppLocalizations.of(context)!.fpLikeSongsFeature,
                          description: AppLocalizations.of(context)!.fpLikeSongsSignIn,
                          requiresLoginOnly: true,
                          onAllowed: () {
                            AurumHaptics.light();
                            context.read<FavoritesProvider>().toggleFavorite(song);
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: vGapSm * 0.3),
            FadeTransition(
              opacity: _seekStagger,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05), end: Offset.zero)
                    .animate(CurvedAnimation(
                        parent: _staggerCtrl,
                        curve: const Interval(0.30, 0.85, curve: Curves.easeOutCubic))),
                child: _SeekBar(player: player, hPad: hPad, bgLuma: _currentBg2.computeLuminance()),
              ),
            ),
            SizedBox(height: vGapSm),
            FadeTransition(
              opacity: _ctrlStagger,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05), end: Offset.zero)
                    .animate(CurvedAnimation(
                        parent: _staggerCtrl,
                        curve: const Interval(0.42, 1.0, curve: Curves.easeOutCubic))),
                child: _Controls(
                  player: player,
                  hPad: hPad,
                  playBtnAnim: _playBtnAnim,
                  bg1: _currentBg1,
                  bgLuma: _currentBg2.computeLuminance(),
                  onPlayTap: () => _onPlayTap(player),
                ),
              ),
            ),
            SizedBox(height: isCompact ? 8.0 : 12.0),
            SizedBox(
              height: 28,
              child: Center(
                child: _QualityPills(song: song, hPad: hPad, bgLuma: _currentBg2.computeLuminance()),
              ),
            ),
            const Spacer(),
            _BottomPill(hPad: hPad, bgLuma: _currentBg2.computeLuminance(), onTap: _openPanel),
            SizedBox(height: isCompact ? 8.0 : 12.0),
          ],
        );
    });
  }
}

class _DragTransform extends StatelessWidget {
  final ValueListenable<double> dragYListenable;
  final Widget child;

  const _DragTransform({required this.dragYListenable, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(child: RepaintBoundary(child: child));
  }
}

class _DragHandle extends StatelessWidget {
  final bool isDragging;
  const _DragHandle({required this.isDragging});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isDragging ? 44 : 32,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(isDragging ? 80 : 45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final Song song;
  final double bgLuma;
  final VoidCallback onMore;
  final bool showLyricsTrigger;
  final bool lyricsTriggerActive;
  final VoidCallback? onLyricsTrigger;
  const _TopBar({
    required this.song,
    required this.bgLuma,
    required this.onMore,
    this.showLyricsTrigger = false,
    this.lyricsTriggerActive = false,
    this.onLyricsTrigger,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bgIsLight = bgLuma >= 0.5;
    final textPrimary = bgIsLight ? AurumTheme.lightTextPrimary : Colors.white;
    final textMuted = bgIsLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(170);
    final pillBg = bgIsLight ? AurumTheme.lightBgSurface.withAlpha(200) : Colors.black.withAlpha(70);
    final pillBorder = bgIsLight ? AurumTheme.lightDivider : Colors.white.withAlpha(30);
    final iconColor = bgIsLight ? AurumTheme.lightTextSecondary : Colors.white.withAlpha(230);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        _IconBtn(
          icon: Icons.keyboard_arrow_down_rounded,
          size: 26,
          color: iconColor,
          onTap: () => Navigator.pop(context),
          semanticLabel: l10n.fpClosePlayer,
        ),
        if (showLyricsTrigger) ...[
          const SizedBox(width: 4),
          _ImmersiveLyricsTriggerButton(
            bgLuma: bgLuma,
            isActive: lyricsTriggerActive,
            onTap: onLyricsTrigger!,
          ),
        ],
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: pillBorder, width: 0.5),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                l10n.fpNowPlaying,
                style: TextStyle(
                  color: textMuted,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                song.album.isNotEmpty ? song.album : 'Astra Music',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
        _IconBtn(
          icon: Icons.more_vert_rounded,
          size: 22,
          color: iconColor,
          onTap: onMore,
          semanticLabel: l10n.fpMoreOptions,
        ),
      ]),
    );
  }
}

class TopBarWithCastBanner extends StatelessWidget {
  final Song song;
  final double bgLuma;
  final VoidCallback onMore;
  final bool showLyricsTrigger;
  final bool lyricsTriggerActive;
  final VoidCallback? onLyricsTrigger;
  const TopBarWithCastBanner({
    super.key,
    required this.song,
    required this.bgLuma,
    required this.onMore,
    this.showLyricsTrigger = false,
    this.lyricsTriggerActive = false,
    this.onLyricsTrigger,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _TopBar(
        song: song,
        bgLuma: bgLuma,
        onMore: onMore,
        showLyricsTrigger: showLyricsTrigger,
        lyricsTriggerActive: lyricsTriggerActive,
        onLyricsTrigger: onLyricsTrigger,
      ),
      const CastingBanner(),
    ]);
  }
}

class _Artwork extends StatefulWidget {
  final Song song;
  final PlayerProvider player;
  final double hPad, h, w;
  final double bgLuma;
  final Animation<double> artworkAnim;
  final bool immersiveOpen;
  final AnimationController immersiveCtrl;
  final double immersiveDragY;
  final bool immersiveDragging;
  final VoidCallback onCloseImmersive;
  final VoidCallback onImmersiveDragStart;
  final ValueChanged<double> onImmersiveDragUpdate;
  final ValueChanged<bool> onImmersiveDragEnd;
  final Color bg1, bg2, bg3, bg4;

  const _Artwork({
    required this.song,
    required this.player,
    required this.hPad,
    required this.h,
    required this.w,
    required this.bgLuma,
    required this.artworkAnim,
    required this.immersiveOpen,
    required this.immersiveCtrl,
    required this.immersiveDragY,
    required this.immersiveDragging,
    required this.onCloseImmersive,
    required this.onImmersiveDragStart,
    required this.onImmersiveDragUpdate,
    required this.onImmersiveDragEnd,
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.bg4,
  });

  @override
  State<_Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<_Artwork> with SingleTickerProviderStateMixin {
  double _dragDx = 0;
  bool _dragging = false;

  late final AnimationController _snapBackCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
  );
  Animation<double>? _snapBackAnim;

  @override
  void dispose() {
    _snapBackCtrl.dispose();
    super.dispose();
  }

  double _thresholdFor(double sensitivity) {
    final t = sensitivity.clamp(0.0, 100.0) / 100.0;
    return 220.0 - (150.0 * t);
  }

  void _animateSnapBack() {
    _snapBackCtrl.stop();
    final start = _dragDx;
    if (start == 0) {
      setState(() => _dragging = false);
      return;
    }
    _snapBackAnim = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _snapBackCtrl, curve: Curves.easeOutCubic),
    )..addListener(() {
        if (!mounted) return;
        setState(() => _dragDx = _snapBackAnim!.value);
      });
    _dragging = false;
    _snapBackCtrl.forward(from: 0.0);
  }

  void _handleDragEnd() {
    final sensitivity = AudioPrefs.swipeSensitivity;
    final threshold = _thresholdFor(sensitivity);
    if (_dragDx <= -threshold) {
      AurumHaptics.medium();
      widget.player.skipNext().then((allowed) {
        if (!allowed && mounted) {
          PremiumGate.show(
            context,
            feature: AppLocalizations.of(context)!.fpUnlimitedSkipsFeature,
            description: AppLocalizations.of(context)!.fpUnlimitedSkipsSignIn,
            requiresLoginOnly: true,
          );
        }
      });
    } else if (_dragDx >= threshold) {
      AurumHaptics.medium();
      widget.player.skipPrev();
    }
    _animateSnapBack();
  }

  @override
  Widget build(BuildContext context) {
    const artworkVisualPad = 18.0;
    final maxArtSize =
        (widget.w - artworkVisualPad * 2).clamp(0.0, widget.h * 0.46);
    final bgIsLight = widget.bgLuma >= 0.5;
    return ValueListenableBuilder<bool>(
      valueListenable: AudioPrefs.swipeToChangeNotifier,
      builder: (context, swipeEnabled, _) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: swipeEnabled
              ? (_) {
                  _snapBackCtrl.stop();
                  setState(() => _dragging = true);
                }
              : null,
          onHorizontalDragUpdate: swipeEnabled
              ? (d) => setState(() => _dragDx += d.delta.dx)
              : null,
          onHorizontalDragEnd: swipeEnabled ? (_) => _handleDragEnd() : null,
          onHorizontalDragCancel: swipeEnabled ? _animateSnapBack : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: artworkVisualPad),
            child: Center(
              child: SizedBox(
                width: maxArtSize,
                height: maxArtSize,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ArtworkVisual(
                      dragDx: _dragDx,
                      dragging: _dragging,
                      artworkAnim: widget.artworkAnim,
                      song: widget.song,
                      player: widget.player,
                      bgIsLight: bgIsLight,
                      maxArtSize: maxArtSize,
                    ),
                    if (widget.immersiveOpen || widget.immersiveCtrl.value > 0)
                      RepaintBoundary(
                        child: _ImmersiveLyricsOverlay(
                          controller: widget.immersiveCtrl,
                          song: widget.song,
                          bg1: widget.bg1,
                          bg2: widget.bg2,
                          bg3: widget.bg3,
                          bg4: widget.bg4,
                          dragY: widget.immersiveDragY,
                          isDragging: widget.immersiveDragging,
                          maxArtSize: maxArtSize,
                          onClose: widget.onCloseImmersive,
                          onDragStart: widget.onImmersiveDragStart,
                          onDragUpdate: widget.onImmersiveDragUpdate,
                          onDragEnd: widget.onImmersiveDragEnd,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ArtworkVisual extends StatelessWidget {
  final double dragDx;
  final bool dragging;
  final Animation<double> artworkAnim;
  final Song song;
  final PlayerProvider player;
  final bool bgIsLight;
  final double maxArtSize;

  const _ArtworkVisual({
    required this.dragDx,
    required this.dragging,
    required this.artworkAnim,
    required this.song,
    required this.player,
    required this.bgIsLight,
    required this.maxArtSize,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(dragDx * 0.3, 0),
      child: Transform.scale(
        scale: dragging ? (1.0 - (dragDx.abs() / 800).clamp(0.0, 0.08)) : 1.0,
        child: AnimatedBuilder(
          animation: artworkAnim,
          builder: (_, child) => Transform.scale(
            scale: artworkAnim.value,
            child: child,
          ),
          child: ValueListenableBuilder<String>(
            valueListenable: AudioPrefs.artworkShapeNotifier,
            builder: (context, shape, _) {
              final radius = shape == 'Circle'
                  ? maxArtSize / 2
                  : shape == 'Square'
                      ? 4.0
                      : 20.0;
              return RepaintBoundary(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(bgIsLight
                            ? (player.isPlaying ? 55 : 34)
                            : (player.isPlaying ? 150 : 100)),
                        blurRadius: bgIsLight
                            ? (player.isPlaying ? 40 : 24)
                            : (player.isPlaying ? 70 : 44),
                        offset: const Offset(0, 16),
                      ),
                      BoxShadow(
                        color: Colors.black.withAlpha(bgIsLight ? 24 : 70),
                        blurRadius: bgIsLight ? 12 : 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius),
                    child: AurumArtwork(
                      url: AurumArtwork.upgradeForFullPlayer(song.artworkUrl),
                      size: double.infinity,
                      borderRadius: radius,
                      suppressWhiteShimmer: true,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SongInfo extends StatelessWidget {
  final Song song;
  final double hPad;
  final bool isTablet, isFav;
  final VoidCallback onFavTap;
  final double bgLuma;
  final VoidCallback onLyricsTap;

  const _SongInfo({
    required this.song,
    required this.hPad,
    required this.isTablet,
    required this.isFav,
    required this.onFavTap,
    required this.bgLuma,
    required this.onLyricsTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bgIsLight = bgLuma >= 0.5;
    final textPrimary = bgIsLight ? AurumTheme.lightTextPrimary : Colors.white;
    final textSecondary =
        bgIsLight ? AurumTheme.lightTextSecondary : Colors.white.withAlpha(215);
    final titleSize = isTablet ? 26.0 : 22.0;
    final proximityToEdge = 1.0 - (2.0 * (bgLuma - 0.5).abs()).clamp(0.0, 1.0);
    final shadowColor = bgIsLight
        ? Colors.white.withAlpha((55 + proximityToEdge * 35).round())
        : Colors.black.withAlpha((160 + proximityToEdge * 40).round());
    final shadowBlur1 = bgIsLight ? 7.0 + proximityToEdge * 4 : 16.0 + proximityToEdge * 6;
    const shadowBlur2 = 7.0;
    final textShadows = bgIsLight
        ? [Shadow(color: shadowColor, blurRadius: shadowBlur1)]
        : [
            Shadow(color: shadowColor, blurRadius: shadowBlur1),
            Shadow(color: shadowColor, blurRadius: shadowBlur2),
          ];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MarqueeText(
                  text: song.title,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    letterSpacing: -0.5,
                    shadows: textShadows,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.1,
                    shadows: textShadows,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _FavButton(isFav: isFav, onTap: onFavTap),
              const SizedBox(height: 4),
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: isLight
                      ? AurumTheme.lightBgSurface.withAlpha(180)
                      : Colors.white.withAlpha(10),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(
                    color: isLight ? AurumTheme.lightDivider : Colors.white.withAlpha(14),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CastIconButton(size: 18, color: textSecondary),
                    GestureDetector(
                      onTap: () => showAudioOutputSheet(context),
                      child: Semantics(
                        label: l10n.audioOutputPickerTitle,
                        button: true,
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: Icon(Icons.speaker_group_rounded, size: 18, color: textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImmersiveLyricsTriggerButton extends StatelessWidget {
  final double bgLuma;
  final bool isActive;
  final VoidCallback onTap;
  const _ImmersiveLyricsTriggerButton({
    required this.bgLuma,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgIsLight = bgLuma >= 0.5;
    final iconColor = isActive
        ? (bgIsLight ? AurumTheme.lightTextPrimary : Colors.white)
        : (bgIsLight
            ? AurumTheme.lightTextSecondary
            : Colors.white.withAlpha(180));
    final fillColor = isActive
        ? (bgIsLight
            ? AurumTheme.lightTextPrimary.withAlpha(30)
            : Colors.white.withAlpha(42))
        : (bgIsLight
            ? AurumTheme.lightTextPrimary.withAlpha(18)
            : Colors.white.withAlpha(22));
    final borderColor = isActive
        ? (bgIsLight
            ? AurumTheme.lightTextPrimary.withAlpha(60)
            : Colors.white.withAlpha(90))
        : Colors.transparent;

    return AurumPressable(
      onTap: onTap,
      scaleAmount: 0.90,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: fillColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1),
        ),
        child: isActive
            ? ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFFEA4335),
                    Color(0xFFFBBC05),
                    Color(0xFF34A853),
                    Color(0xFF4285F4),
                  ],
                ).createShader(bounds),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 13,
                  color: Colors.white,
                ),
              )
            : Icon(
                Icons.auto_awesome_rounded,
                size: 13,
                color: iconColor,
              ),
      ),
    );
  }
}

class _ImmersiveGlowLayer extends StatelessWidget {
  final AnimationController controller;
  const _ImmersiveGlowLayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final rawT = (controller.value * 30).round() / 30;
        final glowVisibility = rawT < 0.14
            ? Curves.easeOut.transform((rawT / 0.14).clamp(0.0, 1.0))
            : rawT > 0.90
                ? Curves.easeIn.transform((1.0 - ((rawT - 0.90) / 0.10)).clamp(0.0, 1.0))
                : 1.0;
        if (glowVisibility <= 0.001) return const SizedBox.shrink();
        return IgnorePointer(
          child: CustomPaint(
            painter: _GlowAuraPainter(visibility: glowVisibility, t: rawT),
          ),
        );
      },
    );
  }
}

class _ImmersiveLyricsOverlay extends StatefulWidget {
  final AnimationController controller;
  final Song song;
  final Color bg1, bg2, bg3, bg4;
  final double dragY;
  final bool isDragging;
  final double maxArtSize;
  final VoidCallback onClose;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final ValueChanged<bool> onDragEnd;

  const _ImmersiveLyricsOverlay({
    required this.controller,
    required this.song,
    required this.bg1,
    required this.bg2,
    required this.bg3,
    required this.bg4,
    required this.dragY,
    required this.isDragging,
    required this.maxArtSize,
    required this.onClose,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_ImmersiveLyricsOverlay> createState() => _ImmersiveLyricsOverlayState();
}

class _ImmersiveLyricsOverlayState extends State<_ImmersiveLyricsOverlay> {
  static const double _dismissDistance = 120.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AudioPrefs.artworkShapeNotifier,
      builder: (context, shape, _) {
        final radius = shape == 'Circle'
            ? widget.maxArtSize / 2
            : shape == 'Square'
                ? 4.0
                : 20.0;
        return _buildOverlay(context, radius);
      },
    );
  }

  Widget _buildOverlay(BuildContext context, double radius) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final rawT = widget.controller.value;
        final t = Curves.easeInOutCubic.transform(rawT);

        final glowVisibility = t < 0.14
            ? Curves.easeOut.transform((t / 0.14).clamp(0.0, 1.0))
            : t > 0.90
                ? Curves.easeIn.transform((1.0 - ((t - 0.90) / 0.10)).clamp(0.0, 1.0))
                : 1.0;

        final artOpacity = (1.0 - (t / 0.45)).clamp(0.0, 1.0);
        final lyricsOpacity = (t / 0.55).clamp(0.0, 1.0);

        final artScale = 1.0 + (1 - artOpacity) * 0.05;
        final lyricsScale = 0.98 + lyricsOpacity * 0.02;
        final artBlur = glowVisibility * 4.0;

        final dragT = widget.isDragging
            ? (widget.dragY / (MediaQuery.of(context).size.height * 0.6))
                .clamp(0.0, 1.0)
            : 0.0;
        final overlayOpacity = t * (1 - dragT);

        if (t <= 0.0 && !widget.isDragging) {
          return const SizedBox.shrink();
        }

        return IgnorePointer(
          ignoring: t < 0.05,
          child: Opacity(
            opacity: overlayOpacity,
            child: Transform.translate(
              offset: Offset(0, widget.isDragging ? widget.dragY : 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(
                    fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: (1 - artOpacity).clamp(0.0, 1.0),
                      child: Builder(builder: (context) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(radius),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                ensureContrastSafe(widget.bg1, isLight: false),
                                ensureContrastSafe(widget.bg2, isLight: false),
                                ensureContrastSafe(widget.bg3, isLight: false),
                                ensureContrastSafe(widget.bg4, isLight: false),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    if (artOpacity > 0.001)
                      Opacity(
                        opacity: artOpacity,
                        child: Transform.scale(
                          scale: artScale,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: artBlur,
                              sigmaY: artBlur,
                            ),
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(48),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: AurumArtwork(
                                      url: AurumArtwork.upgradeForFullPlayer(widget.song.artworkUrl),
                                      size: double.infinity,
                                      borderRadius: 24,
                                      fadeIn: false,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (lyricsOpacity > 0.001)
                      Opacity(
                        opacity: lyricsOpacity,
                        child: Transform.scale(
                          scale: lyricsScale,
                          child: Column(
                            children: [
                              const SizedBox(height: 8),
                              Container(
                                width: 36,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(60),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const Expanded(child: AurumLyricsPage(onDarkBackdrop: true)),
                            ],
                          ),
                        ),
                      ),
                    if (lyricsOpacity > 0.001)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IgnorePointer(
                          ignoring: lyricsOpacity < 0.4,
                          child: Opacity(
                            opacity: lyricsOpacity,
                            child: AurumPressable(
                              onTap: widget.onClose,
                              scaleAmount: 0.90,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withAlpha(70),
                                  border: Border.all(
                                    color: Colors.white.withAlpha(50),
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GlowAuraPainter extends CustomPainter {
  final double visibility;
  final double t;
  const _GlowAuraPainter({
    required this.visibility,
    required this.t,
  });

  static const List<Color> _palette = [
    Color(0xFFEA4335),
    Color(0xFFFBBC05),
    Color(0xFF34A853),
    Color(0xFF4285F4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (visibility <= 0.001) return;

    final w = size.width;
    final h = size.height;
    final radius = math.max(w, h) * 0.62;

    final blooms = <_EdgeBloom>[
      _EdgeBloom(Offset(w * 0.5, -h * 0.12), _palette[0]),
      _EdgeBloom(Offset(w * 1.12, h * 0.5), _palette[1]),
      _EdgeBloom(Offset(w * 0.5, h * 1.12), _palette[2]),
      _EdgeBloom(Offset(-w * 0.12, h * 0.5), _palette[3]),
    ];

    for (var i = 0; i < blooms.length; i++) {
      final phase = (t * 2 * math.pi * 1.4) + (i * math.pi / 2);
      final breathe = 0.75 + 0.25 * (0.5 + 0.5 * math.sin(phase));
      final alpha = (190 * visibility * breathe).round().clamp(0, 255);

      final bloom = blooms[i];
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            bloom.color.withAlpha(alpha),
            bloom.color.withAlpha((alpha * 0.35).round()),
            bloom.color.withAlpha(0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: bloom.center, radius: radius));
      canvas.drawCircle(bloom.center, radius, paint);
    }

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withAlpha((90 * visibility).round())
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRect(
      Rect.fromLTWH(1.5, 1.5, w - 3, h - 3),
      rimPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GlowAuraPainter oldDelegate) =>
      oldDelegate.visibility != visibility || oldDelegate.t != t;
}

class _EdgeBloom {
  final Offset center;
  final Color color;
  const _EdgeBloom(this.center, this.color);
}

class _InlineLyricsStrip extends StatefulWidget {
  final double hPad;
  final double bgLuma;
  final VoidCallback onTap;
  const _InlineLyricsStrip({
    required this.hPad,
    required this.bgLuma,
    required this.onTap,
  });

  @override
  State<_InlineLyricsStrip> createState() => _InlineLyricsStripState();
}

class _InlineLyricsStripState extends State<_InlineLyricsStrip> {
  static const double _stripHeight = 34.0;

  LyricsResult? _result;
  String? _loadedForId;
  Song? _loadedForSong;

  @override
  Widget build(BuildContext context) {
    final watchedSong = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    if (watchedSong != null && watchedSong.id != _loadedForId) {
      _loadedForId = watchedSong.id;
      _loadedForSong = watchedSong;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetch();
      });
    }

    final bgIsLight = widget.bgLuma >= 0.5;
    final activeColor = bgIsLight ? AurumTheme.lightTextPrimary : Colors.white;
    final mutedColor = bgIsLight
        ? AurumTheme.lightTextSecondary
        : Colors.white.withAlpha(150);

    final result = _result;
    Widget content;
    if (result == null || !result.hasAny) {
      content = const SizedBox.shrink();
    } else if (!result.hasSynced) {
      content = _PlainLineTeaser(plain: result.plain!, mutedColor: mutedColor);
    } else {
      content = _SyncedLineTicker(
        result: result,
        activeColor: activeColor,
        mutedColor: mutedColor,
      );
    }

    return SizedBox(
      height: _stripHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.hPad),
          child: content,
        ),
      ),
    );
  }

  int _fetchGeneration = 0;

  Future<void> _fetch() async {
    final myGeneration = ++_fetchGeneration;
    final requestedForId = _loadedForId;
    final result = await context
        .read<PlayerProvider>()
        .fetchSyncedLyrics(forSong: _loadedForSong);
    if (!mounted) return;
    if (myGeneration != _fetchGeneration || requestedForId != _loadedForId) return;
    setState(() => _result = result);
  }
}

class _SyncedLineTicker extends StatelessWidget {
  final LyricsResult result;
  final Color activeColor;
  final Color mutedColor;
  const _SyncedLineTicker({
    required this.result,
    required this.activeColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    final idx = context.select<PlayerProvider, int>(
        (p) => result.activeIndexFor(p.position));
    final lineText =
        (idx >= 0 && idx < result.synced!.length) ? result.synced![idx].text : '';
    final showText = lineText.trim().isNotEmpty;

    return Align(
      alignment: Alignment.centerLeft,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.centerLeft,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          child: showText
              ? Row(
                  key: ValueKey(lineText),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        lineText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: activeColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: mutedColor),
                  ],
                )
              : const SizedBox.shrink(key: ValueKey('empty-line')),
        ),
      ),
    );
  }
}

class _PlainLineTeaser extends StatelessWidget {
  final String plain;
  final Color mutedColor;
  const _PlainLineTeaser({required this.plain, required this.mutedColor});

  @override
  Widget build(BuildContext context) {
    final firstLine = plain
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            firstLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mutedColor,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 18, color: mutedColor),
      ],
    );
  }
}

class _SeekBar extends StatelessWidget {
  final PlayerProvider player;
  final double hPad;
  final double bgLuma;
  const _SeekBar({required this.player, required this.hPad, required this.bgLuma});

  @override
  Widget build(BuildContext context) {
    final bgIsLight = bgLuma >= 0.5;
    final trackActive = bgIsLight ? AurumTheme.lightTextPrimary : Colors.white;
    final trackInactive = bgIsLight ? AurumTheme.lightBgSurface : Colors.white.withAlpha(28);
    final timeColor = bgIsLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(160);

    return AurumSeekBar(
      player: player,
      hPad: hPad,
      activeColor: trackActive,
      inactiveColor: trackInactive,
      timeColor: timeColor,
    );
  }
}

class _Controls extends StatelessWidget {
  final PlayerProvider player;
  final double hPad;
  final Animation<double> playBtnAnim;
  final Color bg1;
  final double bgLuma;
  final VoidCallback onPlayTap;

  const _Controls({
    required this.player,
    required this.hPad,
    required this.playBtnAnim,
    required this.bg1,
    required this.bgLuma,
    required this.onPlayTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLoopOne = player.loopMode == LoopMode.one;
    final isLoopAll = player.loopMode == LoopMode.all;
    final bgIsLight = bgLuma >= 0.5;
    final prevNextColor = bgIsLight
        ? AurumTheme.lightTextPrimary
        : Colors.white.withAlpha(220);
    final toggleOnColor = bgIsLight ? AurumTheme.lightTextPrimary : Colors.white;
    final toggleOffColor = bgIsLight
        ? AurumTheme.lightTextMuted
        : Colors.white.withAlpha(115);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: math.max(0.0, hPad - 21)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CtrlBtn(
            icon: Icons.shuffle_rounded,
            size: 24,
            active: player.shuffle,
            color: player.shuffle ? toggleOnColor : toggleOffColor,
            inactiveColor: toggleOffColor,
            semanticLabel: l10n.fpShuffle,
            onTap: () {
              AurumHaptics.selection();
              player.toggleShuffle();
            },
          ),
          _CtrlBtn(
            icon: Icons.skip_previous_rounded,
            size: 40,
            color: prevNextColor,
            inactiveColor: prevNextColor,
            semanticLabel: l10n.fpPrevious,
            onTap: () {
              AurumHaptics.medium();
              player.skipPrev();
            },
          ),
          ScaleTransition(
            scale: playBtnAnim,
            child: _PremiumPlayButton(
              isPlaying: player.isPlaying,
              isLoading: player.isLoading,
              bg1: bg1,
              onTap: onPlayTap,
            ),
          ),
          _CtrlBtn(
            icon: Icons.skip_next_rounded,
            size: 40,
            color: prevNextColor,
            inactiveColor: prevNextColor,
            semanticLabel: l10n.fpNext,
            onTap: () {
              AurumHaptics.medium();
              player.skipNext().then((allowed) {
                if (!allowed && context.mounted) {
                  PremiumGate.show(
                    context,
                    feature: AppLocalizations.of(context)!.fpUnlimitedSkipsFeature,
                    description: AppLocalizations.of(context)!.fpUnlimitedSkipsSignIn,
                    requiresLoginOnly: true,
                  );
                }
              });
            },
          ),
          _CtrlBtn(
            icon: isLoopOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            size: 24,
            active: isLoopOne || isLoopAll,
            color: (isLoopOne || isLoopAll) ? toggleOnColor : toggleOffColor,
            inactiveColor: toggleOffColor,
            semanticLabel: l10n.fpRepeat,
            onTap: () {
              AurumHaptics.selection();
              player.toggleLoop();
            },
          ),
        ],
      ),
    );
  }
}

class _QualityPills extends StatelessWidget {
  final Song song;
  final double hPad;
  final double bgLuma;
  const _QualityPills({required this.song, required this.hPad, required this.bgLuma});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final parts = <String>[];
    if (song.isLocal) parts.add(l10n.fpLocalBadge);
    if (song.language != null && song.language!.isNotEmpty) {
      parts.add(song.language!.toUpperCase());
    }
    if (song.year != null && song.year!.isNotEmpty) parts.add(song.year!);
    if (parts.isEmpty) return const SizedBox(height: 8);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        children: parts.map((p) => _QualityPill(label: p, bgLuma: bgLuma)).toList(),
      ),
    );
  }
}

class _BottomPill extends StatelessWidget {
  final double hPad;
  final double bgLuma;
  final VoidCallback onTap;
  const _BottomPill({required this.hPad, required this.bgLuma, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bgIsLight = bgLuma >= 0.5;
    final pillBg = bgIsLight ? AurumTheme.lightBgSurface.withAlpha(200) : Colors.white.withAlpha(18);
    final pillBorder = bgIsLight ? AurumTheme.lightDivider : Colors.white.withAlpha(28);
    final iconColor = bgIsLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(180);
    final textColor = bgIsLight ? AurumTheme.lightTextSecondary : Colors.white.withAlpha(200);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: GestureDetector(
        onTap: onTap,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -300) onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pillBorder, width: 0.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.keyboard_arrow_up_rounded, color: iconColor, size: 16),
              const SizedBox(width: 8),
              Text(
                l10n.fpQueueLyricsInfo,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumPlayButton extends StatefulWidget {
  final bool isPlaying, isLoading;
  final Color bg1;
  final VoidCallback onTap;

  const _PremiumPlayButton({
    required this.isPlaying,
    required this.isLoading,
    required this.bg1,
    required this.onTap,
  });

  @override
  State<_PremiumPlayButton> createState() => _PremiumPlayButtonState();
}

class _PremiumPlayButtonState extends State<_PremiumPlayButton> {
  void _handleTap() {
    if (widget.isLoading) return;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final buttonColorMode = context.watch<ThemeProvider>().playerButtonColorMode;
    final accent = context.watch<ThemeProvider>().accentColor;
    final circleColor = buttonColorMode == 'Accent' ? accent : Colors.white;
    final iconColor = buttonColorMode == 'Accent'
        ? (ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
            ? Colors.white
            : Colors.black)
        : Colors.black;

    return Semantics(
      label: widget.isPlaying ? l10n.fpPause : l10n.fpPlay,
      button: true,
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 68,
          height: 68,
          child: Container(
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: circleColor.withAlpha(38),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: widget.bg1.withAlpha(128),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: widget.isLoading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 26,
                          height: 26,
                          child:
                              Center(child: AurumM3Loader(width: 26, height: 2.5)),
                        )
                      : AurumPlayPauseIcon(
                          key: const ValueKey('playpause'),
                          isPlaying: widget.isPlaying,
                          color: iconColor,
                          size: 36,
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FavButton extends StatelessWidget {
  final bool isFav;
  final VoidCallback onTap;
  const _FavButton({required this.isFav, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<ThemeProvider>().accentColor;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: AurumLikeButton(
        isLiked: isFav,
        size: 24,
        likedColor: accent,
        unlikedColor: Colors.white.withAlpha(128),
        onTap: onTap,
      ),
    );
  }
}

class _QualityPill extends StatelessWidget {
  final String label;
  final double bgLuma;
  const _QualityPill({required this.label, required this.bgLuma});

  @override
  Widget build(BuildContext context) {
    final bgIsLight = bgLuma >= 0.5;
    final fill = bgIsLight
        ? AurumTheme.lightBgSurface.withAlpha(210)
        : Colors.white.withAlpha(24);
    final border = bgIsLight
        ? AurumTheme.lightDivider
        : Colors.white.withAlpha(45);
    final textColor = bgIsLight
        ? AurumTheme.lightTextSecondary
        : Colors.white.withAlpha(220);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

void shareSong(BuildContext context, Song song) {
  final l10n = AppLocalizations.of(context)!;
  final text = l10n.fpShareText(song.artist, song.title);
  Share.share(text, subject: song.title);
}

void showAurumFullPlayerOptionsSheet(
  BuildContext context,
  Song song, {
  Color? accentColor,
}) {
  showAurumSongOptions(context, song, showPlayerTools: true);
}

void showSleepTimerForSong(BuildContext context, PlayerProvider player) {
  final handler = player.handler;
  bool finishSong = false;
  bool fadeOut = SleepTimerService.instance.lastFadeOutChoice;
  AurumHaptics.light();
  showAurumModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withAlpha(150),
    builder: (_) => SleepTimerSheet(
      engine: handler,
      finishSong: finishSong,
      fadeOut: fadeOut,
      onFinishSongChanged: (v) => finishSong = v,
      onFadeOutChanged: (v) => fadeOut = v,
    ),
  );
}

void showSongInfoDialog(BuildContext context, Song song) {
  final l10n = AppLocalizations.of(context)!;
  final bgColor = AurumTheme.bgCardOf(context);
  final textPrimary = AurumTheme.textPrimaryOf(context);
  final textMuted = AurumTheme.textSecondaryOf(context);
  final divider = AurumTheme.dividerOf(context);

  final rows = <MapEntry<String, String>>[
    MapEntry(l10n.fpSongInfoTitle, song.title),
    MapEntry(l10n.fpSongInfoArtist, song.artist),
    if (song.album.isNotEmpty) MapEntry(l10n.fpSongInfoAlbum, song.album),
    if (song.durationString.isNotEmpty) MapEntry(l10n.fpSongInfoDuration, song.durationString),
    if (song.year != null && song.year!.isNotEmpty) MapEntry(l10n.fpSongInfoYear, song.year!),
    if (song.language != null && song.language!.isNotEmpty) MapEntry(l10n.fpSongInfoLanguage, song.language!),
  ];

  AurumHaptics.light();
  showAurumModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withAlpha(150),
    builder: (_) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: bgColor.withAlpha(245),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: divider, width: 0.5)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: textMuted.withAlpha(80),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: AurumTheme.accentOf(context), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        l10n.fpSongInfo,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (final row in rows) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              row.key,
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              row.value,
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (row.key != rows.last.key)
                      Divider(height: 1, color: divider),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PremiumContentPanel extends StatefulWidget {
  final Color bg1, bg2, bg3;
  final int initialTab;
  const _PremiumContentPanel(
      {required this.bg1, required this.bg2, required this.bg3, this.initialTab = 0});

  @override
  State<_PremiumContentPanel> createState() => _PremiumContentPanelState();
}

class _PremiumContentPanelState extends State<_PremiumContentPanel>
    with TickerProviderStateMixin {
  late int _activeTab = widget.initialTab;
  final ValueNotifier<double> _dragYNotifier = ValueNotifier(0.0);
  double get _dragY => _dragYNotifier.value;
  set _dragY(double v) => _dragYNotifier.value = v;

  static const _tabSwitchDuration = Duration(milliseconds: 140);

  late final AnimationController _springBackCtrl;
  Animation<double>? _springBackAnim;

  late final AnimationController _exitCtrl;
  late final Animation<double> _exitTranslate;
  late final Animation<double> _exitFade;

  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _springBackCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _springBackCtrl.addListener(() {
      if (_springBackAnim != null) {
        _dragY = _springBackAnim!.value;
      }
    });

    _exitCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _exitTranslate = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic));
    _exitFade = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(
            parent: _exitCtrl,
            curve: const Interval(0.7, 1.0, curve: Curves.easeInCubic)));
  }

  @override
  void dispose() {
    _springBackCtrl.dispose();
    _exitCtrl.dispose();
    _dragYNotifier.dispose();
    super.dispose();
  }

  void _switchTab(int idx) {
    if (idx == _activeTab) return;
    AurumHaptics.selection();
    setState(() => _activeTab = idx);
  }

  void _springBackToZero() {
    _springBackAnim = Tween<double>(begin: _dragY, end: 0).animate(
      CurvedAnimation(parent: _springBackCtrl, curve: Curves.elasticOut),
    );
    _springBackCtrl
      ..reset()
      ..forward();
  }

  double _dismissStartDragY = 0;

  void _dismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    AurumHaptics.light();
    _springBackCtrl.stop();
    _dismissStartDragY = _dragY;
    _exitCtrl.forward().then((_) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final panelHeight = (screenH * 0.92 + bottomInset)
        .clamp(360.0, screenH - topInset - 12.0 + bottomInset);
    final exitOffsetY = _exitTranslate.value * screenH * 0.4;

    final List<Color> glassColors = isLight
        ? [
            Color.lerp(widget.bg1, Colors.white, 0.86)!.withAlpha(196),
            Color.lerp(widget.bg2, Colors.white, 0.90)!.withAlpha(204),
            Color.lerp(widget.bg3, Colors.white, 0.94)!.withAlpha(214),
          ]
        : [
            Color.lerp(widget.bg1, const Color(0xFF0A0A16), 0.5)!
                .withAlpha(168),
            Color.lerp(widget.bg2, const Color(0xFF060610), 0.5)!
                .withAlpha(180),
            Color.lerp(widget.bg3, const Color(0xFF020206), 0.6)!
                .withAlpha(198),
          ];

    final borderColor =
        isLight ? AurumTheme.lightDivider : Colors.white.withAlpha(28);
    final highlightColor =
        isLight ? Colors.white.withAlpha(140) : Colors.white.withAlpha(40);
    final handleColor = isLight
        ? AurumTheme.lightTextMuted.withAlpha(90)
        : Colors.white.withAlpha(40);

    final overlayStyle = isLight
        ? SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
            systemNavigationBarIconBrightness: Brightness.dark,
          )
        : SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
            systemNavigationBarIconBrightness: Brightness.light,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: AnimatedBuilder(
      animation: _exitCtrl,
      builder: (context, _) {
        return ValueListenableBuilder<double>(
          valueListenable: _dragYNotifier,
          builder: (context, dragY, panelChild) {
            final effectiveDragY = _isDismissing ? _dismissStartDragY : dragY;
            final dragFraction = (effectiveDragY / screenH).clamp(0.0, 1.0);
            final dragOpacity =
                1.0 - ((dragFraction - 0.75) / 0.25).clamp(0.0, 1.0);
            final scale = (1.0 - dragFraction * 0.06).clamp(0.88, 1.0);
            final opacity = _isDismissing
                ? _exitFade.value
                : (dragOpacity * _exitFade.value).clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(
                  0,
                  effectiveDragY.clamp(0.0, screenH) + exitOffsetY),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: Opacity(
                  opacity: opacity,
                  child: panelChild,
                ),
              ),
            );
          },
          child: SizedBox(
                width: screenW,
                height: panelHeight,
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(32)),
                  child: RepaintBoundary(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(32)),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: glassColors,
                                stops: const [0.0, 0.5, 1.0],
                              ),
                              border: Border(
                                top: BorderSide(color: borderColor, width: 0.5),
                              ),
                            ),
                            child: Column(children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onVerticalDragUpdate: (d) {
                                  _springBackCtrl.stop();
                                  _dragY = (_dragY + d.delta.dy)
                                      .clamp(0.0, double.infinity);
                                },
                                onVerticalDragEnd: (d) {
                                  if (_dragY > 90 ||
                                      (d.primaryVelocity ?? 0) > 600) {
                                    _dismiss();
                                  } else {
                                    _springBackToZero();
                                  }
                                },
                                child: Container(
                                  width: double.infinity,
                                  color: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 32,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: handleColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                              _buildTabBar(isLight),
                              Expanded(
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: (notification) {
                                    if (notification is OverscrollNotification &&
                                        notification.overscroll < 0) {
                                      _springBackCtrl.stop();
                                      _dragY += -notification.overscroll;
                                    } else if (notification is ScrollEndNotification) {
                                      if (_dragY > 90) {
                                        _dismiss();
                                      } else if (_dragY > 0) {
                                        _springBackToZero();
                                      }
                                    }
                                    return false;
                                  },
                                  child: AnimatedSwitcher(
                                  duration: _tabSwitchDuration,
                                  switchInCurve: Curves.easeOut,
                                  switchOutCurve: Curves.easeIn,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                  layoutBuilder:
                                      (currentChild, previousChildren) =>
                                          Stack(
                                    alignment: Alignment.topCenter,
                                    children: [
                                      ...previousChildren,
                                      if (currentChild != null) currentChild,
                                    ],
                                  ),
                                  child: KeyedSubtree(
                                    key: ValueKey(_activeTab),
                                    child: Padding(
                                      padding: EdgeInsets.only(bottom: bottomInset),
                                      child: _buildTabContent(),
                                    ),
                                  ),
                                ),
                                ),
                              ),
                            ]),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 1,
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(32)),
                                gradient: LinearGradient(
                                  colors: [
                                    highlightColor,
                                    highlightColor.withAlpha(0),
                                  ],
                                  stops: const [0.0, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        );
      },
    ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case 0:
        return const _QueuePage();
      case 1:
        return const AurumLyricsPage();
      case 2:
        return const _InfoPage();
      default:
        return const _QueuePage();
    }
  }

  Widget _buildTabBar(bool isLight) {
    final l10n = AppLocalizations.of(context)!;
    final tabs = [l10n.fpQueue, l10n.fpLyrics, l10n.fpInfo];

    final inactiveBg =
        isLight ? Colors.black.withAlpha(10) : Colors.white.withAlpha(16);
    final activeBg =
        isLight ? Colors.white : Colors.white.withAlpha(235);
    final activeText = Colors.black87;
    final inactiveText =
        isLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(150);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: SizedBox(
        height: 48,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final isActive = _activeTab == i;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? 0 : 3,
                  right: i == tabs.length - 1 ? 0 : 3,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _switchTab(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: isActive ? activeBg : inactiveBg,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: Colors.black.withAlpha(30),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        color: isActive ? activeText : inactiveText,
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _QueuePage extends StatefulWidget {
  const _QueuePage();

  @override
  State<_QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<_QueuePage> {
  List<Song> _localQueue = const [];
  int? _localCurrent;

  List<String>? _pendingTargetIds;

  DateTime? _pendingTargetSetAt;
  static const _pendingTargetTimeout = Duration(seconds: 3);

  void _syncFromProvider(List<Song> queue, int? current) {
    final pending = _pendingTargetIds;
    if (pending != null) {
      final setAt = _pendingTargetSetAt;
      final timedOut = setAt == null ||
          DateTime.now().difference(setAt) > _pendingTargetTimeout;
      final incomingIds = List.generate(queue.length, (i) => queue[i].id);
      if (incomingIds.length == pending.length &&
          incomingIds.join(',') == pending.join(',')) {
        _pendingTargetIds = null;
        _pendingTargetSetAt = null;
        _localCurrent = current;
        return;
      }
      if (incomingIds.length == pending.length && !timedOut) {
        return;
      }
      _pendingTargetIds = null;
      _pendingTargetSetAt = null;
    }
    _localQueue = List<Song>.of(queue);
    _localCurrent = current;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final mutedIcon =
        isLight ? AurumTheme.lightTextMuted.withAlpha(70) : Colors.white.withAlpha(22);
    final mutedText =
        isLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(60);

    return Selector<PlayerProvider,
        ({List<Song> queue, int? current, bool building, String sig})>(
      selector: (_, player) => (
        queue: player.queue,
        current: player.currentIndex,
        building: player.isBuildingQueue,
        sig: player.queue.map((e) => e.id).join('|'),
      ),
      builder: (context, data, _) {
        _syncFromProvider(data.queue, data.current);
        final queue = _localQueue;
        final current = _localCurrent;

        if (queue.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.queue_music_rounded,
                    color: mutedIcon, size: 56),
                const SizedBox(height: 16),
                Text(
                  l10n.fpQueueEmpty,
                  style: TextStyle(
                    color: mutedText,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          );
        }

        final upNext = <int>[];
        for (int i = 0; i < queue.length; i++) {
          if (i != current) upNext.add(i);
        }

        final seenIds = <String, int>{};
        final tileKeys = List<Key>.generate(queue.length, (i) {
          final id = queue[i].id;
          final n = (seenIds[id] = (seenIds[id] ?? 0) + 1);
          return ValueKey('upnext_${id}_$n');
        });

        return CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            if (current != null && current < queue.length)
              SliverToBoxAdapter(
                child: _NowPlayingHeader(song: queue[current]),
              ),
            if (upNext.isEmpty && data.building)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.fpUpNext,
                        style: TextStyle(
                          color: mutedText,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const AurumM3Loader(width: 22, height: 2.5),
                          const SizedBox(width: 12),
                          Text(
                            l10n.fpFindingSongs,
                            style: TextStyle(color: mutedText, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (upNext.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(
                    l10n.fpUpNext,
                    style: TextStyle(
                      color: mutedText,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.8,
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              sliver: SliverReorderableList(
                itemCount: upNext.length,
                proxyDecorator: (child, index, animation) {
                  return Material(
                    type: MaterialType.transparency,
                    child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) {
                      final t = Curves.easeOut.transform(animation.value);
                      final scale = 1.0 + (0.03 * t);
                      return Transform.scale(
                        scale: scale,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha((110 * t).round()),
                                blurRadius: 20 * t,
                                offset: Offset(0, 6 * t),
                              ),
                            ],
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: child,
                    ),
                  );
                },
                onReorder: (oldListIdx, newListIdx) {
                  AurumHaptics.medium();
                  final fromQueueIdx = upNext[oldListIdx];
                  var toListIdx = newListIdx;
                  if (oldListIdx < newListIdx) toListIdx -= 1;
                  final toQueueIdx = upNext[toListIdx];
                  setState(() {
                    final item = _localQueue.removeAt(fromQueueIdx);
                    final clampedTo = toQueueIdx.clamp(0, _localQueue.length);
                    _localQueue.insert(clampedTo, item);
                    if (fromQueueIdx == _localCurrent) {
                      _localCurrent = clampedTo;
                    } else if (fromQueueIdx < (_localCurrent ?? -1) &&
                        clampedTo >= (_localCurrent ?? -1)) {
                      _localCurrent = (_localCurrent ?? 0) - 1;
                    } else if (fromQueueIdx > (_localCurrent ?? -1) &&
                        clampedTo <= (_localCurrent ?? -1)) {
                      _localCurrent = (_localCurrent ?? 0) + 1;
                    }
                  });
                  _pendingTargetIds =
                      _localQueue.map((s) => s.id).toList();
                  _pendingTargetSetAt = DateTime.now();
                  unawaited(context
                      .read<PlayerProvider>()
                      .moveQueueItem(fromQueueIdx, toQueueIdx));
                },
                itemBuilder: (context, listIdx) {
                  final queueIdx = upNext[listIdx];
                  final isNextUp = listIdx == 0;
                  return KeyedSubtree(
                    key: tileKeys[queueIdx],
                    child: _QueueTile(
                      song: queue[queueIdx],
                      isCurrent: false,
                      isNextUp: isNextUp,
                      index: listIdx + 1,
                      reorderIndex: listIdx,
                      onTap: () {
                        AurumHaptics.selection();
                        context.read<PlayerProvider>().skipToIndex(queueIdx);
                      },
                      onRemove: () {
                        AurumHaptics.medium();
                        context.read<PlayerProvider>().removeFromQueue(queueIdx);
                      },
                      onPlayNext: () async {
                        AurumHaptics.selection();
                        final song = queue[queueIdx];
                        final p = context.read<PlayerProvider>();
                        await p.removeFromQueue(queueIdx);
                        await p.playNext(song);
                      },
                      onMoveToTop: () {
                        AurumHaptics.selection();
                        final p = context.read<PlayerProvider>();
                        final target = (p.currentIndex ?? 0) + 1;
                        p.moveQueueItem(queueIdx, target);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NowPlayingHeader extends StatelessWidget {
  final Song song;
  const _NowPlayingHeader({required this.song});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final textPrimary = isLight ? AurumTheme.lightTextPrimary : Colors.white;
    final textSecondary = isLight ? AurumTheme.lightTextSecondary : Colors.white.withAlpha(200);
    final cardBg = isLight
        ? AurumTheme.accent.withAlpha(22)
        : AurumTheme.accent.withAlpha(18);
    final isPlaying = context.select<PlayerProvider, bool>((p) => p.isPlaying);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AurumTheme.accent.withAlpha(40), width: 0.5),
        ),
        child: Row(children: [
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AurumArtwork(url: song.artworkUrl, size: 54, borderRadius: 12),
            ),
            Positioned(
              bottom: 0, right: 0,
              child: Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: AurumTheme.accent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(child: _MiniEqualizerIcon(isPlaying: isPlaying)),
              ),
            ),
          ]),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.fpNowPlaying,
                style: TextStyle(color: AurumTheme.accent.withAlpha(200),
                    fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
              const SizedBox(height: 3),
              Text(song.title,
                style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600, height: 1.2),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(song.artist,
                style: TextStyle(color: textSecondary, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          )),
        ]),
      ),
    );
  }
}

class _MiniEqualizerIcon extends StatefulWidget {
  final bool isPlaying;
  const _MiniEqualizerIcon({this.isPlaying = true});

  @override
  State<_MiniEqualizerIcon> createState() => _MiniEqualizerIconState();
}

class _MiniEqualizerIconState extends State<_MiniEqualizerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    if (widget.isPlaying) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_MiniEqualizerIcon old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !old.isPlaying) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isPlaying && old.isPlaying) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final v = widget.isPlaying ? _ctrl.value : 0.0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(widget.isPlaying ? 0.4 + 0.6 * v : 0.3, 7),
            const SizedBox(width: 1),
            _bar(widget.isPlaying ? 0.9 - 0.5 * v : 0.45, 7),
            const SizedBox(width: 1),
            _bar(widget.isPlaying ? 0.6 + 0.4 * v : 0.3, 7),
          ],
        );
      },
    );
  }

  Widget _bar(double f, double maxH) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        width: 2,
        height: maxH * f,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(180),
          borderRadius: BorderRadius.circular(1),
        ),
      );
}

class _QueueTile extends StatefulWidget {
  final Song song;
  final bool isCurrent;
  final bool isNextUp;
  final int index;
  final int reorderIndex;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onPlayNext;
  final VoidCallback onMoveToTop;

  const _QueueTile({
    required this.song,
    required this.isCurrent,
    this.isNextUp = false,
    required this.index,
    required this.reorderIndex,
    required this.onTap,
    required this.onRemove,
    required this.onPlayNext,
    required this.onMoveToTop,
  });

  @override
  State<_QueueTile> createState() => _QueueTileState();
}

class _QueueTileState extends State<_QueueTile> {
  void _confirmDelete() {
    AurumHaptics.heavy();
    widget.onRemove();
  }

  void _showQuickActions() {
    AurumHaptics.medium();
    final isLight = Theme.of(context).brightness == Brightness.light;
    showAurumModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (sheetCtx) => _QueueQuickActionsSheet(
        song: widget.song,
        isLight: isLight,
        onPlayNext: () {
          Navigator.pop(sheetCtx);
          widget.onPlayNext();
        },
        onMoveToTop: () {
          Navigator.pop(sheetCtx);
          widget.onMoveToTop();
        },
        onRemove: () {
          Navigator.pop(sheetCtx);
          _confirmDelete();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    return RepaintBoundary(
      child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: _showQuickActions,
          child: Builder(builder: (context) {
            final tileBg = widget.isNextUp
                ? (isLight
                    ? AurumTheme.accent.withAlpha(20)
                    : AurumTheme.accent.withAlpha(16))
                : (isLight
                    ? AurumTheme.lightBgSurface.withAlpha(180)
                    : Colors.white.withAlpha(7));
            final tileBorder = widget.isNextUp
                ? AurumTheme.accent.withAlpha(isLight ? 70 : 55)
                : (isLight ? AurumTheme.lightDivider : Colors.white.withAlpha(10));
            final textPrimary = isLight ? AurumTheme.lightTextPrimary : Colors.white.withAlpha(220);
            final textSecondary = isLight ? AurumTheme.lightTextSecondary : Colors.white.withAlpha(80);
            final indexColor = widget.isNextUp
                ? AurumTheme.accent.withAlpha(200)
                : (isLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(45));
            final dragColor = isLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(40);

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: tileBorder,
                  width: widget.isNextUp ? 1.0 : 0.5,
                ),
              ),
              child: Row(children: [
                if (widget.isNextUp)
                  Container(
                    width: 3,
                    height: 36,
                    margin: const EdgeInsets.only(right: 9),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AurumTheme.accent.withAlpha(220),
                          AurumTheme.accent.withAlpha(90),
                        ],
                      ),
                    ),
                  ),
                SizedBox(
                  width: 22,
                  child: Text('${widget.index}',
                    style: TextStyle(color: indexColor, fontSize: 12, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center),
                ),
                const SizedBox(width: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AurumArtwork(url: widget.song.artworkUrl, size: 44, borderRadius: 10),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.song.title,
                      style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(widget.song.artist,
                      style: TextStyle(color: textSecondary, fontSize: 11.5),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                )),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _confirmDelete,
                  icon: Icon(Icons.close_rounded, color: dragColor, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                  splashRadius: 18,
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: ReorderableDragStartListener(
                    index: widget.reorderIndex,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle_rounded, color: dragColor, size: 18),
                    ),
                  ),
                ),
              ]),
            );
          }),
        ),
      );
  }
}

class _QueueQuickActionsSheet extends StatelessWidget {
  final Song song;
  final bool isLight;
  final VoidCallback onPlayNext;
  final VoidCallback onMoveToTop;
  final VoidCallback onRemove;

  const _QueueQuickActionsSheet({
    required this.song,
    required this.isLight,
    required this.onPlayNext,
    required this.onMoveToTop,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bg = isLight ? Colors.white : const Color(0xFF15141C);
    final textPrimary = isLight ? AurumTheme.lightTextPrimary : Colors.white;
    final textSecondary = isLight ? AurumTheme.lightTextSecondary : Colors.white.withAlpha(120);
    final dividerColor = isLight ? AurumTheme.lightDivider : Colors.white.withAlpha(14);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AurumArtwork(url: song.artworkUrl, size: 44, borderRadius: 10),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                      style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(song.artist,
                      style: TextStyle(color: textSecondary, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                )),
              ]),
            ),
            Divider(color: dividerColor, height: 1),
            _actionTile(
              icon: Icons.skip_next_rounded,
              label: l10n.fpPlayNext,
              textPrimary: textPrimary,
              onTap: onPlayNext,
            ),
            _actionTile(
              icon: Icons.vertical_align_top_rounded,
              label: l10n.fpMoveToTop,
              textPrimary: textPrimary,
              onTap: onMoveToTop,
            ),
            _actionTile(
              icon: Icons.delete_outline_rounded,
              label: l10n.fpRemoveFromQueue,
              textPrimary: Colors.redAccent,
              onTap: onRemove,
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color textPrimary,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(children: [
          Icon(icon, color: textPrimary, size: 21),
          const SizedBox(width: 16),
          Text(label,
              style: TextStyle(
                  color: textPrimary, fontSize: 14.5, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

class AurumLyricsPage extends StatefulWidget {
  final bool onDarkBackdrop;
  const AurumLyricsPage({super.key, this.onDarkBackdrop = false});

  @override
  State<AurumLyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<AurumLyricsPage> {
  LyricsResult? _result;
  bool _loading = true;
  bool _notFound = false;
  Song? _loadedFor;
  int _activeIndex = -1;

  int _fetchGeneration = 0;

  final ScrollController _scrollController = ScrollController();
  DateTime _userScrollHoldUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool _needsInstantScroll = true;
  final GlobalKey _listKey = GlobalKey();
  final Map<int, GlobalKey> _lineKeys = {};

  GlobalKey _keyFor(int index) =>
      _lineKeys.putIfAbsent(index, () => GlobalKey());

  LyricsTranslation? _tr;
  bool _trLoading = false;
  bool _trFailed = false;
  int _trGen = 0;
  List<LyricLine>? _trLinesCache;

  LyricsTranslation? get _activeTr =>
      (_tr != null && !_tr!.sameLanguage) ? _tr : null;

  @override
  void initState() {
    super.initState();
    LyricsTranslatePrefs.targetNotifier.addListener(_onTrPrefChanged);
    LyricsTranslatePrefs.modeNotifier.addListener(_onTrModeChanged);
    LyricsTranslatePrefs.ensureLoaded().then((_) {
      if (mounted) _maybeTranslate();
    });
  }

  @override
  void dispose() {
    LyricsTranslatePrefs.targetNotifier.removeListener(_onTrPrefChanged);
    LyricsTranslatePrefs.modeNotifier.removeListener(_onTrModeChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onTrPrefChanged() {
    if (mounted) _maybeTranslate();
  }

  void _onTrModeChanged() {
    if (mounted) setState(() {});
  }

  List<String> _sourceLines() {
    final r = _result;
    if (r == null) return const [];
    if (r.hasSynced) return [for (final l in r.synced!) l.text];
    return (r.plain ?? '').split('\n');
  }

  List<LyricLine> _translatedOnlyLines(
      List<LyricLine> raw, LyricsTranslation tr) {
    return _trLinesCache ??= [
      for (var i = 0; i < raw.length; i++)
        LyricLine(
          time: raw[i].time,
          text: (i < tr.lines.length && tr.lines[i].trim().isNotEmpty)
              ? tr.lines[i]
              : raw[i].text,
        ),
    ];
  }

  Future<void> _maybeTranslate() async {
    final target = LyricsTranslatePrefs.targetNotifier.value;
    final result = _result;
    final song = _loadedFor;
    final gen = ++_trGen;
    if (target == null || result == null || song == null || _loading) {
      if (_tr != null || _trLoading || _trFailed) {
        setState(() {
          _tr = null;
          _trLoading = false;
          _trFailed = false;
          _trLinesCache = null;
        });
      }
      return;
    }
    final src = _sourceLines();
    final cacheKey = '${song.id}|${result.hasSynced ? 's' : 'p'}';
    final cached = LyricsTranslationService.peek(cacheKey, target);
    if (cached != null && cached.lines.length == src.length) {
      setState(() {
        _tr = cached;
        _trLoading = false;
        _trFailed = false;
        _trLinesCache = null;
      });
      return;
    }
    setState(() {
      _trLoading = true;
      _trFailed = false;
      _tr = null;
      _trLinesCache = null;
    });
    final r = await LyricsTranslationService.translate(
      cacheKey: cacheKey,
      lines: src,
      target: target,
      songLanguageHint: song.language,
    );
    if (!mounted || gen != _trGen) return;
    setState(() {
      _trLoading = false;
      _tr = r;
      _trFailed = r == null;
      _trLinesCache = null;
    });
    if (r == null) {
      AurumSnack.show(
        context,
        "Couldn't translate lyrics. Check your connection.",
        duration: const Duration(seconds: 4),
        actionLabel: 'Retry',
        onAction: _maybeTranslate,
      );
    } else if (r.sameLanguage) {
      final n = translationLangFor(target)?.name ?? target;
      AurumSnack.show(context, 'Lyrics are already in $n');
    }
  }

  String? _translateInfo() {
    final tr = _tr;
    if (tr == null) return null;
    final tName = translationLangFor(tr.target)?.name ?? tr.target;
    if (tr.sameLanguage) return 'Already in $tName';
    final code = tr.sourceLang?.split('-').first;
    final sName = translationLangFor(code)?.name ?? code;
    if (sName == null) return null;
    return tr.transliterated ? '$sName (romanised) → $tName' : '$sName → $tName';
  }

  void _openTranslateSheet() {
    AurumHaptics.light();
    showAurumModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TranslateSheet(info: _translateInfo()),
    );
  }

  Future<void> _fetchLyrics() async {
    if (!mounted) return;
    final myGeneration = ++_fetchGeneration;
    final requestedForId = _loadedFor?.id;
    _lineKeys.clear();
    _needsInstantScroll = true;
    _trGen++;
    setState(() {
      _loading = true;
      _notFound = false;
      _result = null;
      _activeIndex = -1;
      _tr = null;
      _trLoading = false;
      _trFailed = false;
      _trLinesCache = null;
    });
    final result = await context
        .read<PlayerProvider>()
        .fetchSyncedLyrics(forSong: _loadedFor);
    if (!mounted) return;
    if (myGeneration != _fetchGeneration || requestedForId != _loadedFor?.id) {
      return;
    }
    setState(() {
      _loading = false;
      if (result.hasAny) {
        _result = result;
      } else {
        _notFound = true;
      }
    });
    if (result.hasAny) _maybeTranslate();
  }

  void _onPositionChanged(Duration position) {
    final result = _result;
    if (result == null || !result.hasSynced) return;
    final idx = result.activeIndexFor(position);
    if (idx != _activeIndex) {
      _activeIndex = idx;
      if (mounted) setState(() {});
      if (idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToActiveLine(idx);
        });
      }
    }
  }

  void _scrollToActiveLine(int index, {bool retry = true}) {
    if (!_scrollController.hasClients) return;
    final lineContext = _lineKeys[index]?.currentContext;
    final listBox =
        _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (lineContext == null || listBox == null) {
      final total = _result?.synced?.length ?? 0;
      if (retry && listBox != null && total > 0) {
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo((max * index / total).clamp(0.0, max));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToActiveLine(index, retry: false);
        });
      }
      return;
    }
    final lineBox = lineContext.findRenderObject() as RenderBox?;
    if (lineBox == null) return;

    final linePositionInList =
        lineBox.localToGlobal(Offset.zero, ancestor: listBox).dy;
    final viewportHeight = _scrollController.position.viewportDimension;
    final currentOffset = _scrollController.offset;

    final lineAbsoluteTop = currentOffset + linePositionInList;
    final targetOffset =
        (lineAbsoluteTop - viewportHeight * 0.30).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    if (_needsInstantScroll) {
      _needsInstantScroll = false;
      _scrollController.jumpTo(targetOffset);
      return;
    }
    if (DateTime.now().isBefore(_userScrollHoldUntil)) return;

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = context.select<PlayerProvider, Song?>((p) => p.currentSong);
    if (song != null && song.id != _loadedFor?.id) {
      _loadedFor = song;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchLyrics();
      });
    }

    final l10n = AppLocalizations.of(context)!;
    final isLight = !widget.onDarkBackdrop &&
        Theme.of(context).brightness == Brightness.light;
    final lyricsAccent =
        context.select<ThemeProvider, Color>((t) => t.accentColor);
    final mutedIcon =
        isLight ? AurumTheme.lightTextMuted.withAlpha(80) : Colors.white.withAlpha(25);
    final primaryMuted =
        isLight ? AurumTheme.lightTextSecondary : Colors.white.withAlpha(140);
    final secondaryMuted =
        isLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(70);

    Widget content;
    if (_loading) {
      content = const Center(
        key: ValueKey('loading'),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 48),
          child: AurumMorphLoader(contained: true),
        ),
      );
    } else if (_notFound) {
      content = Center(
        key: const ValueKey('not-found'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lyrics_rounded, color: mutedIcon, size: 52),
            const SizedBox(height: 16),
            Text(
              l10n.fpNoLyricsFound,
              style: TextStyle(
                color: primaryMuted,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.fpLyricsNotAvailable,
              style: TextStyle(color: secondaryMuted, fontSize: 13),
            ),
          ],
        ),
      );
    } else if (_result!.hasSynced) {
      final rawLines = _result!.synced!;
      final tr = _activeTr;
      final trOnly = tr != null &&
          LyricsTranslatePrefs.modeNotifier.value ==
              TranslationDisplay.translationOnly;
      final displayLines =
          trOnly ? _translatedOnlyLines(rawLines, tr!) : rawLines;
      final subLines = (tr != null && !trOnly) ? tr.lines : null;
      final constellationLines =
          tr != null ? _translatedOnlyLines(rawLines, tr) : rawLines;
      content = ValueListenableBuilder<LyricsViewMode>(
        key: const ValueKey('synced-lyrics'),
        valueListenable: AudioPrefs.lyricsViewModeNotifier,
        builder: (context, mode, _) {
          if (widget.onDarkBackdrop && mode == LyricsViewMode.fullscreen) {
            return ConstellationLyrics(
              lines: constellationLines,
              accent: lyricsAccent,
              isLight: isLight,
            );
          }
          return _SyncedLyricsView(
            lines: displayLines,
            activeIndex: _activeIndex,
            scrollController: _scrollController,
            listKey: _listKey,
            lineKeyFor: _keyFor,
            onPositionChanged: _onPositionChanged,
            isLight: isLight,
            subLines: subLines,
          );
        },
      );
    } else {
      final rawPlain = _result!.plain ?? '';
      final tr = _activeTr;
      final trMode = LyricsTranslatePrefs.modeNotifier.value;
      final srcPlain = rawPlain.split('\n');
      final canPair = tr != null && tr.lines.length == srcPlain.length;
      final displayPlain = (canPair && trMode == TranslationDisplay.translationOnly)
          ? [
              for (var i = 0; i < srcPlain.length; i++)
                (tr!.lines[i].trim().isEmpty ? srcPlain[i] : tr.lines[i])
            ].join('\n')
          : rawPlain;
      final pairPlain = canPair && trMode == TranslationDisplay.both;
      content = ValueListenableBuilder<LyricsStyle>(
        key: const ValueKey('plain-lyrics'),
        valueListenable: AudioPrefs.lyricsStyleNotifier,
        builder: (context, style, _) {
          final lyricsColor =
              isLight ? AurumTheme.lightTextPrimary : Colors.white.withAlpha(200);
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, (1 - v) * 12),
                child: child,
              ),
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
              child: pairPlain
                  ? Text.rich(
                      TextSpan(children: [
                        for (var i = 0; i < srcPlain.length; i++) ...[
                          TextSpan(text: srcPlain[i] + '\n'),
                          if (srcPlain[i].trim().isNotEmpty &&
                              tr!.lines[i].trim().isNotEmpty &&
                              tr.lines[i].trim().toLowerCase() !=
                                  srcPlain[i].trim().toLowerCase()) ...[
                            TextSpan(
                              text: tr.lines[i] + '\n',
                              style: TextStyle(
                                color: lyricsColor.withAlpha(150),
                                fontSize: style.textSize * 0.62,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                            const TextSpan(
                                text: '\n', style: TextStyle(fontSize: 8)),
                          ],
                        ],
                      ]),
                      textAlign: style.position == 'Left'
                          ? TextAlign.left
                          : TextAlign.center,
                      style: TextStyle(
                        color: lyricsColor,
                        fontSize: style.textSize,
                        height: style.lineSpacing,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    )
                  : Text(
                      displayPlain,
                      textAlign: style.position == 'Left'
                          ? TextAlign.left
                          : TextAlign.center,
                      style: TextStyle(
                        color: lyricsColor,
                        fontSize: style.textSize,
                        height: style.lineSpacing,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          );
        },
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              final dragged = (n is ScrollStartNotification && n.dragDetails != null) ||
                  (n is ScrollUpdateNotification && n.dragDetails != null);
              if (dragged) {
                _userScrollHoldUntil =
                    DateTime.now().add(const Duration(seconds: 4));
              }
              return false;
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: content,
            ),
          ),
        ),
        Positioned.fill(
          child: _PositionListenerBridge(onPositionChanged: _onPositionChanged),
        ),
        if (!_loading && !_notFound && _result != null)
          Positioned(
            top: 4,
            right: 14,
            child: ValueListenableBuilder<String?>(
              valueListenable: LyricsTranslatePrefs.targetNotifier,
              builder: (context, target, _) => _TranslateButton(
                isLight: isLight,
                accent: lyricsAccent,
                targetCode: target,
                loading: _trLoading,
                failed: _trFailed,
                onTap: _openTranslateSheet,
              ),
            ),
          ),
      ],
    );
  }
}

class _TranslateButton extends StatelessWidget {
  final bool isLight;
  final Color accent;
  final String? targetCode;
  final bool loading;
  final bool failed;
  final VoidCallback onTap;

  const _TranslateButton({
    required this.isLight,
    required this.accent,
    required this.targetCode,
    required this.loading,
    required this.failed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = targetCode != null;
    final fg = isLight ? AurumTheme.lightTextPrimary : Colors.white;
    final bg = active
        ? accent.withAlpha(isLight ? 60 : 70)
        : (isLight ? Colors.black.withAlpha(14) : Colors.white.withAlpha(22));
    final border = active
        ? accent.withAlpha(140)
        : (isLight ? Colors.black.withAlpha(20) : Colors.white.withAlpha(30));
    final label = active ? targetCode!.split('-').first.toUpperCase() : null;

    return Semantics(
      button: true,
      label: 'Translate lyrics',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          height: 38,
          constraints: const BoxConstraints(minWidth: 38),
          padding: EdgeInsets.symmetric(horizontal: active ? 12 : 0),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: border, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                )
              else
                Icon(
                  failed ? Icons.refresh_rounded : Icons.translate_rounded,
                  size: 18,
                  color: fg,
                ),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TranslateSheet extends StatefulWidget {
  final String? info;
  const _TranslateSheet({this.info});

  @override
  State<_TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<_TranslateSheet> {
  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? Colors.white : const Color(0xFF16141F);
    final fg = isLight ? AurumTheme.lightTextPrimary : Colors.white;
    final muted = isLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(120);
    final line = isLight ? Colors.black.withAlpha(14) : Colors.white.withAlpha(18);
    final accent = context.read<ThemeProvider>().accentColor;
    final langs = kTranslationLanguages;

    return DraggableScrollableSheet(
      initialChildSize: 0.42,
      minChildSize: 0.3,
      maxChildSize: 0.94,
      expand: false,
      builder: (context, scroll) {
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: ValueListenableBuilder<String?>(
            valueListenable: LyricsTranslatePrefs.targetNotifier,
            builder: (context, target, _) {
              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: muted.withAlpha(90),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
                    child: Row(
                      children: [
                        Icon(Icons.translate_rounded, color: accent, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Translate lyrics',
                            style: TextStyle(
                              color: fg,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (target != null)
                          TextButton(
                            onPressed: () {
                              LyricsTranslatePrefs.setTarget(null);
                              Navigator.of(context).pop();
                            },
                            child: const Text('Turn off'),
                          ),
                      ],
                    ),
                  ),
                  if (widget.info != null && target != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.info!,
                          style: TextStyle(color: muted, fontSize: 12.5),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                    child: ValueListenableBuilder<TranslationDisplay>(
                      valueListenable: LyricsTranslatePrefs.modeNotifier,
                      builder: (context, mode, _) {
                        Widget seg(String label, TranslationDisplay m) {
                          final sel = mode == m;
                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                AurumHaptics.selection();
                                LyricsTranslatePrefs.setMode(m);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: sel ? accent.withAlpha(60) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: sel ? fg : muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: isLight
                                ? Colors.black.withAlpha(10)
                                : Colors.white.withAlpha(12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(children: [
                            seg('Lyrics + Translation', TranslationDisplay.both),
                            seg('Translation only', TranslationDisplay.translationOnly),
                          ]),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 28),
                      itemCount: langs.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, indent: 16, endIndent: 16, color: line),
                      itemBuilder: (context, i) {
                        final l = langs[i];
                        final sel = l.code == target;
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(
                            l.native,
                            style: TextStyle(
                              color: fg,
                              fontSize: 15.5,
                              fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                          subtitle: l.native == l.name
                              ? null
                              : Text(l.name, style: TextStyle(color: muted, fontSize: 12.5)),
                          trailing: sel
                              ? Icon(Icons.check_circle_rounded, color: accent)
                              : null,
                          onTap: () {
                            AurumHaptics.selection();
                            LyricsTranslatePrefs.setTarget(l.code);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _PositionListenerBridge extends StatelessWidget {
  final void Function(Duration) onPositionChanged;
  const _PositionListenerBridge({required this.onPositionChanged});

  @override
  Widget build(BuildContext context) {
    final position = context.select<PlayerProvider, Duration>((p) => p.position);
    WidgetsBinding.instance.addPostFrameCallback((_) => onPositionChanged(position));
    return const SizedBox.shrink();
  }
}

class _SyncedLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  final int activeIndex;
  final ScrollController scrollController;
  final GlobalKey listKey;
  final GlobalKey Function(int index) lineKeyFor;
  final void Function(Duration) onPositionChanged;

  final bool isLight;
  final List<String>? subLines;
  const _SyncedLyricsView({
    super.key,
    this.subLines,
    required this.lines,
    required this.activeIndex,
    required this.scrollController,
    required this.listKey,
    required this.lineKeyFor,
    required this.onPositionChanged,
    required this.isLight,
  });

  @override
  State<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<_SyncedLyricsView> {
  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    final activeIndex = widget.activeIndex;
    final scrollController = widget.scrollController;
    final listKey = widget.listKey;
    final lineKeyFor = widget.lineKeyFor;
    final isLight = widget.isLight;
    final bottomPad = MediaQuery.sizeOf(context).height * 0.55;

    return ValueListenableBuilder<LyricsStyle>(
      valueListenable: AudioPrefs.lyricsStyleNotifier,
      builder: (context, style, _) {
        final activeColor =
            isLight ? AurumTheme.lightTextPrimary : Colors.white;
        final pastColor = isLight
            ? AurumTheme.lightTextMuted.withAlpha(100)
            : Colors.white.withAlpha(95);
        final upcomingColor = isLight
            ? AurumTheme.lightTextMuted.withAlpha(170)
            : Colors.white.withAlpha(150);
        final isLeft = style.position == 'Left';
        final align = isLeft ? TextAlign.left : TextAlign.center;

        final list = ListView.builder(
          key: listKey,
          controller: scrollController,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(24, 40, 24, bottomPad),
          itemCount: lines.length,
          itemBuilder: (context, index) {
            final line = lines[index];
            if (line.text.isEmpty) {
              return SizedBox(key: lineKeyFor(index), height: 20);
            }
            final target = index == activeIndex
                ? activeColor
                : (index < activeIndex ? pastColor : upcomingColor);
            return Padding(
              key: lineKeyFor(index),
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.read<PlayerProvider>().seekTo(line.time),
                child: SizedBox(
                  width: double.infinity,
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: target),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    builder: (context, color, _) {
                      final c = color ?? target;
                      final sub = (widget.subLines != null &&
                              index < widget.subLines!.length)
                          ? widget.subLines![index].trim()
                          : '';
                      final mainText = Text(
                        line.text,
                        textAlign: align,
                        style: TextStyle(
                          color: c,
                          fontSize: style.textSize,
                          height: style.lineSpacing,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      );
                      if (sub.isEmpty ||
                          sub.toLowerCase() == line.text.trim().toLowerCase()) {
                        return mainText;
                      }
                      return Column(
                        crossAxisAlignment: isLeft
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.center,
                        children: [
                          mainText,
                          const SizedBox(height: 3),
                          Text(
                            sub,
                            textAlign: align,
                            style: TextStyle(
                              color: Color.lerp(c, null, 0.18),
                              fontSize: style.textSize * 0.62,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );

        return ShaderMask(
          shaderCallback: (rect) {
            return const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black,
                Colors.black,
                Colors.transparent,
              ],
              stops: [0.0, 0.05, 0.86, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstIn,
          child: list,
        );
      },
    );
  }
}

class _InfoPage extends StatelessWidget {
  const _InfoPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final song = context.read<PlayerProvider>().currentSong;
    if (song == null) return const SizedBox.shrink();

    final cardBg = isLight ? AurumTheme.lightBgSurface : Colors.white.withAlpha(7);
    final cardBorder = isLight ? AurumTheme.lightDivider : Colors.white.withAlpha(12);
    final dividerColor = isLight ? AurumTheme.lightDivider : Colors.white.withAlpha(10);
    final labelColor = isLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(70);
    final valueColor = isLight ? AurumTheme.lightTextPrimary : Colors.white;

    final rows = <_InfoRow>[];
    if (song.album.isNotEmpty) rows.add(_InfoRow(l10n.fpSongInfoAlbum, song.album));
    if (song.artist.isNotEmpty) rows.add(_InfoRow(l10n.fpSongInfoArtist, song.artist));
    if (song.year != null && song.year!.isNotEmpty) {
      rows.add(_InfoRow(l10n.fpSongInfoYear, song.year!));
    }
    if (song.language != null && song.language!.isNotEmpty) {
      rows.add(_InfoRow(l10n.fpSongInfoLanguage, song.language!));
    }
    if (song.duration != null) {
      rows.add(_InfoRow(l10n.fpSongInfoDuration, song.durationString));
    }
    rows.add(_InfoRow(l10n.fpSourceLabel, song.isLocal ? l10n.fpLocalLibrary : l10n.fpOnlineStream));

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        _InfoHeader(song: song),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cardBorder, width: 0.5),
          ),
          child: Column(
            children: List.generate(rows.length, (i) {
              return Column(children: [
                _buildInfoRow(rows[i].label, rows[i].value, labelColor, valueColor),
                if (i < rows.length - 1)
                  Divider(
                    color: dividerColor,
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                  ),
              ]);
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, Color labelColor, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: labelColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoHeader extends StatelessWidget {
  final Song song;
  const _InfoHeader({required this.song});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final titleColor = isLight ? AurumTheme.lightTextPrimary : Colors.white;
    final artistColor = isLight ? AurumTheme.lightTextMuted : Colors.white.withAlpha(120);

    return Row(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AurumArtwork(url: song.artworkUrl, size: 72, borderRadius: 14),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              song.title,
              style: TextStyle(
                color: titleColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              song.artist,
              style: TextStyle(
                color: artistColor,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ]);
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}

class _BgLayer extends StatelessWidget {
  final Song song;
  final AnimationController bgCtrl;
  final Color startBg1, startBg2, startBg3, startBg4;
  final Color targetBg1, targetBg2, targetBg3, targetBg4;
  final bool isDragging;
  final GlobalKey<_StaticBlurArtworkState> kenBurnsKey;

  const _BgLayer({
    required this.song,
    required this.bgCtrl,
    required this.startBg1,
    required this.startBg2,
    required this.startBg3,
    required this.startBg4,
    required this.targetBg1,
    required this.targetBg2,
    required this.targetBg3,
    required this.targetBg4,
    required this.kenBurnsKey,
    this.isDragging = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = !context.watch<ThemeProvider>().isDarkOf(context);

    return ValueListenableBuilder<bool>(
      valueListenable: AudioPrefs.showBlurredBgNotifier,
      builder: (context, showBlur, _) => AnimatedBuilder(
      animation: bgCtrl,
      builder: (context, _) {
        final t = bgCtrl.value;
        final bg1 = Color.lerp(startBg1, targetBg1, t)!;
        final bg2 = Color.lerp(startBg2, targetBg2, t)!;
        final bg3 = Color.lerp(startBg3, targetBg3, t)!;
        final bg4 = Color.lerp(startBg4, targetBg4, t)!;

        final staticBlur = !showBlur
            ? const SizedBox.expand()
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  children: [...previousChildren, if (currentChild != null) currentChild],
                ),
                child: _StaticBlurArtwork(
                  key: kenBurnsKey,
                  song: song,
                  isLight: isLight,
                  isDragging: isDragging,
                ),
              );

        return isLight
            ? _buildLight(bg1, bg2, bg3, bg4, staticBlur)
            : _buildDark(bg1, bg2, bg3, bg4, staticBlur);
      },
      ),
    );
  }

  Widget _buildLight(Color bg1, Color bg2, Color bg3, Color bg4, Widget staticBlur) {
    final darkStack = _buildDark(bg1, bg2, bg3, bg4, staticBlur);
    return Stack(fit: StackFit.expand, children: [
      darkStack,
      const IgnorePointer(
        child: ColoredBox(color: Color.fromRGBO(255, 255, 255, 0.14)),
      ),
    ]);
  }

  Widget _buildDark(Color bg1, Color bg2, Color bg3, Color bg4, Widget staticBlur) {
    final dynamicColor = AudioPrefs.dynamicPlayerColorNotifier.value;
    final bgStyle = AudioPrefs.effectivePlayerBgStyle;
    if (!dynamicColor) {
      bg1 = Color.lerp(AurumTheme.accent, Colors.black, 0.35)!;
      bg2 = Color.lerp(AurumTheme.accentDark, Colors.black, 0.58)!;
      bg3 = Color.lerp(AurumTheme.accentDark, Colors.black, 0.78)!;
      bg4 = Color.lerp(AurumTheme.accentLight, Colors.black, 0.42)!;
    }

    if (bgStyle == 'Solid') {
      return ColoredBox(color: Color.lerp(bg1, Colors.black, 0.35)!);
    }

    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Color(0xFF000000)),

      staticBlur,

      if (bgStyle != 'Gradient')
        RepaintBoundary(
          child: CustomPaint(
            painter: _StaticTintVignettePainter(
              tint1: bg1.withAlpha(165),
              tint2: bg2.withAlpha(120),
            ),
            size: Size.infinite,
          ),
        )
      else
        const RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xA0000000),
                  Colors.transparent,
                  Colors.transparent,
                  Color(0xD2000000),
                ],
                stops: [0.0, 0.18, 0.60, 1.0],
              ),
            ),
          ),
        ),
    ]);
  }
}

class _StaticBlurArtwork extends StatefulWidget {
  final Song song;
  final bool isLight;
  final bool isDragging;

  const _StaticBlurArtwork({
    super.key,
    required this.song,
    required this.isLight,
    this.isDragging = false,
  });

  @override
  State<_StaticBlurArtwork> createState() => _StaticBlurArtworkState();
}

class _StaticBlurArtworkState extends State<_StaticBlurArtwork>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _accumulated = Duration.zero;
  Duration _sessionElapsed = Duration.zero;

  static const _cycle = Duration(seconds: 18);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (!widget.isDragging) _startTicker();
  }

  void _onTick(Duration sessionElapsed) {
    if (!mounted) return;
    setState(() => _sessionElapsed = sessionElapsed);
  }

  Duration get _currentElapsed => _accumulated + _sessionElapsed;

  void _startTicker() {
    _sessionElapsed = Duration.zero;
    _ticker.start();
  }

  void _stopTicker() {
    _ticker.stop();
    _accumulated += _sessionElapsed;
    _sessionElapsed = Duration.zero;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_StaticBlurArtwork old) {
    super.didUpdateWidget(old);
    if (widget.isDragging && !old.isDragging) {
      _stopTicker();
    } else if (!widget.isDragging && old.isDragging && !_pausedByParent) {
      _startTicker();
    }
  }

  bool _pausedByParent = false;

  void pause() {
    _pausedByParent = true;
    _stopTicker();
  }

  void resume() {
    if (!_pausedByParent) return;
    _pausedByParent = false;
    if (!widget.isDragging) _startTicker();
  }

  @override
  Widget build(BuildContext context) {
    final phase =
        (_currentElapsed.inMilliseconds % _cycle.inMilliseconds) /
            _cycle.inMilliseconds;
    final t = Curves.easeInOut.transform(
      phase < 0.5 ? phase * 2 : (1 - phase) * 2,
    );
    final scale = 1.0 + 0.06 * t;
    final dx = -6.0 + 12.0 * t;
    final dy = -4.0 + 8.0 * t;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..translate(dx, dy)
        ..scale(scale),
      child: RepaintBoundary(
        child: _BlurredArtworkCore(song: widget.song, isLight: widget.isLight),
      ),
    );
  }
}

class _BlurredArtworkCore extends StatefulWidget {
  final Song song;
  final bool isLight;

  const _BlurredArtworkCore({required this.song, required this.isLight});

  @override
  State<_BlurredArtworkCore> createState() => _BlurredArtworkCoreState();
}

class _BlurredArtworkCoreState extends State<_BlurredArtworkCore> {
  final GlobalKey _repaintKey = GlobalKey();
  ui.Image? _snapshot;
  bool _capturing = false;
  int _captureAttempts = 0;
  static const int _maxCaptureAttempts = 30;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) _capture();
    });
  }

  @override
  void didUpdateWidget(_BlurredArtworkCore old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id ||
        old.song.artworkUrl != widget.song.artworkUrl) {
      _captureAttempts = 0;
      _snapshot?.dispose();
      _snapshot = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
    }
  }

  Future<void> _capture() async {
    if (_capturing || !mounted) return;
    _capturing = true;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null || boundary.debugNeedsPaint) {
        _capturing = false;
        _captureAttempts++;
        if (mounted && _captureAttempts < _maxCaptureAttempts) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
        }
        return;
      }
      final image = await boundary.toImage(pixelRatio: 1.0);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _snapshot?.dispose();
        _snapshot = image;
      });
    } catch (_) {
    } finally {
      _capturing = false;
    }
  }

  @override
  void dispose() {
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.song.artworkUrl.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: widget.isLight
                ? [const Color(0xFFDCD3C0), const Color(0xFFC9BCA0)]
                : [const Color(0xFF241F38), const Color(0xFF120F24)],
          ),
        ),
      );
    }
    final snapshot = _snapshot;
    return RepaintBoundary(
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          child: snapshot != null
              ? SizedBox.expand(
                  key: const ValueKey('baked'),
                  child: RawImage(image: snapshot, fit: BoxFit.cover),
                )
              : RepaintBoundary(
                  key: _repaintKey,
                  child: _LiveBlurArtwork(
                    song: widget.song,
                    isLight: widget.isLight,
                  ),
                ),
        ),
      ),
    );
  }
}

class _LiveBlurArtwork extends StatelessWidget {
  final Song song;
  final bool isLight;

  const _LiveBlurArtwork({required this.song, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: Opacity(
          opacity: 1.0,
          child: Transform.scale(
            scale: 1.55,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: isLight ? 20 : 22,
                sigmaY: isLight ? 20 : 22,
                tileMode: TileMode.clamp,
              ),
              child: AurumArtwork(
                url: song.artworkUrl,
                size: double.infinity,
                borderRadius: 0,
                isBlurredBackground: true,
              fadeIn: true,
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _StaticTintVignettePainter extends CustomPainter {
  final Color tint1, tint2;
  const _StaticTintVignettePainter({required this.tint1, required this.tint2});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fullRect = Rect.fromLTWH(0, 0, w, h);

    final tintRect = Rect.fromCircle(
      center: Offset(w * -0.25, h * -0.55),
      radius: w * 1.35,
    );
    final tintPaint = Paint()
      ..shader = RadialGradient(
        colors: [tint1, tint2, tint2.withAlpha(0)],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(tintRect);
    canvas.drawRect(fullRect, tintPaint);

    final vignettePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xE6000000),
          Color(0x40000000),
          Colors.transparent,
          Colors.transparent,
          Color(0xE6000000),
        ],
        stops: [0.0, 0.30, 0.42, 0.58, 1.0],
      ).createShader(fullRect);
    canvas.drawRect(fullRect, vignettePaint);
  }

  @override
  bool shouldRepaint(_StaticTintVignettePainter old) =>
      tint1 != old.tint1 || tint2 != old.tint2;
}

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scrollAnim;
  bool _overflowing = false;

  TextPainter? _tp;
  String? _tpText;
  TextStyle? _tpStyle;

  TextPainter _painterFor(String text, TextStyle style) {
    if (_tp != null && _tpText == text && _tpStyle == style) return _tp!;
    _tpText = text;
    _tpStyle = style;
    _tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    return _tp!;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 10500));
    _scrollAnim = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.857, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final tp = _painterFor(widget.text, widget.style);

      final overflow = tp.width > constraints.maxWidth;

      if (overflow != _overflowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _overflowing = overflow);
          if (overflow) {
            _ctrl.repeat();
          } else {
            _ctrl.stop();
            _ctrl.reset();
          }
        });
      }

      if (!overflow) {
        return Text(widget.text,
            style: widget.style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis);
      }

      return ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent
          ],
          stops: [0.0, 0.04, 0.92, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: SizedBox(
          height: tp.height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final shift = -(tp.width + 40) * _scrollAnim.value;
                return Stack(children: [
                  Positioned(
                      left: shift,
                      child: Text(widget.text,
                          style: widget.style, maxLines: 1, softWrap: false)),
                  Positioned(
                      left: shift + tp.width + 40,
                      child: Text(widget.text,
                          style: widget.style, maxLines: 1, softWrap: false)),
                ]);
              },
            ),
          ),
        ),
      );
    });
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final Color color;
  final String? semanticLabel;

  const _IconBtn({
    required this.icon,
    required this.size,
    required this.onTap,
    required this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: AurumPressable(
        scaleAmount: 0.85,
        haptic: false,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

class _CtrlBtn extends StatefulWidget {
  final IconData icon;
  final double size;
  final bool active;
  final Color? color;
  final Color inactiveColor;
  final String? semanticLabel;
  final VoidCallback onTap;

  const _CtrlBtn({
    required this.icon,
    required this.onTap,
    required this.inactiveColor,
    this.size = 24,
    this.active = false,
    this.color,
    this.semanticLabel,
  });

  @override
  State<_CtrlBtn> createState() => _CtrlBtnState();
}

class _CtrlBtnState extends State<_CtrlBtn> {
  @override
  Widget build(BuildContext context) {
    final c = widget.color ?? widget.inactiveColor;

    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: AurumPressable(
        scaleAmount: 0.90,
        haptic: false,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: anim, child: child),
                  );
                },
                child: Icon(
                  widget.icon,
                  key: ValueKey('${widget.icon}_${widget.active}'),
                  size: widget.size,
                  color: c,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
