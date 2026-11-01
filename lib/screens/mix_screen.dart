// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'dart:async';
import '../utils/aurum_transitions.dart';
import 'library_screen.dart' show DownloadsScreen;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/aurum_image_cache.dart';
import '../providers/player_provider.dart';
import '../providers/followed_albums_provider.dart';
import '../providers/download_provider.dart';
import '../theme/aurum_theme.dart';
import '../widgets/aurum_artwork.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/aurum_glass.dart';
import '../widgets/aurum_snack.dart';
import '../widgets/song_tile.dart';
import '../widgets/aurum_song_options_sheet.dart' show showAurumPlaylistOptions;
import '../widgets/mini_player_slot.dart';
import 'search_screen.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_immersive_header.dart';
import '../utils/artwork_palette_cache.dart';

class MixScreen extends StatefulWidget {
  final String mixId;
  final String mixName;
  final String artworkUrl;
  final String emoji;
  final List<Song> songs;

  final bool enableRefresh;
  final String? refreshSeed;

  final String? description;

  final Future<List<Song>> Function()? autoLoadMore;

  final Stream<List<Song>> Function()? autoLoadStream;

  const MixScreen({
    super.key,
    required this.mixId,
    required this.mixName,
    required this.artworkUrl,
    required this.emoji,
    required this.songs,
    this.enableRefresh = false,
    this.refreshSeed,
    this.description,
    this.autoLoadMore,
    this.autoLoadStream,
  });

  @override
  State<MixScreen> createState() => _MixScreenState();
}

class _MixScreenState extends State<MixScreen>
    with SingleTickerProviderStateMixin {
  late Color _glowTarget = _peekInitialGlow();

  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late Animation<Color?> _glowAnimation = AlwaysStoppedAnimation(_glowTarget);

  Color get _glow => _glowAnimation.value ?? _glowTarget;

  void _setGlowTarget(Color next) {
    final tween = ColorTween(begin: _glow, end: next);
    _glowTarget = next;
    _glowAnimation = tween.animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeOutCubic),
    );
    _glowController
      ..reset()
      ..forward();
  }

  Color _peekInitialGlow() {
    final url = widget.artworkUrl;
    if (url.isEmpty) return const Color(0xFF1A1630);
    final cached = ArtworkPaletteCache.peek(url);
    return cached?.darkMuted ?? const Color(0xFF1A1630);
  }

  bool _contrastSafeApplied = false;

  late List<Song> _songs = widget.songs;

  late bool _awaitingFirstLoad = widget.songs.isEmpty &&
      (widget.autoLoadMore != null || widget.autoLoadStream != null);

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('Mix');
    _extractGlow();
    _runAutoLoad();
  }

  bool _loadFailed = false;

  StreamSubscription<List<Song>>? _streamSub;

  void _runAutoLoad() {
    final streamFactory = widget.autoLoadStream;
    if (streamFactory != null) {
      _streamSub?.cancel();
      _streamSub = streamFactory().listen(
        (batch) {
          if (!mounted || batch.isEmpty) return;
          setState(() {
            final have = _songs.map((s) => s.id).toSet();
            _songs = [..._songs, ...batch.where((s) => have.add(s.id))];
            _awaitingFirstLoad = false;
            _loadFailed = false;
          });
        },
        onError: (_) {
          if (!mounted) return;
          setState(() {
            _awaitingFirstLoad = false;
            _loadFailed = _songs.isEmpty;
          });
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _awaitingFirstLoad = false;
            _loadFailed = _songs.isEmpty;
          });
        },
        cancelOnError: true,
      );
      return;
    }
    final autoLoadMore = widget.autoLoadMore;
    if (autoLoadMore == null) return;
    autoLoadMore().then((more) {
      if (!mounted) return;
      setState(() {
        if (more.isNotEmpty) {
          final have = _songs.map((s) => s.id).toSet();
          _songs = [..._songs, ...more.where((s) => !have.contains(s.id))];
        }
        _awaitingFirstLoad = false;
        _loadFailed = _songs.isEmpty;
      });
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _awaitingFirstLoad = false;
          _loadFailed = _songs.isEmpty;
        });
      }
    });
  }

  void _retryAutoLoad() {
    setState(() {
      _awaitingFirstLoad = true;
      _loadFailed = false;
    });
    _runAutoLoad();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _glowController.dispose();
    super.dispose();
  }

  bool _precachedHeaderArtwork = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precachedHeaderArtwork) {
      _precachedHeaderArtwork = true;
      _precacheHeaderArtwork();
    }
    if (!_contrastSafeApplied) {
      _contrastSafeApplied = true;
      final safe = ensureContrastSafe(
        _glowTarget,
        isLight: Theme.of(context).brightness == Brightness.light,
      );
      _glowTarget = safe;
      _glowAnimation = AlwaysStoppedAnimation(safe);
    }
  }

  void _precacheHeaderArtwork() {
    final url = widget.artworkUrl;
    if (url.isEmpty ||
        url.startsWith('content://') ||
        url.startsWith('/') ||
        url.startsWith('file://')) {
      return;
    }
    precacheImage(
      ResizeImage.resizeIfNeeded(
        AurumArtwork.screenDecodeWidth(context),
        null,
        CachedNetworkImageProvider(
          AurumArtwork.upgradeForFullPlayer(url),
          cacheManager: AurumImageCache(),
        ),
      ),
      context,
    ).catchError((_) {
    });
  }

  Future<void> _extractGlow() async {
    final c = await extractImmersiveColor(widget.artworkUrl);
    if (c != null && mounted) {
      final safe = ensureContrastSafe(
        c,
        isLight: Theme.of(context).brightness == Brightness.light,
      );
      if (safe.value != _glowTarget.value) {
        _setGlowTarget(safe);
      }
    }
  }

  Future<void> _onRefresh() async {
    final seed = (widget.refreshSeed?.trim().isNotEmpty ?? false)
        ? widget.refreshSeed!.trim()
        : widget.mixName;
    final existingIds = _songs.map((s) => s.id).toList();
    final more = await ApiService.fetchMixRefreshSongs(
      seed: seed,
      existingVideoIds: existingIds,
    );
    if (!mounted || more.isEmpty) return;
    setState(() {
      _songs = [..._songs, ...more];
    });
  }

  String _summaryLine(List<Song> songs) {
    final count = songs.length;
    return '$count ${count == 1 ? 'track' : 'tracks'}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final player = context.read<PlayerProvider>();
    final songs = _songs;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color bgNow(BuildContext c) => immersiveScaffoldBg(c, _glow);
    final screenW = MediaQuery.sizeOf(context).width;
    final topInset = MediaQuery.paddingOf(context).top;
    final headerH = screenW * 1.04;
    final titleColor = isDark ? Colors.white : AurumTheme.textPrimaryOf(context);
    final subColor = isDark
        ? Colors.white.withOpacity(0.72)
        : AurumTheme.textSecondaryOf(context);
    final description = (widget.description ?? '').trim();

    Widget body = AnimatedBuilder(
      animation: _glowController,
      builder: (ctx, child) => ColoredBox(color: bgNow(ctx), child: child),
      child: CustomScrollView(
        cacheExtent: 500,
        slivers: [
          SliverToBoxAdapter(
            child: RepaintBoundary(child: SizedBox(
              height: headerH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Hero(
                      tag: 'mix_art_${widget.mixId}',
                      child: widget.artworkUrl.isNotEmpty
                          ? AurumArtwork(
                              url: AurumArtwork.upgradeForFullPlayer(
                                  widget.artworkUrl),
                              size: double.infinity,
                              borderRadius: 0,
                              decodeToScreenWidth: true,
                            )
                          : AnimatedBuilder(
                              animation: _glowController,
                              builder: (_, child) => ColoredBox(color: _glow, child: child),
                              child: Center(
                                child: Icon(
                                  Icons.music_note_rounded,
                                  size: 64,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ),
                    ),
                  ),

                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: topInset + 90,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.40),
                            Colors.black.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _glowController,
                      builder: (ctx, _) {
                        final bg = bgNow(ctx);
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                bg.withOpacity(0.0),
                                bg.withOpacity(0.0),
                                bg.withOpacity(0.55),
                                bg.withOpacity(0.92),
                                bg,
                              ],
                              stops: const [0.0, 0.40, 0.62, 0.82, 1.0],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 14,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.mixName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Astra Music',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: subColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Playlist • ${DateTime.now().year}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: subColor.withOpacity(0.8),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GlassPill(
                            width: 44,
                            child: _GlassIconButton(
                              icon: Icons.arrow_back_rounded,
                              onTap: () {
                                AurumHaptics.selection();
                                Navigator.pop(context);
                              },
                            ),
                          ),
                          Consumer<FollowedAlbumsProvider>(
                            builder: (context, followedAlbums, _) {
                              final saved =
                                  followedAlbums.isFollowing(widget.mixId);
                              return _GlassPill(
                                width: 132,
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _GlassIconButton(
                                      icon: saved
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      iconColor: saved
                                          ? AurumTheme.accentOf(context)
                                          : Colors.white,
                                      onTap: () {
                                        AurumHaptics.selection();
                                        followedAlbums.toggleFollow(
                                          albumId: widget.mixId,
                                          name: widget.mixName,
                                          artworkUrl: widget.artworkUrl,
                                          isMix: true,
                                          songs: songs,
                                        );
                                        _snack(
                                            context,
                                            saved
                                                ? 'Removed from Library'
                                                : 'Added to Library');
                                      },
                                    ),
                                    _GlassIconButton(
                                      icon: Icons.search_rounded,
                                      onTap: () {
                                        AurumHaptics.selection();
                                        AurumDepthRoute.to(
                                            context, const SearchScreen());
                                      },
                                    ),
                                    _GlassIconButton(
                                      icon: Icons.more_vert_rounded,
                                      onTap: () => showAurumPlaylistOptions(
                                          context,
                                          songs: _songs),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundButton(
                    icon: Icons.shuffle_rounded,
                    onTap: songs.isEmpty
                        ? null
                        : () {
                            AurumHaptics.medium();
                            final queue = List<Song>.from(songs)..shuffle();
                            player.playSong(queue.first,
                                queue: queue, index: 0, curatedQueue: true);
                          },
                  ),
                  const SizedBox(width: 12),
                  AurumPressable(
                    scaleAmount: 0.95,
                    onTap: songs.isEmpty
                        ? null
                        : () {
                            AurumHaptics.medium();
                            player.playSong(songs.first,
                                queue: songs, index: 0, curatedQueue: true);
                          },
                    child: Container(
                      height: 46,
                      constraints: const BoxConstraints(minWidth: 112),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : const Color(0xFF111111))
                            .withOpacity(songs.isEmpty ? 0.4 : 1.0),
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              color:
                                  isDark ? Colors.black : Colors.white,
                              size: 24),
                          const SizedBox(width: 6),
                          Text(
                            'Play',
                            style: TextStyle(
                              color: isDark ? Colors.black : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Consumer<DownloadProvider>(
                    builder: (context, downloads, _) {
                      final allDone = songs.isNotEmpty &&
                          songs.every((s) => downloads.isDownloaded(s.id));
                      return _RoundButton(
                        icon: allDone
                            ? Icons.download_done_rounded
                            : Icons.download_for_offline_outlined,
                        iconSize: 26,
                        onTap: songs.isEmpty
                            ? null
                            : () => _downloadMix(context, downloads),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          if (description.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                child: Text(
                  description,
                  style: TextStyle(
                    color: AurumTheme.textSecondaryOf(context),
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              ),
            ),

          if (songs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                child: Text(
                  _summaryLine(songs),
                  style: TextStyle(
                    color: AurumTheme.textSecondaryOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          if (songs.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 56),
                child: Center(
                  child: _awaitingFirstLoad
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l10n.albumNoSongsFound,
                                style: TextStyle(
                                    color: AurumTheme.textMutedOf(context))),
                            if (_loadFailed &&
                                (widget.autoLoadMore != null ||
                                    widget.autoLoadStream != null)) ...[
                              const SizedBox(height: 14),
                              TextButton.icon(
                                onPressed: _retryAutoLoad,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(l10n.commonRetry),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => SongTile(
                  song: songs[i],
                  queue: songs,
                  index: i,
                  curatedQueue: true,
                  ytStyle: true,
                ),
                childCount: songs.length,
                addRepaintBoundaries: false,
                addAutomaticKeepAlives: false,
              ),
            ),

          if (widget.enableRefresh && songs.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    l10n.mixPullForMore,
                    style: TextStyle(
                      color: AurumTheme.textMutedOf(context).withOpacity(0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );

    if (widget.enableRefresh) {
      body = RefreshIndicator(
        onRefresh: _onRefresh,
        edgeOffset: topInset + 8,
        color: AurumTheme.accentOf(context),
        backgroundColor: AurumTheme.bgElevatedOf(context),
        child: body,
      );
    }

    final scaffold = AnimatedBuilder(
      animation: _glowController,
      child: body,
      builder: (ctx, child) => Scaffold(
        backgroundColor: bgNow(ctx),
        bottomNavigationBar: const MiniPlayerSlot(),
        body: child,
      ),
    );

    if (!isDark) return scaffold;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: scaffold,
    );
  }

  void _snack(BuildContext context, String msg) {
    if (!mounted) return;
    AurumSnack.show(context, msg);
  }

  Future<void> _downloadMix(
      BuildContext context, DownloadProvider downloads) async {
    final toQueue = _songs
        .where((s) =>
            !downloads.isDownloaded(s.id) && !downloads.isDownloading(s.id))
        .toList();
    if (toQueue.isEmpty) {
      _snack(context, 'Already downloaded');
      return;
    }
    for (final song in toQueue) {
      unawaited(downloads.download(song));
    }
    if (!context.mounted) return;
    AurumDepthRoute.to(context, const DownloadsScreen());
  }
}

class _GlassPill extends StatelessWidget {
  final Widget child;
  final double width;
  const _GlassPill({super.key, required this.child, required this.width});

  static const double height = 44;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: AurumGlass(
        sigma: 6,
        borderRadius: BorderRadius.circular(height / 2),
        isDark: true,
        child: SizedBox(width: width, height: height, child: child),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color iconColor;

  const _GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 21, color: iconColor),
        splashRadius: 20,
        onPressed: onTap,
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double iconSize;

  const _RoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = onTap == null;
    final fg = AurumTheme.textPrimaryOf(context);
    return AurumPressable(
      scaleAmount: 0.9,
      onTap: disabled
          ? null
          : () {
              AurumHaptics.selection();
              onTap!();
            },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (isDark ? Colors.white : Colors.black)
              .withOpacity(isDark ? 0.12 : 0.07),
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: disabled ? fg.withOpacity(0.35) : fg,
        ),
      ),
    );
  }
}
