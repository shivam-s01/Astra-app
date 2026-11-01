// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/artist.dart' show ArtistAlbum, RelatedArtist;
import '../providers/player_provider.dart';
import '../providers/source_provider.dart';
import '../providers/library_provider.dart';
import '../providers/recently_played_provider.dart';
import '../utils/route_drag_dismiss.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/aurum_image_cache.dart';
import '../services/home_feed_cache.dart';
import '../services/recommendation_engine.dart';
import '../providers/download_provider.dart';
import '../services/audio_prefs.dart';
import '../services/native_engine_bridge.dart';
import '../theme/aurum_theme.dart';
import '../widgets/aurum_artwork.dart';
import '../widgets/aurum_scroll_nudge.dart';
import '../widgets/aurum_stage_backdrop.dart';
import '../widgets/faded_horizontal_list.dart';
import '../widgets/song_tile.dart';
import '../widgets/aurum_song_options_sheet.dart';
import '../services/quick_picks_filter.dart';
import '../widgets/aurum_snack.dart';
import 'album_screen.dart';
import '../main.dart' show aurumRouteObserver, aurumDebugErrorWidgetBuilder;
import '../widgets/aurum_loader.dart';
import '../widgets/aurum_morph_loader.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/aurum_coach_tip.dart';
import '../widgets/aurum_promo_screen.dart' show AurumPromoData;
import '../widgets/mini_player.dart';
import '../widgets/aurum_equalizer_bars.dart';
import '../widgets/aurum_stacked_artwork.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_transitions.dart';
import 'package:shimmer/shimmer.dart';
import 'settings_screen.dart';
import 'artist_screen.dart';
import 'profile_screen.dart';
import 'library_screen.dart' show PlaylistDetailScreen;
import 'login_screen.dart';
import 'full_player_screen.dart';
import 'edge_to_edge_full_player.dart';
import 'spotify_full_player_screen.dart';
import 'mix_screen.dart';
import 'moods_genres_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/playlist_provider.dart';
import '../providers/followed_artists_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/premium_provider.dart';
import '../services/sync_service.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_sheet.dart';
import '../utils/aurum_motion.dart';

class _FullPlayerRouteBackdrop extends StatefulWidget {
  final bool isDark;
  final Widget child;
  final Animation<double>? routeAnimation;
  const _FullPlayerRouteBackdrop({
    required this.isDark,
    required this.child,
    this.routeAnimation,
  });

  @override
  State<_FullPlayerRouteBackdrop> createState() =>
      _FullPlayerRouteBackdropState();
}

class _FullPlayerRouteBackdropState extends State<_FullPlayerRouteBackdrop> {
  bool _showBackdrop = true;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showBackdrop = false);
      });
    });
    widget.routeAnimation?.addStatusListener(_onRouteStatusChanged);
    _safetyTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _showBackdrop) setState(() => _showBackdrop = false);
    });
  }

  void _onRouteStatusChanged(AnimationStatus status) {
    if (!mounted || !_showBackdrop) return;
    if (status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed) {
      setState(() => _showBackdrop = false);
    }
  }

  @override
  void dispose() {
    widget.routeAnimation?.removeStatusListener(_onRouteStatusChanged);
    _safetyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBackdrop) return widget.child;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        widget.child,
      ],
    );
  }
}

bool _openingFullPlayer = false;

bool _hasOpenedFullPlayerThisSession = false;

void pushFullPlayer(BuildContext context, {VoidCallback? onClosed}) {
  if (_openingFullPlayer) {
    return;
  }
  _openingFullPlayer = true;
  AurumHaptics.light();
  try {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, anim, ___) {
          final selectedStyle = context.read<ThemeProvider>().fullPlayerStyle;
          final fullPlayer = selectedStyle == 'Edge to Edge'
              ? const EdgeToEdgeFullPlayer()
              : selectedStyle == 'Spotify'
                  ? const SpotifyFullPlayerScreen()
                  : const FullPlayerScreen();
          if (_hasOpenedFullPlayerThisSession) {
            return fullPlayer;
          }
          _hasOpenedFullPlayerThisSession = true;
          return _FullPlayerRouteBackdrop(
            routeAnimation: anim,
            isDark: context.read<ThemeProvider>().isDarkOf(context),
            child: fullPlayer,
          );
        },
        transitionsBuilder: (context, anim, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(routeDragCurve(context, anim,
                  curve: AurumMotion.standard)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 380),
      ),
    ).then((_) {
      _openingFullPlayer = false;
      onClosed?.call();
    }, onError: (e) {
      _openingFullPlayer = false;
    });
  } catch (e) {
    _openingFullPlayer = false;
  }
  Future.delayed(const Duration(milliseconds: 1500), () {
    _openingFullPlayer = false;
  });
}

class HomeScreen extends StatefulWidget {
  final bool isActive;
  const HomeScreen({super.key, this.isActive = true});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _onlineLoading = true;
  String? _onlineError;
  int _playlistRefreshKey = 0;
  int _quickPicksRefreshKey = 0;
  RefreshStage _refreshStage = const RefreshStage(
    quickPicks: true,
    shelves: false,
    similarArtistRows: false,
    similarSongRows: false,
  );

  List<ArtistSimple> _homeArtists = [];
  bool _artistsLoading = true;

  bool _isFirstArtistUpdate = true;

  final ScrollController _scrollCtrl = ScrollController();
  final AurumScrollDelta _scrollDelta = AurumScrollDelta();

  final ValueNotifier<List<SongSection>> _onlineSectionsNotifier =
      ValueNotifier<List<SongSection>>([]);
  List<SongSection> get _onlineSections => _onlineSectionsNotifier.value;
  set _onlineSections(List<SongSection> v) => _onlineSectionsNotifier.value = v;

  @override
  void initState() {
    super.initState();
    _scrollDelta.attach(_scrollCtrl);
    _hydrateFromCache();
    final lib = context.read<LibraryProvider>();
    if (!lib.hasLoaded) lib.load();
    HomeFeedCache.isArtistsFresh().then((fresh) {
      if (!mounted) return;
      if (fresh && _homeArtists.isEmpty) _hydrateFromCache();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = context.read<PlayerProvider>();
      player.onPlaybackError = (error, {silent = false}) {
        debugPrint('[Aurum] Playback error${silent ? " (silent, auto-recovered)" : ""}: $error');
        if (!mounted || silent) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AurumTheme.bgCardOf(context),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              error,
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 13,
              ),
            ),
          ),
        );
      };

      _maybeShowAutoSleepGuardResumePrompt(player);
    });
  }

  Future<void> _maybeShowAutoSleepGuardResumePrompt(PlayerProvider player) async {
    final engine = NativeAudioEngine();
    final lastPauseMs = await engine.autoSleepGuardPeekLastAutoPause();
    if (lastPauseMs == null || !mounted) return;
    await engine.autoSleepGuardConsumeLastAutoPause();
    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final pausedAt = DateTime.fromMillisecondsSinceEpoch(lastPauseMs);
    final timeLabel = TimeOfDay.fromDateTime(pausedAt).format(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AurumTheme.bgCardOf(context),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          l10n.asgResumePromptSubtitle(timeLabel),
          style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 13),
        ),
        action: SnackBarAction(
          label: l10n.asgResumePromptResume,
          textColor: AurumTheme.accentOf(context),
          onPressed: () => player.togglePlay(),
        ),
      ),
    );
  }

  Future<void> _hydrateFromCache() async {
    final cachedArtists = await HomeFeedCache.loadArtists();
    if (!mounted) return;
    if (_homeArtists.isEmpty && cachedArtists.isNotEmpty) {
      setState(() {
        _homeArtists = cachedArtists;
        _artistsLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _scrollDelta.dispose();
    _scrollCtrl.dispose();
    _onlineSectionsNotifier.dispose();
    super.dispose();
  }

  // ignore: unused_element
  Future<void> _loadArtists() async {
    _isFirstArtistUpdate = true;
    try {
      await ApiService.fetchHomeArtistsStreaming((artists) {
        if (!mounted) return;
        if (_isFirstArtistUpdate && artists.length < _homeArtists.length) {
          _isFirstArtistUpdate = false;
          return;
        }
        _isFirstArtistUpdate = false;
        setState(() { _homeArtists = artists; _artistsLoading = false; });
        unawaited(HomeFeedCache.saveArtists(artists));
      });
      if (kDebugMode && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text('Artist fetch: ${_homeArtists.length} artists — ${ApiService.lastArtistFetchDebug}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _artistsLoading = false);
      if (kDebugMode && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text('Artist load error: $e'),
          ),
        );
      }
    }
  }

  Future<void> _onPullToRefresh() async {
    final position = await HomeFeedCache.bumpPullRefreshAndGetPosition();
    if (!mounted) return;
    final stage = RefreshStage.forPosition(position);
    setState(() {
      _refreshStage = stage;
      _quickPicksRefreshKey++;
      _playlistRefreshKey++;
    });
  }

  // ignore: unused_element
  Future<void> _loadOnline({bool clearExisting = true}) async {
    setState(() {
      final willBeEmpty = clearExisting || _onlineSections.isEmpty;
      _onlineLoading = willBeEmpty;
      _onlineError = null;
      _playlistRefreshKey++;
    });
    if (clearExisting) _onlineSections = [];
    final liveSections = clearExisting ? <SongSection>[] : List<SongSection>.from(_onlineSections);
    Timer? flushTimer;
    try {
      final recentlyPlayedProvider = context.read<RecentlyPlayedProvider>();
      final topArtists  = recentlyPlayedProvider.topArtists(count: 3);
      final topArtistsRotating = recentlyPlayedProvider.rotatingTopArtists(
        count: 3,
        seed: math.Random().nextInt(1000000),
      );
      final recentSongs = recentlyPlayedProvider.history.take(10).toList();
      void flushLiveSections() {
        if (!mounted) return;
        setState(() {
          _onlineSections = List<SongSection>.from(liveSections);
          _onlineLoading = false;
        });
      }

      await ApiService.fetchHomeStreaming(
        topArtists: topArtists,
        topArtistsRotating: topArtistsRotating,
        recentlyPlayed: recentSongs,
        fastFirstSection: liveSections.isEmpty,
        onSection: (section) {
          final existingIdx = liveSections.indexWhere((s) => s.id == section.id);
          if (existingIdx != -1) {
            liveSections[existingIdx] = section;
          } else {
            liveSections.add(section);
          }
          flushTimer?.cancel();
          flushTimer = Timer(const Duration(milliseconds: 400), flushLiveSections);
        },
      ).timeout(const Duration(seconds: 25));
      flushTimer?.cancel();
      if (mounted) {
        setState(() {
          _onlineSections = List<SongSection>.from(liveSections);
          _onlineLoading = false;
        });
      }
      unawaited(HomeFeedCache.saveSections(liveSections));
    } on TimeoutException {
      flushTimer?.cancel();
      if (mounted) {
        setState(() {
          _onlineLoading = false;
          if (liveSections.isNotEmpty) {
            _onlineSections = List<SongSection>.from(liveSections);
            _onlineError = null;
          } else {
            _onlineError = AppLocalizations.of(context)!.homeFailedToLoad;
          }
        });
      }
      if (liveSections.isNotEmpty) {
        unawaited(HomeFeedCache.saveSections(liveSections));
      }
    } catch (e) {
      flushTimer?.cancel();
      if (mounted) {
        final connectivity = await Connectivity().checkConnectivity();
        if (!mounted) return;
        final isOffline = connectivity.every((r) => r == ConnectivityResult.none);
        setState(() {
          _onlineLoading = false;
          if (_onlineSections.isEmpty) {
            _onlineError = isOffline
                ? AppLocalizations.of(context)!.homeFailedToLoadCheckConnection
                : AppLocalizations.of(context)!.homeFailedToLoad;
          }
        });
      }
      if (!_onlineRetriedAfterFailure && _onlineSections.isNotEmpty && mounted) {
        _onlineRetriedAfterFailure = true;
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) _loadOnline(clearExisting: false);
        });
      }
    }
  }

  bool _onlineRetriedAfterFailure = false;

  @override
  Widget build(BuildContext context) {
    final src = context.watch<SourceProvider>();
    final isOnline = src.isOnline;

    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      body: Stack(
        children: [
          AurumStageBackdrop(scrollController: _scrollCtrl),

          RefreshIndicator(
            color: AurumTheme.accentOf(context),
            backgroundColor: AurumTheme.bgCardOf(context),
            strokeWidth: 2.6,
            displacement: 48,
            onRefresh: () => isOnline ? _onPullToRefresh() : context.read<LibraryProvider>().refresh(),
            child: AurumScrollDeltaScope(
              notifier: _scrollDelta.notifier,
              child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              cacheExtent: 1200,
              slivers: [
                _buildAppBar(context),
                if (!isOnline)
                  const SliverToBoxAdapter(child: _OfflineContent(key: ValueKey('offline')))
                else ...[
                  SliverToBoxAdapter(
                    child: _QuickPicksSection(
                      refreshKey: _quickPicksRefreshKey,
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: _ForgottenFavouritesSection(),
                  ),
                  SliverToBoxAdapter(
                    child: _HomeShelvesAndSimilarSection(
                      refreshKey: _playlistRefreshKey,
                      stage: _refreshStage,
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      floating: true,
      snap: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 12,
      flexibleSpace: AnimatedBuilder(
        animation: _scrollCtrl,
        builder: (context, _) {
          var t = 0.0;
          if (_scrollCtrl.hasClients) {
            t = (_scrollCtrl.position.pixels / 48.0).clamp(0.0, 1.0);
          }
          final bg = AurumTheme.bgOf(context);
          return IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bg.withOpacity(0.96 * t),
                    bg.withOpacity(0.96 * t),
                    bg.withOpacity(0.0),
                  ],
                  stops: const [0.0, 0.88, 1.0],
                ),
              ),
            ),
          );
        },
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      title: AurumPressable(
        scaleAmount: 0.95,
        onTap: null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  AurumTheme.accentLightOf(context),
                  AurumTheme.accentOf(context),
                  AurumTheme.accentDarkOf(context),
                ],
                stops: const [0.0, 0.5, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Image.asset(
                'assets/images/astra_wordmark.png',
                height: 14,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [AurumTheme.accentDarkOf(context), AurumTheme.accentOf(context), AurumTheme.accentLightOf(context)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AurumTheme.accentOf(context).withOpacity(0.5),
                    blurRadius: 14,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: const Text(
                '✦ Plus',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (kDebugMode)
          IconButton(
            icon: Icon(Icons.bug_report_outlined,
                color: AurumTheme.textSecondaryOf(context)),
            onPressed: () async {
              final playerProvider = context.read<PlayerProvider>();
              final result = await ApiService.debugPlaybackPath(
                realPlaybackTest: playerProvider.runRealPlaybackTest,
              );
              if (!context.mounted) return;
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(AppLocalizations.of(context)!.homePlaybackDiagnostics),
                  content: SingleChildScrollView(
                    child: SelectableText(result),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.of(context)!.commonClose),
                    ),
                  ],
                ),
              );
            },
          ),
        _TopBarIconButton(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onPressed: () => AurumDepthRoute.to(context, const SettingsScreen()),
        ),
        const _ProfileAvatarButton(),
      ],
    );
  }
}

Widget _buildOnlineShimmer(BuildContext context) {
  return Shimmer.fromColors(
      baseColor: AurumTheme.bgCardOf(context),
      highlightColor: AurumTheme.bgElevatedOf(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(3, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 130,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AurumTheme.bgCardOf(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 4,
                    itemBuilder: (_, __) => Container(
                      width: 140,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: AurumTheme.bgCardOf(context),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )),
        ),
      ),
    );
  }

Widget _buildOnlineError(BuildContext context, {String? message, required VoidCallback onRetry}) {
  return SizedBox(
    height: 300,
    child: Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.wifi_off_rounded, size: 48,
            color: AurumTheme.textMutedOf(context)),
        const SizedBox(height: 12),
        Text(
          message ?? AppLocalizations.of(context)!.homeFailedToLoad,
          textAlign: TextAlign.center,
          style: TextStyle(color: AurumTheme.textMutedOf(context)),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: onRetry,
          child: Text(AppLocalizations.of(context)!.commonRetry, style: TextStyle(color: AurumTheme.accentOf(context))),
        ),
      ]),
    ),
  );
}

class _SongSectionRow extends StatefulWidget {
  final SongSection section;
  const _SongSectionRow({required this.section});

  @override
  State<_SongSectionRow> createState() => _SongSectionRowState();
}

class _SongSectionRowState extends State<_SongSectionRow> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;

    void openAsPlaylist() {
      AurumHaptics.selection();
      final art = section.songs
          .where((s) => s.artworkUrl.isNotEmpty)
          .map((s) => s.artworkUrl)
          .firstOrNull ?? '';
      AurumDepthRoute.to(
        context,
        MixScreen(
          mixId: section.id,
          mixName: section.title,
          artworkUrl: art,
          emoji: '',
          songs: section.songs,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: openAsPlaylist,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        section.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: openAsPlaylist,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: AurumTheme.textPrimaryOf(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FadedHorizontalList(
            height: 214,
            controller: _scrollController,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 600,
              padding: const EdgeInsets.only(right: 12),
              itemCount: section.songs.length.clamp(0, 12),
              itemBuilder: (_, i) {
                if (i >= section.songs.length) return const SizedBox.shrink();
                return _SongGridCard(
                  song: section.songs[i],
                  queue: section.songs,
                  index: i,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SongGridCard extends StatefulWidget {
  final Song song;
  final List<Song> queue;
  final int index;
  const _SongGridCard({required this.song, required this.queue, required this.index});

  @override
  State<_SongGridCard> createState() => _SongGridCardState();
}

class _SongGridCardState extends State<_SongGridCard> {
  Timer? _prewarmTimer;

  @override
  void initState() {
    super.initState();
    if (widget.song.source == SongSource.youtube) {
      final delayMs = 120 + (widget.song.id.hashCode.abs() % 280);
      _prewarmTimer = Timer(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        ApiService.prewarmYtStream(widget.song);
      });
    }
  }

  @override
  void dispose() {
    _prewarmTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final queue = widget.queue;
    final index = widget.index;
    final isPlaying = context.select<PlayerProvider, bool>(
      (p) => p.currentSong?.id == song.id,
    );
    final isActuallyPlaying = context.select<PlayerProvider, bool>(
      (p) => p.isPlaying,
    );
    return RepaintBoundary(
      child: AurumScrollNudge(
        child: GestureDetector(
      onTap: () {
        AurumHaptics.selection();
        context.read<PlayerProvider>().playSong(song, queue: queue, index: index);
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 152,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    AurumArtwork(url: song.artworkUrl, size: 152, borderRadius: 0),
                    if (isPlaying)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: AurumEqualizerBars(
                            playing: isActuallyPlaying,
                            color: AurumTheme.accentOf(context),
                            size: 16,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textMutedOf(context),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}

class _StaggeredSection extends StatefulWidget {
  final String sectionId;
  final Widget child;
  const _StaggeredSection({super.key, required this.sectionId, required this.child});

  @override
  State<_StaggeredSection> createState() => _StaggeredSectionState();
}

final _seenSections = <String>{};

class _StaggeredSectionState extends State<_StaggeredSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;
  late Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AurumMotion.durationOrZero(AurumMotion.long2),
    );
    _fade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _ctrl, curve: AurumMotion.standard),
    );

    const maxAnimatedSections = 6;
    if (_seenSections.contains(widget.sectionId)) {
      _ctrl.value = 1.0;
    } else {
      final newSectionOrder = _seenSections.length;
      _seenSections.add(widget.sectionId);
      if (newSectionOrder >= maxAnimatedSections) {
        _ctrl.value = 1.0;
      } else {
        Future.delayed(Duration(milliseconds: 50 + newSectionOrder * 70), () {
          if (mounted) _ctrl.forward();
        });
      }
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: child),
      ),
      child: widget.child,
    );
  }
}

class _OfflineContent extends StatelessWidget {
  const _OfflineContent({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadProvider>().completed;

    final libLoading = lib.status == LibraryStatus.idle || lib.status == LibraryStatus.loading;
    if (libLoading && downloads.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: const Center(child: AurumMorphLoader(size: 56, contained: true)),
      );
    }
    if (lib.status == LibraryStatus.noPermission && downloads.isEmpty) {
      return _msg(context, Icons.folder_off_rounded,
          AppLocalizations.of(context)!.homeStoragePermissionNeeded, AppLocalizations.of(context)!.homeGrantPermission, () => lib.load());
    }
    if (lib.allSongs.isEmpty && downloads.isEmpty) {
      return _msg(context, Icons.music_off_rounded,
          AppLocalizations.of(context)!.homeNoLocalSongs, AppLocalizations.of(context)!.homeScanAgain, () => lib.refresh());
    }

    final scannedPaths = lib.allSongs.map((s) => s.localPath).whereType<String>().toSet();
    final appDownloadedSongs = downloads
        .map((d) => d.localPath != null ? d.song.copyWith(localPath: d.localPath) : d.song)
        .where((s) => s.localPath == null || !scannedPaths.contains(s.localPath))
        .toList();

    final librarySections = lib.sections.isNotEmpty
        ? lib.sections
        : (lib.allSongs.isNotEmpty
            ? [SongSection(title: AppLocalizations.of(context)!.homeLocalSongs, songs: lib.allSongs)]
            : <SongSection>[]);

    final sections = <SongSection>[
      if (appDownloadedSongs.isNotEmpty)
        SongSection(id: 'astra_downloads', title: 'Downloaded on Astra', songs: appDownloadedSongs),
      ...librarySections,
    ];

    final totalCount = appDownloadedSongs.length + lib.allSongs.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
          child: Row(children: [
            Icon(Icons.download_done_rounded, color: AurumTheme.accentOf(context), size: 16),
            const SizedBox(width: 6),
            Text(
              '$totalCount songs on device',
              style: TextStyle(
                color: AurumTheme.textSecondaryOf(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
        ...sections.asMap().entries.map((e) => _StaggeredSection(
          key: ValueKey('offline_${e.value.id}'),
          sectionId: 'offline_${e.value.id}',
          child: _OfflineSectionRow(section: e.value),
        )),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _msg(BuildContext context, IconData icon, String msg,
      String label, VoidCallback onTap) {
    return SizedBox(
      height: 300,
      child: Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 48, color: AurumTheme.textMutedOf(context)),
          const SizedBox(height: 12),
          Text(msg, style: TextStyle(color: AurumTheme.textMutedOf(context))),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onTap,
            child: Text(label, style: TextStyle(color: AurumTheme.accentOf(context))),
          ),
        ]),
      ),
    );
  }
}

class _OfflineSectionRow extends StatefulWidget {
  final SongSection section;
  const _OfflineSectionRow({required this.section});

  @override
  State<_OfflineSectionRow> createState() => _OfflineSectionRowState();
}

class _OfflineSectionRowState extends State<_OfflineSectionRow> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openMix(BuildContext context) {
    AurumHaptics.selection();
    final section = widget.section;
    final art = section.songs
        .map((s) => s.artworkUrl)
        .firstWhere((u) => u.isNotEmpty, orElse: () => '');
    AurumDepthRoute.to(
      context,
      MixScreen(
        mixId: section.id,
        mixName: section.title,
        artworkUrl: art,
        emoji: '',
        songs: section.songs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final isAstraDownloads = section.id == 'astra_downloads';
    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: AurumTheme.accentGradientOf(context),
                      ),
                    ),
                    if (isAstraDownloads) ...[
                      Icon(Icons.download_done_rounded,
                          size: 16, color: AurumTheme.accentOf(context)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        section.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openMix(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: AurumTheme.bgCardOf(context).withOpacity(0.6),
                      border: Border.all(
                        color: AurumTheme.dividerOf(context),
                        width: 0.6,
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.commonSeeAll,
                      style: TextStyle(
                        color: AurumTheme.accentOf(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FadedHorizontalList(
            height: 214,
            controller: _scrollController,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 600,
              padding: const EdgeInsets.only(right: 12),
              itemCount: section.songs.length.clamp(0, 12),
              itemBuilder: (_, i) {
                if (i >= section.songs.length) return const SizedBox.shrink();
                return _SongGridCard(
                  song: section.songs[i],
                  queue: section.songs,
                  index: i,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _TopBarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fg = AurumTheme.textPrimaryOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AurumTheme.bgCardOf(context).withOpacity(isDark ? 0.62 : 0.85),
          border: Border.all(color: fg.withOpacity(0.10), width: 0.8),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          tooltip: tooltip,
          icon: Icon(icon, size: 21, color: fg),
          onPressed: () {
            AurumHaptics.selection();
            onPressed();
          },
        ),
      ),
    );
  }
}

class _ProfileAvatarButton extends StatelessWidget {
  const _ProfileAvatarButton();

  Future<void> _openProfile(BuildContext context) async {
    AurumHaptics.light();
    final auth = context.read<AuthProvider>();

    if (!auth.isSignedIn) {
      await Navigator.push<bool>(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (context, animation, __, child) => ColoredBox(
            color: AurumTheme.bgOf(context),
            child: FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.05),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: animation, curve: AurumMotion.standard)),
                child: child,
              ),
            ),
          ),
        ),
      );
      return;
    }

    await AurumDepthRoute.to(context, const ProfileScreen());
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = context.watch<AuthProvider>().avatarUrl;

    return Padding(
      padding: const EdgeInsets.only(right: 12, left: 4),
      child: AurumCoachTip(
        prefKey: 'profile_signin_promo_seen_v2',
        icon: Icons.auto_awesome_rounded,
        title: 'Make it yours',
        message:
            'Sign in for smarter recommendations and a library that stays in sync.',
        promo: AurumPromoData.signIn,
        onPromoAction: () => _openProfile(context),
        enabled: () => !context.read<AuthProvider>().isSignedIn,
        ready: () async {
          try {
            final p = await SharedPreferences.getInstance();
            return (p.getBool('notif_prompted_v1') ?? false) &&
                (p.getBool('asked_launch_permissions') ?? false);
          } catch (_) {
            return true;
          }
        },
        child: AurumPressable(
        scaleAmount: 0.90,
        onTap: () => _openProfile(context),
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AurumTheme.accentGradientOf(context),
          ),
          padding: const EdgeInsets.all(1.5),
          child: ClipOval(
            child: avatarUrl != null
                ? CachedNetworkImage(
                    imageUrl: avatarUrl,
                    cacheManager: AurumImageCache(),
                    fit: BoxFit.cover,
                    memCacheWidth: 96,
                    memCacheHeight: 96,
                    placeholder: (_, __) => _defaultIcon(context),
                    errorWidget: (_, __, ___) => _defaultIcon(context),
                  )
                : _defaultIcon(context),
          ),
        ),
      ),
      ),
    );
  }

  Widget _defaultIcon(BuildContext context) => Container(
        color: AurumTheme.bgOf(context),
        child: Icon(Icons.person_rounded,
            color: AurumTheme.textSecondaryOf(context), size: 22),
      );
}

class _SpeedDialSection extends StatelessWidget {
  const _SpeedDialSection();

  static const int _kMaxShown = 8;

  @override
  Widget build(BuildContext context) {
    final history = context.watch<RecentlyPlayedProvider>().history;
    if (history.isEmpty) return const SizedBox.shrink();
    final songs = history.take(_kMaxShown).toList();
    final player = context.read<PlayerProvider>();

    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)?.homeListenAgain ?? 'Speed dial',
            style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 118,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 500,
              padding: const EdgeInsets.only(right: 12),
              itemCount: songs.length,
              itemBuilder: (_, i) => _SafeListenAgainCard(
                song: songs[i],
                compact: true,
                onTap: () {
                  player.playSong(songs[i], queue: songs, index: i);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountPlaylistsSection extends StatelessWidget {
  const _AccountPlaylistsSection();

  @override
  Widget build(BuildContext context) {
    final playlists = context.watch<PlaylistProvider>().playlists;
    if (playlists.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your playlists',
            style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 700,
              padding: const EdgeInsets.only(right: 12),
              itemCount: playlists.length,
              itemBuilder: (_, i) =>
                  _AccountPlaylistCard(playlist: playlists[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountPlaylistCard extends StatelessWidget {
  final AurumPlaylist playlist;
  const _AccountPlaylistCard({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return _ErrorBoundary(
      fallback: const SizedBox(width: 148),
      child: AurumPressable(
        scaleAmount: 0.96,
        onTap: () {
          AurumHaptics.selection();
          AurumDepthRoute.to(
            context,
            PlaylistDetailScreen(playlistId: playlist.id),
          );
        },
        child: Container(
          width: 148,
          margin: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: playlist.coverArt != null
                    ? AurumArtwork(
                        url: playlist.coverArt!, size: 296, borderRadius: 12)
                    : Container(
                        width: 148,
                        height: 148,
                        color: AurumTheme.bgCardOf(context),
                        child: Icon(Icons.queue_music_rounded,
                            color: AurumTheme.accentOf(context), size: 40),
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${playlist.songCount} songs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textSecondaryOf(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MixedForYouSection extends StatelessWidget {
  const _MixedForYouSection();

  static const int _kMaxMixes = 6;

  @override
  Widget build(BuildContext context) {
    final recently = context.watch<RecentlyPlayedProvider>();
    final artists = recently.topArtists(count: _kMaxMixes);
    if (artists.isEmpty) return const SizedBox.shrink();

    final history = recently.history;

    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mixed for you',
            style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 700,
              padding: const EdgeInsets.only(right: 12),
              itemCount: artists.length,
              itemBuilder: (_, i) {
                final artistName = artists[i];
                final seedSongs = history
                    .where((s) => s.artist == artistName)
                    .take(20)
                    .toList();
                if (seedSongs.isEmpty) return const SizedBox.shrink();
                return _MixCard(artistName: artistName, seedSongs: seedSongs);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MixCard extends StatelessWidget {
  final String artistName;
  final List<Song> seedSongs;
  const _MixCard({required this.artistName, required this.seedSongs});

  @override
  Widget build(BuildContext context) {
    return _ErrorBoundary(
      fallback: const SizedBox(width: 148),
      child: AurumPressable(
        scaleAmount: 0.96,
        onTap: () {
          AurumHaptics.selection();
          AurumDepthRoute.to(
            context,
            MixScreen(
              mixId: 'mix_${artistName.hashCode}',
              mixName: '$artistName Mix',
              artworkUrl: seedSongs.first.artworkUrl,
              emoji: '',
              songs: seedSongs,
              enableRefresh: true,
              refreshSeed: artistName,
            ),
          );
        },
        child: Container(
          width: 148,
          margin: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AurumArtwork(
                    url: seedSongs.first.artworkUrl,
                    size: 296,
                    borderRadius: 12),
              ),
              const SizedBox(height: 6),
              Text(
                '$artistName Mix',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListenAgainSection extends StatelessWidget {
  const _ListenAgainSection();

  @override
  Widget build(BuildContext context) {
    final history = context.watch<RecentlyPlayedProvider>().history;
    return _RecentlyPlayedSection(
      title: AppLocalizations.of(context)!.homeListenAgain,
      songs: history.take(12).toList(),
    );
  }
}

class _RecentlyPlayedSection extends StatelessWidget {
  final String title;
  final List<Song> songs;
  const _RecentlyPlayedSection({required this.title, required this.songs});

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) return const SizedBox.shrink();
    final player = context.read<PlayerProvider>();
    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 168,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 600,
              padding: const EdgeInsets.only(right: 12),
              itemCount: songs.length,
              itemBuilder: (_, i) => _SafeListenAgainCard(
                song: songs[i],
                onTap: () {
                  player.playSong(songs[i], queue: songs, index: i);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeListenAgainCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final bool compact;
  const _SafeListenAgainCard({
    required this.song,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = compact ? 92.0 : 130.0;
    return _ErrorBoundary(
      fallback: SizedBox(width: width),
      child: AurumPressable(
        scaleAmount: 0.96,
        onTap: onTap,
        child: Container(
          width: width,
          margin: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(compact ? 10 : 12),
                child: AurumArtwork(
                    url: song.artworkUrl,
                    size: compact ? 184 : 260,
                    borderRadius: compact ? 10 : 12),
              ),
              const SizedBox(height: 6),
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!compact)
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AurumTheme.textSecondaryOf(context),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBoundary extends StatelessWidget {
  final Widget child;
  final Widget fallback;
  const _ErrorBoundary({required this.child, required this.fallback});

  @override
  Widget build(BuildContext context) {
    ErrorWidget.builder = (details) => fallback;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ErrorWidget.builder = aurumDebugErrorWidgetBuilder;
    });
    return child;
  }
}

class _ForgottenFavouritesSection extends StatelessWidget {
  const _ForgottenFavouritesSection();

  @override
  Widget build(BuildContext context) {
    final history = context.watch<RecentlyPlayedProvider>().history;
    if (history.isEmpty) return const SizedBox.shrink();

    final candidateIds = RecommendationEngine.rediscoverCandidateIds(count: 10);
    if (candidateIds.isEmpty) return const SizedBox.shrink();

    final byId = {for (final s in history) s.id: s};
    final songs = candidateIds
        .map((id) => byId[id])
        .whereType<Song>()
        .toList();
    if (songs.isEmpty) return const SizedBox.shrink();

    final player = context.read<PlayerProvider>();
    return Padding(
      padding: const EdgeInsets.only(top: 32, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 18,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: AurumTheme.accentGradientOf(context),
                ),
              ),
              Expanded(
                child: Text(
                  AppLocalizations.of(context)!.homeForgottenFavourites,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ForgottenFavouriteCard(
            song: songs.first,
            onTap: () {
              AurumHaptics.selection();
              player.playSong(songs.first, queue: songs, index: 0);
            },
          ),
        ],
      ),
    );
  }
}

class _ForgottenFavouriteCard extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  const _ForgottenFavouriteCard({required this.song, required this.onTap});

  static String _formatViewCount(int count) {
    if (count >= 1000000000) {
      return '${(count / 1000000000).toStringAsFixed(1)}B';
    }
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AurumPressable(
      scaleAmount: 0.97,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AurumArtwork(
                        url: song.artworkUrl, size: 560, borderRadius: 0),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.75),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              song.viewCount != null
                  ? '${song.artist} • ${_formatViewCount(song.viewCount!)} views'
                  : song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AurumTheme.textSecondaryOf(context),
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      );
  }
}

class _ArtistStrip extends StatefulWidget {
  final List<ArtistSimple> artists;
  final bool loading;
  const _ArtistStrip({required this.artists, required this.loading});

  @override
  State<_ArtistStrip> createState() => _ArtistStripState();
}

class _ArtistStripState extends State<_ArtistStrip> {
  static const int _maxShown = 4;

  @override
  Widget build(BuildContext context) {
    final artists = widget.artists;
    final loading = widget.loading;
    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.homePopularArtists,
            style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          loading
              ? _buildChipShimmer(context)
              : artists.isEmpty
                  ? const SizedBox.shrink()
                  : SizedBox(
                      height: 150,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: artists.take(_maxShown).length,
                        itemBuilder: (context, index) {
                          final a = artists.take(_maxShown).toList()[index];
                          return _ArtistChip(key: ValueKey(a.id), artist: a);
                        },
                      ),
                    ),
        ],
      ),
    );
  }

  Widget _buildChipShimmer(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Shimmer.fromColors(
        baseColor: AurumTheme.bgCardOf(context),
        highlightColor: AurumTheme.bgElevatedOf(context),
        child: Row(
          children: List.generate(4, (_) => Container(
            width: 110,
            margin: const EdgeInsets.only(right: 16),
            child: Column(
              children: [
                CircleAvatar(radius: 52, backgroundColor: AurumTheme.bgCardOf(context)),
                const SizedBox(height: 10),
                Container(
                  height: 13,
                  width: 70,
                  decoration: BoxDecoration(
                    color: AurumTheme.bgCardOf(context),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          )),
        ),
      ),
    );
  }
}

class _ArtistChip extends StatelessWidget {
  final ArtistSimple artist;
  const _ArtistChip({super.key, required this.artist});

  void _open(BuildContext context) {
    AurumHaptics.selection();
    AurumDepthRoute.to(
      context,
      ArtistScreen(
        artistId: artist.id.isNotEmpty ? artist.id : null,
        artistName: artist.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentArtist = context.select<PlayerProvider, bool>(
      (p) => p.currentSong != null &&
          p.currentSong!.artist.toLowerCase() == artist.name.toLowerCase(),
    );
    final isActuallyPlaying = context.select<PlayerProvider, bool>((p) => p.isPlaying);

    return RepaintBoundary(
      child: AurumPressable(
      scaleAmount: 0.94,
      onTap: () => _open(context),
      child: Container(
        width: 110,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          children: [
            AurumStackedArtwork(
              url: artist.imageUrl,
              size: 104,
              circular: true,
              showNowPlaying: isCurrentArtist,
              isPlaying: isActuallyPlaying,
              stackColor: AurumTheme.accentOf(context),
            ),
            const SizedBox(height: 10),
            Text(
              artist.name,
              style: TextStyle(
                color: isCurrentArtist
                    ? AurumTheme.accentOf(context)
                    : AurumTheme.textPrimaryOf(context),
                fontSize: 13,
                fontWeight: isCurrentArtist ? FontWeight.w700 : FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

List<String> _uniquePrimaryArtists(List<String> raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final r in raw) {
    final primary = r
        .split(RegExp(r'\s*(?:,|&|\+|/|;|\bfeat\.?\b|\bft\.?\b)\s*',
            caseSensitive: false))
        .first
        .trim();
    final key = primary.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (key.isEmpty || !seen.add(key)) continue;
    out.add(primary);
  }
  return out;
}

List<({String artistName, String? artistImageUrl, RelatedArtist? relatedArtist, List<ArtistAlbum> albums})> _dedupeSimilarRows(
    List<({String artistName, String? artistImageUrl, RelatedArtist? relatedArtist, List<ArtistAlbum> albums})> rows) {
  final seenArtists = <String>{};
  final seenImages = <String>{};
  final seenAlbums = <String>{};
  final seenRelated = <String>{};
  String norm(String v) => v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final out = <({String artistName, String? artistImageUrl, RelatedArtist? relatedArtist, List<ArtistAlbum> albums})>[];
  for (final row in rows) {
    final aKey = norm(row.artistName);
    final img = (row.artistImageUrl ?? '').trim();
    if (aKey.isEmpty || seenArtists.contains(aKey)) continue;
    if (img.isNotEmpty && seenImages.contains(img)) continue;

    final albums = <ArtistAlbum>[];
    final rowKeys = <String>{};
    for (final al in row.albums) {
      final k = norm(al.name);
      if (k.isEmpty || seenAlbums.contains(k) || !rowKeys.add(k)) continue;
      albums.add(al);
    }
    if (albums.length < 3) continue;

    var related = row.relatedArtist;
    if (related != null) {
      final rk = related.id.isNotEmpty ? related.id : norm(related.name);
      if (norm(related.name) == aKey || seenRelated.contains(rk)) {
        related = null;
      } else {
        seenRelated.add(rk);
      }
    }

    seenArtists.add(aKey);
    if (img.isNotEmpty) seenImages.add(img);
    seenAlbums.addAll(rowKeys);
    out.add((
      artistName: row.artistName,
      artistImageUrl: row.artistImageUrl,
      relatedArtist: related,
      albums: albums,
    ));
  }
  return out;
}

class _SimilarArtistsRow extends StatelessWidget {
  final String seedArtistName;
  final String? seedArtistImageUrl;
  final RelatedArtist? relatedArtist;
  final List<ArtistAlbum> albums;
  const _SimilarArtistsRow({
    super.key,
    required this.seedArtistName,
    required this.seedArtistImageUrl,
    required this.relatedArtist,
    required this.albums,
  });

  void _openSeedArtist(BuildContext context) {
    AurumHaptics.selection();
    AurumDepthRoute.to(
      context,
      ArtistScreen(artistName: seedArtistName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _openSeedArtist(context),
                child: ClipOval(
                  child: AurumArtwork(
                    url: seedArtistImageUrl ?? '',
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openSeedArtist(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Similar to',
                        style: TextStyle(
                          color: AurumTheme.textSecondaryOf(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        seedArtistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _openSeedArtist(context),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.arrow_forward,
                      color: AurumTheme.textPrimaryOf(context),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FadedHorizontalList(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 500,
              padding: const EdgeInsets.only(right: 12),
              itemCount: albums.length + (relatedArtist != null ? 1 : 0),
              itemBuilder: (_, i) {
                if (relatedArtist != null) {
                  if (i == 0) {
                    return _RelatedArtistChipCard(
                      key: ValueKey('related_${relatedArtist!.id}'),
                      artist: relatedArtist!,
                    );
                  }
                  return _SimilarArtistAlbumCard(
                    key: ValueKey('${albums[i - 1].id}_${i - 1}'),
                    album: albums[i - 1],
                  );
                }
                return _SimilarArtistAlbumCard(
                  key: ValueKey('${albums[i].id}_$i'),
                  album: albums[i],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedArtistChipCard extends StatelessWidget {
  final RelatedArtist artist;
  const _RelatedArtistChipCard({super.key, required this.artist});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          AurumHaptics.light();
          AurumDepthRoute.to(
            context,
            ArtistScreen(
              artistId: artist.id.startsWith('yt_') ? artist.id : 'yt_${artist.id}',
              artistName: artist.name,
            ),
          );
        },
        child: Container(
          width: 148,
          margin: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipOval(
                child: AurumArtwork(
                  url: artist.imageUrl,
                  size: 148,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimilarSongsRow extends StatelessWidget {
  final Song seedSong;
  final List<Song> related;
  const _SimilarSongsRow({
    super.key,
    required this.seedSong,
    required this.related,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AurumArtwork(
                  url: seedSong.artworkUrl,
                  size: 44,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Similar to',
                      style: TextStyle(
                        color: AurumTheme.textSecondaryOf(context),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      seedSong.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AurumTheme.textPrimaryOf(context),
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FadedHorizontalList(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 500,
              padding: const EdgeInsets.only(right: 12),
              itemCount: related.length,
              itemBuilder: (_, i) => _SimilarSongCard(
                key: ValueKey('${related[i].id}_$i'),
                song: related[i],
                queue: related,
                index: i,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimilarSongCard extends StatelessWidget {
  final Song song;
  final List<Song> queue;
  final int index;
  const _SimilarSongCard({
    super.key,
    required this.song,
    required this.queue,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          AurumHaptics.light();
          context.read<PlayerProvider>().playSong(
                song,
                queue: queue,
                index: index,
              );
        },
        child: Container(
          width: 148,
          margin: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AurumArtwork(url: song.artworkUrl, size: 148, borderRadius: 16),
              ),
              const SizedBox(height: 10),
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (song.artist.isNotEmpty)
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AurumTheme.textSecondaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimilarArtistAlbumCard extends StatelessWidget {
  final ArtistAlbum album;
  const _SimilarArtistAlbumCard({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          AurumHaptics.light();
          AurumDepthRoute.to(
            context,
            AlbumScreen(
              albumId: album.id,
              albumName: album.name,
              artworkUrl: album.artworkUrl,
            ),
          );
        },
        child: Container(
          width: 148,
          margin: const EdgeInsets.only(right: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AurumArtwork(url: album.artworkUrl, size: 148, borderRadius: 16),
              ),
              const SizedBox(height: 10),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (album.year != null && album.year!.isNotEmpty)
                Text(
                  album.year!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AurumTheme.textSecondaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPicksSection extends StatefulWidget {
  final int refreshKey;
  const _QuickPicksSection({this.refreshKey = 0});

  @override
  State<_QuickPicksSection> createState() => _QuickPicksSectionState();
}

class _QuickPicksSectionState extends State<_QuickPicksSection> {
  List<Song>? _songs;
  bool _failed = false;
  List<Song> _pool = const [];

  static const int _kSeedCount = 3;
  static const int _kMaxShown = 24;

  RecentlyPlayedProvider? _recent;
  String? _seedKey;
  int _playsSinceLoad = 0;
  bool _loading = false;

  String _currentSeedKey() => _recent!.history
      .take(_kSeedCount)
      .map((s) => s.id)
      .where((id) => id.isNotEmpty)
      .join('|');

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _recent = context.read<RecentlyPlayedProvider>();
    _seedKey = _currentSeedKey();
    _recent!.addListener(_onHistoryChanged);
  }

  @override
  void dispose() {
    _recent?.removeListener(_onHistoryChanged);
    _pageCtrl?.dispose();
    super.dispose();
  }

  PageController? _pageCtrl;
  double _pageFraction = 0;
  int _gradualGen = 0;
  final Set<String> _fading = <String>{};

  PageController _pageController(double fraction) {
    final existing = _pageCtrl;
    if (existing != null && (fraction - _pageFraction).abs() < 0.001) {
      return existing;
    }
    final fresh = PageController(viewportFraction: fraction);
    _pageCtrl = fresh;
    _pageFraction = fraction;
    if (existing != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => existing.dispose());
    }
    return fresh;
  }

  Future<void> _applyGradually(List<Song> target) async {
    final gen = ++_gradualGen;
    final cur = List<Song>.from(_songs ?? const <Song>[]);
    for (var i = 0; i < target.length; i++) {
      if (!mounted || gen != _gradualGen) return;
      final want = target[i];
      if (i < cur.length) {
        if (cur[i].id == want.id) continue;
        final j = cur.indexWhere((s) => s.id == want.id, i + 1);
        if (j >= 0) {
          final t = cur[i];
          cur[i] = cur[j];
          cur[j] = t;
        } else {
          cur[i] = want;
        }
      } else {
        if (cur.any((s) => s.id == want.id)) continue;
        cur.add(want);
      }
      setState(() => _songs = List<Song>.from(cur));
      await Future<void>.delayed(const Duration(milliseconds: 110));
    }
    if (!mounted || gen != _gradualGen) return;
    if (cur.length > target.length) {
      cur.removeRange(target.length, cur.length);
      setState(() => _songs = List<Song>.from(cur));
    }
  }

  void _onHistoryChanged() {
    if (!mounted || _recent == null || _loading) return;
    final key = _currentSeedKey();
    if (key.isEmpty || key == _seedKey) return;
    final hadSongs = _songs != null && _songs!.isNotEmpty;
    final firstKey = _seedKey == null || _seedKey!.isEmpty;
    _seedKey = key;
    if (firstKey && hadSongs) return;
    _playsSinceLoad++;
    if (hadSongs && _playsSinceLoad < 3) return;
    _playsSinceLoad = 0;
    _loading = true;
    _load(silent: hadSongs).whenComplete(() => _loading = false);
  }

  VoidCallback _removeFromRow(bool Function(Song) test) {
    if (!mounted) return () {};
    _gradualGen++;
    final prevSongs = _songs;
    final prevPool = _pool;
    List<Song>? afterSongs;
    setState(() {
      _pool = _pool.where((s) => !test(s)).toList();
      final next = (_songs ?? const <Song>[]).where((s) => !test(s)).toList();
      if (next.length < _kMaxShown) {
        final have = next.map((s) => s.id).toSet();
        for (final s in _pool) {
          if (next.length >= _kMaxShown) break;
          if (have.add(s.id)) next.add(s);
        }
      }
      _songs = next;
      afterSongs = next;
    });
    unawaited(HomeFeedCache.saveQuickPicks(_pool, touch: false));
    return () {
      if (!mounted) return;
      if (!identical(_songs, afterSongs)) return;
      setState(() {
        _songs = prevSongs;
        _pool = prevPool;
      });
      unawaited(HomeFeedCache.saveQuickPicks(_pool, touch: false));
    };
  }

  void _showUndo(String message, VoidCallback onUndo) {
    if (!mounted) return;
    AurumSnack.show(
      context,
      message,
      duration: const Duration(seconds: 5),
      actionLabel: 'Undo',
      onAction: onUndo,
    );
  }

  void _dismissFromRow(
    bool Function(Song) test,
    String message,
    VoidCallback onUnhide,
  ) {
    final ids = (_songs ?? const <Song>[])
        .where(test)
        .map((s) => s.id)
        .toSet();
    VoidCallback? rowUndo;
    var undone = false;
    if (mounted && ids.isNotEmpty) setState(() => _fading.addAll(ids));
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (!mounted || undone) return;
      _fading.removeAll(ids);
      rowUndo = _removeFromRow(test);
    });
    _showUndo(message, () {
      undone = true;
      onUnhide();
      final u = rowUndo;
      if (u != null) {
        u();
      } else if (mounted) {
        setState(() => _fading.removeAll(ids));
      }
    });
  }

  void _onNotInterested(Song song) {
    unawaited(QuickPicksFilter.hideSong(song));
    _dismissFromRow(
      (s) => s.id == song.id,
      "Got it — this song won't show in Quick picks",
      () => unawaited(QuickPicksFilter.unhideSong(song)),
    );
  }

  void _onDontRecommendArtist(Song song) {
    if (!QuickPicksFilter.canHideArtist(song.artist)) return;
    unawaited(QuickPicksFilter.hideArtist(song.artist));
    final first = QuickPicksFilter.primaryArtistName(song.artist);
    _dismissFromRow(
      (s) => QuickPicksFilter.isHidden(s) || s.id == song.id,
      first.isEmpty
          ? 'Got it — fewer songs like this'
          : 'Got it — fewer songs from $first',
      () => unawaited(QuickPicksFilter.unhideArtist(song.artist)),
    );
  }

  Future<void> _hydrateFromCache() async {
    await QuickPicksFilter.load();
    final cached = QuickPicksFilter.apply(await HomeFeedCache.loadQuickPicks());
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _songs = cached.take(_kMaxShown).toList();
        _pool = cached;
      });
      if (!await HomeFeedCache.isQuickPicksFresh() &&
          !await HomeFeedCache.coldAttemptedRecently('quickpicks')) {
        await HomeFeedCache.markColdAttempt('quickpicks');
        _load(silent: true);
      }
    } else {
      if (await HomeFeedCache.coldAttemptedRecently('quickpicks')) {
        if (mounted) setState(() => _songs = const []);
        return;
      }
      await HomeFeedCache.markColdAttempt('quickpicks');
      _load();
    }
  }

  @override
  void didUpdateWidget(_QuickPicksSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      if (AudioPrefs.dataSaverActiveNotifier.value) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = _pageCtrl;
          if (mounted && c != null && c.hasClients) {
            unawaited(c.animateToPage(0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut));
          }
        });
      } else {
        final old = _pageCtrl;
        _pageCtrl = null;
        if (old != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
        }
      }
      _rotateFromPool();
    }
  }

  void _rotateFromPool() {
    final saver = AudioPrefs.dataSaverActiveNotifier.value;
    if (_pool.length <= _kMaxShown && !(saver && _pool.length >= 6)) {
      _load(silent: true);
      return;
    }
    _pool = List<Song>.from(_pool)..shuffle(math.Random(widget.refreshKey));
    final next = _pool.take(_kMaxShown).toList();
    if (!mounted) return;
    if (saver) {
      unawaited(_applyGradually(next));
      return;
    }
    setState(() => _songs = next);
    unawaited(HomeFeedCache.saveQuickPicks(_pool));
  }

  Widget _qpSlot(List<Song> songs, int i) {
    final saver = AudioPrefs.dataSaverActiveNotifier.value;
    final row = _QuickPickListRow(
      key: ValueKey(saver
          ? 'quickpick_${songs[i].id}'
          : 'quickpick_${songs[i].id}_${widget.refreshKey}'),
      song: songs[i],
      queue: songs,
      index: i,
      removing: _fading.contains(songs[i].id),
      onNotInterested: () => _onNotInterested(songs[i]),
      onDontRecommendArtist: QuickPicksFilter.canHideArtist(songs[i].artist)
          ? () => _onDontRecommendArtist(songs[i])
          : null,
    );
    if (!saver) return row;
    return AnimatedSwitcher(
      key: ValueKey('qp_slot_$i'),
      duration: const Duration(milliseconds: 320),
      layoutBuilder: (current, previous) => Stack(
        children: <Widget>[...previous, if (current != null) current],
      ),
      child: row,
    );
  }

  Future<void> _load({bool silent = false}) async {
    _gradualGen++;
    if (!silent && mounted) setState(() => _failed = false);
    var ok = false;
    try {
      final history =
          context.read<RecentlyPlayedProvider>().history.take(_kSeedCount);
      final seedIds = history
          .map((s) => s.id)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (seedIds.isEmpty) {
        if (mounted) setState(() { _songs = silent ? _songs : const []; _failed = !silent; });
        return;
      }

      final saver = AudioPrefs.dataSaverActiveNotifier.value;
      Future<List<Song>> fetchSeed(String id) =>
          ApiService.fetchYouMightAlsoLike(id)
              .catchError((_) => const <Song>[]);
      var results = saver && seedIds.length > 1
          ? <List<Song>>[await fetchSeed(seedIds.first)]
          : await Future.wait(seedIds.map(fetchSeed));

      final poolCap = _kMaxShown * 4;
      await QuickPicksFilter.load();

      List<Song> buildPool(List<List<Song>> lists) {
        final seen = <String>{};
        final built = <Song>[];
        final skippedVariants = <Song>[];
        var idx = 0;
        while (built.length < poolCap) {
          var anyLeft = false;
          for (final list in lists) {
            if (idx >= list.length) continue;
            anyLeft = true;
            final s = list[idx];
            if (s.id.isEmpty || !seen.add(s.id)) continue;
            if (RecommendationEngine.isNonMusicContent(s)) continue;
            if (QuickPicksFilter.isHidden(s)) continue;
            if (RecommendationEngine.isInherentVariant(s.title) ||
                RecommendationEngine.isLowQualityUpload(s.title)) {
              skippedVariants.add(s);
              continue;
            }
            built.add(s);
            if (built.length >= poolCap) break;
          }
          if (!anyLeft) break;
          idx++;
        }
        if (built.length < 12) {
          for (final s in skippedVariants) {
            if (built.length >= 12) break;
            built.add(s);
          }
        }
        return built;
      }

      var pool = buildPool(results);
      if (saver && seedIds.length > results.length && pool.length < _kMaxShown) {
        final rest = await Future.wait(
            seedIds.skip(results.length).map(fetchSeed));
        results = [...results, ...rest];
        pool = buildPool(results);
      }

      pool.sort((a, b) => RecommendationEngine.scoreCandidate(a)
          .compareTo(RecommendationEngine.scoreCandidate(b)));
      final merged = pool.reversed.take(_kMaxShown).toList();

      if (!mounted) return;
      if (merged.isEmpty) {
        setState(() { if (!silent) _failed = true; });
        return;
      }
      ok = true;
      final fullPool = pool.reversed.toList();
      unawaited(HomeFeedCache.saveQuickPicks(fullPool));
      setState(() {
        _songs = merged;
        _failed = false;
        _pool = fullPool;
      });
    } catch (_) {
      if (mounted && !silent) setState(() => _failed = true);
    } finally {
      if (!ok && !silent) {
        unawaited(HomeFeedCache.clearColdAttempt('quickpicks'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final songs = _songs;

    if (songs == null && !_failed) {
      return Padding(
        padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShelfTitleSkeleton(),
            const SizedBox(height: 14),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AurumTheme.bgCardOf(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 14,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AurumTheme.bgCardOf(context),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 12,
                            width: 140,
                            decoration: BoxDecoration(
                              color: AurumTheme.bgCardOf(context),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    if (songs == null || songs.isEmpty) {
      return const SizedBox.shrink();
    }

    const rowsPerColumn = 4;
    final columnCount = (songs.length / rowsPerColumn).ceil();

    return Padding(
      padding: const EdgeInsets.only(top: 28, left: 12, right: 0, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 4,
                  height: 18,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: AurumTheme.accentGradientOf(context),
                  ),
                ),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.homeQuickPicks,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(context),
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 68.0 * rowsPerColumn,
            child: PageView.builder(
              controller: _pageController(
                  (MediaQuery.of(context).size.width - 24) /
                      MediaQuery.of(context).size.width),
              physics: const PageScrollPhysics(),
              padEnds: false,
              itemCount: columnCount,
              itemBuilder: (_, colIndex) {
                final start = colIndex * rowsPerColumn;
                final end = (start + rowsPerColumn).clamp(0, songs.length);
                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = start; i < end; i++)
                        _qpSlot(songs, i),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickPickListRow extends StatelessWidget {
  final Song song;
  final List<Song> queue;
  final int index;
  final VoidCallback? onNotInterested;
  final VoidCallback? onDontRecommendArtist;
  final bool removing;
  const _QuickPickListRow({
    super.key,
    required this.song,
    required this.queue,
    required this.index,
    this.onNotInterested,
    this.onDontRecommendArtist,
    this.removing = false,
  });

  @override
  Widget build(BuildContext context) {
    final isPlaying = context.select<PlayerProvider, bool>(
      (p) => p.currentSong?.id == song.id,
    );
    final isActuallyPlaying = context.select<PlayerProvider, bool>(
      (p) => p.currentSong?.id == song.id && p.isPlaying,
    );
    final accent = AurumTheme.accentOf(context);

    void openMenu() => showAurumSongOptions(
          context,
          song,
          ytStyle: true,
          onNotInterested: onNotInterested,
          onDontRecommendArtist: onDontRecommendArtist,
        );

    final content = RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isPlaying ? accent.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              AurumHaptics.selection();
              context
                  .read<PlayerProvider>()
                  .playSong(song, queue: queue, index: index);
            },
            onLongPress: openMenu,
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 4, right: 0, top: 6, bottom: 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AurumArtwork(
                              url: song.artworkUrl, size: 52, borderRadius: 0),
                          if (isPlaying)
                            Container(
                              color: Colors.black.withOpacity(0.5),
                              alignment: Alignment.center,
                              child: AurumEqualizerBars(
                                playing: isActuallyPlaying,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaying
                                ? accent
                                : AurumTheme.textPrimaryOf(context),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AurumTheme.textMutedOf(context),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'More options',
                    child: InkResponse(
                      radius: 24,
                      onTap: openMenu,
                      child: SizedBox(
                        width: 44,
                        height: 52,
                        child: Icon(
                          Icons.more_vert,
                          size: 20,
                          color: AurumTheme.textMutedOf(context),
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

    return IgnorePointer(
      ignoring: removing,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: removing ? 0.0 : 1.0),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInOutCubic,
        child: content,
        builder: (context, v, child) => ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: v,
            child: Opacity(opacity: v, child: child),
          ),
        ),
      ),
    );
  }
}

class _HomeShelvesAndSimilarSection extends StatefulWidget {
  final int refreshKey;
  final RefreshStage stage;
  const _HomeShelvesAndSimilarSection({
    this.refreshKey = 0,
    this.stage = const RefreshStage(
      quickPicks: true,
      shelves: false,
      similarArtistRows: false,
      similarSongRows: false,
    ),
  });

  @override
  State<_HomeShelvesAndSimilarSection> createState() =>
      _HomeShelvesAndSimilarSectionState();
}

class _HomeShelvesAndSimilarSectionState
    extends State<_HomeShelvesAndSimilarSection> {
  List<HomeShelf>? _shelves;
  List<({String artistName, String? artistImageUrl, RelatedArtist? relatedArtist, List<ArtistAlbum> albums})>? _similarRows;
  List<({Song seedSong, List<Song> related})>? _similarSongRows;
  bool _shelvesFailed = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    _recent = context.read<RecentlyPlayedProvider>();
    _hadHistory = _recent!.history.isNotEmpty;
    _recent!.addListener(_onHistoryChanged);
  }

  RecentlyPlayedProvider? _recent;
  bool _hadHistory = false;
  bool _personalLoading = false;

  Future<void> _onHistoryChanged() async {
    if (_hadHistory || _personalLoading) return;
    if (_recent == null || _recent!.history.isEmpty) return;
    _hadHistory = true;
    if (await HomeFeedCache.isSimilarArtistRowsFresh() &&
        await HomeFeedCache.isSimilarSongRowsFresh()) {
      return;
    }
    if (!mounted) return;
    _personalLoading = true;
    await _load(skipShelves: true);
    _personalLoading = false;
  }

  @override
  void dispose() {
    _recent?.removeListener(_onHistoryChanged);
    super.dispose();
  }

  Future<void> _hydrateFromCache() async {
    final cachedShelves = await HomeFeedCache.loadHomeShelves();
    final cachedSimilar = await HomeFeedCache.loadSimilarArtistRows();
    final cachedSimilarSongs = await HomeFeedCache.loadSimilarSongRows();
    if (!mounted) return;
    if (cachedShelves.isNotEmpty ||
        cachedSimilar.isNotEmpty ||
        cachedSimilarSongs.isNotEmpty) {
      setState(() {
        if (cachedShelves.isNotEmpty) _shelves = cachedShelves;
        if (cachedSimilar.isNotEmpty) _similarRows = cachedSimilar;
        if (cachedSimilarSongs.isNotEmpty) _similarSongRows = cachedSimilarSongs;
      });
    }
    final shelvesCacheFresh = await HomeFeedCache.isHomeShelvesFresh();
    final artistCacheFresh = await HomeFeedCache.isSimilarArtistRowsFresh();
    final songCacheFresh = await HomeFeedCache.isSimilarSongRowsFresh();
    final attempted = await HomeFeedCache.coldAttemptedRecently('shelves');
    final shelvesFresh =
        (cachedShelves.isNotEmpty && shelvesCacheFresh) || attempted;
    final similarFresh =
        (cachedSimilar.isNotEmpty && artistCacheFresh) || attempted;
    final similarSongsFresh =
        (cachedSimilarSongs.isNotEmpty && songCacheFresh) || attempted;
    if (shelvesFresh && similarFresh && similarSongsFresh) return;
    await HomeFeedCache.markColdAttempt('shelves');
    if (!mounted) return;
    _load(
      skipShelves: shelvesFresh,
      skipSimilar: similarFresh,
      skipSimilarSongs: similarSongsFresh,
    );
  }

  @override
  void didUpdateWidget(_HomeShelvesAndSimilarSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      final saver = AudioPrefs.dataSaverActiveNotifier.value;
      final rotShelves = saver &&
          widget.stage.shelves &&
          (_shelves?.isNotEmpty ?? false);
      final rotSimilar = saver &&
          widget.stage.similarArtistRows &&
          (_similarRows?.isNotEmpty ?? false);
      final rotSongs = saver &&
          widget.stage.similarSongRows &&
          (_similarSongRows?.isNotEmpty ?? false);
      if (rotShelves || rotSimilar || rotSongs) {
        unawaited(_rotateLocally(widget.refreshKey,
            shelves: rotShelves, similar: rotSimilar, songs: rotSongs));
      }
      final skipShelves = !widget.stage.shelves || rotShelves;
      final skipSimilar = !widget.stage.similarArtistRows || rotSimilar;
      final skipSongs = !widget.stage.similarSongRows || rotSongs;
      if (!(skipShelves && skipSimilar && skipSongs)) {
        _load(
          refreshKey: widget.refreshKey,
          skipShelves: skipShelves,
          skipSimilar: skipSimilar,
          skipSimilarSongs: skipSongs,
        );
      }
    }
  }

  int _rotGen = 0;

  HomeShelf _shuffledShelf(HomeShelf s, math.Random rnd) {
    if (s.isList) {
      if (s.songs.length < 2) return s;
      return HomeShelf(
        title: s.title,
        items: s.items,
        strapline: s.strapline,
        isList: true,
        songs: List<Song>.of(s.songs)..shuffle(rnd),
      );
    }
    if (s.items.length < 2) return s;
    return HomeShelf(
      title: s.title,
      items: List<HomeShelfItem>.of(s.items)..shuffle(rnd),
      strapline: s.strapline,
      isList: false,
      songs: s.songs,
    );
  }

  Future<void> _rotateLocally(
    int seed, {
    required bool shelves,
    required bool similar,
    required bool songs,
  }) async {
    final gen = ++_rotGen;
    final rnd = math.Random(seed);
    const gap = Duration(milliseconds: 420);
    bool alive() => mounted && gen == _rotGen;

    if (similar) {
      for (var i = 0;; i++) {
        if (!alive()) return;
        final cur = _similarRows;
        if (cur == null || i >= cur.length) break;
        final r = cur[i];
        final albums = List<ArtistAlbum>.of(r.albums)..shuffle(rnd);
        setState(() {
          final l = [...?_similarRows];
          if (i < l.length) {
            l[i] = (
              artistName: r.artistName,
              artistImageUrl: r.artistImageUrl,
              relatedArtist: r.relatedArtist,
              albums: albums,
            );
            _similarRows = l;
          }
        });
        await Future<void>.delayed(gap);
      }
    }
    if (songs) {
      for (var i = 0;; i++) {
        if (!alive()) return;
        final cur = _similarSongRows;
        if (cur == null || i >= cur.length) break;
        final r = cur[i];
        final related = List<Song>.of(r.related)..shuffle(rnd);
        setState(() {
          final l = [...?_similarSongRows];
          if (i < l.length) {
            l[i] = (seedSong: r.seedSong, related: related);
            _similarSongRows = l;
          }
        });
        await Future<void>.delayed(gap);
      }
    }
    if (shelves) {
      for (var i = 0;; i++) {
        if (!alive()) return;
        final cur = _shelves;
        if (cur == null || i >= cur.length) break;
        final shuffled = _shuffledShelf(cur[i], rnd);
        setState(() {
          final l = [...?_shelves];
          if (i < l.length) {
            l[i] = shuffled;
            _shelves = l;
          }
        });
        await Future<void>.delayed(gap);
      }
    }
  }

  Future<void> _load({
    int? refreshKey,
    bool skipShelves = false,
    bool skipSimilar = false,
    bool skipSimilarSongs = false,
  }) async {
    _rotGen++;
    final seed = refreshKey ?? widget.refreshKey;
    final shelvesFuture =
        skipShelves ? null : ApiService.fetchHomeShelvesForDisplay(
      refreshSeed: seed,
    );
    final similarFuture = skipSimilar ? null : _loadSimilarRows();
    final similarSongsFuture =
        skipSimilarSongs ? null : _loadSimilarSongRows();

    final tasks = <Future<void>>[];
    if (shelvesFuture != null) {
      tasks.add(() async {
        List<HomeShelf> shelves;
        bool failed;
        try {
          shelves = await shelvesFuture;
          failed = shelves.isEmpty;
        } catch (_) {
          shelves = const [];
          failed = true;
        }
        if (failed) unawaited(HomeFeedCache.clearColdAttempt('shelves'));
        if (!mounted) return;
        setState(() {
          if (shelves.isNotEmpty || _shelves == null) {
            _shelves = shelves;
            _shelvesFailed = failed;
          }
        });
        unawaited(HomeFeedCache.saveHomeShelves(shelves));
      }());
    }
    if (similarFuture != null) {
      tasks.add(() async {
        final similar = await similarFuture;
        if (!mounted) return;
        setState(() {
          if (similar.isNotEmpty || _similarRows == null) _similarRows = similar;
        });
        unawaited(HomeFeedCache.saveSimilarArtistRows(similar));
      }());
    }
    if (similarSongsFuture != null) {
      tasks.add(() async {
        final songs = await similarSongsFuture;
        if (!mounted) return;
        setState(() {
          if (songs.isNotEmpty || _similarSongRows == null) {
            _similarSongRows = songs;
          }
        });
        unawaited(HomeFeedCache.saveSimilarSongRows(songs));
      }());
    }
    await Future.wait(tasks);
  }

  Future<List<({String artistName, String? artistImageUrl, RelatedArtist? relatedArtist, List<ArtistAlbum> albums})>>
      _loadSimilarRows() async {
    try {
      await RecommendationEngine.load();
      final rawSeeds = RecommendationEngine.rotatingAffinityArtists(
        count: 6,
        seed: widget.refreshKey,
      );
      final seedArtists = _uniquePrimaryArtists(rawSeeds);
      if (seedArtists.isEmpty) return const [];
      Future<({String artistName, String? artistImageUrl, RelatedArtist? relatedArtist, List<ArtistAlbum> albums})?>
          fetchOne(String artist) async {
        try {
          return await ApiService.fetchSimilarArtistAlbums(artist,
              rotate: widget.refreshKey);
        } catch (_) {
          return null;
        }
      }
      final fetched = <({String artistName, String? artistImageUrl, RelatedArtist? relatedArtist, List<ArtistAlbum> albums})?>[];
      fetched.addAll(await Future.wait(seedArtists.take(2).map(fetchOne)));
      if (seedArtists.length > 2) fetched.add(await fetchOne(seedArtists[2]));
      var rows = _dedupeSimilarRows(
          fetched.where((r) => r != null).map((r) => r!).toList());
      for (var i = 3; i < seedArtists.length && rows.length < 3; i++) {
        final extra = await fetchOne(seedArtists[i]);
        if (extra == null) continue;
        rows = _dedupeSimilarRows([...rows, extra]);
      }
      return rows.take(3).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<({Song seedSong, List<Song> related})>> _loadSimilarSongRows() async {
    try {
      final history = context.read<RecentlyPlayedProvider>().history;
      final streamable = <Song>[];
      final seenIds = <String>{};
      for (final s in history) {
        if (s.isLocal || s.id.isEmpty) continue;
        if (!seenIds.add(s.id)) continue;
        streamable.add(s);
      }
      if (streamable.isEmpty) return const [];
      final pool = streamable.take(10).toList()
        ..shuffle(math.Random(widget.refreshKey));
      final seeds = pool.take(2).toList();

      Future<({Song seedSong, List<Song> related})> fetchOne(Song song) async {
        try {
          final related = await ApiService.fetchYouMightAlsoLike(song.id)
              .timeout(const Duration(seconds: 8), onTimeout: () => const <Song>[]);
          return (seedSong: song, related: related);
        } catch (_) {
          return (seedSong: song, related: const <Song>[]);
        }
      }
      final results = await Future.wait(seeds.map(fetchOne));
      return results.where((r) => r.related.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final shelves = _shelves;

    if (shelves == null && !_shelvesFailed) {
      return Padding(
        padding: const EdgeInsets.only(top: 28, left: 12, right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShelfTitleSkeleton(),
            const SizedBox(height: 12),
            FadedHorizontalList(
              height: 172,
              child: const _YtPlaylistsForYouSkeleton(),
            ),
          ],
        ),
      );
    }

    if (shelves == null || shelves.isEmpty) {
      if ((_similarRows ?? const []).isEmpty &&
          (_similarSongRows ?? const []).isEmpty) {
        return const SizedBox.shrink();
      }
    }

    final similar = _dedupeSimilarRows(_similarRows ?? const []);
    final similarSongs = _similarSongRows ?? const [];
    final realShelves = shelves ?? const [];

    final children = <Widget>[
      for (final row in similar)
        _SimilarArtistsRow(
          key: ValueKey('similar_artist_${row.artistName}'),
          seedArtistName: row.artistName,
          seedArtistImageUrl: row.artistImageUrl,
          relatedArtist: row.relatedArtist,
          albums: row.albums,
        ),
      for (final row in similarSongs)
        _SimilarSongsRow(
          key: ValueKey('similar_song_${row.seedSong.id}'),
          seedSong: row.seedSong,
          related: row.related,
        ),
      for (final shelf in realShelves)
        _RealHomeShelfRow(
          key: ValueKey('real_shelf_${shelf.title}'),
          shelf: shelf,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ShelfTitleSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 20,
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _RealHomeShelfRow extends StatelessWidget {
  final HomeShelf shelf;
  const _RealHomeShelfRow({super.key, required this.shelf});

  static const String _kFeaturedForYouTitle = 'Featured playlists for you';

  void _openArrow(BuildContext context) {
    AurumHaptics.selection();
    if (shelf.title == _kFeaturedForYouTitle) {
      AurumDepthRoute.to(context, const MoodsGenresScreen());
    } else {
      AurumDepthRoute.to(context, _ShelfSeeAllScreen(shelf: shelf));
    }
  }

  @override
  Widget build(BuildContext context) {
    final showArrow = !shelf.isList &&
        (shelf.title == _kFeaturedForYouTitle || shelf.items.length > 4);
    if (shelf.isList) {
      return Padding(
        padding: const EdgeInsets.only(top: 32, left: 12, right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 4,
                        height: 18,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: AurumTheme.accentGradientOf(context),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          shelf.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AurumTheme.textPrimaryOf(context),
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (shelf.songs.isNotEmpty)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        AurumHaptics.selection();
                        context.read<PlayerProvider>().playSong(
                              shelf.songs.first,
                              queue: shelf.songs,
                              index: 0,
                            );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AurumTheme.dividerOf(context),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded,
                                size: 18,
                                color: AurumTheme.textPrimaryOf(context)),
                            const SizedBox(width: 4),
                            Text(
                              'Play all',
                              style: TextStyle(
                                color: AurumTheme.textPrimaryOf(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < shelf.songs.length; i++)
              _QuickPickListRow(
                key: ValueKey('${shelf.title}_shelf_${shelf.songs[i].id}_$i'),
                song: shelf.songs[i],
                queue: shelf.songs,
                index: i,
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 32, left: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (shelf.strapline != null) ...[
                      Text(
                        shelf.strapline!.toUpperCase(),
                        style: TextStyle(
                          color: AurumTheme.accentLightOf(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 4,
                          height: 18,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: AurumTheme.accentGradientOf(context),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            shelf.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AurumTheme.textPrimaryOf(context),
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showArrow)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _openArrow(context),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AurumTheme.bgCardOf(context).withOpacity(0.6),
                        border: Border.all(
                          color: AurumTheme.dividerOf(context),
                          width: 0.6,
                        ),
                      ),
                      child: Icon(
                        Icons.arrow_forward,
                        color: AurumTheme.textPrimaryOf(context),
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FadedHorizontalList(
            height: 172,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              cacheExtent: 600,
              padding: const EdgeInsets.only(right: 12),
              itemCount: shelf.items.length,
              itemBuilder: (_, i) {
                final item = shelf.items[i];
                if (item.isAlbum) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _HomeAlbumCardWidget(
                      card: HomeAlbumCard(
                        albumId: item.browseId,
                        title: item.title,
                        artist: item.subtitle,
                        artworkUrl: item.artworkUrl,
                      ),
                    ),
                  );
                }
                return _RealShelfPlaylistCard(item: item, shelfTitle: shelf.title);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RealShelfPlaylistCard extends StatefulWidget {
  final HomeShelfItem item;
  final bool fullWidth;
  final String shelfTitle;
  const _RealShelfPlaylistCard({
    required this.item,
    required this.shelfTitle,
    this.fullWidth = false,
  });

  @override
  State<_RealShelfPlaylistCard> createState() =>
      _RealShelfPlaylistCardState();
}

class _RealShelfPlaylistCardState extends State<_RealShelfPlaylistCard> {
  bool _pressed = false;
  bool _resolving = false;

  Future<void> _open() async {
    if (_resolving) return;
    AurumHaptics.selection();
    if (widget.item.isArtist) {
      AurumDepthRoute.to(
        context,
        ArtistScreen(
          artistId: 'yt_${widget.item.browseId}',
          artistName: widget.item.title,
        ),
      );
      return;
    }
    setState(() => _resolving = true);
    if (mounted) setState(() => _resolving = false);
    if (!mounted) return;
    AurumDepthRoute.to(
      context,
      MixScreen(
        mixId: widget.item.browseId,
        mixName: widget.item.title,
        artworkUrl: widget.item.artworkUrl,
        emoji: '',
        songs: const [],
        autoLoadMore: () async {
          final firstPage = await ApiService.resolveHomeShelfPlaylist(widget.item);
          if (firstPage.isEmpty) return firstPage;
          final more = await ApiService.fetchHomeShelfPlaylistMore(
            widget.item,
            existingVideoIds: firstPage.map((s) => s.id).toList(),
          );
          return [...firstPage, ...more];
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.item;
    return RepaintBoundary(
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _open,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1.0,
          duration: AurumMotion.durationOrZero(AurumMotion.short1),
          curve: Curves.easeOut,
          child: Container(
            width: widget.fullWidth ? null : 172,
            margin: widget.fullWidth
                ? EdgeInsets.zero
                : const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (c.artworkUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: c.artworkUrl,
                      cacheManager: AurumImageCache(),
                      fit: BoxFit.cover,
                      memCacheWidth: 380,
                      placeholder: (_, __) =>
                          Container(color: AurumTheme.bgCardOf(context)),
                      errorWidget: (_, __, ___) =>
                          Container(color: AurumTheme.bgCardOf(context)),
                    )
                  else
                    Container(color: AurumTheme.bgCardOf(context)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.85),
                        ],
                        stops: const [0.35, 1.0],
                      ),
                    ),
                  ),
                  if (widget.shelfTitle == 'Trending community playlists' ||
                      widget.shelfTitle == 'Featured playlists for you')
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.45),
                        ),
                        child: const Icon(
                          Icons.play_circle_outline,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            height: 1.2,
                          ),
                        ),
                        if (c.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            c.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_resolving)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black45,
                        child: Center(
                          child: AurumMorphLoader(size: 22),
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
  }
}

class _HomeAlbumCardWidget extends StatelessWidget {
  final HomeAlbumCard card;
  const _HomeAlbumCardWidget({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () {
          AurumHaptics.light();
          AurumDepthRoute.to(
            context,
            AlbumScreen(
              albumId: card.albumId,
              albumName: card.title,
              artworkUrl: card.artworkUrl,
            ),
          );
        },
        child: SizedBox(
          width: 172,
          height: 172,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AurumArtwork(url: card.artworkUrl, size: 130, borderRadius: 16),
              ),
              const SizedBox(height: 6),
              Text(
                card.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (card.artist.isNotEmpty)
                Text(
                  card.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AurumTheme.textSecondaryOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfSeeAllScreen extends StatelessWidget {
  final HomeShelf shelf;
  const _ShelfSeeAllScreen({required this.shelf});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          shelf.title,
          style: TextStyle(
            color: AurumTheme.textPrimaryOf(context),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 20,
          crossAxisSpacing: 14,
          childAspectRatio: 1.0,
        ),
        itemCount: shelf.items.length,
        itemBuilder: (_, i) {
          final item = shelf.items[i];
          if (item.isAlbum) {
            return Center(
              child: _HomeAlbumCardWidget(
                card: HomeAlbumCard(
                  albumId: item.browseId,
                  title: item.title,
                  artist: item.subtitle,
                  artworkUrl: item.artworkUrl,
                ),
              ),
            );
          }
          return _RealShelfPlaylistCard(
            item: item,
            shelfTitle: shelf.title,
            fullWidth: true,
          );
        },
      ),
    );
  }
}

const String _kRealMoodAllId = '__all__';

class _RealMoodChipsSection extends StatefulWidget {
  final int refreshKey;
  const _RealMoodChipsSection({this.refreshKey = 0});

  @override
  State<_RealMoodChipsSection> createState() => _RealMoodChipsSectionState();
}

class _RealMoodChipsSectionState extends State<_RealMoodChipsSection> {
  List<MoodGenreCategory>? _categories;
  bool _categoriesFailed = false;

  String _selectedMood = _kRealMoodAllId;
  List<HomeShelf>? _categoryShelves;
  bool _categoryFailed = false;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void didUpdateWidget(_RealMoodChipsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshKey != widget.refreshKey) {
      _selectedMood = _kRealMoodAllId;
      _categoryShelves = null;
      _categoryFailed = false;
      _loadCategories(force: !AudioPrefs.dataSaverActiveNotifier.value);
    }
  }

  Future<void> _loadCategories({bool force = false}) async {
    try {
      List<MoodGenreSection>? sections;
      if (!force && AudioPrefs.dataSaverActiveNotifier.value) {
        final cached = await MoodGenreCacheStore.load();
        if (cached != null &&
            cached.isNotEmpty &&
            await MoodGenreCacheStore.isFresh()) {
          sections = cached;
        }
      }
      if (sections == null) {
        sections = await ApiService.fetchMoodsAndGenres();
        if (sections.isNotEmpty && AudioPrefs.dataSaverActiveNotifier.value) {
          unawaited(MoodGenreCacheStore.save(sections));
        }
      }
      if (!mounted) return;
      final flat = <MoodGenreCategory>[
        for (final section in sections) ...section.items,
      ];
      setState(() {
        _categories = flat;
        _categoriesFailed = flat.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _categoriesFailed = true);
    }
  }

  Future<void> _onMoodTap(String id) async {
    AurumHaptics.selection();
    if (id == _selectedMood) return;
    setState(() {
      _selectedMood = id;
      _categoryShelves = null;
      _categoryFailed = false;
    });
    if (id == _kRealMoodAllId) return;

    final categories = _categories;
    if (categories == null) return;
    final match = categories.where((c) => c.params == id).firstOrNull;
    if (match == null) return;

    final token = ++_loadToken;
    try {
      final shelves =
          await ApiService.fetchMoodGenreCategory(match.browseId, match.params);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _categoryShelves = shelves;
        _categoryFailed = shelves.isEmpty;
      });
    } catch (_) {
      if (mounted && token == _loadToken) {
        setState(() => _categoryFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;

    if (categories == null && _categoriesFailed) {
      return const SizedBox.shrink();
    }
    if (categories == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 28, left: 12, right: 0),
        child: SizedBox(
          height: 34,
          child: Shimmer.fromColors(
            baseColor: AurumTheme.bgCardOf(context),
            highlightColor: AurumTheme.bgElevatedOf(context),
            child: Row(
              children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Container(
                      width: 74,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AurumTheme.bgCardOf(context),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12),
            child: SizedBox(
              height: 34,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(right: 12),
                cacheExtent: 300,
                itemCount: categories.length + 1,
                itemBuilder: (_, i) {
                  final isAll = i == 0;
                  final id = isAll ? _kRealMoodAllId : categories[i - 1].params;
                  final label =
                      isAll ? AppLocalizations.of(context)!.homeMoodAll : categories[i - 1].title;
                  final selected = id == _selectedMood;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => _onMoodTap(id),
                      child: AnimatedContainer(
                        duration: AurumMotion.durationOrZero(AurumMotion.medium1),
                        curve: Curves.easeOut,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AurumTheme.accentOf(context)
                              : AurumTheme.bgCardOf(context),
                          borderRadius: BorderRadius.circular(20),
                          border: selected
                              ? null
                              : Border.all(
                                  color: AurumTheme.textPrimaryOf(context)
                                      .withOpacity(0.10),
                                  width: 1,
                                ),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Theme.of(context).colorScheme.onPrimary
                                : AurumTheme.textPrimaryOf(context)
                                    .withOpacity(0.85),
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_selectedMood != _kRealMoodAllId) ...[
            const SizedBox(height: 12),
            if (_categoryShelves == null && !_categoryFailed)
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 12),
                child: FadedHorizontalList(
                  height: 172,
                  child: const _YtPlaylistsForYouSkeleton(),
                ),
              )
            else if (_categoryFailed || (_categoryShelves?.isEmpty ?? true))
              const SizedBox.shrink()
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final shelf in _categoryShelves!)
                    _RealHomeShelfRow(
                      key: ValueKey('${shelf.title}_$_selectedMood'),
                      shelf: shelf,
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _YtPlaylistsForYouSkeleton extends StatelessWidget {
  const _YtPlaylistsForYouSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(right: 12),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        width: 130,
        height: 130,
        margin: const EdgeInsets.only(right: 12),
        child: Shimmer.fromColors(
          baseColor: AurumTheme.bgCardOf(context),
          highlightColor: AurumTheme.textPrimaryOf(context).withOpacity(0.06),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AurumTheme.bgCardOf(context),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}

class _YtPlaylistsForYouRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _YtPlaylistsForYouRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: Icon(Icons.refresh_rounded,
              size: 18, color: AurumTheme.textSecondaryOf(context)),
          label: Text(
            'Retry',
            style: TextStyle(
              color: AurumTheme.textSecondaryOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: AurumTheme.bgCardOf(context),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePremiumBanner extends StatefulWidget {
  final bool isActive;
  const _HomePremiumBanner({this.isActive = true});

  @override
  State<_HomePremiumBanner> createState() => _HomePremiumBannerState();
}

class _HomePremiumBannerState extends State<_HomePremiumBanner>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _shimmer =
        CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOutSine);
    if (AudioPrefs.enableAnimationsNotifier.value && widget.isActive) {
      _shimmerCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(_HomePremiumBanner old) {
    super.didUpdateWidget(old);
    if (old.isActive == widget.isActive) return;
    if (!widget.isActive) {
      _shimmerCtrl.stop();
    } else if (AudioPrefs.enableAnimationsNotifier.value &&
        !_shimmerCtrl.isAnimating) {
      _shimmerCtrl.repeat();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (AudioPrefs.enableAnimationsNotifier.value &&
          widget.isActive &&
          !_shimmerCtrl.isAnimating) {
        _shimmerCtrl.repeat();
      }
    } else {
      _shimmerCtrl.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const paymentDisabled = true;
    if (paymentDisabled) return const SizedBox.shrink();
    final isPremium = context.watch<PremiumProvider>().isPremium;
    if (isPremium) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
      child: AurumPressable(
        scaleAmount: 0.97,
        onTap: null,
        child: AnimatedBuilder(
          animation: _shimmer,
          builder: (_, __) {
            final t = _shimmer.value;
            final sweep = (t * 2.6) - 0.8;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: const [
                    Color(0xFF2A1E00),
                    Color(0xFF1A1200),
                  ],
                ),
                border: Border.all(
                  color: AurumTheme.accent.withOpacity(0.3),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AurumTheme.accent.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: const [
                      AurumTheme.accentDark,
                      AurumTheme.accentLight,
                      AurumTheme.accent,
                    ],
                    stops: [
                      (sweep - 0.4).clamp(0.0, 1.0),
                      sweep.clamp(0.0, 1.0),
                      (sweep + 0.4).clamp(0.0, 1.0),
                    ],
                  ).createShader(bounds),
                  child: const Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        shaderCallback: (b) => LinearGradient(
                          colors: const [
                            AurumTheme.accentDark,
                            AurumTheme.accentLight,
                          ],
                          stops: [
                            (sweep - 0.5).clamp(0.0, 1.0),
                            (sweep + 0.5).clamp(0.0, 1.0),
                          ],
                        ).createShader(b),
                        child: const Text(
                          'Unlock Astra Plus ✦',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '320kbps • Offline • No ads • More',
                        style: TextStyle(
                          color: AurumTheme.accent.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: AurumTheme.accentGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Try',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }
}

// ignore: avoid_void_async
void unawaited(Future<void> f) {}
