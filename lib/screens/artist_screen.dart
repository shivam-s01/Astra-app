// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'package:aurum_music/widgets/aurum_loader.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/artist.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/followed_artists_provider.dart';
import '../services/api_service.dart';
import '../theme/aurum_theme.dart';
import '../widgets/aurum_artwork.dart';
import '../widgets/aurum_glass.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/song_tile.dart';
import '../widgets/mini_player_slot.dart';
import '../widgets/aurum_snack.dart';
import '../utils/aurum_transitions.dart';
import 'album_screen.dart';
import 'artist_all_songs_screen.dart';
import 'artist_all_albums_screen.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_haptics.dart';

class ArtistScreen extends StatefulWidget {
  final String? artistId;
  final String artistName;

  const ArtistScreen({super.key, this.artistId, required this.artistName});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  Artist? _artist;
  bool _loading = true;
  bool _failed = false;

  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _barT = ValueNotifier<double>(0);
  final ValueNotifier<double> _stretch = ValueNotifier<double>(0);
  final ValueNotifier<List<Song>> _liveSongs = ValueNotifier<List<Song>>(const []);

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('Artist');
    _scroll.addListener(_onScroll);
    final id = _normalizedId(widget.artistId);
    if (id != null) {
      final cached = ApiService.peekCachedArtist(id);
      if (cached != null) {
        _artist = cached;
        _liveSongs.value = cached.topSongs;
        _loading = false;
      }
    }
    _loadStreaming();
  }

  static String? _normalizedId(String? raw) {
    final id = raw?.trim();
    if (id == null || id.isEmpty || id == 'yt_') return null;
    if (id.startsWith('yt_')) return id;
    if (RegExp(r'^UC[0-9A-Za-z_-]{20,}$').hasMatch(id)) return 'yt_$id';
    return id;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _barT.dispose();
    _stretch.dispose();
    _liveSongs.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final o = _scroll.offset;
    final t = ((o - 40) / 90).clamp(0.0, 1.0);
    if (_barT.value != t) _barT.value = t;
    final st = o < 0 ? -o : 0.0;
    if (_stretch.value != st) _stretch.value = st;
  }

  Future<void> _loadStreaming() async {
    setState(() {
      _loading = _artist == null;
      _failed = false;
    });
    try {
      String? id = _normalizedId(widget.artistId);
      id ??= await ApiService.resolveArtistId(widget.artistName);
      if (!mounted) return;
      if (id != null && !id.startsWith('yt_')) {
        id = await ApiService.resolveArtistId(widget.artistName);
        if (!mounted) return;
      }
      if (id == null || id.isEmpty) {
        setState(() {
          _loading = false;
          _failed = _artist == null;
        });
        return;
      }
      var gotAny = false;
      await ApiService.fetchArtistStreaming(id,
          songCount: 200, isCancelled: () => !mounted, onUpdate: (artist) {
        if (!mounted) return;
        gotAny = true;
        _liveSongs.value = artist.topSongs;
        setState(() {
          _artist = artist;
          _loading = false;
        });
      });
      if (!mounted) return;
      if (!gotAny && _artist == null) {
        setState(() { _loading = false; _failed = true; });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _artist == null;
      });
    }
  }

  String _formatFollowers(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      bottomNavigationBar: const MiniPlayerSlot(),
      body: _loading
          ? _buildLoading(context)
          : _failed
              ? _buildError(context)
              : _buildContent(context, _artist!),
    );
  }

  Widget _buildLoading(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        Positioned(
          top: topPad + 8,
          left: 4,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              AurumHaptics.selection();
              Navigator.pop(context);
            },
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  widget.artistName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const AurumMorphLoader(size: 44, contained: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      children: [
        Positioned(
          top: 8,
          left: 4,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                AurumHaptics.selection();
                Navigator.pop(context);
              },
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_off_rounded,
                  size: 56, color: AurumTheme.textMutedOf(context)),
              const SizedBox(height: 12),
              Text(l10n.asCouldntLoad(widget.artistName),
                  style: TextStyle(color: AurumTheme.textSecondaryOf(context))),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  AurumHaptics.light();
                  _loadStreaming();
                },
                child: Text(l10n.asRetry),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, Artist artist) {
    final l10n = AppLocalizations.of(context)!;
    final player = context.read<PlayerProvider>();
    final followed = context.watch<FollowedArtistsProvider>();
    final isFollowing = followed.isFollowing(artist.id);
    final media = MediaQuery.of(context);
    final topPad = media.padding.top;
    final heroH = (media.size.width * 1.2).clamp(400.0, 560.0).toDouble();

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          cacheExtent: 600,
          slivers: [
            SliverToBoxAdapter(
              child: _buildHero(
                  context, artist, player, followed, isFollowing, heroH, topPad),
            ),

        if (_pickLatestRelease(artist) case final latest?)
          SliverToBoxAdapter(
            child: _ArtistLatestReleaseCard(
              album: latest,
              label: l10n.asLatestRelease,
              typeLabel: latest.type == 'single'
                  ? l10n.asTypeSingle
                  : l10n.asTypeAlbum,
            ),
          ),

        if (artist.topSongs.isNotEmpty) ...[
          _sectionHeader(
            context,
            l10n.asPopular,
            onSeeAll: () {
              AurumHaptics.light();
              AurumDepthRoute.to(
                context,
                ArtistAllSongsScreen(
                  artistName: artist.name,
                  songs: artist.topSongs,
                  liveSongs: _liveSongs,
                ),
              );
            },
          ),
          _ArtistTopSongsSection(songs: artist.topSongs),
        ],

        if (artist.topAlbums.isNotEmpty) ...[
          _sectionHeader(
            context,
            l10n.asAlbums,
            onSeeAll: () {
              AurumHaptics.light();
              AurumDepthRoute.to(
                context,
                ArtistAllAlbumsScreen(
                  artistName: artist.name,
                  title: l10n.asAlbums,
                  albums: artist.topAlbums,
                ),
              );
            },
          ),
          _albumGrid(context, artist.topAlbums),
        ],

        if (artist.singles.isNotEmpty) ...[
          _sectionHeader(
            context,
            l10n.asSingles,
            onSeeAll: () {
              AurumHaptics.light();
              AurumDepthRoute.to(
                context,
                ArtistAllAlbumsScreen(
                  artistName: artist.name,
                  title: l10n.asSingles,
                  albums: artist.singles,
                ),
              );
            },
          ),
          _albumGrid(context, artist.singles),
        ],

        if (artist.relatedArtists.isNotEmpty) ...[
          _sectionHeader(context, l10n.asFansAlsoLike),
          _relatedArtistsRow(context, artist.relatedArtists),
        ],

        if (artist.bio.isNotEmpty) ...[
          _sectionHeader(context, l10n.asAbout),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              child: Text(
                artist.bio,
                style: TextStyle(
                  color: AurumTheme.textSecondaryOf(context),
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ] else
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopBar(context, artist, topPad),
        ),
      ],
    );
  }

  Widget _buildHero(
    BuildContext context,
    Artist artist,
    PlayerProvider player,
    FollowedArtistsProvider followed,
    bool isFollowing,
    double heroH,
    double topPad,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final bg = AurumTheme.bgOf(context);
    final hasSongs = artist.topSongs.isNotEmpty;
    final primary = AurumTheme.textPrimaryOf(context);

    return RepaintBoundary(
      child: SizedBox(
      height: heroH,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _stretch,
            builder: (context, st, child) => Transform.scale(
              scale: 1 + (st / heroH),
              alignment: Alignment.bottomCenter,
              child: child,
            ),
            child: RepaintBoundary(
              child: AurumArtwork(
                  url: artist.imageUrl, size: 700, borderRadius: 0),
            ),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _stretch,
            builder: (context, st, child) => Positioned(
              top: -st,
              left: 0,
              right: 0,
              height: topPad + 90,
              child: child!,
            ),
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
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bg.withOpacity(0.0),
                    bg.withOpacity(0.0),
                    bg.withOpacity(0.88),
                    bg,
                  ],
                  stops: const [0.0, 0.42, 0.80, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  artist.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primary,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                if (artist.followerCount > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    l10n.asMonthlyListeners(
                        _formatFollowers(artist.followerCount)),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AurumTheme.textSecondaryOf(context),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (artist.isVerified) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: AurumTheme.accentOf(context),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded,
                            size: 11, color: Colors.black),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.asVerifiedArtist,
                        style: TextStyle(
                          color: AurumTheme.textSecondaryOf(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ArtistGlassButton(
                      icon: Icons.shuffle_rounded,
                      onTap: !hasSongs
                          ? null
                          : () {
                              final shuffled = List<Song>.from(artist.topSongs)
                                ..shuffle();
                              player.playSong(shuffled.first,
                                  queue: shuffled,
                                  index: 0,
                                  curatedQueue: true);
                            },
                    ),
                    const SizedBox(width: 12),
                    AurumPressable(
                      scaleAmount: 0.94,
                      onTap: !hasSongs
                          ? null
                          : () {
                              AurumHaptics.medium();
                              player.playSong(artist.topSongs.first,
                                  queue: artist.topSongs,
                                  index: 0,
                                  curatedQueue: true);
                            },
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          color: hasSongs ? primary : primary.withOpacity(0.3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: bg, size: 26),
                            const SizedBox(width: 6),
                            Text(
                              l10n.commonPlay,
                              style: TextStyle(
                                color: bg,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ArtistGlassButton(
                      icon: isFollowing
                          ? Icons.check_rounded
                          : Icons.person_add_alt_1_rounded,
                      active: isFollowing,
                      onTap: () async {
                        final wasFollowing = followed.isFollowing(artist.id);
                        await followed.toggleFollow(
                          artistId: artist.id,
                          name: artist.name,
                          imageUrl: artist.imageUrl,
                        );
                        if (!context.mounted) return;
                        AurumSnack.show(
                          context,
                          wasFollowing
                              ? 'Unfollowed ${artist.name}'
                              : 'Following ${artist.name}',
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, Artist artist, double topPad) {
    final bg = AurumTheme.bgOf(context);
    final primary = AurumTheme.textPrimaryOf(context);
    return ValueListenableBuilder<double>(
      valueListenable: _barT,
      builder: (context, t, _) {
        final iconColor = Color.lerp(Colors.white, primary, t)!;
        return SizedBox(
          height: topPad + 56,
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: t,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border(
                          bottom: BorderSide(
                              color: AurumTheme.dividerOf(context), width: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: topPad),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: t < 0.6
                          ? AurumGlass(
                              sigma: 6,
                              borderRadius: BorderRadius.circular(20),
                              isDark: true,
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  splashRadius: 20,
                                  icon: Icon(Icons.arrow_back_rounded,
                                      color: iconColor, size: 22),
                                  onPressed: () {
                                    AurumHaptics.selection();
                                    Navigator.pop(context);
                                  },
                                ),
                              ),
                            )
                          : IconButton(
                              padding: EdgeInsets.zero,
                              splashRadius: 20,
                              icon: Icon(Icons.arrow_back_rounded,
                                  color: iconColor, size: 22),
                              onPressed: () {
                                AurumHaptics.selection();
                                Navigator.pop(context);
                              },
                            ),
                    ),
                    Expanded(
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(0, (1 - t) * 6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                artist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 52),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(BuildContext context, String title,
      {VoidCallback? onSeeAll}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (onSeeAll != null)
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onSeeAll,
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
      ),
    );
  }

  Widget _albumGrid(BuildContext context, List<ArtistAlbum> albums) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 190,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          cacheExtent: 500,
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final a = albums[i];
            return RepaintBoundary(
              child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  AurumHaptics.light();
                  AurumDepthRoute.to(
                    context,
                    AlbumScreen(
                      albumId: a.id,
                      albumName: a.name,
                      artworkUrl: a.artworkUrl,
                    ),
                  );
                },
                child: SizedBox(
                  width: 130,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AurumArtwork(url: a.artworkUrl, size: 130, borderRadius: 10),
                      const SizedBox(height: 8),
                      Text(
                        a.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (a.year != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          a.year!,
                          style: TextStyle(
                            color: AurumTheme.textMutedOf(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _relatedArtistsRow(BuildContext context, List<RelatedArtist> artists) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 168,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          cacheExtent: 500,
          itemCount: artists.length,
          itemBuilder: (context, i) {
            final a = artists[i];
            return RepaintBoundary(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () {
                    AurumHaptics.light();
                    AurumDepthRoute.to(
                      context,
                      ArtistScreen(
                        artistId: a.id.startsWith('yt_') ? a.id : 'yt_${a.id}',
                        artistName: a.name,
                      ),
                    );
                  },
                  child: SizedBox(
                    width: 120,
                    child: Column(
                      children: [
                        ClipOval(
                          child: AurumArtwork(url: a.imageUrl, size: 120, borderRadius: 60),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          a.name,
                          textAlign: TextAlign.center,
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
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ArtistTopSongsSection extends StatelessWidget {
  static const int _previewCount = 10;
  final List<Song> songs;
  const _ArtistTopSongsSection({required this.songs});

  @override
  Widget build(BuildContext context) {
    final visibleCount =
        songs.length > _previewCount ? _previewCount : songs.length;

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => SongTile(
          song: songs[i],
          queue: songs,
          index: i,
          curatedQueue: true,
        ),
        childCount: visibleCount,
        addRepaintBoundaries: false,
        addAutomaticKeepAlives: false,
      ),
    );
  }
}

class _ArtistGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;

  const _ArtistGlassButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final primary = AurumTheme.textPrimaryOf(context);
    return AurumPressable(
      scaleAmount: 0.9,
      onTap: disabled
          ? null
          : () {
              AurumHaptics.selection();
              onTap!();
            },
      child: SizedBox(
        width: 48,
        height: 48,
        child: AurumGlass(
          sigma: 6,
          borderRadius: BorderRadius.circular(24),
          isDark: Theme.of(context).brightness == Brightness.dark,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              size: 22,
              color: disabled
                  ? AurumTheme.textMutedOf(context).withOpacity(0.4)
                  : active
                      ? AurumTheme.accentOf(context)
                      : primary,
            ),
          ),
        ),
      ),
    );
  }
}

ArtistAlbum? _pickLatestRelease(Artist artist) {
  ArtistAlbum? best;
  int bestYear = -1;
  void scan(List<ArtistAlbum> list) {
    for (final a in list) {
      final y = int.tryParse(a.year ?? '') ?? -1;
      if (y > bestYear) {
        best = a;
        bestYear = y;
      }
    }
  }

  scan(artist.singles);
  scan(artist.topAlbums);
  return bestYear < 0 ? null : best;
}

class _ArtistLatestReleaseCard extends StatelessWidget {
  final ArtistAlbum album;
  final String label;
  final String typeLabel;
  const _ArtistLatestReleaseCard({
    required this.album,
    required this.label,
    required this.typeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final meta =
        album.year == null ? typeLabel : '$typeLabel \u2022 ${album.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: RepaintBoundary(
        child: AurumPressable(
          scaleAmount: 0.98,
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AurumTheme.bgCardOf(context),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                AurumArtwork(
                  url: album.artworkUrl,
                  size: 96,
                  borderRadius: 12,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AurumTheme.textMutedOf(context),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        album.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 17,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AurumTheme.textMutedOf(context),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
