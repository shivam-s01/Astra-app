// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;

import '../providers/player_provider.dart';
import '../providers/favorites_provider.dart';
import '../models/song.dart';
import '../models/lyrics.dart' show LyricsResult, LyricLine;
import '../widgets/aurum_artwork.dart';
import '../utils/artwork_palette_cache.dart';
import '../utils/route_drag_dismiss.dart';
import '../widgets/aurum_seek_bar.dart';
import '../widgets/aurum_like_button.dart';
import '../widgets/aurum_play_pause_icon.dart';
import '../widgets/aurum_song_options_sheet.dart' show showAurumSongOptions;
import '../utils/aurum_haptics.dart';
import '../widgets/jam_entry.dart';
import '../services/jam_service.dart';
import '../services/api_service.dart';
import '../services/lyrics_translation_handle.dart';
import '../utils/aurum_transitions.dart' show AurumDepthRoute;
import 'artist_screen.dart';
import 'queue_screen.dart';
import 'library_screen.dart' show showAddToPlaylistSheet;
import 'full_player_screen.dart' show AurumLyricsPage, showSongInfoDialog;

class SpotifyFullPlayerScreen extends StatefulWidget {
  const SpotifyFullPlayerScreen({super.key});

  @override
  State<SpotifyFullPlayerScreen> createState() =>
      _SpotifyFullPlayerScreenState();
}

class _SpotifyFullPlayerScreenState extends State<SpotifyFullPlayerScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  final ValueNotifier<double> _collapseN = ValueNotifier<double>(0.0);

  static const double _collapseDistance = 120.0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    final t = (_scrollCtrl.offset / _collapseDistance).clamp(0.0, 1.0);
    if (t != _collapseN.value) _collapseN.value = t;
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _collapseN.dispose();
    super.dispose();
  }

  void _openFullLyrics(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => const _LyricsPageWrapper(),
        transitionsBuilder: (_, animation, __, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _openQueue(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: null,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => const QueueScreen(),
        transitionsBuilder: (ctx, animation, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(routeDragCurve(ctx, animation)),
          child: child,
        ),
      ),
    );
  }

  static const double _dismissDistance = 120.0;
  static const double _dismissVelocity = 900.0;

  final PullDownDismissController _pull = PullDownDismissController();

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, (Song?, bool, bool, LoopMode, bool)>(
      selector: (_, p) =>
          (p.currentSong, p.isLoading, p.isPlaying, p.loopMode, p.shuffle),
      builder: (context, _, __) {
        final player = context.read<PlayerProvider>();
        final song = player.currentSong;
        if (song == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF121212),
            body: SizedBox.shrink(),
          );
        }
        final favorites = context.watch<FavoritesProvider>();

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: PullDownDismiss(
            controller: _pull,
            scrollController: _scrollCtrl,
            dismissDistance: _dismissDistance,
            dismissVelocity: _dismissVelocity,
            child: RepaintBoundary(
              child: ColoredBox(
                color: const Color(0xFF121212),
                child: Stack(
                    children: [
                      _BackgroundGlow(
                        artworkUrl:
                            AurumArtwork.upgradeForFullPlayer(song.artworkUrl),
                      ),
                      SafeArea(
                        bottom: false,
                        child: Column(
                          children: [
                            ValueListenableBuilder<double>(
                              valueListenable: _collapseN,
                              builder: (context, collapseT, _) =>
                                  _CollapsingHeader(
                                collapseT: collapseT,
                                song: song,
                                favorites: favorites,
                                onClose: () =>
                                    Navigator.of(context).maybePop(),
                                onMore: () => showAurumSongOptions(
                                  context,
                                  song,
                                  showPlayerTools: true,
                                ),
                              ),
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  const double peek = 64.0;
                                  final double page1H =
                                      (constraints.maxHeight - peek)
                                          .clamp(0.0, double.infinity)
                                          .toDouble();
                                  return SingleChildScrollView(
                                    controller: _scrollCtrl,
                                    physics: _pull.physics,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          height: page1H,
                                          child: _PlayerPage(
                                            player: player,
                                            song: song,
                                            onOpenQueue: () =>
                                                _openQueue(context),
                                          ),
                                        ),
                                        _LyricsPreviewCard(
                                          player: player,
                                          onOpenFullScreen: () =>
                                              _openFullLyrics(context),
                                        ),
                                        const SizedBox(height: 20),
                                        _ArtistsSection(song: song),
                                        _DescriptionCard(song: song),
                                        const SizedBox(height: 40),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
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

class _LyricsPageWrapper extends StatelessWidget {
  const _LyricsPageWrapper();

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, Song?>(
      selector: (_, p) => p.currentSong,
      builder: (context, song, _) {
        final favorites = context.watch<FavoritesProvider>();
        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: Stack(
            children: [
              if (song != null)
                _BackgroundGlow(
                  artworkUrl: AurumArtwork.upgradeForFullPlayer(
                      song.artworkUrl),
                ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 28),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          if (song != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: AurumArtwork(
                                url: song.artworkUrl,
                                size: 40,
                                borderRadius: 6,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: song == null
                                ? const Text(
                                    'Lyrics',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          if (song != null) ...[
                            AurumLikeButton(
                              isLiked: favorites.isFavorite(song.id),
                              size: 22,
                              likedColor: const Color(0xFF1ED760),
                              unlikedColor: Colors.white,
                              onTap: () {
                                AurumHaptics.light();
                                favorites.toggleFavorite(song);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.more_vert_rounded,
                                  color: Colors.white, size: 22),
                              onPressed: () => showAurumSongOptions(
                                context,
                                song,
                                showPlayerTools: true,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Expanded(child: AurumLyricsPage(onDarkBackdrop: true)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BackgroundGlow extends StatefulWidget {
  final String artworkUrl;
  const _BackgroundGlow({required this.artworkUrl});

  @override
  State<_BackgroundGlow> createState() => _BackgroundGlowState();
}

class _BackgroundGlowState extends State<_BackgroundGlow> {
  static const Color _base = Color(0xFF121212);
  static const Color _neutral = Color(0xFF2A2A2A);

  Color _tint = _neutral;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _BackgroundGlow old) {
    super.didUpdateWidget(old);
    if (old.artworkUrl != widget.artworkUrl) _resolve();
  }

  Color _pick(ArtworkPalette p) {
    final raw =
        p.gradientColors.isNotEmpty ? p.gradientColors.first : p.dominant;
    final hsv = HSVColor.fromColor(raw);

    if (hsv.saturation < 0.12) {
      final v = (0.16 + hsv.value * 0.10).clamp(0.16, 0.26).toDouble();
      return HSVColor.fromAHSV(1.0, hsv.hue, 0.0, v).toColor();
    }

    final sat = (hsv.saturation * 0.88).clamp(0.30, 0.82).toDouble();
    final val = (hsv.value * 0.62).clamp(0.20, 0.50).toDouble();
    return HSVColor.fromAHSV(1.0, hsv.hue, sat, val).toColor();
  }

  Future<void> _resolve() async {
    final url = widget.artworkUrl;
    if (url.isEmpty) return;

    final cached = ArtworkPaletteCache.peek(url);
    if (cached != null) {
      if (mounted) setState(() => _tint = _pick(cached));
      return;
    }
    ArtworkPaletteCache.getFast(url).then((fast) {
      if (!mounted || widget.artworkUrl != url || fast == null) return;
      setState(() => _tint = _pick(fast));
    });
    final full = await ArtworkPaletteCache.get(url);
    if (!mounted || widget.artworkUrl != url) return;
    setState(() => _tint = _pick(full));
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: _tint),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOut,
        builder: (context, color, _) {
          final c = color ?? _tint;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c, Color.lerp(c, _base, 0.5)!, _base],
                stops: const [0.0, 0.38, 0.85],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CollapsingHeader extends StatelessWidget {
  final double collapseT;
  final Song song;
  final FavoritesProvider favorites;
  final VoidCallback onClose;
  final VoidCallback onMore;

  const _CollapsingHeader({
    required this.collapseT,
    required this.song,
    required this.favorites,
    required this.onClose,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        children: [
          Opacity(
            opacity: (1 - collapseT * 1.6).clamp(0.0, 1.0),
            child: IgnorePointer(
              ignoring: collapseT > 0.5,
              child:
                  _ExpandedHeaderRow(onClose: onClose, song: song, onMore: onMore),
            ),
          ),
          Opacity(
            opacity: ((collapseT - 0.35) / 0.65).clamp(0.0, 1.0),
            child: IgnorePointer(
              ignoring: collapseT < 0.5,
              child: _CollapsedHeaderRow(
                  song: song, favorites: favorites, onMore: onMore),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedHeaderRow extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onMore;
  final Song song;
  const _ExpandedHeaderRow(
      {required this.onClose, required this.song, required this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: Colors.white, size: 30),
            onPressed: onClose,
          ),
          Expanded(
            child: Column(
              children: [
                const Text(
                  'NOW PLAYING',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '"${song.title}"',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded,
                color: Colors.white, size: 24),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

class _CollapsedHeaderRow extends StatelessWidget {
  final Song song;
  final FavoritesProvider favorites;
  final VoidCallback onMore;
  const _CollapsedHeaderRow(
      {required this.song, required this.favorites, required this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: AurumArtwork(url: song.artworkUrl, size: 44, borderRadius: 6),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          AurumLikeButton(
            isLiked: favorites.isFavorite(song.id),
            size: 22,
            likedColor: const Color(0xFF1ED760),
            unlikedColor: Colors.white,
            onTap: () => favorites.toggleFavorite(song),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded,
                color: Colors.white, size: 22),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

class _PlayerPage extends StatelessWidget {
  final PlayerProvider player;
  final Song song;
  final VoidCallback onOpenQueue;
  const _PlayerPage({
    required this.player,
    required this.song,
    required this.onOpenQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              const double sideMargin = 20.0;
              const double vPad = 10.0;
              final double byWidth = c.maxWidth - sideMargin * 2;
              final double byHeight = c.maxHeight - vPad * 2;
              final double side =
                  (byWidth < byHeight ? byWidth : byHeight)
                      .clamp(0.0, 4000.0)
                      .toDouble();
              return Center(
                child: PhysicalModel(
                  color: Colors.black,
                  elevation: 20,
                  shadowColor: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                  child: AurumArtwork(
                    url: AurumArtwork.upgradeForFullPlayer(song.artworkUrl),
                    size: side,
                    borderRadius: 8,
                  ),
                ),
              );
            },
          ),
        ),
        _TitleRow(song: song),
        _ControlsBlock(player: player, song: song),
        _IconActionsRow(
          player: player,
          song: song,
          onOpenQueue: onOpenQueue,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  final Song song;
  const _TitleRow({required this.song});

  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesProvider>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AurumLikeButton(
            isLiked: favorites.isFavorite(song.id),
            size: 27,
            likedColor: const Color(0xFF1ED760),
            unlikedColor: Colors.white,
            onTap: () {
              AurumHaptics.light();
              favorites.toggleFavorite(song);
            },
          ),
        ],
      ),
    );
  }
}

class _ControlsBlock extends StatelessWidget {
  final PlayerProvider player;
  final Song song;
  const _ControlsBlock({required this.player, required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
      child: Column(
        children: [
          AurumSeekBar(
            player: player,
            hPad: 24,
            activeColor: Colors.white,
            inactiveColor: Colors.white24,
            timeColor: Colors.white60,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.shuffle_rounded,
                    size: 22,
                    color: player.shuffle
                        ? const Color(0xFF1ED760)
                        : Colors.white70,
                  ),
                  onPressed: () {
                    AurumHaptics.light();
                    player.toggleShuffle();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous_rounded,
                      color: Colors.white, size: 36),
                  onPressed: () {
                    AurumHaptics.light();
                    player.skipPrev();
                  },
                ),
                _PlayPauseButton(player: player),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded,
                      color: Colors.white, size: 36),
                  onPressed: () {
                    AurumHaptics.light();
                    player.skipNext();
                  },
                ),
                IconButton(
                  icon: Icon(
                    player.loopMode == LoopMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    size: 22,
                    color: player.loopMode == LoopMode.off
                        ? Colors.white70
                        : const Color(0xFF1ED760),
                  ),
                  onPressed: () {
                    AurumHaptics.light();
                    player.toggleLoop();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final PlayerProvider player;
  const _PlayPauseButton({required this.player});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            AurumHaptics.medium();
            player.togglePlay();
          },
          child: Center(
            child: player.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.black,
                    ),
                  )
                : AurumPlayPauseIcon(
                    isPlaying: player.isPlaying,
                    color: Colors.black,
                    size: 30,
                  ),
          ),
        ),
      ),
    );
  }
}

class _IconActionsRow extends StatelessWidget {
  final PlayerProvider player;
  final Song song;
  final VoidCallback onOpenQueue;
  const _IconActionsRow({
    required this.player,
    required this.song,
    required this.onOpenQueue,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.info_outline_rounded,
                    color: Colors.white70, size: 22),
                onPressed: () => showSongInfoDialog(context, song),
              ),
              ListenableBuilder(
                listenable: JamService.instance,
                builder: (context, _) => IconButton(
                  tooltip: 'Jam',
                  icon: JamConnectIcon(
                    size: 22,
                    color: JamService.instance.inRoom
                        ? const Color(0xFF1ED760)
                        : Colors.white70,
                  ),
                  onPressed: () => openJamPage(context),
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.playlist_add_rounded,
                    color: Colors.white70, size: 24),
                onPressed: () {
                  AurumHaptics.light();
                  showAddToPlaylistSheet(context, song);
                },
              ),
              IconButton(
                icon: const Icon(Icons.queue_music_rounded,
                    color: Colors.white70, size: 22),
                onPressed: onOpenQueue,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LyricsPreviewCard extends StatefulWidget {
  final PlayerProvider player;
  final VoidCallback onOpenFullScreen;
  const _LyricsPreviewCard({
    required this.player,
    required this.onOpenFullScreen,
  });

  @override
  State<_LyricsPreviewCard> createState() => _LyricsPreviewCardState();
}

class _LyricsPreviewCardState extends State<_LyricsPreviewCard> {
  static const double _peekHeight = 200.0;

  bool _loading = true;
  LyricsResult? _result;
  String? _loadedForSongId;
  final LyricsTranslationHandle _tr = LyricsTranslationHandle();

  @override
  void initState() {
    super.initState();
    _tr.addListener(_onTr);
    _load();
  }

  @override
  void dispose() {
    _tr.removeListener(_onTr);
    _tr.dispose();
    super.dispose();
  }

  void _onTr() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final song = widget.player.currentSong;
    if (song == null) return;
    _loadedForSongId = song.id;
    _tr.update(song: song, result: null);
    try {
      final result = await widget.player.fetchSyncedLyrics();
      if (!mounted || _loadedForSongId != song.id) return;
      setState(() {
        _result = result;
        _loading = false;
      });
      _tr.update(song: song, result: result.hasAny ? result : null);
    } catch (_) {
      if (!mounted || _loadedForSongId != song.id) return;
      setState(() {
        _result = null;
        _loading = false;
      });
    }
  }

  String _plainPeek(LyricsResult r) {
    final src = r.plain!.split('\n');
    final out = <String>[];
    for (var i = 0; i < src.length && out.length < 5; i++) {
      if (src[i].trim().isEmpty) continue;
      out.add(_tr.lineAt(i) ?? src[i].trim());
    }
    return out.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.player.currentSong;
    if (song != null &&
        _loadedForSongId != null &&
        _loadedForSongId != song.id) {
      _loading = true;
      _result = null;
      _loadedForSongId = song.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }

    final result = _result;
    final hasLyrics = result?.hasAny ?? false;
    final hasSynced = result?.hasSynced ?? false;
    // Keep the card in its loading state until the chosen script is ready, so
    // Hindi never flashes before the converted text.
    final busy = _loading || _tr.pending;

    return Container(
      height: _peekHeight,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A2E7A), Color(0xFF2B1854)],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: (busy || !hasLyrics) ? null : widget.onOpenFullScreen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Lyrics',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (busy)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white54,
                        ),
                      )
                    else if (hasLyrics)
                      Text(
                        'Show',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: busy
                      ? const SizedBox.shrink()
                      : !hasLyrics
                          ? const Center(
                              child: Text(
                                'Lyrics not found',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : hasSynced
                              ? _LivePeekLines(result: result!, handle: _tr)
                              : Align(
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                    _plainPeek(result!),
                                    maxLines: 5,
                                    overflow: TextOverflow.fade,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LivePeekLines extends StatefulWidget {
  final LyricsResult result;
  final LyricsTranslationHandle handle;
  const _LivePeekLines({required this.result, required this.handle});

  @override
  State<_LivePeekLines> createState() => _LivePeekLinesState();
}

class _LivePeekLinesState extends State<_LivePeekLines> {
  static const double _plainExtent = 34.0;
  static const double _pairExtent = 56.0;

  double get _lineExtent =>
      (widget.handle.active != null && !widget.handle.onlyConverted)
          ? _pairExtent
          : _plainExtent;

  final ScrollController _ctrl = ScrollController();
  int _lastActive = -2;
  double _lastExt = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _glideTo(int active) {
    if (!_ctrl.hasClients) return;
    final target = ((active - 1) * _lineExtent)
        .clamp(0.0, _ctrl.position.maxScrollExtent)
        .toDouble();
    _ctrl.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.result.synced!;
    final active = context.select<PlayerProvider, int>(
        (p) => widget.result.activeIndexFor(p.position));

    if (_lastExt != _lineExtent) {
      _lastExt = _lineExtent;
      _lastActive = -2;
    }
    if (active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _glideTo(active < 0 ? 0 : active);
      });
    }

    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, 0.7, 1.0],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _ctrl,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemExtent: _lineExtent,
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final isActive = i == active;
          final isPast = active >= 0 && i < active;
          final raw = lines[i].text.trim();
          final conv = raw.isEmpty ? null : widget.handle.lineAt(i);
          final only = widget.handle.onlyConverted;
          final mainText = raw.isEmpty ? '♪' : ((only && conv != null) ? conv : raw);
          final sub = (!only && conv != null && conv.toLowerCase() != raw.toLowerCase())
              ? conv
              : null;
          final mainColor = isActive
              ? Colors.white
              : Colors.white.withOpacity(isPast ? 0.38 : 0.6);
          return Align(
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: AnimatedDefaultTextStyle(
                    key: ValueKey(mainText),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      color: mainColor,
                      fontSize: isActive ? 17 : 15.5,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      height: 1.2,
                    ),
                    child: Text(
                      mainText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (sub != null)
                  TweenAnimationBuilder<double>(
                    key: ValueKey(sub),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, child) => Opacity(
                      opacity: v,
                      child: Transform.translate(
                          offset: Offset(0, (1 - v) * 8), child: child),
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOut,
                      style: TextStyle(
                        color: Colors.white.withOpacity(
                            isActive ? 0.78 : (isPast ? 0.26 : 0.42)),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                      child: Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ArtistsSection extends StatefulWidget {
  final Song song;
  const _ArtistsSection({required this.song});

  @override
  State<_ArtistsSection> createState() => _ArtistsSectionState();
}

class _ArtistsSectionState extends State<_ArtistsSection> {
  static final _splitPattern = RegExp(
    r'\s*(?:,|&|/|\bfeat\.?\b|\bft\.?\b|\bx\b|\bvs\.?\b)\s*',
    caseSensitive: false,
  );

  List<String> get _names => _splitNames(widget.song.artist);

  List<String> _splitNames(String raw) {
    final parts = raw
        .split(_splitPattern)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? [raw.trim()] : parts;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            'Artists',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final name in _names) ...[
          _SingleArtistCard(
            artistName: name,
            fallbackImageUrl: widget.song.artworkUrl,
            knownArtistId: name.trim().toLowerCase() ==
                    widget.song.artist.trim().toLowerCase()
                ? widget.song.artistChannelId
                : null,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SingleArtistCard extends StatefulWidget {
  final String artistName;
  final String? knownArtistId;
  final String fallbackImageUrl;
  const _SingleArtistCard({
    required this.artistName,
    required this.fallbackImageUrl,
    this.knownArtistId,
  });

  @override
  State<_SingleArtistCard> createState() => _SingleArtistCardState();
}

class _SingleArtistCardState extends State<_SingleArtistCard> {
  bool _loading = true;
  String? _resolvedId;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SingleArtistCard old) {
    super.didUpdateWidget(old);
    if (old.artistName != widget.artistName ||
        old.knownArtistId != widget.knownArtistId) {
      setState(() {
        _loading = true;
        _resolvedId = null;
        _imageUrl = null;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final wanted = widget.artistName;
    try {
      final results = await ApiService.searchArtists(wanted, limit: 3)
          .timeout(const Duration(seconds: 8));
      if (!mounted || wanted != widget.artistName) return;

      ArtistSimple? pick;
      final lower = wanted.trim().toLowerCase();
      for (final r in results) {
        if (r.name.trim().toLowerCase() == lower) {
          pick = r;
          break;
        }
      }
      pick ??= results.isNotEmpty ? results.first : null;

      setState(() {
        _resolvedId = widget.knownArtistId ?? pick?.id;
        _imageUrl = (pick != null && pick.imageUrl.isNotEmpty)
            ? pick.imageUrl
            : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted && wanted == widget.artistName) {
        setState(() {
          _resolvedId = widget.knownArtistId;
          _loading = false;
        });
      }
    }
  }

  void _open(BuildContext context) {
    AurumHaptics.selection();
    AurumDepthRoute.to(
      context,
      ArtistScreen(artistId: _resolvedId, artistName: widget.artistName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF1B1B1B),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _open(context),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_imageUrl != null && _imageUrl!.isNotEmpty)
                    AurumArtwork(
                      url: _imageUrl!,
                      size: double.infinity,
                      borderRadius: 0,
                    )
                  else if (widget.fallbackImageUrl.isNotEmpty)
                    AurumArtwork(
                      url: AurumArtwork.upgradeForFullPlayer(
                          widget.fallbackImageUrl),
                      size: double.infinity,
                      borderRadius: 0,
                    )
                  else
                    ColoredBox(
                      color: Colors.white.withOpacity(0.06),
                      child: Center(
                        child: Icon(Icons.person_rounded,
                            color: Colors.white.withOpacity(0.3), size: 48),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.75),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 14,
                    right: 16,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Artist',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: Colors.white70, size: 22),
                      ],
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

class _DescriptionCard extends StatelessWidget {
  final Song song;
  const _DescriptionCard({required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4A2E7A), Color(0xFF2B1854)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${song.durationString.isNotEmpty ? song.durationString : '--:--'} • ${song.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  '${song.title} • ${song.artist}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => showSongInfoDialog(context, song),
                child: const Text(
                  'More',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
