// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'dart:async';
import '../utils/aurum_transitions.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../widgets/feedback_dialog.dart';
import '../services/feedback_service.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../theme/aurum_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/aurum_glass.dart';
import '../widgets/aurum_artwork.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/aurum_play_pause_icon.dart';
import '../models/song.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import '../providers/player_provider.dart';
import '../providers/theme_provider.dart';
import '../services/update_service.dart';
import '../services/audio_prefs.dart';
import '../services/lyrics_translation_handle.dart';
import '../services/sync_service.dart';
import '../providers/auth_provider.dart';
import '../providers/premium_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/followed_artists_provider.dart';
import '../providers/followed_albums_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/recently_played_provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_motion.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _tab = 0;

  final _homeKey = GlobalKey<State<HomeScreen>>();

  List<Widget> get _screens => [
    HomeScreen(key: _homeKey, isActive: _tab == 0),
    SearchScreen(isActive: _tab == 1),
    const LibraryScreen(),
  ];

  static const Map<int, int> _barIndexToTab = {0: 0, 1: 1, 2: 2};

  void _handleNavTap(int barIndex) {
    if (_barIndexToTab[barIndex] == 1 && _tab == 1) {
      SearchScreen.focusRequest.value++;
      return;
    }
    primaryFocus?.unfocus(disposition: UnfocusDisposition.scope);
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');

    final tab = _barIndexToTab[barIndex];
    if (tab != null) {
      setState(() => _tab = tab);
      AnalyticsService.instance
          .logScreen(const ['Home', 'Search', 'Library'][tab]);
    }
  }

  int get _activeBarIndex =>
      _barIndexToTab.entries.firstWhere((e) => e.value == _tab).key;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  DateTime _lastShakeAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const double _shakeThreshold = 27.0;
  static const Duration _shakeCooldown = Duration(milliseconds: 900);

  void _startShakeListener() {
    _accelSub?.cancel();
    _accelSub = null;
    if (!AudioPrefs.shakeToSkipNotifier.value) return;
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      final magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      final delta = (magnitude - 9.8).abs();
      if (delta < _shakeThreshold) return;

      final now = DateTime.now();
      if (now.difference(_lastShakeAt) < _shakeCooldown) return;
      _lastShakeAt = now;

      if (!mounted) return;
      final player = context.read<PlayerProvider>();
      if (!player.hasSong) return;
      AurumHaptics.medium();
      player.skipNext();
    });
  }

  String? _lastTrackedSongId;
  VoidCallback? _feedbackListener;
  PlayerProvider? _trackedPlayer;

  void _startFeedbackTracking() {
    final player = context.read<PlayerProvider>();
    _trackedPlayer = player;
    _feedbackListener = () {
      final song = player.currentSong;
      if (song == null || song.id == _lastTrackedSongId) return;
      _lastTrackedSongId = song.id;
      FeedbackService.onSongPlayed().then((shouldPrompt) {
        if (shouldPrompt && mounted) {
          final rootNavigator = Navigator.of(context, rootNavigator: true);
          if (rootNavigator.canPop()) return;
          showFeedbackDialog(context);
        }
      });
    };
    player.addListener(_feedbackListener!);
  }

  VoidCallback? _playbackErrorListener;

  void _startPlaybackErrorTracking() {
    final player = _trackedPlayer ?? context.read<PlayerProvider>();
    _playbackErrorListener = () {
      final err = player.playbackError;
      if (err == null || !mounted) return;
      final failedSong = player.lastFailedSong;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(err),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: failedSong == null
              ? null
              : SnackBarAction(
                  label: 'RETRY',
                  onPressed: () => player.playSong(failedSong),
                ),
        ));
      player.clearPlaybackError();
    };
    player.addListener(_playbackErrorListener!);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startShakeListener();
    AudioPrefs.shakeToSkipNotifier.addListener(_startShakeListener);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _startFeedbackTracking();
      _startPlaybackErrorTracking();
      // Warm the lyrics-conversion cache so Hinglish/Hindi is already ready
      // before any lyrics surface opens.
      LyricsTranslationPrefetcher.attach(context.read<PlayerProvider>());

      final prefs = await SharedPreferences.getInstance();

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lastCold = prefs.getInt('last_cold_net_ms') ?? 0;
      final coldNetDue = !AudioPrefs.dataSaverActiveNotifier.value ||
          nowMs - lastCold > 24 * 60 * 60 * 1000;
      if (coldNetDue) {
        await prefs.setInt('last_cold_net_ms', nowMs);
        _handleForegroundSync();
      }

      const migrationFlag = 'check_updates_regression_fix_applied_v1';
      if (prefs.getBool('check_updates') == false &&
          !(prefs.getBool(migrationFlag) ?? false)) {
        await prefs.remove('check_updates');
        await prefs.setBool(migrationFlag, true);
      }

      final checkUpdates = prefs.getBool('check_updates') ?? true;
      if (checkUpdates && coldNetDue && mounted) {
        await UpdateService.checkForUpdate(context);
      }

      if (!mounted) return;

      final askedPermissions = prefs.getBool('asked_launch_permissions') ?? false;
      if (!askedPermissions && mounted) {
        await _requestLaunchPermissions();
        await prefs.setBool('asked_launch_permissions', true);
      }

    });
  }

  Future<void> _requestLaunchPermissions() async {
    try {
      final audio = await Permission.audio.request();
      if (!audio.isGranted) await Permission.storage.request();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AudioPrefs.shakeToSkipNotifier.removeListener(_startShakeListener);
    _accelSub?.cancel();
    LyricsTranslationPrefetcher.detach();
    if (_feedbackListener != null) {
      _trackedPlayer?.removeListener(_feedbackListener!);
    }
    if (_playbackErrorListener != null) {
      _trackedPlayer?.removeListener(_playbackErrorListener!);
    }
    super.dispose();
  }

  bool _wasPaused = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _wasPaused = true;
      _accelSub?.cancel();
      _accelSub = null;
      _saveQueue();
    } else if (state == AppLifecycleState.resumed) {
      if (_accelSub == null) _startShakeListener();
      if (_wasPaused) {
        _wasPaused = false;
        _handleForegroundSync();
      }
    }
  }

  Future<void> _handleForegroundSync() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn) return;
    try {
      await SyncService.instance.syncAll(
        playlists: context.read<PlaylistProvider>(),
        followedArtists: context.read<FollowedArtistsProvider>(),
        followedAlbums: context.read<FollowedAlbumsProvider>(),
        favorites: context.read<FavoritesProvider>(),
        history: context.read<RecentlyPlayedProvider>(),
      );
    } catch (_) {
    }
  }

  Future<void> _saveQueue() async {
    if (!mounted) return;
    final player = context.read<PlayerProvider>();
    final prefs = await SharedPreferences.getInstance();
    final keepQueue = prefs.getBool('keep_queue') ?? true;
    if (!keepQueue) return;

    if (player.queue.isEmpty) return;

    try {
      final queueJson =
          jsonEncode(player.queue.map((s) => s.toJson()).toList());
      await prefs.setString('saved_queue', queueJson);
      await prefs.setInt('saved_queue_index', player.currentIndex);
    } catch (_) {}
  }

  Future<void> _restoreQueueIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final keepQueue = prefs.getBool('keep_queue') ?? true;
    if (!keepQueue) return;

    final queueJson = prefs.getString('saved_queue');
    if (queueJson == null || queueJson.isEmpty) return;

    try {
      final List<dynamic> decoded = jsonDecode(queueJson);
      final songs = decoded
          .whereType<Map<String, dynamic>>()
          .map(Song.fromJson)
          .toList();
      if (songs.isEmpty) return;

      final index = (prefs.getInt('saved_queue_index') ?? 0)
          .clamp(0, songs.length - 1);

      if (!mounted) return;
      await context.read<PlayerProvider>().restoreQueueSilently(songs, index);
    } catch (_) {
      await prefs.remove('saved_queue');
      await prefs.remove('saved_queue_index');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _tab == 0) return;
        if (_tab == 2 && LibraryBackScope.handleBack()) return;
        primaryFocus?.unfocus(disposition: UnfocusDisposition.scope);
        SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        setState(() => _tab = 0);
      },
      child: Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: IndexedStack(index: _tab, children: _screens),
      ),
      bottomNavigationBar: Material(
        color: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        child: _GlassBackdropPassthrough(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: AudioPrefs.liquidGlassEnabledNotifier,
                builder: (context, glassOn, _unusedChild) {
                  final chipShowsInstead = _activeBarIndex == 1 && glassOn;
                  return Selector<PlayerProvider, bool>(
                    selector: (_, p) => p.miniPlayerVisible && !chipShowsInstead,
                    builder: (context, visible, __) => AnimatedSwitcher(
                      duration: AurumMotion.durationOrZero(AurumMotion.medium1),
                      switchInCurve: AurumMotion.standard,
                      switchOutCurve: AurumMotion.standardReverse,
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      transitionBuilder: (child, anim) => GlassSafeEnter(
                        anim: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(anim),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.97, end: 1.0).animate(anim),
                            alignment: Alignment.bottomCenter,
                            child: child,
                          ),
                        ),
                      ),
                      child: visible
                          ? const MiniPlayer(key: ValueKey('mini_player_visible'))
                          : const SizedBox.shrink(key: ValueKey('mini_player_hidden')),
                    ),
                  );
                },
              ),
              AurumBottomNavBar(
                currentIndex: _activeBarIndex,
                onTap: _handleNavTap,
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _NavTabTapPump extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _NavTabTapPump({required this.child, required this.onTap});

  @override
  State<_NavTabTapPump> createState() => _NavTabTapPumpState();
}

class _NavTabTapPumpState extends State<_NavTabTapPump>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AurumMotion.durationOrZero(AurumMotion.short1),
    reverseDuration: AurumMotion.durationOrZero(AurumMotion.medium2),
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.86).animate(
    CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.elasticOut,
    ),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(TapDownDetails _) => _ctrl.forward();
  void _up(TapUpDetails _) => _ctrl.reverse();
  void _cancel() => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _down,
      onTapUp: _up,
      onTapCancel: _cancel,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

class AurumBottomNavBar extends StatelessWidget {
  const AurumBottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });
  final int currentIndex;
  final ValueChanged<int> onTap;

  static List<({dynamic outline, dynamic filled, String label})> _items(AppLocalizations l10n) => [
    (outline: Icons.home_outlined, filled: Icons.home, label: l10n.navHome),
    (outline: Icons.search, filled: Icons.search, label: l10n.navSearch),
    (outline: Icons.library_music_outlined, filled: Icons.library_music_outlined, label: l10n.navLibrary),
  ];

  static const double _barHeight = 64.0;
  static const double barHeight = _barHeight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = _items(l10n);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<bool>(
      valueListenable: AudioPrefs.liquidGlassEnabledNotifier,
      builder: (context, glassOn, __) {
        final docked = !glassOn;
        final searchActive = currentIndex == 1 && !docked;
        return SafeArea(
          top: false,
          child: Padding(
            padding: docked
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: AnimatedSwitcher(
              duration: AurumMotion.durationOrZero(AurumMotion.medium2),
              switchInCurve: AurumMotion.standard,
              switchOutCurve: AurumMotion.standardReverse,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1.0).animate(anim),
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              ),
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              child: searchActive
                  ? _CollapsedSearchButton(
                      key: const ValueKey('nav_collapsed_search'),
                      docked: docked,
                      isDark: isDark,
                      onTap: () => onTap(1),
                    )
                  : _FullNavRow(
                      key: ValueKey('nav_full_$docked'),
                      docked: docked,
                      isDark: isDark,
                      items: items,
                      currentIndex: currentIndex,
                      onTap: onTap,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _FullNavRow extends StatelessWidget {
  final bool docked;
  final bool isDark;
  final List<({dynamic outline, dynamic filled, String label})> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _FullNavRow({
    super.key,
    required this.docked,
    required this.isDark,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      clipBehavior: Clip.none,
      borderRadius: docked
          ? BorderRadius.zero
          : BorderRadius.circular(28),
      child: ValueListenableBuilder<bool>(
        valueListenable: AudioPrefs.liquidGlassEnabledNotifier,
        builder: (context, glassOn, navBarContent) {
          final blurSigma = glassOn ? AudioPrefs.glassNavSigma : 0.0;
          final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
          final effectiveBlurSigma = isTopRoute ? blurSigma : 0.0;
          if (docked && glassOn) {
            return SizedBox(
              height: AurumBottomNavBar._barHeight,
              child: AurumGlass(
                sigma: effectiveBlurSigma,
                borderRadius: BorderRadius.zero,
                isDark: isDark,
                tintColor: AurumTheme.bgCardOf(context),
                useTintInGlass: false,
                child: navBarContent!,
              ),
            );
          }
          if (docked) {
            return SizedBox(
              height: AurumBottomNavBar._barHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.0),
                              Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  navBarContent!,
                ],
              ),
            );
          }
          return SizedBox(
            height: AurumBottomNavBar._barHeight,
            child: AurumGlass(
              sigma: effectiveBlurSigma,
              borderRadius: BorderRadius.circular(28),
              isDark: isDark,
              tintColor: AurumTheme.bgCardOf(context),
              useTintInGlass: false,
              child: navBarContent!,
            ),
          );
        },
        child: LayoutBuilder(
            builder: (context, constraints) {
              final slotWidth = constraints.maxWidth / items.length;
              return Row(
                children: List.generate(items.length, (i) {
                  final item = items[i];
                  final selected = i == currentIndex;
                  return SizedBox(
                    width: slotWidth,
                    height: AurumBottomNavBar._barHeight,
                    child: _NavTabTapPump(
                      onTap: () {
                        if (!selected) AurumHaptics.selection();
                        onTap(i);
                      },
                      child: Center(
                        child: AnimatedContainer(
                        duration: AurumMotion.durationOrZero(AurumMotion.medium2),
                        curve: AurumMotion.standard,
                        padding: selected
                            ? const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8)
                            : const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: isDark ? 0.14 : 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: selected
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    item.filled,
                                    size: 22,
                                    color: AurumTheme.textPrimaryOf(context),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    item.label,
                                    style: TextStyle(
                                      fontFamily: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.fontFamily,
                                      fontSize: 13,
                                      height: 1.0,
                                      fontWeight: FontWeight.w600,
                                      color: AurumTheme.textPrimaryOf(context),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    item.outline,
                                    size: 24,
                                    color: AurumTheme.textMutedOf(context),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.label,
                                    style: TextStyle(
                                      fontFamily: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.fontFamily,
                                      fontSize: 11,
                                      height: 1.0,
                                      fontWeight: FontWeight.w500,
                                      color: AurumTheme.textMutedOf(context),
                                    ),
                                  ),
                                ],
                              ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
        ),
      ),
    );
  }
}

class _CollapsedSearchButton extends StatelessWidget {
  final bool docked;
  final bool isDark;
  final VoidCallback onTap;
  const _CollapsedSearchButton({
    super.key,
    required this.docked,
    required this.isDark,
    required this.onTap,
  });

  static const double _size = 56.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: docked ? 12 : 0,
        right: docked ? 12 : 0,
        bottom: docked ? 8 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _CompactMiniPlayerChip(docked: docked, isDark: isDark),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AudioPrefs.liquidGlassEnabledNotifier,
            builder: (context, glassOn, button) {
              final blurSigma = glassOn ? AudioPrefs.glassNavSigma : 0.0;
              final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
              final effectiveBlurSigma = isTopRoute ? blurSigma : 0.0;
              return SizedBox(
                width: _size,
                height: _size,
                child: AurumGlass(
                  sigma: effectiveBlurSigma,
                  borderRadius: BorderRadius.circular(_size / 2),
                  isDark: isDark,
                  tintColor: AurumTheme.bgCardOf(context),
                  useTintInGlass: false,
                  child: button!,
                ),
              );
            },
            child: _NavTabTapPump(
              onTap: onTap,
              child: Icon(
                Icons.search,
                size: 24,
                color: AurumTheme.textPrimaryOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactMiniPlayerChip extends StatelessWidget {
  final bool docked;
  final bool isDark;
  const _CompactMiniPlayerChip({required this.docked, required this.isDark});

  static const double _height = 52.0;

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, Song?>(
      selector: (_, p) => p.miniPlayerVisible ? p.currentSong : null,
      builder: (context, song, __) {
        if (song == null) return const SizedBox.shrink();
        return SizedBox(
          height: _height,
          child: ValueListenableBuilder<bool>(
            valueListenable: AudioPrefs.liquidGlassEnabledNotifier,
            builder: (context, glassOn, content) {
              final blurSigma = glassOn ? AudioPrefs.glassNavSigma : 0.0;
              final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;
              final effectiveBlurSigma = isTopRoute ? blurSigma : 0.0;
              return AurumGlass(
                sigma: effectiveBlurSigma,
                borderRadius: BorderRadius.circular(_height / 2),
                isDark: isDark,
                tintColor: AurumTheme.bgCardOf(context),
                useTintInGlass: false,
                child: content!,
              );
            },
            child: AurumPressable(
              scaleAmount: 0.97,
              haptic: false,
              onTap: () => pushFullPlayer(context),
              child: Padding(
                padding: const EdgeInsets.only(left: 6, right: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(_height / 2 - 4),
                      child: AurumArtwork(
                        url: song.artworkUrl,
                        size: _height - 8,
                        borderRadius: _height / 2 - 4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AurumTheme.textPrimaryOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Selector<PlayerProvider, ({bool isLoading, bool isPlaying})>(
                      selector: (_, p) =>
                          (isLoading: p.isLoading, isPlaying: p.isPlaying),
                      builder: (context, state, _) {
                        if (state.isLoading) {
                          return const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        return AurumPressable(
                          scaleAmount: 0.85,
                          haptic: false,
                          onTap: () {
                            AurumHaptics.heavy();
                            context.read<PlayerProvider>().togglePlay();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: AurumPlayPauseIcon(
                              isPlaying: state.isPlaying,
                              color: AurumTheme.textPrimaryOf(context),
                              size: 20,
                            ),
                          ),
                        );
                      },
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

class _GlassBackdropPassthrough extends StatelessWidget {
  final Widget child;
  const _GlassBackdropPassthrough({required this.child});
  @override
  Widget build(BuildContext context) => child;
}
