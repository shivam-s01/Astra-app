// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:aurum_music/widgets/aurum_loader.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/aurum_image_cache.dart';
import '../widgets/aurum_glass.dart';
import '../widgets/aurum_wide_thumb.dart';
import '../widgets/aurum_equalizer_bars.dart';
import '../widgets/aurum_song_options_sheet.dart' show showAurumSongOptions;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:provider/provider.dart';
import '../theme/aurum_theme.dart';
import '../providers/player_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/library_provider.dart';
import '../providers/recently_played_provider.dart';
import '../providers/download_provider.dart';
import '../providers/playlist_provider.dart';
import '../services/api_service.dart' show ApiService;
import '../services/playlist_import_service.dart';
import '../models/artist.dart';
import '../widgets/aurum_snack.dart';
import '../widgets/aurum_coach_tip.dart';
import '../widgets/aurum_promo_screen.dart' show AurumPromoData;
import '../providers/premium_provider.dart';
import '../providers/auth_provider.dart';
import '../services/sync_service.dart';
import '../services/recommendation_engine.dart';
import '../models/download_item.dart';
import '../widgets/song_tile.dart';
import '../widgets/aurum_artwork.dart';
import '../widgets/aurum_stacked_artwork.dart';
import '../widgets/aurum_cover_color.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/aurum_empty_state.dart';
import '../widgets/mini_player_slot.dart';
import 'full_player_screen.dart';
import '../widgets/premium_gate.dart';
import '../models/song.dart';
import '../utils/aurum_transitions.dart';
import 'settings_screen.dart';
import 'liked_screen.dart';
import '../providers/followed_artists_provider.dart';
import '../providers/followed_albums_provider.dart';
import 'artist_screen.dart';
import 'album_screen.dart';
import 'mix_screen.dart';
import '../widgets/aurum_focus_field.dart';
import '../utils/aurum_immersive_header.dart';
import '../utils/artwork_palette_cache.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_sheet.dart';
import '../utils/aurum_motion.dart';

class LibraryBackScope {
  LibraryBackScope._();

  static Object? _owner;
  static bool Function()? _handler;

  static void _register(Object owner, bool Function() handler) {
    _owner = owner;
    _handler = handler;
  }

  static void _unregister(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
      _handler = null;
    }
  }

  static bool handleBack() => _handler?.call() ?? false;
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

enum _LibTab { library, playlists, songs, artists, albums }

class _LibraryScreenState extends State<LibraryScreen> {
  _LibTab _tab = _LibTab.library;

  bool _artistsSelecting = false;

  final ValueNotifier<int> _exitArtistsSelect = ValueNotifier<int>(0);

  bool _handleInnerBack() {
    if (_artistsSelecting) {
      _exitArtistsSelect.value++;
      return true;
    }
    if (_tab != _LibTab.library) {
      setState(() => _tab = _LibTab.library);
      return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    LibraryBackScope._register(this, _handleInnerBack);
  }

  @override
  void dispose() {
    LibraryBackScope._unregister(this);
    _exitArtistsSelect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(context),
            _buildTabRow(context),
            Expanded(
              child: AnimatedSwitcher(
                duration: AurumMotion.durationOrZero(AurumMotion.short2),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: _buildTabBody(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Text(
            AppLocalizations.of(context)!.navLibrary,
            style: TextStyle(
              color: AurumTheme.accentOf(context),
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const Spacer(),
          _TopIconButton(
            icon: Icons.settings_outlined,
            onTap: () => AurumDepthRoute.to(context, const SettingsScreen()),
          ),
        ],
      ),
    );
  }

  Widget _buildTabRow(BuildContext context) {
    final tabs = <_LibTab, String>{
      _LibTab.library: AppLocalizations.of(context)!.navLibrary,
      _LibTab.playlists: AppLocalizations.of(context)!.libraryPlaylists,
      _LibTab.songs: AppLocalizations.of(context)!.librarySongs,
      _LibTab.artists: AppLocalizations.of(context)!.libraryArtists,
      _LibTab.albums: AppLocalizations.of(context)!.libraryAlbums,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: AurumTheme.bgSurfaceOf(context),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(
            color: AurumTheme.accentOf(context).withOpacity(0.22),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final entry in tabs.entries)
              Expanded(
                child: _TabChip(
                  label: entry.value,
                  selected: _tab == entry.key,
                  onTap: () {
                    if (_tab == entry.key) return;
                    AurumHaptics.selection();
                    setState(() => _tab = entry.key);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBody(BuildContext context) {
    switch (_tab) {
      case _LibTab.library:
        return _AurumLibraryOverviewTab(
          onSeeAllArtists: () => setState(() => _tab = _LibTab.artists),
        );
      case _LibTab.playlists:
        return const _AurumPlaylistsTab();
      case _LibTab.songs:
        return const _AurumSongsTab();
      case _LibTab.artists:
        return _AurumArtistsTab(
          exitSelectSignal: _exitArtistsSelect,
          onSelectModeChanged: (v) => _artistsSelecting = v,
        );
      case _LibTab.albums:
        return const _AurumAlbumsTab();
    }
  }
}

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AurumTheme.bgSurfaceOf(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          AurumHaptics.light();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, color: AurumTheme.textSecondaryOf(context), size: 19),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final gradient = selected ? AurumTheme.accentGradientOf(context) : null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AurumMotion.durationOrZero(AurumMotion.short2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: gradient,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AurumTheme.accentOf(context).withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : AurumTheme.textSecondaryOf(context),
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AurumSongsTab extends StatefulWidget {
  const _AurumSongsTab();

  @override
  State<_AurumSongsTab> createState() => _AurumSongsTabState();
}

class _AurumSongsTabState extends State<_AurumSongsTab> {
  bool _newestFirst = true;
  _SongsFilter _filter = _SongsFilter.liked;

  @override
  void initState() {
    super.initState();
    final lib = context.read<LibraryProvider>();
    final fav = context.read<FavoritesProvider>();
    if (!fav.isLoading && fav.favorites.isEmpty) {
      _filter = _SongsFilter.all;
    }
    if (_filter == _SongsFilter.all && !lib.hasLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => lib.load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryProvider>();
    context.select<FavoritesProvider, (int, bool)>(
        (f) => (f.favorites.length, f.isLoading));
    context.select<DownloadProvider, int>((d) => d.completed.length);
    final favorites = context.read<FavoritesProvider>();
    final downloads = context.read<DownloadProvider>();

    final needsScan = _filter == _SongsFilter.all;

    if (needsScan &&
        (lib.status == LibraryStatus.loading || lib.status == LibraryStatus.idle)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 48),
          child: AurumM3Loader(),
        ),
      );
    }

    if (needsScan && lib.status == LibraryStatus.noPermission) {
      return _AurumPermissionState(onGrant: () => lib.load());
    }

    List<Song> songs;
    switch (_filter) {
      case _SongsFilter.liked:
        songs = List<Song>.from(favorites.favorites);
        break;
      case _SongsFilter.downloaded:
        songs = downloads.completed.map((d) => d.song).toList();
        break;
      case _SongsFilter.all:
        songs = List<Song>.from(lib.allSongs);
        break;
    }
    final ordered = _newestFirst ? songs : songs.reversed.toList();

    final totalSeconds = ordered.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final durationLabel = _formatDuration(totalSeconds);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1200,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              children: [
                _SongsFilterChip(
                  label: AppLocalizations.of(context)!.libraryLiked,
                  selected: _filter == _SongsFilter.liked,
                  onTap: () {
                    AurumHaptics.selection();
                    setState(() => _filter = _SongsFilter.liked);
                  },
                ),
                const SizedBox(width: 10),
                _SongsFilterChip(
                  label: AppLocalizations.of(context)!.libraryDownloaded,
                  selected: _filter == _SongsFilter.downloaded,
                  onTap: () {
                    AurumHaptics.selection();
                    setState(() => _filter = _SongsFilter.downloaded);
                  },
                ),
                const SizedBox(width: 10),
                _SongsFilterChip(
                  label: AppLocalizations.of(context)!.libraryAllSongs,
                  selected: _filter == _SongsFilter.all,
                  onTap: () {
                    AurumHaptics.selection();
                    setState(() => _filter = _SongsFilter.all);
                    final lib = context.read<LibraryProvider>();
                    if (lib.status == LibraryStatus.idle) lib.load();
                  },
                ),
                const SizedBox(width: 10),
                _SortRow(
                  newestFirst: _newestFirst,
                  onToggle: () {
                    AurumHaptics.selection();
                    setState(() => _newestFirst = !_newestFirst);
                  },
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _HeroActionCard(
              title: AppLocalizations.of(context)!.libraryYourCollection,
              subtitle: ordered.isEmpty
                  ? AppLocalizations.of(context)!.libraryNoSongsYetInPlaylist
                  : '${AppLocalizations.of(context)!.librarySongsCount(ordered.length)} • $durationLabel',
              buttonLabel: AppLocalizations.of(context)!.commonPlay,
              icon: Icons.play_arrow_rounded,
              onButtonTap: ordered.isEmpty
                  ? null
                  : () => context.read<PlayerProvider>().playSong(
                        ordered.first,
                        queue: ordered,
                        index: 0,
                        curatedQueue: true,
                      ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        if (ordered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _AurumEmptyState(
              icon: Icons.music_note_rounded,
              title: AppLocalizations.of(context)!.albumNoSongsFound,
              subtitle: _filter == _SongsFilter.liked
                  ? AppLocalizations.of(context)!.libraryLikedEmptyDesc
                  : _filter == _SongsFilter.downloaded
                      ? AppLocalizations.of(context)!.libraryDownloadedEmptyDesc
                      : AppLocalizations.of(context)!.libraryLocalEmptyDesc,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _AurumSongRow(
                    song: ordered[i],
                    queue: ordered,
                    index: i,
                  ),
                ),
                childCount: ordered.length,
              ),
            ),
          ),
      ],
    );
  }

  static String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final mm = m % 60;
      return '${h}h ${mm}m';
    }
    return '${m}m ${s}s';
  }
}

enum _SongsFilter { liked, downloaded, all }

class _SongsFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SongsFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AurumTheme.accentOf(context) : AurumTheme.bgSurfaceOf(context),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : AurumTheme.textPrimaryOf(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _SortRow extends StatelessWidget {
  final bool newestFirst;
  final VoidCallback onToggle;
  const _SortRow({required this.newestFirst, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: AurumTheme.bgSurfaceOf(context),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    newestFirst ? AppLocalizations.of(context)!.libraryNewestFirst : AppLocalizations.of(context)!.libraryOldestFirst,
                    style: TextStyle(
                      color: AurumTheme.accentOf(context),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: AurumTheme.accentOf(context), size: 18),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: AurumTheme.bgSurfaceOf(context),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(11),
              child: Icon(
                newestFirst
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                color: AurumTheme.accentOf(context),
                size: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroActionCard extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final IconData icon;
  final VoidCallback? onButtonTap;
  final VoidCallback? onMoreTap;
  final Widget? leading;

  const _HeroActionCard({
    this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.icon,
    this.onButtonTap,
    this.onMoreTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AurumTheme.bgElevatedOf(context),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: TextStyle(
                      color: AurumTheme.accentOf(context).withOpacity(0.75),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context).withOpacity(0.65),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Material(
                      color: AurumTheme.accentOf(context),
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: onButtonTap == null
                            ? null
                            : () {
                                AurumHaptics.light();
                                onButtonTap!();
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                buttonLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (onMoreTap != null) ...[
                      const SizedBox(width: 10),
                      Material(
                        color: Colors.white.withOpacity(0.35),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onMoreTap,
                          child: Padding(
                            padding: EdgeInsets.all(11),
                            child: Icon(Icons.more_horiz_rounded,
                                color: AurumTheme.accentOf(context), size: 18),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AurumSongRow extends StatelessWidget {
  final Song song;
  final List<Song> queue;
  final int index;
  const _AurumSongRow({
    required this.song,
    required this.queue,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final isFav = context.select<FavoritesProvider, bool>((f) => f.isFavorite(song.id));
    return Material(
      color: AurumTheme.bgSurfaceOf(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          AurumHaptics.selection();
          context.read<PlayerProvider>().playSong(
                song,
                queue: queue,
                index: index,
                curatedQueue: true,
              );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: song.artworkUrl.isEmpty
                    ? Container(
                        width: 46,
                        height: 46,
                        color: AurumTheme.bgSurfaceOf(context),
                        child: Icon(Icons.music_note_rounded,
                            color: AurumTheme.accentOf(context), size: 20),
                      )
                    : AurumArtwork(url: song.artworkUrl, size: 46, borderRadius: 12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isFav) ...[
                          const Icon(Icons.favorite_rounded,
                              color: Colors.redAccent, size: 14),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AurumTheme.textPrimaryOf(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist.isEmpty ? AppLocalizations.of(context)!.libraryUnknownArtist : song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AurumTheme.textMutedOf(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (song.durationString.isNotEmpty)
                Text(
                  song.durationString,
                  style: TextStyle(
                    color: AurumTheme.textMutedOf(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.more_vert_rounded,
                    color: AurumTheme.textMutedOf(context), size: 20),
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                onPressed: () => showAurumSongOptionsSheet(context, song),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showAurumSongOptionsSheet(BuildContext context, Song song) {
  showAurumSongOptions(context, song);
}

class _AurumEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _AurumEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AurumTheme.bgSurfaceOf(context),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AurumTheme.accentOf(context), size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AurumTheme.textMutedOf(context),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AurumPermissionState extends StatelessWidget {
  final VoidCallback onGrant;
  const _AurumPermissionState({required this.onGrant});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AurumTheme.bgSurfaceOf(context),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_rounded, color: AurumTheme.accentOf(context), size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              AppLocalizations.of(context)!.libraryPermissionRequired,
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context)!.libraryStoragePermissionDesc,
              textAlign: TextAlign.center,
              style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 18),
            Material(
              color: AurumTheme.accentOf(context),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onGrant,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  child: Text(AppLocalizations.of(context)!.libraryGrantPermission,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AurumArtistsTab extends StatefulWidget {
  final ValueNotifier<int>? exitSelectSignal;
  final ValueChanged<bool>? onSelectModeChanged;
  const _AurumArtistsTab({this.exitSelectSignal, this.onSelectModeChanged});

  @override
  State<_AurumArtistsTab> createState() => _AurumArtistsTabState();
}

class _AurumArtistsTabState extends State<_AurumArtistsTab> {
  bool _newestFirst = true;

  void _onExitSelectSignal() {
    if (_selectMode) _exitSelectMode();
  }

  bool _lastReportedSelect = false;
  void _reportSelect() {
    if (_lastReportedSelect == _selectMode) return;
    _lastReportedSelect = _selectMode;
    widget.onSelectModeChanged?.call(_selectMode);
  }

  @override
  void initState() {
    super.initState();
    widget.exitSelectSignal?.addListener(_onExitSelectSignal);
  }

  @override
  void didUpdateWidget(covariant _AurumArtistsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exitSelectSignal != widget.exitSelectSignal) {
      oldWidget.exitSelectSignal?.removeListener(_onExitSelectSignal);
      widget.exitSelectSignal?.addListener(_onExitSelectSignal);
    }
  }

  @override
  void dispose() {
    widget.exitSelectSignal?.removeListener(_onExitSelectSignal);
    if (_lastReportedSelect) widget.onSelectModeChanged?.call(false);
    super.dispose();
  }

  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  void _enterSelectMode(String firstId) {
    AurumHaptics.medium();
    setState(() {
      _selectMode = true;
      _selectedIds
        ..clear()
        ..add(firstId);
    });
  }

  void _toggleSelected(String id) {
    AurumHaptics.selection();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectMode = false;
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _confirmUnfollowSelected(List<Map<String, dynamic>> ordered) async {
    final count = _selectedIds.length;
    final confirmed = await showAurumModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.libraryUnfollowArtistsConfirm(count),
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: Text(AppLocalizations.of(context)!.commonCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: Text(AppLocalizations.of(context)!.libraryUnfollow),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    AurumHaptics.medium();
    final ids = List<String>.from(_selectedIds);
    _exitSelectMode();
    await context.read<FollowedArtistsProvider>().unfollowMany(ids);
  }

  @override
  Widget build(BuildContext context) {
    if (_lastReportedSelect != _selectMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportSelect();
      });
    }
    final followedProvider = context.watch<FollowedArtistsProvider>();
    if (followedProvider.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppLocalizations.of(context)!.libraryLoadingArtists,
                  style: TextStyle(color: AurumTheme.textMutedOf(context))),
              const SizedBox(height: 12),
              const AurumM3Loader(),
            ],
          ),
        ),
      );
    }

    final seenArtistIds = <String>{};
    final base = followedProvider.followed.where((m) {
      final id = (m['id'] ?? '').toString();
      final name = (m['name'] ?? '').toString();
      if (id.isEmpty || name.isEmpty) return false;
      return seenArtistIds.add(id);
    }).toList();
    final ordered = _newestFirst ? base : base.reversed.toList();
    final top = ordered.isNotEmpty ? ordered.first : null;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1200,
      slivers: [
        if (top != null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: _TopArtistAndCountRow(
                top: top,
                totalCount: ordered.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 18)),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _selectMode
                ? Row(
                    children: [
                      Material(
                        color: AurumTheme.bgSurfaceOf(context),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            AurumHaptics.light();
                            _exitSelectMode();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: Icon(Icons.close_rounded,
                                color: AurumTheme.textPrimaryOf(context), size: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        AppLocalizations.of(context)!.librarySelectedCount(_selectedIds.length),
                        style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Builder(builder: (context) {
                        final allIds = ordered.map((m) => (m['id'] ?? '').toString()).toSet();
                        final allSelected = allIds.isNotEmpty &&
                            _selectedIds.length == allIds.length;
                        return TextButton(
                          onPressed: () {
                            AurumHaptics.selection();
                            setState(() {
                              if (allSelected) {
                                _selectedIds.clear();
                              } else {
                                _selectedIds
                                  ..clear()
                                  ..addAll(allIds);
                              }
                            });
                          },
                          child: Text(
                            allSelected ? AppLocalizations.of(context)!.libraryDeselectAll : AppLocalizations.of(context)!.librarySelectAll,
                            style: TextStyle(
                              color: AurumTheme.accentOf(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }),
                      IconButton(
                        icon: Icon(
                          Icons.person_remove_outlined,
                          color: _selectedIds.isEmpty
                              ? AurumTheme.textMutedOf(context)
                              : Colors.redAccent,
                        ),
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : () => _confirmUnfollowSelected(ordered),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _SortRow(
                        newestFirst: _newestFirst,
                        onToggle: () {
                          AurumHaptics.selection();
                          setState(() => _newestFirst = !_newestFirst);
                        },
                      ),
                    ],
                  ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (ordered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _AurumEmptyState(
              icon: Icons.person_rounded,
              title: AppLocalizations.of(context)!.libraryNoArtistsSavedYet,
              subtitle: AppLocalizations.of(context)!.libraryArtistsYouFollowAppearHere,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final artistId = (ordered[i]['id'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AurumArtistRow(
                      artist: ordered[i],
                      selectMode: _selectMode,
                      selected: _selectedIds.contains(artistId),
                      onEnterSelectMode: () => _enterSelectMode(artistId),
                      onToggleSelected: () => _toggleSelected(artistId),
                    ),
                  );
                },
                childCount: ordered.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _TopArtistAndCountRow extends StatefulWidget {
  final Map<String, dynamic> top;
  final int totalCount;
  const _TopArtistAndCountRow({required this.top, required this.totalCount});

  @override
  State<_TopArtistAndCountRow> createState() => _TopArtistAndCountRowState();
}

class _TopArtistAndCountRowState extends State<_TopArtistAndCountRow> {
  bool _resolving = false;

  Future<void> _playAll(String id, String name) async {
    if (_resolving) return;
    if (id.isEmpty) {
      AurumDepthRoute.to(context, ArtistScreen(artistId: id, artistName: name));
      return;
    }
    AurumHaptics.light();
    setState(() => _resolving = true);
    try {
      final artist = await ApiService.fetchArtist(id);
      if (!mounted) return;
      final songs = artist?.topSongs ?? const <Song>[];
      if (songs.isEmpty) {
        AurumSnack.show(context, AppLocalizations.of(context)!.libraryNoPlayableSongsFor(name));
        return;
      }
      context.read<PlayerProvider>().playSong(
            songs.first,
            queue: songs,
            index: 0,
            curatedQueue: true,
          );
    } catch (e) {
      if (!mounted) return;
      AurumSnack.show(context, AppLocalizations.of(context)!.libraryCouldntLoadSongsFor(name));
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.top;
    final totalCount = widget.totalCount;
    final name = (top['name'] ?? '').toString();
    final id = (top['id'] ?? '').toString();
    final imageUrl = (top['imageUrl'] ?? '').toString();

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () => AurumDepthRoute.to(
                  context,
                  ArtistScreen(artistId: id, artistName: name),
                ),
                child: Ink(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AurumTheme.accentGradientOf(context),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AurumTheme.accentOf(context).withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.55),
                                  width: 1.5),
                            ),
                            child: ClipOval(
                              child: imageUrl.isEmpty
                                  ? Container(
                                      width: 46,
                                      height: 46,
                                      color: Colors.white.withOpacity(0.2),
                                      child: const Icon(Icons.person_rounded,
                                          color: Colors.white, size: 22),
                                    )
                                  : AurumArtwork(
                                      url: imageUrl, size: 46, borderRadius: 23),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        AppLocalizations.of(context)!.libraryTopArtistEyebrow,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        name.isEmpty ? AppLocalizations.of(context)!.libraryUnknown : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: _resolving ? null : () => _playAll(id, name),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 11),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_resolving)
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AurumTheme.accentDarkOf(context),
                                        ),
                                      )
                                    else
                                      Icon(Icons.play_arrow_rounded,
                                          color: AurumTheme.accentDarkOf(context),
                                          size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      _resolving ? AppLocalizations.of(context)!.libraryLoading : AppLocalizations.of(context)!.commonPlayAll,
                                      style: TextStyle(
                                        color: AurumTheme.accentDarkOf(context),
                                        fontSize: 13.5,
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
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Material(
              color: AurumTheme.bgElevatedOf(context),
              borderRadius: BorderRadius.circular(28),
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () {
                  AurumHaptics.selection();
                  AurumDepthRoute.to(context, const _ArtistsScreen());
                },
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: AurumTheme.accentOf(context).withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.people_alt_rounded,
                                color: AurumTheme.accentOf(context), size: 18),
                          ),
                          Icon(Icons.arrow_forward_rounded,
                              color: AurumTheme.textMutedOf(context), size: 16),
                        ],
                      ),
                      Text(
                        '$totalCount',
                        style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)!.libraryArtistsFollowedLabel(totalCount),
                        style: TextStyle(
                          color: AurumTheme.textMutedOf(context),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AurumArtistRow extends StatefulWidget {
  final Map<String, dynamic> artist;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onEnterSelectMode;
  final VoidCallback? onToggleSelected;

  const _AurumArtistRow({
    required this.artist,
    this.selectMode = false,
    this.selected = false,
    this.onEnterSelectMode,
    this.onToggleSelected,
  });

  @override
  State<_AurumArtistRow> createState() => _AurumArtistRowState();
}

class _AurumArtistRowState extends State<_AurumArtistRow> {
  bool _resolving = false;

  Future<void> _playAll(String id, String name) async {
    if (_resolving) return;
    if (id.isEmpty) return;
    AurumHaptics.light();
    setState(() => _resolving = true);
    try {
      final artist = await ApiService.fetchArtist(id);
      if (!mounted) return;
      final songs = artist?.topSongs ?? const <Song>[];
      if (songs.isEmpty) {
        AurumSnack.show(context, AppLocalizations.of(context)!.libraryNoPlayableSongsFor(name));
        return;
      }
      context.read<PlayerProvider>().playSong(
            songs.first,
            queue: songs,
            index: 0,
            curatedQueue: true,
          );
    } catch (e) {
      if (!mounted) return;
      AurumSnack.show(context, AppLocalizations.of(context)!.libraryCouldntLoadSongsFor(name));
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final artist = widget.artist;
    final selectMode = widget.selectMode;
    final selected = widget.selected;
    final id = (artist['id'] ?? '').toString();
    final name = (artist['name'] ?? '').toString();
    final imageUrl = (artist['imageUrl'] ?? '').toString();

    return Material(
      color: selected
          ? AurumTheme.accentOf(context).withOpacity(0.12)
          : AurumTheme.bgSurfaceOf(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          if (selectMode) {
            widget.onToggleSelected?.call();
            return;
          }
          AurumHaptics.selection();
          AurumDepthRoute.to(context, ArtistScreen(artistId: id, artistName: name));
        },
        onLongPress: () {
          if (selectMode) return;
          AurumHaptics.medium();
          widget.onEnterSelectMode?.call();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipOval(
                child: imageUrl.isEmpty
                    ? Container(
                        width: 48,
                        height: 48,
                        color: AurumTheme.bgSurfaceOf(context),
                        child: Icon(Icons.person_rounded,
                            color: AurumTheme.accentOf(context), size: 22),
                      )
                    : AurumArtwork(url: imageUrl, size: 48, borderRadius: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? AppLocalizations.of(context)!.libraryUnknown : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AurumTheme.textPrimaryOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.libraryArtistTag,
                      style: TextStyle(
                        color: AurumTheme.textMutedOf(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (selectMode)
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected
                      ? AurumTheme.accentOf(context)
                      : AurumTheme.textMutedOf(context),
                  size: 24,
                )
              else
                Material(
                  color: AurumTheme.accentOf(context),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _resolving ? null : () => _playAll(id, name),
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: _resolving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
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

class _AurumAlbumsTab extends StatefulWidget {
  const _AurumAlbumsTab();

  @override
  State<_AurumAlbumsTab> createState() => _AurumAlbumsTabState();
}

class _AurumAlbumsTabState extends State<_AurumAlbumsTab> {
  bool _newestFirst = true;
  bool _gridView = true;

  @override
  Widget build(BuildContext context) {
    final followedProvider = context.watch<FollowedAlbumsProvider>();
    if (followedProvider.isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 48),
          child: AurumM3Loader(),
        ),
      );
    }

    final base = followedProvider.followed;
    final ordered = _newestFirst ? base : base.reversed.toList();
    final featured = ordered.isNotEmpty ? ordered.first : null;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1200,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
            child: Row(
              children: [
                _SortRow(
                  newestFirst: _newestFirst,
                  onToggle: () {
                    AurumHaptics.selection();
                    setState(() => _newestFirst = !_newestFirst);
                  },
                ),
                const Spacer(),
                _ViewToggle(
                  gridView: _gridView,
                  onChanged: (v) {
                    AurumHaptics.selection();
                    setState(() => _gridView = v);
                  },
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
        if (featured != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _FeaturedAlbumHero(album: featured),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        if (ordered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _AurumEmptyState(
              icon: Icons.album_rounded,
              title: AppLocalizations.of(context)!.libraryNoAlbumsSavedYet,
              subtitle: AppLocalizations.of(context)!.libraryAlbumsYouSaveAppearHere,
            ),
          )
        else if (_gridView)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                childAspectRatio: 0.78,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _AurumAlbumTile(album: ordered[i]),
                childCount: ordered.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AurumAlbumRow(album: ordered[i]),
                ),
                childCount: ordered.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  final bool gridView;
  final ValueChanged<bool> onChanged;
  const _ViewToggle({required this.gridView, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AurumTheme.bgSurfaceOf(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewToggleButton(
            icon: Icons.view_list_rounded,
            selected: !gridView,
            onTap: () => onChanged(false),
          ),
          _ViewToggleButton(
            icon: Icons.album_rounded,
            selected: gridView,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ViewToggleButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ViewToggleButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AurumTheme.accentOf(context) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: selected ? Colors.white : AurumTheme.accentOf(context)),
        ),
      ),
    );
  }
}

class _FeaturedAlbumHero extends StatefulWidget {
  final Map<String, dynamic> album;
  const _FeaturedAlbumHero({required this.album});

  @override
  State<_FeaturedAlbumHero> createState() => _FeaturedAlbumHeroState();
}

class _FeaturedAlbumHeroState extends State<_FeaturedAlbumHero> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    final id = (album['id'] ?? '').toString();
    final name = (album['name'] ?? '').toString();
    final artworkUrl = (album['artworkUrl'] ?? '').toString();
    final isMix = album['isMix'] == true;

    void open() {
      if (isMix) {
        final songs = context.read<FollowedAlbumsProvider>().songsFor(id);
        AurumDepthRoute.to(
          context,
          MixScreen(mixId: id, mixName: name, artworkUrl: artworkUrl, emoji: '', songs: songs),
        );
      } else {
        AurumDepthRoute.to(
          context,
          AlbumScreen(albumId: id, albumName: name, artworkUrl: artworkUrl),
        );
      }
    }

    Future<void> play() async {
      if (_loading) return;
      AurumHaptics.light();
      final player = context.read<PlayerProvider>();
      setState(() => _loading = true);
      List<Song> songs;
      try {
        if (isMix) {
          songs = context.read<FollowedAlbumsProvider>().songsFor(id);
        } else {
          final r = await ApiService.fetchAlbumSongsWithArtwork(id);
          final art = r.headerArtworkUrl.isNotEmpty ? r.headerArtworkUrl : artworkUrl;
          songs = r.songs
              .map((s) => s.artworkUrl.isEmpty && art.isNotEmpty
                  ? s.copyWith(artworkUrl: art)
                  : s)
              .toList();
        }
      } catch (_) {
        songs = const <Song>[];
      }
      if (!mounted) return;
      setState(() => _loading = false);
      if (songs.isEmpty) {
        AurumSnack.show(context, AppLocalizations.of(context)!.libraryNoPlayableSongsFor(name));
        return;
      }
      player.playSong(songs.first, queue: songs, index: 0, curatedQueue: true);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AurumTheme.bgElevatedOf(context),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AurumArtwork(url: artworkUrl, size: 90, borderRadius: 14),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.libraryFeaturedAlbum,
                  style: TextStyle(
                    color: AurumTheme.accentOf(context).withOpacity(0.75),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name.isEmpty ? AppLocalizations.of(context)!.libraryUnknownAlbum : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Material(
                      color: AurumTheme.accentOf(context),
                      borderRadius: BorderRadius.circular(22),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: play,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.play_arrow_rounded,
                                      color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(AppLocalizations.of(context)!.commonPlay,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: Colors.white.withOpacity(0.35),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: open,
                        child: Padding(
                          padding: const EdgeInsets.all(13),
                          child: Icon(Icons.chevron_right_rounded,
                              semanticLabel: name,
                              color: AurumTheme.accentOf(context), size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AurumAlbumTile extends StatelessWidget {
  final Map<String, dynamic> album;
  const _AurumAlbumTile({required this.album});

  @override
  Widget build(BuildContext context) {
    final id = (album['id'] ?? '').toString();
    final name = (album['name'] ?? '').toString();
    final artworkUrl = (album['artworkUrl'] ?? '').toString();
    final isMix = album['isMix'] == true;

    return RepaintBoundary(
      child: AurumPressable(
        onTap: () {
          if (isMix) {
            final songs = context.read<FollowedAlbumsProvider>().songsFor(id);
            AurumDepthRoute.to(
              context,
              MixScreen(mixId: id, mixName: name, artworkUrl: artworkUrl, emoji: '', songs: songs),
            );
          } else {
            AurumDepthRoute.to(
              context,
              AlbumScreen(albumId: id, albumName: name, artworkUrl: artworkUrl),
            );
          }
        },
        onLongPress: () {
          AurumHaptics.medium();
          _showUnsaveSheet(context, id, name, artworkUrl);
        },
        scaleAmount: 0.95,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AurumArtwork(url: artworkUrl, size: 300, borderRadius: 16),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name.isEmpty ? AppLocalizations.of(context)!.libraryUnknownAlbum : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUnsaveSheet(
      BuildContext context, String id, String name, String artworkUrl) {
    final rootContext = context;
    showAurumModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AurumArtwork(url: artworkUrl, size: 44, borderRadius: 8),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bookmark_remove_rounded, color: Colors.redAccent),
              title: Text(AppLocalizations.of(context)!.libraryRemoveFromSavedAlbums,
                  style: TextStyle(color: AurumTheme.textPrimaryOf(context))),
              onTap: () {
                Navigator.pop(sheetContext);
                rootContext.read<FollowedAlbumsProvider>().toggleFollow(
                      albumId: id,
                      name: name,
                      artworkUrl: artworkUrl,
                    );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AurumAlbumRow extends StatelessWidget {
  final Map<String, dynamic> album;
  const _AurumAlbumRow({required this.album});

  @override
  Widget build(BuildContext context) {
    final id = (album['id'] ?? '').toString();
    final name = (album['name'] ?? '').toString();
    final artworkUrl = (album['artworkUrl'] ?? '').toString();
    final isMix = album['isMix'] == true;

    return Material(
      color: AurumTheme.bgSurfaceOf(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          AurumHaptics.selection();
          if (isMix) {
            final songs = context.read<FollowedAlbumsProvider>().songsFor(id);
            AurumDepthRoute.to(
              context,
              MixScreen(mixId: id, mixName: name, artworkUrl: artworkUrl, emoji: '', songs: songs),
            );
          } else {
            AurumDepthRoute.to(
              context,
              AlbumScreen(albumId: id, albumName: name, artworkUrl: artworkUrl),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AurumArtwork(url: artworkUrl, size: 48, borderRadius: 12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? AppLocalizations.of(context)!.libraryUnknownAlbum : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AurumTheme.textPrimaryOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.libraryAlbumTag,
                      style: TextStyle(
                        color: AurumTheme.textMutedOf(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AurumTheme.textMutedOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AurumLibraryOverviewTab extends StatefulWidget {
  const _AurumLibraryOverviewTab({required this.onSeeAllArtists});

  final VoidCallback onSeeAllArtists;

  @override
  State<_AurumLibraryOverviewTab> createState() => _AurumLibraryOverviewTabState();
}

class _AurumLibraryOverviewTabState extends State<_AurumLibraryOverviewTab> {
  @override
  Widget build(BuildContext context) {
    final favorites = context.watch<FavoritesProvider>();
    final downloadedCount =
        context.select<DownloadProvider, int>((d) => d.completed.length);
    final recentlyPlayed = context.watch<RecentlyPlayedProvider>();
    final playlists = context.watch<PlaylistProvider>();
    final followedArtists = context.watch<FollowedArtistsProvider>();

    final likedCount = favorites.favorites.length;
    final recent = recentlyPlayed.history.take(10).toList();
    final hasRecent = recent.isNotEmpty;
    final heroTitle = !hasRecent
        ? AppLocalizations.of(context)!.libraryYourLibrary
        : (recent.first.album.isNotEmpty ? recent.first.album : recent.first.title);
    final previewPlaylists =
        PlaylistProvider.pinnedFirst(playlists.playlists).take(2).toList();
    final seenPreviewArtistIds = <String>{};
    final previewArtists = followedArtists.followed.where((m) {
      final aid = (m['id'] ?? '').toString();
      final aname = (m['name'] ?? '').toString();
      if (aid.isEmpty || aname.isEmpty) return false;
      return seenPreviewArtistIds.add(aid);
    }).take(8).toList();

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      cacheExtent: 1200,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _HeroActionCard(
              eyebrow: hasRecent ? AppLocalizations.of(context)!.libraryMostPlayed : null,
              title: heroTitle,
              subtitle: hasRecent
                  ? (recent.first.artist.isNotEmpty ? recent.first.artist : AppLocalizations.of(context)!.libraryUnknownArtist)
                  : AppLocalizations.of(context)!.libraryStartPlayingToGrow,
              buttonLabel: AppLocalizations.of(context)!.commonPlayAll,
              icon: Icons.play_arrow_rounded,
              leading: !hasRecent
                  ? null
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AurumArtwork(url: recent.first.artworkUrl, size: 68, borderRadius: 14),
                    ),
              onButtonTap: !hasRecent
                  ? null
                  : () => context.read<PlayerProvider>().playSong(
                        recent.first,
                        queue: recent,
                        index: 0,
                        curatedQueue: true,
                      ),
              onMoreTap: !hasRecent
                  ? null
                  : () => showAurumSongOptionsSheet(context, recent.first),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _QuickAccessGrid(
              likedCount: likedCount,
              downloadedCount: downloadedCount,
            ),
          ),
        ),
        if (recent.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SizedBox(height: 26)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Text(
                    AppLocalizations.of(context)!.libraryRecentlyPlayed,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      AurumHaptics.light();
                      AurumDepthRoute.to(context, const _HistoryScreen());
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.commonSeeAll,
                            style: TextStyle(
                              color: AurumTheme.accentOf(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: AurumTheme.accentOf(context),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 168,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: recent.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: _RecentlyPlayedCard(
                    song: recent[i],
                    queue: recent,
                    index: i,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 26)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context)!.libraryYourPlaylists,
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => AurumDepthRoute.to(context, const PlaylistsScreen()),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    AppLocalizations.of(context)!.commonSeeAll,
                    style: TextStyle(
                      color: AurumTheme.accentOf(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (playlists.playlists.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
              child: GestureDetector(
                onTap: () => AurumDepthRoute.to(context, const PlaylistsScreen()),
                child: _AurumEmptyState(
                  icon: Icons.playlist_play_rounded,
                  title: AppLocalizations.of(context)!.libraryNoPlaylistsYet,
                  subtitle: AppLocalizations.of(context)!.libraryCreateFromSongMenu,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AurumPlaylistRow(playlist: previewPlaylists[i]),
                ),
                childCount: previewPlaylists.length,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Text(
                  AppLocalizations.of(context)!.libraryYourArtists,
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onSeeAllArtists,
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    AppLocalizations.of(context)!.commonSeeAll,
                    style: TextStyle(
                      color: AurumTheme.accentOf(context),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (previewArtists.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
              child: GestureDetector(
                onTap: widget.onSeeAllArtists,
                child: _AurumEmptyState(
                  icon: Icons.person_rounded,
                  title: AppLocalizations.of(context)!.libraryNoArtistsSavedYet,
                  subtitle: AppLocalizations.of(context)!.libraryFollowArtistToSeeHere,
                ),
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 110),
              child: SizedBox(
                height: 128,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: previewArtists.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: _AurumArtistPreviewCard(artist: previewArtists[i]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AurumArtistPreviewCard extends StatelessWidget {
  final Map<String, dynamic> artist;
  const _AurumArtistPreviewCard({required this.artist});

  @override
  Widget build(BuildContext context) {
    final id = (artist['id'] ?? '').toString();
    final name = (artist['name'] ?? '').toString();
    final imageUrl = (artist['imageUrl'] ?? '').toString();

    return SizedBox(
      width: 84,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            AurumHaptics.selection();
            AurumDepthRoute.to(context, ArtistScreen(artistId: id, artistName: name));
          },
          child: Column(
            children: [
              ClipOval(
                child: imageUrl.isEmpty
                    ? Container(
                        width: 72,
                        height: 72,
                        color: AurumTheme.bgSurfaceOf(context),
                        child: Icon(Icons.person_rounded,
                            color: AurumTheme.accentOf(context), size: 30),
                      )
                    : AurumArtwork(url: imageUrl, size: 72, borderRadius: 36),
              ),
              const SizedBox(height: 8),
              Text(
                name.isEmpty ? AppLocalizations.of(context)!.libraryUnknown : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 12.5,
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

class _AurumPlaylistsTab extends StatefulWidget {
  const _AurumPlaylistsTab();

  @override
  State<_AurumPlaylistsTab> createState() => _AurumPlaylistsTabState();
}

class _AurumPlaylistsTabState extends State<_AurumPlaylistsTab> {
  _PlaylistSort _sort = _PlaylistSort.custom;
  bool _gridView = false;
  bool _reorderLocked = true;
  String? _activeTag;

  String _sortLabel(_PlaylistSort s) {
    switch (s) {
      case _PlaylistSort.custom:
        return AppLocalizations.of(context)!.librarySortCustom;
      case _PlaylistSort.name:
        return AppLocalizations.of(context)!.librarySortName;
      case _PlaylistSort.dateAdded:
        return AppLocalizations.of(context)!.librarySortDateAdded;
      case _PlaylistSort.mostPlayed:
        return AppLocalizations.of(context)!.librarySortMostPlayed;
    }
  }

  List<AurumPlaylist> _sorted(PlaylistProvider pp) {
    final base = _activeTag == null
        ? pp.customOrdered()
        : pp.byTag(_activeTag!);
    if (_sort == _PlaylistSort.custom) return base;
    final list = List<AurumPlaylist>.from(base);
    switch (_sort) {
      case _PlaylistSort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _PlaylistSort.dateAdded:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _PlaylistSort.mostPlayed:
        list.sort((a, b) => b.songCount.compareTo(a.songCount));
        break;
      case _PlaylistSort.custom:
        break;
    }
    return PlaylistProvider.pinnedFirst(list);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaylistProvider>(
      builder: (context, pp, _) {
        final tags = pp.allTags;
        final visible = _sorted(pp);
        final canReorder = _sort == _PlaylistSort.custom &&
            _activeTag == null &&
            !_reorderLocked;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          cacheExtent: 1200,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    _SortDropdown(
                      label: _sortLabel(_sort),
                      onSelected: (s) => setState(() => _sort = s),
                    ),
                    const Spacer(),
                    _ToolbarIconButton(
                      icon: _reorderLocked
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      selected: !_reorderLocked,
                      onTap: _sort != _PlaylistSort.custom
                          ? null
                          : () => setState(() => _reorderLocked = !_reorderLocked),
                    ),
                    const SizedBox(width: 8),
                    _PlaylistViewToggle(
                      gridView: _gridView,
                      onChanged: (g) => setState(() => _gridView = g),
                    ),
                    const SizedBox(width: 8),
                    _ImportCoachAnchor(
                      child: _ToolbarIconButton(
                        icon: Icons.cloud_download_outlined,
                        onTap: () => _showImportPlaylistDialog(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ToolbarIconButton(
                      icon: Icons.add_rounded,
                      filled: true,
                      onTap: () => _showCreateDialog(context),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  children: [
                    _TagFilterChip(
                      icon: Icons.filter_alt_rounded,
                      label: AppLocalizations.of(context)!.libraryTagAll,
                      selected: _activeTag == null,
                      onTap: () => setState(() => _activeTag = null),
                    ),
                    const SizedBox(width: 10),
                    for (final tag in tags) ...[
                      _TagFilterChip(
                        label: tag,
                        selected: _activeTag == tag,
                        onTap: () => setState(
                            () => _activeTag = _activeTag == tag ? null : tag),
                      ),
                      const SizedBox(width: 10),
                    ],
                    _TagFilterChip(
                      icon: Icons.add_rounded,
                      label: AppLocalizations.of(context)!.libraryManageTags,
                      selected: false,
                      onTap: () => _showManageTagsSheet(context, pp),
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyPlaylists(
                    onCreateTap: () => _showCreateDialog(context)),
              )
            else if (_gridView)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.86,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _PlaylistGridTile(playlist: visible[i]),
                    childCount: visible.length,
                  ),
                ),
              )
            else if (canReorder)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 110),
                sliver: SliverReorderableList(
                  itemCount: visible.length,
                  onReorder: (oldIndex, newIndex) {
                    final pinnedCount =
                        visible.where((p) => p.isPinned).length;
                    if (oldIndex < pinnedCount) return;
                    if (newIndex < pinnedCount) newIndex = pinnedCount;
                    AurumHaptics.medium();
                    pp.reorderPlaylist(oldIndex, newIndex);
                  },
                  itemBuilder: (context, i) => _PlaylistListRow(
                    key: ValueKey(visible[i].id),
                    playlist: visible[i],
                    index: i,
                    reorderable: !visible[i].isPinned,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 110),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _PlaylistListRow(
                      key: ValueKey(visible[i].id),
                      playlist: visible[i],
                      index: i,
                      reorderable: false,
                    ),
                    childCount: visible.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    PremiumGate.guard(
      context,
      feature: l10n.libraryCreatePlaylist,
      description: l10n.libraryLoginToOrganizeDesc,
      requiresLoginOnly: true,
      onAllowed: () async {
        await showDialog(
          context: context,
          builder: (_) => _CreatePlaylistDialog(),
        );
      },
    );
  }

  Future<void> _showManageTagsSheet(
      BuildContext context, PlaylistProvider pp) async {
    await showAurumModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ManageTagsSheet(pp: pp),
    );
  }
}

class _QuickAccessGrid extends StatelessWidget {
  final int likedCount;
  final int downloadedCount;
  const _QuickAccessGrid({required this.likedCount, required this.downloadedCount});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.7,
      children: [
        _QuickAccessCard(
          icon: Icons.favorite_rounded,
          iconColor: Colors.redAccent,
          title: AppLocalizations.of(context)!.libraryLikedSongs,
          subtitle: AppLocalizations.of(context)!.libraryTracksCount(likedCount),
          onTap: () => AurumDepthRoute.to(context, const LikedScreen()),
        ),
        _QuickAccessCard(
          icon: Icons.check_circle_rounded,
          iconColor: AurumTheme.accentOf(context),
          title: AppLocalizations.of(context)!.libraryOffline,
          subtitle: downloadedCount == 0 ? AppLocalizations.of(context)!.libraryDownloaded : AppLocalizations.of(context)!.libraryDownloadedLowerCount(downloadedCount),
          onTap: () => AurumDepthRoute.to(context, const DownloadsScreen()),
        ),
        _QuickAccessCard(
          icon: Icons.trending_up_rounded,
          iconColor: AurumTheme.accentOf(context),
          title: AppLocalizations.of(context)!.libraryMyTop50,
          subtitle: AppLocalizations.of(context)!.libraryAllTime,
          onTap: () => AurumDepthRoute.to(context, const _TopSongsScreen()),
        ),
        _QuickAccessCard(
          icon: Icons.folder_rounded,
          iconColor: AurumTheme.accentOf(context),
          title: AppLocalizations.of(context)!.libraryLocalFiles,
          subtitle: AppLocalizations.of(context)!.libraryOnDevice,
          onTap: () => AurumDepthRoute.to(context, const _LocalFilesScreen()),
        ),
        _QuickAccessCard(
          icon: Icons.history_rounded,
          iconColor: AurumTheme.accentOf(context),
          title: AppLocalizations.of(context)!.libraryHistory,
          subtitle: AppLocalizations.of(context)!.libraryRecentlyPlayed,
          onTap: () => AurumDepthRoute.to(context, const _HistoryScreen()),
        ),
      ],
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickAccessCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AurumTheme.bgSurfaceOf(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          AurumHaptics.light();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(context),
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentlyPlayedCard extends StatelessWidget {
  final Song song;
  final List<Song> queue;
  final int index;
  const _RecentlyPlayedCard({
    required this.song,
    required this.queue,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      child: AurumPressable(
        onTap: () {
          AurumHaptics.selection();
          context.read<PlayerProvider>().playSong(
                song,
                queue: queue,
                index: index,
                curatedQueue: true,
              );
        },
        scaleAmount: 0.95,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AurumArtwork(url: song.artworkUrl, size: 128, borderRadius: 16),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: AurumTheme.accentOf(context),
                    shape: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              song.artist.isEmpty ? AppLocalizations.of(context)!.libraryUnknownArtist : song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AurumTheme.textMutedOf(context),
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AurumPlaylistRow extends StatelessWidget {
  final AurumPlaylist playlist;
  const _AurumPlaylistRow({required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AurumTheme.bgSurfaceOf(context),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => AurumDepthRoute.to(
          context,
          PlaylistDetailScreen(playlistId: playlist.id),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: playlist.coverArt == null || playlist.coverArt!.isEmpty
                    ? Container(
                        width: 48,
                        height: 48,
                        color: AurumTheme.bgSurfaceOf(context),
                        child: Icon(Icons.playlist_play_rounded,
                            color: AurumTheme.accentOf(context), size: 22),
                      )
                    : AurumArtwork(url: playlist.coverArt!, size: 48, borderRadius: 12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AurumTheme.textPrimaryOf(context),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.librarySongsCount(playlist.songCount),
                      style: TextStyle(
                        color: AurumTheme.textMutedOf(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AurumTheme.textMutedOf(context)),
            ],
          ),
        ),
      ),
    );
  }
}

enum _PlaylistSort { custom, name, dateAdded, mostPlayed }

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  _PlaylistSort _sort = _PlaylistSort.custom;
  bool _gridView = false;
  bool _reorderLocked = true;
  String? _activeTag;

  String _sortLabel(_PlaylistSort s) {
    switch (s) {
      case _PlaylistSort.custom:
        return AppLocalizations.of(context)!.librarySortCustom;
      case _PlaylistSort.name:
        return AppLocalizations.of(context)!.librarySortName;
      case _PlaylistSort.dateAdded:
        return AppLocalizations.of(context)!.librarySortDateAdded;
      case _PlaylistSort.mostPlayed:
        return AppLocalizations.of(context)!.librarySortMostPlayed;
    }
  }

  List<AurumPlaylist> _sorted(PlaylistProvider pp) {
    final base = _activeTag == null
        ? pp.customOrdered()
        : pp.byTag(_activeTag!);
    if (_sort == _PlaylistSort.custom) return base;
    final list = List<AurumPlaylist>.from(base);
    switch (_sort) {
      case _PlaylistSort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _PlaylistSort.dateAdded:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _PlaylistSort.mostPlayed:
        list.sort((a, b) => b.songCount.compareTo(a.songCount));
        break;
      case _PlaylistSort.custom:
        break;
    }
    return PlaylistProvider.pinnedFirst(list);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<PlaylistProvider>(
      builder: (context, pp, _) {
        final tags = pp.allTags;
        final visible = _sorted(pp);
        final canReorder = _sort == _PlaylistSort.custom &&
            _activeTag == null &&
            !_reorderLocked;

        return Scaffold(
          backgroundColor: AurumTheme.bgOf(context),
          bottomNavigationBar: const MiniPlayerSlot(),
          resizeToAvoidBottomInset: false,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            cacheExtent: 1200,
            slivers: [
              SliverAppBar(
                expandedHeight: 110,
                floating: true,
                snap: true,
                backgroundColor: AurumTheme.bgOf(context),
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_rounded,
                      color: AurumTheme.textSecondaryOf(context), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.fromLTRB(52, 0, 20, 16),
                  title: Text(l10n.libraryPlaylists,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AurumTheme.textPrimaryOf(context))),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      _SortDropdown(
                        label: _sortLabel(_sort),
                        onSelected: (s) => setState(() => _sort = s),
                      ),
                      const Spacer(),
                      _ToolbarIconButton(
                        icon: _reorderLocked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        selected: !_reorderLocked,
                        onTap: _sort != _PlaylistSort.custom
                            ? null
                            : () => setState(() => _reorderLocked = !_reorderLocked),
                      ),
                      const SizedBox(width: 8),
                      _PlaylistViewToggle(
                        gridView: _gridView,
                        onChanged: (g) => setState(() => _gridView = g),
                      ),
                      const SizedBox(width: 8),
                      _ImportCoachAnchor(
                        child: _ToolbarIconButton(
                          icon: Icons.cloud_download_outlined,
                          onTap: () => _showImportPlaylistDialog(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ToolbarIconButton(
                        icon: Icons.add_rounded,
                        filled: true,
                        onTap: () => _showCreateDialog(context),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    children: [
                      _TagFilterChip(
                        icon: Icons.filter_alt_rounded,
                        label: AppLocalizations.of(context)!.libraryTagAll,
                        selected: _activeTag == null,
                        onTap: () => setState(() => _activeTag = null),
                      ),
                      const SizedBox(width: 10),
                      for (final tag in tags) ...[
                        _TagFilterChip(
                          label: tag,
                          selected: _activeTag == tag,
                          onTap: () => setState(
                              () => _activeTag = _activeTag == tag ? null : tag),
                        ),
                        const SizedBox(width: 10),
                      ],
                      _TagFilterChip(
                        icon: Icons.add_rounded,
                        label: AppLocalizations.of(context)!.libraryManageTags,
                        selected: false,
                        onTap: () => _showManageTagsSheet(context, pp),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              if (visible.isEmpty)
                SliverFillRemaining(
                  child: _EmptyPlaylists(
                      onCreateTap: () => _showCreateDialog(context)),
                )
              else if (_gridView)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.86,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _PlaylistGridTile(playlist: visible[i]),
                      childCount: visible.length,
                    ),
                  ),
                )
              else if (canReorder)
                SliverReorderableList(
                  itemCount: visible.length,
                  onReorder: (oldIndex, newIndex) {
                    final pinnedCount =
                        visible.where((p) => p.isPinned).length;
                    if (oldIndex < pinnedCount) return;
                    if (newIndex < pinnedCount) newIndex = pinnedCount;
                    AurumHaptics.medium();
                    pp.reorderPlaylist(oldIndex, newIndex);
                  },
                  itemBuilder: (context, i) => _PlaylistListRow(
                    key: ValueKey(visible[i].id),
                    playlist: visible[i],
                    index: i,
                    reorderable: !visible[i].isPinned,
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _PlaylistListRow(
                      key: ValueKey(visible[i].id),
                      playlist: visible[i],
                      index: i,
                      reorderable: false,
                    ),
                    childCount: visible.length,
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    PremiumGate.guard(
      context,
      feature: l10n.libraryCreatePlaylist,
      description: l10n.libraryLoginToOrganizeDesc,
      requiresLoginOnly: true,
      onAllowed: () async {
        await showDialog(
          context: context,
          builder: (_) => _CreatePlaylistDialog(),
        );
      },
    );
  }

  Future<void> _showManageTagsSheet(
      BuildContext context, PlaylistProvider pp) async {
    await showAurumModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ManageTagsSheet(pp: pp),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final String label;
  final ValueChanged<_PlaylistSort> onSelected;
  const _SortDropdown({required this.label, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PlaylistSort>(
      onSelected: onSelected,
      color: AurumTheme.bgCardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (context) => [
        _menuItem(context, _PlaylistSort.custom, AppLocalizations.of(context)!.librarySortCustom),
        _menuItem(context, _PlaylistSort.name, AppLocalizations.of(context)!.librarySortName),
        _menuItem(context, _PlaylistSort.dateAdded, AppLocalizations.of(context)!.librarySortDateAdded),
        _menuItem(context, _PlaylistSort.mostPlayed, AppLocalizations.of(context)!.librarySortMostPlayed),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AurumTheme.bgSurfaceOf(context),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: AurumTheme.textPrimaryOf(context), size: 18),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<_PlaylistSort> _menuItem(
      BuildContext context, _PlaylistSort value, String label) {
    return PopupMenuItem(
      value: value,
      child: Text(label,
          style: TextStyle(color: AurumTheme.textPrimaryOf(context))),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final bool selected;
  final VoidCallback? onTap;
  const _ToolbarIconButton({
    required this.icon,
    this.filled = false,
    this.selected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled || selected
        ? AurumTheme.accentOf(context)
        : AurumTheme.bgSurfaceOf(context);
    final fg = filled || selected ? Colors.white : AurumTheme.textPrimaryOf(context);
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: fg, size: 20),
          ),
        ),
      ),
    );
  }
}

class _PlaylistViewToggle extends StatelessWidget {
  final bool gridView;
  final ValueChanged<bool> onChanged;
  const _PlaylistViewToggle({required this.gridView, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AurumTheme.bgSurfaceOf(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlaylistViewToggleButton(
            icon: Icons.view_list_rounded,
            selected: !gridView,
            onTap: () => onChanged(false),
          ),
          _PlaylistViewToggleButton(
            icon: Icons.grid_view_rounded,
            selected: gridView,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _PlaylistViewToggleButton extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _PlaylistViewToggleButton({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AurumTheme.accentOf(context) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon,
              color: selected ? Colors.white : AurumTheme.textMutedOf(context),
              size: 18),
        ),
      ),
    );
  }
}

class _TagFilterChip extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TagFilterChip({
    this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AurumTheme.accentOf(context) : AurumTheme.bgSurfaceOf(context),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16,
                    color: selected ? Colors.white : AurumTheme.textPrimaryOf(context)),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : AurumTheme.textPrimaryOf(context),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistListRow extends StatefulWidget {
  final AurumPlaylist playlist;
  final int index;
  final bool reorderable;
  const _PlaylistListRow({
    super.key,
    required this.playlist,
    required this.index,
    required this.reorderable,
  });

  @override
  State<_PlaylistListRow> createState() => _PlaylistListRowState();
}

class _PlaylistListRowState extends State<_PlaylistListRow> {
  void _warmCover() {
    final coverArt = widget.playlist.coverArt;
    if (coverArt != null && coverArt.isNotEmpty) {
      ArtworkPaletteCache.warm(coverArt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final index = widget.index;
    final reorderable = widget.reorderable;
    final row = AurumPressable(
      onTap: () {
        _warmCover();
        AurumDepthRoute.to(
          context,
          PlaylistDetailScreen(playlistId: playlist.id),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AurumTheme.textMutedOf(context).withOpacity(0.08),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 60,
                height: 60,
                child: playlist.coverArt == null || playlist.coverArt!.isEmpty
                    ? PlaylistColorCover(
                        artworkUrl: playlist.songs.isNotEmpty
                            ? playlist.songs.first.artworkUrl
                            : '',
                        size: 60,
                        borderRadius: 12,
                      )
                    : AurumArtwork(
                        url: playlist.coverArt!, size: 60, borderRadius: 12),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (playlist.isPinned) ...[
                        Icon(Icons.push_pin_rounded,
                            size: 14, color: AurumTheme.accentOf(context)),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AurumTheme.textPrimaryOf(context),
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        AppLocalizations.of(context)!.libraryTracksCount(playlist.songCount),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AurumTheme.textMutedOf(context), fontSize: 12.5),
                      ),
                      if (playlist.isYtSynced) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AurumTheme.bgSurfaceOf(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(AppLocalizations.of(context)!.libraryYoutubeSynced,
                              style: TextStyle(
                                  color: AurumTheme.textMutedOf(context),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Material(
              color: AurumTheme.accentOf(context),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: playlist.songs.isEmpty
                    ? null
                    : () => context.read<PlayerProvider>().playSong(
                          playlist.songs.first,
                          queue: playlist.songs,
                          index: 0,
                          curatedQueue: true,
                        ),
                child: const Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.more_vert_rounded,
                  color: AurumTheme.textMutedOf(context), size: 20),
              onPressed: () => _showPlaylistMenu(context, playlist),
            ),
            if (reorderable)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.drag_handle_rounded,
                      color: AurumTheme.textMutedOf(context), size: 22),
                ),
              ),
          ],
        ),
      ),
    );
    return row;
  }

  void _showPlaylistMenu(BuildContext context, AurumPlaylist playlist) {
    showAurumModalBottomSheet(
      context: context,
      backgroundColor: AurumTheme.bgCardOf(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                  playlist.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: AurumTheme.accentOf(context)),
              title: Text(playlist.isPinned ? 'Unpin from top' : 'Pin to top',
                  style: TextStyle(color: AurumTheme.textPrimaryOf(context))),
              onTap: () {
                final pp = context.read<PlaylistProvider>();
                Navigator.pop(sheetContext);
                AurumHaptics.medium();
                pp.setPinned(playlist.id, !playlist.isPinned);
              },
            ),
            ListTile(
              leading: Icon(Icons.edit_rounded, color: AurumTheme.accentOf(context)),
              title: Text(AppLocalizations.of(context)!.commonRename, style: TextStyle(color: AurumTheme.textPrimaryOf(context))),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (!context.mounted) return;
                await showDialog(
                  context: context,
                  builder: (_) => _RenamePlaylistDialog(playlist: playlist),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: Text(AppLocalizations.of(context)!.commonDelete, style: TextStyle(color: AurumTheme.textPrimaryOf(context))),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (!context.mounted) return;
                final l10n = AppLocalizations.of(context)!;
                final pp = context.read<PlaylistProvider>();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AurumTheme.bgElevatedOf(context),
                    title: Text(l10n.libraryDeletePlaylistConfirm(playlist.name),
                        style: TextStyle(color: AurumTheme.textPrimaryOf(context))),
                    content: Text(l10n.libraryActionCannotBeUndone,
                        style: TextStyle(color: AurumTheme.textMutedOf(context))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l10n.commonCancel,
                              style: TextStyle(color: AurumTheme.textMutedOf(context)))),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l10n.commonDelete,
                              style: const TextStyle(color: Colors.redAccent))),
                    ],
                  ),
                );
                if (confirmed == true) await pp.deletePlaylist(playlist.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistGridTile extends StatefulWidget {
  final AurumPlaylist playlist;
  const _PlaylistGridTile({required this.playlist});

  @override
  State<_PlaylistGridTile> createState() => _PlaylistGridTileState();
}

class _PlaylistGridTileState extends State<_PlaylistGridTile> {
  void _warmCover() {
    final coverArt = widget.playlist.coverArt;
    if (coverArt != null && coverArt.isNotEmpty) {
      ArtworkPaletteCache.warm(coverArt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    return AurumPressable(
      onTap: () {
        _warmCover();
        AurumDepthRoute.to(
          context,
          PlaylistDetailScreen(playlistId: playlist.id),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  playlist.coverArt == null || playlist.coverArt!.isEmpty
                      ? PlaylistColorCover(
                          artworkUrl: playlist.songs.isNotEmpty
                              ? playlist.songs.first.artworkUrl
                              : '',
                          size: 200,
                          borderRadius: 16,
                        )
                      : AurumArtwork(
                          url: playlist.coverArt!, size: 200, borderRadius: 16),
                  if (playlist.isPinned)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.push_pin_rounded,
                            color: Colors.white, size: 13),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Material(
                      color: AurumTheme.accentOf(context),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: playlist.songs.isEmpty
                            ? null
                            : () => context.read<PlayerProvider>().playSong(
                                  playlist.songs.first,
                                  queue: playlist.songs,
                                  index: 0,
                                  curatedQueue: true,
                                ),
                        child: const Padding(
                          padding: EdgeInsets.all(9),
                          child: Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(AppLocalizations.of(context)!.libraryTracksCount(playlist.songCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ManageTagsSheet extends StatefulWidget {
  final PlaylistProvider pp;
  const _ManageTagsSheet({required this.pp});

  @override
  State<_ManageTagsSheet> createState() => _ManageTagsSheetState();
}

class _ManageTagsSheetState extends State<_ManageTagsSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmPin() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final res = await widget.pp.pinByName(text);
    if (!mounted) return;
    switch (res.status) {
      case PinStatus.pinned:
        AurumHaptics.medium();
        FocusScope.of(context).unfocus();
        Navigator.of(context).pop();
        break;
      case PinStatus.alreadyPinned:
        setState(() => _error = 'Already pinned to the top');
        break;
      case PinStatus.ambiguous:
        setState(() => _error = 'More than one match — type the full name');
        break;
      case PinStatus.notFound:
        setState(() => _error = 'No playlist found with that name');
        break;
    }
  }

  Future<void> _pinPlaylist(AurumPlaylist pl) async {
    AurumHaptics.medium();
    await widget.pp.setPinned(pl.id, true);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final muted = AurumTheme.textMutedOf(context);
    final primary = AurumTheme.textPrimaryOf(context);
    final accent = AurumTheme.accentOf(context);
    return AnimatedBuilder(
      animation: widget.pp,
      builder: (context, _) {
        final tags = widget.pp.allTags;
        final pinned = widget.pp.pinnedPlaylists;
        final q = _controller.text.trim().toLowerCase();
        final suggestions = q.isEmpty
            ? const <AurumPlaylist>[]
            : widget.pp.playlists
                .where((p) => !p.isPinned && p.name.toLowerCase().contains(q))
                .take(4)
                .toList();
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                color: AurumTheme.bgCardOf(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context)!.libraryManageTags,
                        style: TextStyle(
                            color: primary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in tags)
                            Chip(
                              label: Text(tag, style: TextStyle(color: primary)),
                              backgroundColor: AurumTheme.bgSurfaceOf(context),
                              deleteIcon:
                                  const Icon(Icons.close_rounded, size: 16),
                              onDeleted: () =>
                                  widget.pp.deleteTagEverywhere(tag),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Icon(Icons.push_pin_rounded, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Text('Pin to top',
                            style: TextStyle(
                                color: primary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                        'Type a playlist name and confirm — it stays at the top, always.',
                        style: TextStyle(color: muted, fontSize: 12.5)),
                    if (pinned.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final pl in pinned)
                            Chip(
                              avatar: Icon(Icons.push_pin_rounded,
                                  size: 14, color: accent),
                              label: Text(pl.name,
                                  style: TextStyle(color: primary)),
                              backgroundColor: AurumTheme.bgSurfaceOf(context),
                              deleteIcon:
                                  const Icon(Icons.close_rounded, size: 16),
                              onDeleted: () =>
                                  widget.pp.setPinned(pl.id, false),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            style: TextStyle(color: primary),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _confirmPin(),
                            onChanged: (_) => setState(() => _error = null),
                            decoration: InputDecoration(
                              hintText: 'Playlist name',
                              hintStyle: TextStyle(color: muted),
                              filled: true,
                              fillColor: AurumTheme.bgSurfaceOf(context),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Material(
                          color: accent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: _confirmPin,
                            child: const Padding(
                              padding: EdgeInsets.all(14),
                              child: Icon(Icons.check_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12.5)),
                    ],
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final pl in suggestions)
                            ActionChip(
                              label: Text(pl.name,
                                  style: TextStyle(color: primary)),
                              backgroundColor: AurumTheme.bgSurfaceOf(context),
                              onPressed: () => _pinPlaylist(pl),
                            ),
                        ],
                      ),
                    ],
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

class _ImportCoachAnchor extends StatelessWidget {
  final Widget child;
  const _ImportCoachAnchor({required this.child});

  @override
  Widget build(BuildContext context) {
    return AurumCoachTip(
      prefKey: 'import_playlist_promo_seen_v2',
      icon: Icons.cloud_download_rounded,
      title: 'Import playlist',
      message: 'Spotify, YouTube & more — just in sec',
      promo: AurumPromoData.importPlaylist,
      onPromoAction: () => _showImportPlaylistDialog(context),
      enabled: () => true,
      child: child,
    );
  }
}

const Color _kPlaylistFallbackGlow = Color(0xFF1A1630);
const Duration _kPlaylistGlowDuration = Duration(milliseconds: 420);

Color _playlistPosterColor(String id) {
  var h = 7;
  for (final u in id.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1.0, (h % 360).toDouble(), 0.58, 0.42).toColor();
}

String _playlistHeaderArtUrl(String url) {
  if (url.isEmpty) return url;
  return AurumArtwork.upgradeForFullPlayer(url);
}

String _playlistCreatedLine(DateTime created) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  final d = created.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return 'Created at $hh:$mm - ${d.day} ${months[d.month - 1]} ${d.year}';
}

class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  bool _reordering = false;

  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _stretch = ValueNotifier<double>(0);

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final o = _scroll.offset;
    final st = o < 0 ? -o : 0.0;
    if (_stretch.value != st) _stretch.value = st;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _stretch.dispose();
    super.dispose();
  }

  Color _glowTarget = _kPlaylistFallbackGlow;
  String? _glowArt;
  bool _inited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    final pl = context.read<PlaylistProvider>().getById(widget.playlistId);
    if (pl != null) _precacheHeader(pl.coverArt ?? '');
  }

  void _precacheHeader(String art) {
    if (art.isEmpty || art.startsWith('content://')) return;
    final ImageProvider provider;
    if (art.startsWith('/') || art.startsWith('file://')) {
      final path =
          art.startsWith('file://') ? art.replaceFirst('file://', '') : art;
      provider = ResizeImage(FileImage(File(path)), width: 1200);
    } else {
      provider = CachedNetworkImageProvider(
        _playlistHeaderArtUrl(art),
        maxWidth: 1200,
        cacheManager: AurumImageCache(),
      );
    }
    precacheImage(provider, context).catchError((_) {});
  }

  void _ensureGlow(AurumPlaylist pl) {
    final art = pl.coverArt ?? '';
    if (art == _glowArt) return;
    _glowArt = art;
    if (art.isEmpty) {
      _glowTarget = _playlistPosterColor(pl.id);
      return;
    }
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cached = ArtworkPaletteCache.peek(art);
    if (cached != null) {
      _glowTarget = ensureContrastSafe(cached.darkMuted, isLight: isLight);
      return;
    }
    unawaited(_resolveGlow(art, isLight));
  }

  Future<void> _resolveGlow(String art, bool isLight) async {
    await _routeSettled();
    if (!mounted || _glowArt != art) return;
    final c = await extractImmersiveColor(art);
    if (!mounted || c == null || _glowArt != art) return;
    final safe = ensureContrastSafe(c, isLight: isLight);
    if (safe.value == _glowTarget.value) return;
    setState(() => _glowTarget = safe);
  }

  Future<void> _routeSettled() async {
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.status == AnimationStatus.completed) return;
    final done = Completer<void>();
    void listener(AnimationStatus s) {
      if ((s == AnimationStatus.completed || s == AnimationStatus.dismissed) &&
          !done.isCompleted) {
        done.complete();
      }
    }

    anim.addStatusListener(listener);
    try {
      await done.future.timeout(const Duration(milliseconds: 900));
    } on TimeoutException {
    } finally {
      anim.removeStatusListener(listener);
    }
  }

  void _enterSelectMode(String firstSongId) {
    if (_reordering) return;
    AurumHaptics.medium();
    setState(() {
      _selecting = true;
      _selectedIds
        ..clear()
        ..add(firstSongId);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String songId) {
    AurumHaptics.selection();
    setState(() {
      if (!_selectedIds.remove(songId)) {
        _selectedIds.add(songId);
      }
      if (_selectedIds.isEmpty) _selecting = false;
    });
  }

  Future<void> _changeCover(AurumPlaylist pl) async {
    final provider = context.read<PlaylistProvider>();
    final l10n = AppLocalizations.of(context)!;
    AurumHaptics.selection();

    final action = await showAurumModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AurumTheme.bgElevatedOf(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AurumTheme.textMutedOf(ctx).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.photo_library_rounded,
                    color: AurumTheme.accentOf(ctx)),
                title: Text(l10n.libraryChooseFromGallery,
                    style: TextStyle(
                        color: AurumTheme.textPrimaryOf(ctx),
                        fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx, 'pick'),
              ),
              if (pl.hasCustomCover)
                ListTile(
                  leading:
                      const Icon(Icons.restore_rounded, color: Colors.redAccent),
                  title: Text(l10n.libraryRemoveCustomCover,
                      style: TextStyle(
                          color: AurumTheme.textPrimaryOf(ctx),
                          fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (action == 'pick') {
      try {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 92,
          maxWidth: 1200,
          maxHeight: 1200,
        );
        if (picked != null) {
          await provider.setCoverImage(pl.id, picked.path);
        }
      } catch (e) {
        debugPrint('[PlaylistDetail] cover pick failed: $e');
        if (mounted) AurumSnack.show(context, 'Could not set cover');
      }
    } else if (action == 'remove') {
      await provider.clearCoverImage(pl.id);
    }
  }

  void _showRowMenu(AurumPlaylist pl, Song song, int index) {
    final l10n = AppLocalizations.of(context)!;
    AurumHaptics.light();
    showAurumModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black54,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AurumTheme.bgElevatedOf(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AurumTheme.textMutedOf(ctx).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    AurumWideThumb(
                      url: song.artworkUrl,
                      width: 80,
                      height: 45,
                      borderRadius: 6,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AurumTheme.textPrimaryOf(ctx),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AurumTheme.textSecondaryOf(ctx),
                                  fontSize: 13.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  thickness: 0.6,
                  color: AurumTheme.textMutedOf(ctx).withOpacity(0.18)),
              ListTile(
                leading: Icon(Icons.check_circle_outline_rounded,
                    color: AurumTheme.accentOf(ctx)),
                title: Text(l10n.libraryEnterSelectMode,
                    style: TextStyle(color: AurumTheme.textPrimaryOf(ctx))),
                onTap: () {
                  Navigator.pop(ctx);
                  _enterSelectMode(song.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded,
                    color: Colors.redAccent),
                title: Text(l10n.libraryRemoveFromPlaylist,
                    style: TextStyle(color: AurumTheme.textPrimaryOf(ctx))),
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<PlaylistProvider>().removeSong(pl.id, song.id);
                },
              ),
              ListTile(
                leading: Icon(Icons.more_horiz_rounded,
                    color: AurumTheme.textSecondaryOf(ctx)),
                title: Text('More options',
                    style: TextStyle(color: AurumTheme.textPrimaryOf(ctx))),
                onTap: () {
                  Navigator.pop(ctx);
                  showAurumSongOptions(context, song, compact: true);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pp = context.watch<PlaylistProvider>();
    final pl = pp.getById(widget.playlistId);

    if (pl == null) {
      return Scaffold(
        backgroundColor: immersiveScaffoldBg(context, _glowTarget),
        bottomNavigationBar: const MiniPlayerSlot(),
        body: Center(
          child: Text(l10n.libraryPlaylistNotFound,
              style: TextStyle(color: AurumTheme.textMutedOf(context))),
        ),
      );
    }

    if (_selecting) {
      final validIds = pl.songs.map((s) => s.id).toSet();
      _selectedIds.removeWhere((id) => !validIds.contains(id));
      if (_selectedIds.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selecting = false);
        });
      }
    }

    _ensureGlow(pl);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = immersiveScaffoldBg(context, _glowTarget);
    final headerH = MediaQuery.sizeOf(context).width * 1.04;
    final songs = pl.songs;
    final duration = pl.totalDurationString;
    final summary = '${songs.length} ${songs.length == 1 ? 'track' : 'tracks'}'
        '${duration.isNotEmpty ? ' • $duration' : ''}';

    final rowKeys = List<String>.filled(songs.length, '');
    final indexByKey = <String, int>{};
    final seenIds = <String, int>{};
    for (var i = 0; i < songs.length; i++) {
      final id = songs[i].id;
      final n = seenIds.update(id, (v) => v + 1, ifAbsent: () => 0);
      final k = n == 0 ? id : '$id#$n';
      rowKeys[i] = k;
      indexByKey[k] = i;
    }

    final scroll = CustomScrollView(
      controller: _scroll,
      cacheExtent: 500,
      slivers: [
        if (_selecting)
          _SelectModeAppBar(
            background: bg,
            selectedCount: _selectedIds.length,
            totalCount: songs.map((s) => s.id).toSet().length,
            allSelected:
                _selectedIds.length == songs.map((s) => s.id).toSet().length,
            onClose: _exitSelectMode,
            onToggleSelectAll: () {
              AurumHaptics.light();
              setState(() {
                if (_selectedIds.length == songs.map((s) => s.id).toSet().length) {
                  _selectedIds.clear();
                } else {
                  _selectedIds
                    ..clear()
                    ..addAll(songs.map((s) => s.id));
                }
              });
            },
            onRemove: () => _confirmRemoveSelected(context, pl),
          )
        else ...[
          SliverToBoxAdapter(
            child: _PlaylistHeader(
              playlist: pl,
              height: headerH,
              stretch: _stretch,
              bg: bg,
              poster: _playlistPosterColor(pl.id),
              onBack: () {
                AurumHaptics.selection();
                Navigator.pop(context);
              },
              onEditCover: () => _changeCover(pl),
              onMore: () => _showPlaylistOptions(context, pl),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: _PlaylistActionRow(playlist: pl),
            ),
          ),
        ],

        if (songs.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
              child: Text(
                summary,
                style: TextStyle(
                  color: AurumTheme.textSecondaryOf(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

        if (_reordering && songs.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Drag the handles to reorder',
                      style: TextStyle(
                        color: AurumTheme.textMutedOf(context),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      AurumHaptics.selection();
                      setState(() => _reordering = false);
                    },
                    child: Text('Done',
                        style: TextStyle(
                            color: AurumTheme.accentOf(context),
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),

        if (songs.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 36, 40, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    summary,
                    style: TextStyle(
                      color: AurumTheme.textSecondaryOf(context),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AurumTheme.accentOf(context).withOpacity(0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AurumTheme.accentOf(context).withOpacity(0.30)),
                    ),
                    child: Icon(Icons.music_note_rounded,
                        color: AurumTheme.accentOf(context), size: 36),
                  ),
                  const SizedBox(height: 20),
                  Text(l10n.libraryNoSongsYetInPlaylist,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(l10n.librarySearchAndAddSongsHere,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AurumTheme.textMutedOf(context),
                          fontSize: 13,
                          height: 1.5)),
                ],
              ),
            ),
          )
        else if (_reordering)
          SliverReorderableList(
            itemCount: songs.length,
            onReorder: (oldIdx, newIdx) {
              if (_selecting) return;
              context
                  .read<PlaylistProvider>()
                  .reorderSong(pl.id, oldIdx, newIdx);
            },
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = Curves.easeOut.transform(animation.value);
                  return Transform.scale(
                    scale: 1.0 + (0.03 * t),
                    child: Material(
                      color: Colors.transparent,
                      elevation: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AurumTheme.bgCardOf(context),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.28 * t),
                              blurRadius: 20 * t,
                              offset: Offset(0, 6 * t),
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    ),
                  );
                },
                child: child,
              );
            },
            itemBuilder: (context, i) {
              final song = songs[i];
              return KeyedSubtree(
                key: ValueKey('${pl.id}_${song.id}_$i'),
                child: _PlaylistTrackRow(
                  song: song,
                  playlist: pl,
                  index: i,
                  selecting: _selecting,
                  selected: _selectedIds.contains(song.id),
                  reordering: true,
                  onEnterSelectMode: () => _enterSelectMode(song.id),
                  onToggleSelected: () => _toggleSelected(song.id),
                  onMenu: () => _showRowMenu(pl, song, i),
                ),
              );
            },
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final song = songs[i];
                return _PlaylistTrackRow(
                  key: ValueKey(rowKeys[i]),
                  song: song,
                  playlist: pl,
                  index: i,
                  selecting: _selecting,
                  selected: _selectedIds.contains(song.id),
                  reordering: false,
                  onEnterSelectMode: () => _enterSelectMode(song.id),
                  onToggleSelected: () => _toggleSelected(song.id),
                  onMenu: () => _showRowMenu(pl, song, i),
                );
              },
              childCount: songs.length,
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) return null;
                return indexByKey[key.value];
              },
              addRepaintBoundaries: false,
              addAutomaticKeepAlives: false,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );

    final scaffold = PopScope(
      canPop: !_selecting && !_reordering,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _exitSelectMode();
        } else if (_reordering) {
          setState(() => _reordering = false);
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        bottomNavigationBar: const MiniPlayerSlot(),
        body: _PlaylistAnimatedBg(color: bg, child: scroll),
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

  Future<void> _confirmRemoveSelected(
      BuildContext context, AurumPlaylist pl) async {
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AurumTheme.bgElevatedOf(context),
        title: Text(l10n.libraryRemoveSelectedFromPlaylist,
            style: TextStyle(color: AurumTheme.textPrimaryOf(context))),
        content: Text(l10n.libraryRemoveSelectedConfirm(count),
            style: TextStyle(color: AurumTheme.textMutedOf(context))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel,
                  style:
                      TextStyle(color: AurumTheme.textMutedOf(context)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.libraryRemoveSelectedFromPlaylist,
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final ids = Set<String>.from(_selectedIds);
      await context.read<PlaylistProvider>().removeSongs(pl.id, ids);
      if (mounted) {
        setState(() {
          _selecting = false;
          _selectedIds.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.libraryRemovedSongsFromPlaylist(ids.length)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AurumTheme.bgElevatedOf(context),
          ),
        );
      }
    }
  }

  void _showPlaylistOptions(BuildContext context, AurumPlaylist pl) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    showAurumModalBottomSheet(
      context: context,
      backgroundColor:
          isLight ? AurumTheme.bgCardOf(context) : AurumTheme.darkBgElevated,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AurumTheme.textMutedOf(context).withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading:
                  Icon(Icons.edit_rounded, color: AurumTheme.accentOf(context)),
              title: Text(l10n.libraryRenamePlaylist,
                  style:
                      TextStyle(color: AurumTheme.textPrimaryOf(context))),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, pl);
              },
            ),
            if (pl.songs.isNotEmpty)
              Builder(builder: (ctx2) {
                final dl = ctx2.watch<DownloadProvider>();
                final allDownloaded =
                    pl.songs.every((s) => dl.isDownloaded(s.id));
                final downloading = dl.isPlaylistDownloading(pl.id);
                if (allDownloaded) return const SizedBox.shrink();
                return ListTile(
                  leading: downloading
                      ? SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AurumTheme.accentOf(context),
                            value: () {
                              final (done, total) =
                                  dl.playlistDownloadProgress(pl.songs);
                              return total == 0 ? null : done / total;
                            }(),
                          ),
                        )
                      : Icon(Icons.download_rounded,
                          color: AurumTheme.accentOf(context)),
                  title: Text(
                    downloading
                        ? l10n.libraryDownloadingPlaylist
                        : l10n.libraryDownloadPlaylist,
                    style:
                        TextStyle(color: AurumTheme.textPrimaryOf(context)),
                  ),
                  onTap: downloading
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          context.read<DownloadProvider>().downloadPlaylist(
                                playlistId: pl.id,
                                songs: pl.songs,
                              );
                        },
                );
              }),
            if (pl.songs.length > 1)
              ListTile(
                leading: Icon(Icons.swap_vert_rounded,
                    color: AurumTheme.accentOf(context)),
                title: Text('Reorder songs',
                    style:
                        TextStyle(color: AurumTheme.textPrimaryOf(context))),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _selecting = false;
                    _selectedIds.clear();
                    _reordering = true;
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent),
              title: Text(l10n.libraryDeletePlaylist,
                  style: const TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, pl);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context, AurumPlaylist pl) async {
    await showDialog(
      context: context,
      builder: (_) => _RenamePlaylistDialog(playlist: pl),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AurumPlaylist pl) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AurumTheme.bgElevatedOf(context),
        title: Text(l10n.libraryDeletePlaylistConfirm(pl.name),
            style: TextStyle(color: AurumTheme.textPrimaryOf(context))),
        content: Text(l10n.libraryActionCannotBeUndone,
            style: TextStyle(color: AurumTheme.textMutedOf(context))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel,
                  style: TextStyle(
                      color: AurumTheme.textMutedOf(context)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.commonDelete,
                  style: const TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final pp = context.read<PlaylistProvider>();
      Navigator.pop(context);
      await pp.deletePlaylist(pl.id);
    }
  }
}

class _SelectModeAppBar extends StatelessWidget {
  final Color background;
  final int selectedCount;
  final int totalCount;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onRemove;

  const _SelectModeAppBar({
    required this.background,
    required this.selectedCount,
    required this.totalCount,
    required this.allSelected,
    required this.onClose,
    required this.onToggleSelectAll,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SliverAppBar(
      pinned: true,
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close_rounded,
            color: AurumTheme.textSecondaryOf(context), size: 22),
        onPressed: onClose,
      ),
      title: Text(
        l10n.librarySelectedCount(selectedCount),
        style: TextStyle(
          color: AurumTheme.textPrimaryOf(context),
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        TextButton(
          onPressed: onToggleSelectAll,
          child: Text(
            allSelected ? l10n.libraryDeselectAll : l10n.librarySelectAll,
            style: TextStyle(
              color: AurumTheme.accentOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline_rounded,
              color: selectedCount == 0
                  ? AurumTheme.textMutedOf(context).withOpacity(0.4)
                  : Colors.redAccent),
          onPressed: selectedCount == 0 ? null : onRemove,
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: AurumTheme.textMutedOf(context).withOpacity(0.1),
        ),
      ),
    );
  }
}

class _PlaylistAnimatedBg extends StatelessWidget {
  final Color color;
  final Widget child;
  const _PlaylistAnimatedBg({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: color, end: color),
      duration: _kPlaylistGlowDuration,
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, c, child) =>
          ColoredBox(color: c ?? color, child: child),
    );
  }
}

class _PlaylistHeaderFade extends StatelessWidget {
  final Color bg;
  const _PlaylistHeaderFade({required this.bg});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: bg, end: bg),
      duration: _kPlaylistGlowDuration,
      curve: Curves.easeOutCubic,
      builder: (context, c, _) {
        final b = c ?? bg;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                b.withOpacity(0.0),
                b.withOpacity(0.0),
                b.withOpacity(0.55),
                b.withOpacity(0.92),
                b,
              ],
              stops: const [0.0, 0.40, 0.62, 0.82, 1.0],
            ),
          ),
        );
      },
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  final AurumPlaylist playlist;
  final double height;
  final ValueNotifier<double> stretch;
  final Color bg;
  final Color poster;
  final VoidCallback onBack;
  final VoidCallback onEditCover;
  final VoidCallback onMore;

  const _PlaylistHeader({
    required this.playlist,
    required this.height,
    required this.stretch,
    required this.bg,
    required this.poster,
    required this.onBack,
    required this.onEditCover,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topInset = MediaQuery.paddingOf(context).top;
    final art = playlist.coverArt ?? '';
    final titleColor = isDark ? Colors.white : AurumTheme.textPrimaryOf(context);
    final subColor = isDark
        ? Colors.white.withOpacity(0.72)
        : AurumTheme.textSecondaryOf(context);
    final description = playlist.description.trim();

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onEditCover,
              child: ValueListenableBuilder<double>(
                valueListenable: stretch,
                builder: (context, st, child) => Transform.scale(
                  scale: 1 + (st / height),
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
                child: RepaintBoundary(
                  child: art.isNotEmpty
                      ? _PlaylistHeaderArt(url: art)
                      : _PlaylistPoster(color: poster),
                ),
              ),
            ),
          ),

          ValueListenableBuilder<double>(
            valueListenable: stretch,
            builder: (context, st, child) => Positioned(
              top: -st,
              left: 0,
              right: 0,
              height: topInset + 90,
              child: child!,
            ),
            child: IgnorePointer(
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
          ),

          Positioned.fill(
            child: IgnorePointer(child: _PlaylistHeaderFade(bg: bg)),
          ),

          Positioned(
            left: 24,
            right: 24,
            bottom: 14,
            child: IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subColor,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    playlist.isYtSynced ? 'YouTube Playlist' : 'Your Playlist',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: subColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _playlistCreatedLine(playlist.createdAt),
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
          ),

          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PlGlassPill(
                    width: 44,
                    child: _PlGlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: onBack,
                    ),
                  ),
                  _PlGlassPill(
                    width: 88,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _PlGlassIconButton(
                          icon: Icons.add_photo_alternate_rounded,
                          onTap: onEditCover,
                        ),
                        _PlGlassIconButton(
                          icon: Icons.more_vert_rounded,
                          onTap: onMore,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistHeaderArt extends StatelessWidget {
  final String url;
  const _PlaylistHeaderArt({required this.url});

  @override
  Widget build(BuildContext context) {
    final hi = _playlistHeaderArtUrl(url);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(
        key: ValueKey(url),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AurumArtwork(
              url: hi,
              size: double.infinity,
              borderRadius: 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistPoster extends StatelessWidget {
  final Color color;
  const _PlaylistPoster({required this.color});

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final top = hsl
        .withLightness((hsl.lightness + 0.10).clamp(0.0, 0.85))
        .toColor();
    final bottom = hsl
        .withLightness((hsl.lightness * 0.62).clamp(0.0, 1.0))
        .toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, color, bottom],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, -0.7),
                radius: 1.1,
                colors: [
                  Colors.white.withOpacity(0.20),
                  Colors.white.withOpacity(0.0),
                ],
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.30),
            child: Icon(
              Icons.queue_music_rounded,
              size: 96,
              color: Colors.white.withOpacity(0.90),
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlGlassPill extends StatelessWidget {
  final Widget child;
  final double width;
  const _PlGlassPill({required this.child, required this.width});

  static const double _height = 44;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: _height,
      child: AurumGlass(
        sigma: 6,
        borderRadius: BorderRadius.circular(_height / 2),
        isDark: true,
        child: SizedBox(width: width, height: _height, child: child),
      ),
    );
  }
}

class _PlGlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _PlGlassIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        icon: Icon(icon, size: 21, color: Colors.white),
        splashRadius: 20,
        onPressed: onTap,
      ),
    );
  }
}

class _PlRoundButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _PlRoundButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AurumPressable(
      scaleAmount: 0.9,
      onTap: onTap == null
          ? null
          : () {
              AurumHaptics.selection();
              onTap!();
            },
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (isDark ? Colors.white : Colors.black)
              .withOpacity(isDark ? 0.12 : 0.07),
        ),
        child: child,
      ),
    );
  }
}

class _PlaylistActionRow extends StatelessWidget {
  final AurumPlaylist playlist;
  const _PlaylistActionRow({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final songs = playlist.songs;
    final empty = songs.isEmpty;
    final fg = AurumTheme.textPrimaryOf(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PlRoundButton(
          onTap: empty
              ? null
              : () {
                  final queue = List<Song>.from(songs)..shuffle();
                  context.read<PlayerProvider>().playSong(queue.first,
                      queue: queue, index: 0, curatedQueue: true);
                },
          child: Icon(Icons.shuffle_rounded,
              size: 22, color: empty ? fg.withOpacity(0.35) : fg),
        ),
        const SizedBox(width: 12),
        AurumPressable(
          scaleAmount: 0.95,
          onTap: empty
              ? null
              : () {
                  AurumHaptics.medium();
                  context.read<PlayerProvider>().playSong(songs.first,
                      queue: songs, index: 0, curatedQueue: true);
                },
          child: Container(
            height: 46,
            constraints: const BoxConstraints(minWidth: 112),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : const Color(0xFF111111))
                  .withOpacity(empty ? 0.4 : 1.0),
              borderRadius: BorderRadius.circular(23),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded,
                    color: isDark ? Colors.black : Colors.white, size: 24),
                const SizedBox(width: 6),
                Text(
                  l10n.commonPlay,
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
        _PlaylistDownloadButton(playlist: playlist),
      ],
    );
  }
}

class _PlaylistDownloadButton extends StatelessWidget {
  final AurumPlaylist playlist;
  const _PlaylistDownloadButton({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final songs = playlist.songs;
    final st = context.select<DownloadProvider, (bool, bool, int, int)>((d) {
      final downloading = d.isPlaylistDownloading(playlist.id);
      final (done, total) = d.playlistDownloadProgress(songs);
      final allDone =
          songs.isNotEmpty && songs.every((s) => d.isDownloaded(s.id));
      return (allDone, downloading, done, total);
    });
    final (allDone, downloading, done, total) = st;
    final fg = AurumTheme.textPrimaryOf(context);
    final l10n = AppLocalizations.of(context)!;

    final Widget icon;
    if (downloading) {
      icon = SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: fg,
          value: total == 0 ? null : done / total,
        ),
      );
    } else if (allDone) {
      icon = Icon(Icons.download_done_rounded, size: 26, color: fg);
    } else {
      icon = Icon(
        Icons.download_for_offline_outlined,
        size: 26,
        color: songs.isEmpty ? fg.withOpacity(0.35) : fg,
      );
    }

    return _PlRoundButton(
      onTap: songs.isEmpty
          ? null
          : () {
              if (downloading) {
                AurumDepthRoute.to(context, const DownloadsScreen());
              } else if (allDone) {
                AurumSnack.show(context, 'Already downloaded');
              } else {
                context.read<DownloadProvider>().downloadPlaylist(
                      playlistId: playlist.id,
                      songs: songs,
                    );
                AurumSnack.show(context, l10n.libraryDownloadingPlaylist);
              }
            },
      child: icon,
    );
  }
}

class _PlaylistTrackRow extends StatefulWidget {
  final Song song;
  final AurumPlaylist playlist;
  final int index;
  final bool selecting;
  final bool selected;
  final bool reordering;
  final VoidCallback onEnterSelectMode;
  final VoidCallback onToggleSelected;
  final VoidCallback onMenu;

  const _PlaylistTrackRow({
    super.key,
    required this.song,
    required this.playlist,
    required this.index,
    required this.selecting,
    required this.selected,
    required this.reordering,
    required this.onEnterSelectMode,
    required this.onToggleSelected,
    required this.onMenu,
  });

  @override
  State<_PlaylistTrackRow> createState() => _PlaylistTrackRowState();
}

class _PlaylistTrackRowState extends State<_PlaylistTrackRow> {
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
    final playState = context.select<PlayerProvider, int>((p) =>
        p.currentSong?.id != song.id ? 0 : (p.isPlaying ? 2 : 1));
    final isCurrent = playState != 0;
    final isActive = playState == 2;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AurumTheme.accentOf(context);
    final ink = (isDark ? Colors.white : Colors.black);

    return RepaintBoundary(
      child: ColoredBox(
        color: widget.selected ? accent.withOpacity(0.10) : Colors.transparent,
        child: InkWell(
          onTap: widget.reordering
              ? null
              : () {
            if (widget.selecting) {
              widget.onToggleSelected();
              return;
            }
            AurumHaptics.light();
            context
                .read<PlayerProvider>()
                .playSong(
                  song,
                  queue: widget.playlist.songs,
                  index: widget.index,
                  curatedQueue: true,
                )
                .catchError((e) {
              debugPrint('[_PlaylistTrackRow] playSong error: $e');
            });
          },
          onLongPress: (widget.selecting || widget.reordering)
              ? null
              : widget.onEnterSelectMode,
          splashColor: ink.withValues(alpha: 0.06),
          highlightColor: ink.withValues(alpha: 0.04),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 9, 4, 9),
                child: Row(
                  children: [
                    if (widget.selecting)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _PlaylistCheck(selected: widget.selected),
                      ),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        AurumWideThumb(
                          url: song.artworkUrl,
                          width: 80,
                          height: 45,
                          borderRadius: 6,
                        ),
                        if (isCurrent)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: AurumEqualizerBars(
                                  playing: isActive,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isCurrent
                                  ? accent
                                  : AurumTheme.textPrimaryOf(context),
                              fontSize: 16,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AurumTheme.textSecondaryOf(context),
                              fontSize: 13.5,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.reordering)
                      ReorderableDragStartListener(
                        index: widget.index,
                        child: SizedBox(
                          width: 56,
                          height: 44,
                          child: Icon(
                            Icons.drag_handle_rounded,
                            size: 24,
                            color: AurumTheme.textSecondaryOf(context),
                          ),
                        ),
                      )
                    else if (!widget.selecting) ...[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onMenu,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.more_vert_rounded,
                            size: 22,
                            color: AurumTheme.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    ] else
                      const SizedBox(width: 16),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                    left: widget.selecting ? 150 : 114, right: 16),
                child: Divider(
                  height: 1,
                  thickness: 0.6,
                  color: ink.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistCheck extends StatelessWidget {
  final bool selected;
  const _PlaylistCheck({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AurumMotion.durationOrZero(AurumMotion.short2),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: selected ? AurumTheme.accentGradientOf(context) : null,
        color: selected ? null : Colors.transparent,
        border: Border.all(
          color: selected
              ? Colors.transparent
              : AurumTheme.textMutedOf(context).withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded,
              size: 16, color: AurumTheme.bgOf(context))
          : null,
    );
  }
}

class _EmptyPlaylists extends StatelessWidget {
  final VoidCallback onCreateTap;
  const _EmptyPlaylists({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purpleAccent.withOpacity(0.15),
                    AurumTheme.accentOf(context).withOpacity(0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.purpleAccent.withOpacity(0.25), width: 1.5),
              ),
              child: const Icon(Icons.queue_music_rounded,
                  color: Colors.purpleAccent, size: 48),
            ),
            const SizedBox(height: 24),
            Text(l10n.libraryNoPlaylistsYet,
                style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              l10n.libraryCreateFirstPlaylistDesc,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AurumTheme.textMutedOf(context),
                  fontSize: 14,
                  height: 1.6),
            ),
            const SizedBox(height: 32),
            AurumPressable(
              onTap: onCreateTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 36, vertical: 15),
                decoration: BoxDecoration(
                  gradient: AurumTheme.accentGradientOf(context),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: AurumTheme.accentOf(context).withOpacity(0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded,
                        color: AurumTheme.bgOf(context), size: 20),
                    const SizedBox(width: 8),
                    Text(l10n.libraryCreatePlaylist,
                        style: TextStyle(
                            color: AurumTheme.bgOf(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () => _showImportPlaylistDialog(context),
              icon: Icon(Icons.cloud_download_outlined,
                  size: 18, color: AurumTheme.accentOf(context)),
              label: Text(l10n.libraryImportPlaylist,
                  style: TextStyle(
                      color: AurumTheme.accentOf(context),
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  final Song? initialSong;
  const _CreatePlaylistDialog({this.initialSong});

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AurumTheme.bgElevatedOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      scrollable: true,
      title: Text(l10n.libraryNewPlaylist,
          style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AurumFocusField(
            builder: (focusNode) => _AurumTextField(
              controller: _nameCtrl,
              focusNode: focusNode,
              label: l10n.libraryPlaylistNameLabel,
            ),
          ),
          const SizedBox(height: 12),
          _AurumTextField(
            controller: _descCtrl,
            label: l10n.libraryDescriptionOptionalLabel,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel,
              style:
                  TextStyle(color: AurumTheme.textMutedOf(context))),
        ),
        AurumPressable(
          onTap: _creating ? null : () => _create(l10n),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: AurumTheme.accentGradientOf(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: _creating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: Center(child: AurumM3Loader(width: 16, height: 2)))
                : Text(l10n.commonCreate,
                    style: TextStyle(
                        color: AurumTheme.bgOf(context),
                        fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Future<void> _create(AppLocalizations l10n) async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _nameCtrl.text = l10n.libraryDefaultPlaylistName;
    }
    setState(() => _creating = true);
    final AurumPlaylist pl;
    try {
      pl = await context.read<PlaylistProvider>().createPlaylist(
            name: _nameCtrl.text.trim().isEmpty
                ? l10n.libraryDefaultPlaylistName
                : _nameCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            initialSong: widget.initialSong,
          );
    } catch (_) {
      if (mounted) setState(() => _creating = false);
      return;
    }
    if (mounted) {
      Navigator.pop(context);
      AurumDepthRoute.to(
        context,
        PlaylistDetailScreen(playlistId: pl.id),
      );
    }
  }
}

Future<void> _showImportPlaylistDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  PremiumGate.guard(
    context,
    feature: l10n.libraryImportPlaylist,
    description: l10n.libraryLoginToOrganizeDesc,
    requiresLoginOnly: true,
    onAllowed: () async {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ImportPlaylistDialog(hostContext: context),
      );
    },
  );
}

enum _ImportStage { idle, working, done }

class _ImportPlaylistDialog extends StatefulWidget {
  final BuildContext hostContext;
  const _ImportPlaylistDialog({required this.hostContext});

  @override
  State<_ImportPlaylistDialog> createState() => _ImportPlaylistDialogState();
}

class _ImportPlaylistDialogState extends State<_ImportPlaylistDialog> {
  final _linkCtrl = TextEditingController();
  _ImportStage _stage = _ImportStage.idle;
  String? _errorText;
  PlaylistImportProgress? _progress;
  PlaylistImportResult? _result;
  String? _playlistId;
  ImportCancelToken? _cancel;
  PlaylistImportSource? _detected;

  @override
  void initState() {
    super.initState();
    _linkCtrl.addListener(_onLinkChanged);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _linkCtrl.removeListener(_onLinkChanged);
    _linkCtrl.dispose();
    super.dispose();
  }

  void _onLinkChanged() {
    final d = PlaylistImportService.detect(_linkCtrl.text);
    if (d != _detected || _errorText != null) {
      setState(() {
        _detected = d;
        _errorText = null;
      });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _linkCtrl.text = text;
    _linkCtrl.selection = TextSelection.collapsed(offset: text.length);
  }

  String _errorMessage(AppLocalizations l10n, PlaylistImportError e) {
    switch (e) {
      case PlaylistImportError.invalidLink:
        return l10n.libraryImportInvalidLinkError;
      case PlaylistImportError.unsupportedLink:
        return l10n.libraryImportUnsupportedLinkError;
      case PlaylistImportError.isMix:
        return l10n.libraryYoutubeImportMixError;
      case PlaylistImportError.notFound:
        return l10n.libraryImportNotFoundError;
      case PlaylistImportError.empty:
        return l10n.libraryImportEmptyError;
      case PlaylistImportError.network:
        return l10n.libraryImportNetworkError;
      case PlaylistImportError.noMatches:
        return l10n.libraryImportNoMatchesError;
      case PlaylistImportError.failed:
        return l10n.libraryImportFailedError;
    }
  }

  Future<void> _import(AppLocalizations l10n) async {
    final link = _linkCtrl.text.trim();
    if (link.isEmpty) {
      setState(() => _errorText = l10n.libraryImportLinkEmptyError);
      return;
    }
    FocusScope.of(context).unfocus();
    final pp = context.read<PlaylistProvider>();
    final host = widget.hostContext;
    final cancel = ImportCancelToken();
    setState(() {
      _stage = _ImportStage.working;
      _errorText = null;
      _cancel = cancel;
      _progress =
          const PlaylistImportProgress(phase: PlaylistImportPhase.reading);
    });

    try {
      final result = await PlaylistImportService.importFromLink(
        link,
        cancel: cancel,
        onProgress: (p) {
          if (mounted && !cancel.isCancelled) setState(() => _progress = p);
        },
      );
      if (!mounted || cancel.isCancelled) return;

      final playlist = await pp.addImportedPlaylist(
        name: result.name.isEmpty
            ? l10n.libraryImportedPlaylistDefaultName
            : result.name,
        songs: result.songs,
        youtubeSynced: result.source == PlaylistImportSource.youtube,
      );
      if (!mounted || cancel.isCancelled) return;

      final clean = result.unmatched.isEmpty && !result.possiblyTruncated;
      if (clean) {
        Navigator.pop(context);
        if (host.mounted) {
          AurumSnack.show(host, l10n.libraryImportedCount(result.songs.length));
          AurumDepthRoute.to(
            host,
            PlaylistDetailScreen(playlistId: playlist.id),
          );
        }
        return;
      }
      setState(() {
        _stage = _ImportStage.done;
        _result = result;
        _playlistId = playlist.id;
      });
    } on PlaylistImportCancelled {
    } on PlaylistImportException catch (e) {
      if (!mounted || _cancel != cancel) return;
      setState(() {
        _stage = _ImportStage.idle;
        _progress = null;
        _errorText = _errorMessage(l10n, e.reason);
      });
    } catch (_) {
      if (!mounted || _cancel != cancel) return;
      setState(() {
        _stage = _ImportStage.idle;
        _progress = null;
        _errorText = l10n.libraryImportFailedError;
      });
    }
  }

  void _cancelImport() {
    _cancel?.cancel();
    setState(() {
      _stage = _ImportStage.idle;
      _progress = null;
    });
  }

  void _openPlaylist() {
    final id = _playlistId;
    final host = widget.hostContext;
    Navigator.pop(context);
    if (id != null && host.mounted) {
      AurumDepthRoute.to(host, PlaylistDetailScreen(playlistId: id));
    }
  }

  Widget _gradientButton(String label, VoidCallback? onTap) {
    return AurumPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          gradient: AurumTheme.accentGradientOf(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: AurumTheme.bgOf(context), fontWeight: FontWeight.w700)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final muted = AurumTheme.textMutedOf(context);
    final title = _stage == _ImportStage.done
        ? l10n.libraryImportDoneTitle
        : l10n.libraryImportPlaylist;

    late final Widget content;
    late final List<Widget> actions;

    switch (_stage) {
      case _ImportStage.idle:
        final detectedLabel = _detected == PlaylistImportSource.spotify
            ? l10n.libraryImportDetectedSpotify
            : _detected == PlaylistImportSource.youtube
                ? l10n.libraryImportDetectedYoutube
                : null;
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.libraryImportPlaylistDesc,
              style: TextStyle(color: muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            AurumFocusField(
              builder: (focusNode) => _AurumTextField(
                controller: _linkCtrl,
                focusNode: focusNode,
                label: l10n.libraryImportLinkLabel,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (detectedLabel != null)
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 15, color: AurumTheme.accentOf(context)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(detectedLabel,
                              style: TextStyle(
                                  color: AurumTheme.accentOf(context),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  )
                else
                  const Spacer(),
                TextButton.icon(
                  onPressed: _paste,
                  icon: Icon(Icons.content_paste_rounded,
                      size: 16, color: AurumTheme.accentOf(context)),
                  label: Text(l10n.libraryImportPaste,
                      style: TextStyle(
                          color: AurumTheme.accentOf(context),
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 4),
              Text(
                _errorText!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 12.5),
              ),
            ],
          ],
        );
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel, style: TextStyle(color: muted)),
          ),
          _gradientButton(l10n.commonImport, () => _import(l10n)),
        ];
        break;

      case _ImportStage.working:
        final p = _progress;
        final doneCount = p?.done ?? 0;
        final totalCount = p?.total ?? 0;
        final matching =
            p?.phase == PlaylistImportPhase.matching && totalCount > 0;
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              matching
                  ? l10n.libraryImportMatching(doneCount, totalCount)
                  : l10n.libraryImportReading,
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: matching
                    ? (doneCount / totalCount).clamp(0.0, 1.0).toDouble()
                    : null,
                minHeight: 5,
                color: AurumTheme.accentOf(context),
                backgroundColor: muted.withOpacity(0.18),
              ),
            ),
          ],
        );
        actions = [
          TextButton(
            onPressed: _cancelImport,
            child: Text(l10n.commonCancel, style: TextStyle(color: muted)),
          ),
        ];
        break;

      case _ImportStage.done:
        final r = _result!;
        const maxShown = 40;
        content = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.libraryImportDoneBody(r.songs.length, r.totalTracks),
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (r.possiblyTruncated) ...[
              const SizedBox(height: 8),
              Text(l10n.libraryImportTruncatedNote,
                  style: TextStyle(color: muted, fontSize: 12.5, height: 1.4)),
            ],
            if (r.unmatched.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                l10n.libraryImportUnmatchedHeader(r.unmatched.length),
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              for (final t in r.unmatched.take(maxShown))
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    t.artists.isEmpty ? t.title : '${t.title} — ${t.artistLine}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                ),
              if (r.unmatched.length > maxShown)
                Text(
                  l10n.libraryImportUnmatchedMore(
                      r.unmatched.length - maxShown),
                  style: TextStyle(color: muted, fontSize: 12.5),
                ),
            ],
          ],
        );
        actions = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose, style: TextStyle(color: muted)),
          ),
          _gradientButton(l10n.libraryImportOpenPlaylist, _openPlaylist),
        ];
        break;
    }

    return PopScope(
      canPop: _stage != _ImportStage.working,
      child: AlertDialog(
        backgroundColor: AurumTheme.bgElevatedOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        scrollable: true,
        title: Text(title,
            style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontWeight: FontWeight.w800)),
        content: content,
        actions: actions,
      ),
    );
  }
}

class _RenamePlaylistDialog extends StatefulWidget {
  final AurumPlaylist playlist;
  const _RenamePlaylistDialog({required this.playlist});

  @override
  State<_RenamePlaylistDialog> createState() => _RenamePlaylistDialogState();
}

class _RenamePlaylistDialogState extends State<_RenamePlaylistDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.playlist.name);
    _descCtrl = TextEditingController(text: widget.playlist.description);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: AurumTheme.bgElevatedOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      scrollable: true,
      title: Text(l10n.libraryEditPlaylist,
          style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AurumFocusField(
            builder: (focusNode) => _AurumTextField(
              controller: _nameCtrl,
              focusNode: focusNode,
              label: l10n.libraryPlaylistNameLabel,
            ),
          ),
          const SizedBox(height: 12),
          _AurumTextField(
              controller: _descCtrl, label: l10n.libraryDescriptionOptionalLabel),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel,
              style:
                  TextStyle(color: AurumTheme.textMutedOf(context))),
        ),
        AurumPressable(
          onTap: () async {
            await context.read<PlaylistProvider>().renamePlaylist(
                  widget.playlist.id,
                  _nameCtrl.text,
                  newDescription: _descCtrl.text,
                );
            if (mounted) Navigator.pop(context);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: AurumTheme.accentGradientOf(context),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(l10n.commonSave,
                style: TextStyle(
                    color: AurumTheme.bgOf(context),
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

Future<void> showAddToPlaylistSheet(BuildContext context, Song song) async {
  final pp = context.read<PlaylistProvider>();
  final isLight = Theme.of(context).brightness == Brightness.light;
  final l10n = AppLocalizations.of(context)!;

  await showAurumModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor:
        isLight ? AurumTheme.bgCardOf(context) : AurumTheme.darkBgElevated,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) {
      return Consumer<PlaylistProvider>(
        builder: (context, pp, _) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.85,
            builder: (_, scrollCtrl) => Column(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: AurumTheme.textMutedOf(context).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      AurumArtwork(
                          url: song.artworkUrl, size: 44, borderRadius: 8),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.libraryAddToPlaylist,
                                style: TextStyle(
                                    color:
                                        AurumTheme.textPrimaryOf(context),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            Text(song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color:
                                        AurumTheme.textMutedOf(context),
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                    color: AurumTheme.textMutedOf(context).withOpacity(0.1),
                    height: 1),
                ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AurumTheme.accentOf(context).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AurumTheme.accentOf(context).withOpacity(0.3)),
                    ),
                    child: Icon(Icons.add_rounded,
                        color: AurumTheme.accentOf(context), size: 22),
                  ),
                  title: Text(l10n.libraryNewPlaylistLower,
                      style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontWeight: FontWeight.w600)),
                  onTap: () {
                    PremiumGate.guard(
                      context,
                      feature: l10n.libraryCreatePlaylist,
                      description: l10n.libraryLoginToOrganizeDesc,
                      requiresLoginOnly: true,
                      onAllowed: () {
                        Navigator.pop(ctx);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!context.mounted) return;
                          showDialog(
                            context: context,
                            builder: (_) =>
                                _CreatePlaylistDialog(initialSong: song),
                          );
                        });
                      },
                    );
                  },
                ),
                Expanded(
                  child: pp.playlists.isEmpty
                      ? Center(
                          child: Text(l10n.libraryNoPlaylistsYet,
                              style: TextStyle(
                                  color: AurumTheme.textMutedOf(context))))
                      : ListView.builder(
                          controller: scrollCtrl,
                          physics: const BouncingScrollPhysics(),
                          cacheExtent: 600,
                          itemCount: pp.playlists.length,
                          itemExtent: 72,
                          itemBuilder: (_, i) {
                            final pl = pp.playlists[i];
                            final alreadyIn = pp.isSongInPlaylist(pl.id, song.id);
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: pl.coverArt == null || pl.coverArt!.isEmpty
                                      ? PlaylistColorCover(
                                          artworkUrl: pl.songs.isNotEmpty
                                              ? pl.songs.first.artworkUrl
                                              : '',
                                          size: 44,
                                          borderRadius: 8,
                                        )
                                      : AurumArtwork(
                                          url: pl.coverArt!,
                                          size: 44,
                                          borderRadius: 8),
                                ),
                              ),
                              title: Text(pl.name,
                                  style: TextStyle(
                                      color: AurumTheme.textPrimaryOf(context),
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  l10n.librarySongsCount(pl.songCount),
                                  style: TextStyle(
                                      color: AurumTheme.textMutedOf(context),
                                      fontSize: 12)),
                              trailing: alreadyIn
                                  ? Icon(Icons.check_circle_rounded,
                                      color: AurumTheme.accentOf(context), size: 22)
                                  : null,
                              onTap: alreadyIn
                                  ? null
                                  : () async {
                                      final added = await context
                                          .read<PlaylistProvider>()
                                          .addSong(pl.id, song);
                                      if (context.mounted) {
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                          content: Text(added
                                              ? l10n.libraryAddedToPlaylist(pl.name)
                                              : l10n.libraryAlreadyInPlaylist(pl.name)),
                                          backgroundColor:
                                              added ? AurumTheme.accentOf(context) : null,
                                          behavior: SnackBarBehavior.floating,
                                          duration:
                                              const Duration(seconds: 2),
                                        ));
                                      }
                                    },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      );
    },
  );
}

class _AurumTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final FocusNode? focusNode;

  const _AurumTextField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      style: TextStyle(color: AurumTheme.textPrimaryOf(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 13),
        filled: true,
        fillColor: AurumTheme.bgOf(context).withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AurumTheme.textMutedOf(context).withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AurumTheme.textMutedOf(context).withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AurumTheme.accentOf(context), width: 1.5),
        ),
      ),
    );
  }
}

class _TopSongsScreen extends StatelessWidget {
  const _TopSongsScreen();

  @override
  Widget build(BuildContext context) {
    return Consumer<RecentlyPlayedProvider>(
      builder: (context, rp, _) {
        final byId = <String, Song>{
          for (final d in context.read<DownloadProvider>().completed)
            d.song.id: d.song,
          for (final s in context.read<FavoritesProvider>().favorites) s.id: s,
          for (final s in rp.history) s.id: s,
        };
        final rankedIds = RecommendationEngine.topPlayedSongIds(count: 50);
        final topSongs = rankedIds
            .map((id) => byId[id])
            .whereType<Song>()
            .toList();

        return Scaffold(
          backgroundColor: AurumTheme.bgOf(context),
          bottomNavigationBar: const MiniPlayerSlot(),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            cacheExtent: 1200,
            slivers: [
              SliverAppBar(
                expandedHeight: 120,
                floating: false,
                pinned: true,
                backgroundColor: AurumTheme.bgOf(context),
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: AurumTheme.textPrimaryOf(context), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
                  title: Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AurumTheme.accentOf(context).withOpacity(0.15),
                      ),
                      child: Icon(Icons.trending_up_rounded,
                          color: AurumTheme.accentOf(context), size: 16),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppLocalizations.of(context)!.libraryMyTop50,
                      style: TextStyle(
                        color: AurumTheme.accentOf(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]),
                ),
              ),
              if (topSongs.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AurumTheme.accentOf(context).withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.trending_up_rounded,
                              color: AurumTheme.accentOf(context).withOpacity(0.5),
                              size: 36),
                        ),
                        const SizedBox(height: 20),
                        Text(AppLocalizations.of(context)!.libraryNoTopSongsYet,
                            style: TextStyle(
                                color: AurumTheme.textPrimaryOf(context),
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(AppLocalizations.of(context)!.libraryKeepListeningTopSongs,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AurumTheme.textMutedOf(context),
                                fontSize: 13)),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Row(children: [
                      Text(
                        AppLocalizations.of(context)!.libraryRankedByPlays(topSongs.length),
                        style: TextStyle(
                            color: AurumTheme.textMutedOf(context),
                            fontSize: 13),
                      ),
                      const Spacer(),
                      AurumPressable(
                        onTap: () {
                          context.read<PlayerProvider>().playSong(
                              topSongs[0],
                              queue: topSongs,
                              index: 0,
                              curatedQueue: true);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: AurumTheme.accentGradientOf(context),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AurumTheme.accentOf(context).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              )
                            ],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.play_arrow_rounded,
                                color: AurumTheme.bg, size: 16),
                            const SizedBox(width: 4),
                            Text(AppLocalizations.of(context)!.commonPlayAll,
                                style: TextStyle(
                                    color: AurumTheme.bg,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final song = topSongs[i];
                      final rank = i + 1;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 32,
                              child: Text(
                                '$rank',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: rank <= 3
                                      ? AurumTheme.accentOf(context)
                                      : AurumTheme.textMutedOf(context),
                                  fontSize: rank <= 3 ? 17 : 14,
                                  fontWeight: rank <= 3
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SongTile(
                                song: song,
                                queue: topSongs,
                                index: i,
                                curatedQueue: true,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: topSongs.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HistoryScreen extends StatefulWidget {
  const _HistoryScreen();
  @override
  State<_HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<_HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _headerCtrl;
  late final Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
      vsync: this,
      duration: AurumMotion.durationOrZero(AurumMotion.long2),
    )..forward();
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    super.dispose();
  }

  static String _groupLabel(int? playedAtMs, AppLocalizations l10n) {
    if (playedAtMs == null) return l10n.libraryHistoryOlder;
    final now = DateTime.now();
    final t = DateTime.fromMillisecondsSinceEpoch(playedAtMs);
    final mins = now.difference(t).inMinutes;
    if (mins < 10) return l10n.libraryHistoryJustNow;
    if (mins < 60) return l10n.libraryHistoryRecent;
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    if (days <= 0) return l10n.libraryHistoryEarlierToday;
    if (days == 1) return l10n.libraryHistoryYesterday;
    return l10n.libraryHistoryOlder;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<RecentlyPlayedProvider>(
      builder: (context, rp, _) {
        final history = rp.history;

        return Scaffold(
          backgroundColor: AurumTheme.bgOf(context),
          bottomNavigationBar: const MiniPlayerSlot(),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            cacheExtent: 1200,
            slivers: [
              SliverAppBar(
                expandedHeight: 120,
                floating: false,
                pinned: true,
                backgroundColor: AurumTheme.bgOf(context),
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded,
                      color: AurumTheme.textPrimaryOf(context), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: history.isNotEmpty
                    ? [
                        IconButton(
                          icon: Icon(Icons.shuffle_rounded,
                              color: AurumTheme.accentOf(context), size: 22),
                          tooltip: l10n.commonShuffle,
                          onPressed: () {
                            AurumHaptics.selection();
                            final shuffled = [...history]..shuffle();
                            context.read<PlayerProvider>().playSong(
                                shuffled[0],
                                queue: shuffled,
                                index: 0,
                                curatedQueue: true);
                          },
                        ),
                        const SizedBox(width: 4),
                      ]
                    : null,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
                  title: FadeTransition(
                    opacity: _headerFade,
                    child: Row(children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AurumTheme.accentOf(context).withOpacity(0.15),
                        ),
                        child: Icon(Icons.history_rounded,
                            color: AurumTheme.accentOf(context), size: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.libraryHistory,
                        style: TextStyle(
                          color: AurumTheme.accentOf(context),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),

              if (history.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AurumTheme.accentOf(context).withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.history_rounded,
                              color: AurumTheme.accentOf(context).withOpacity(0.5),
                              size: 36),
                        ),
                        const SizedBox(height: 20),
                        Text(l10n.libraryNoHistoryYet,
                            style: TextStyle(
                                color: AurumTheme.textPrimaryOf(context),
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(l10n.librarySongsYouPlayAppearHere,
                            style: TextStyle(
                                color: AurumTheme.textMutedOf(context),
                                fontSize: 13)),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _headerFade,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Row(children: [
                        Text(
                          l10n.librarySongsCount(history.length),
                          style: TextStyle(
                              color: AurumTheme.textMutedOf(context),
                              fontSize: 13),
                        ),
                        const Spacer(),
                        AurumPressable(
                          onTap: () {
                            context.read<PlayerProvider>().playSong(
                                history[0],
                                queue: history,
                                index: 0,
                                curatedQueue: true);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: AurumTheme.accentGradientOf(context),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AurumTheme.accentOf(context).withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                )
                              ],
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: AurumTheme.bg, size: 16),
                              const SizedBox(width: 4),
                              Text(l10n.commonPlayAll,
                                  style: TextStyle(
                                      color: AurumTheme.bg,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AurumPressable(
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor:
                                    AurumTheme.bgElevatedOf(context),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                                title: Text(l10n.libraryClearHistoryTitle,
                                    style: TextStyle(
                                        color:
                                            AurumTheme.textPrimaryOf(context),
                                        fontWeight: FontWeight.w800)),
                                content: Text(
                                    l10n.libraryClearHistoryConfirm(history.length),
                                    style: TextStyle(
                                        color:
                                            AurumTheme.textMutedOf(context))),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(l10n.commonCancel,
                                          style: TextStyle(
                                              color: AurumTheme
                                                  .textMutedOf(context)))),
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, true),
                                      child: Text(l10n.commonClear,
                                          style: const TextStyle(
                                              color: Colors.redAccent))),
                                ],
                              ),
                            );
                            if (confirmed == true && context.mounted) {
                              await context
                                  .read<RecentlyPlayedProvider>()
                                  .clearHistory();
                              unawaited(
                                  SyncService.instance.clearRemoteHistory());
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.redAccent.withOpacity(0.3)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.delete_outline_rounded,
                                  color: Colors.redAccent, size: 15),
                              const SizedBox(width: 4),
                              Text(l10n.commonClear,
                                  style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),

                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final song = history[i];
                      final currentGroup =
                          _groupLabel(rp.playedAtFor(song.id), l10n);
                      final prevGroup = i > 0
                          ? _groupLabel(rp.playedAtFor(history[i - 1].id), l10n)
                          : null;
                      final showHeader = currentGroup != prevGroup;

                      return _AnimatedHistoryItem(
                        index: i,
                        itemKey: song.id,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showHeader)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 20, 20, 6),
                                child: Text(
                                  currentGroup,
                                  style: TextStyle(
                                    color: AurumTheme.textMutedOf(context),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            SongTile(
                                song: song,
                                queue: history,
                                index: i,
                                curatedQueue: true),
                          ],
                        ),
                      );
                    },
                    childCount: history.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ],
          ),
        );
      },
    );
  }
}

final _seenHistoryItems = <String>{};

class _AnimatedHistoryItem extends StatefulWidget {
  final int index;
  final Widget child;
  final String? itemKey;
  const _AnimatedHistoryItem({required this.index, required this.child, this.itemKey});

  @override
  State<_AnimatedHistoryItem> createState() => _AnimatedHistoryItemState();
}

class _AnimatedHistoryItemState extends State<_AnimatedHistoryItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    final cappedIndex = widget.index.clamp(0, 15);
    _ctrl = AnimationController(
      vsync: this,
      duration: AurumMotion.durationOrZero(AurumMotion.long1),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AurumMotion.standard));

    final seenKey = widget.itemKey ?? 'idx_${widget.index}';
    if (_seenHistoryItems.contains(seenKey)) {
      _ctrl.value = 1.0;
    } else {
      _seenHistoryItems.add(seenKey);
      Future.delayed(Duration(milliseconds: 30 + cappedIndex * 40), () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _LocalFilesScreen extends StatefulWidget {
  const _LocalFilesScreen();

  @override
  State<_LocalFilesScreen> createState() => _LocalFilesScreenState();
}

class _LocalFilesScreenState extends State<_LocalFilesScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  List<Song> _filtered(List<Song> songs) {
    if (_query.trim().isEmpty) return songs;
    final q = _query.trim().toLowerCase();
    return songs.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.artist.toLowerCase().contains(q) ||
          s.album.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lib = context.watch<LibraryProvider>();
    final filtered = _filtered(lib.allSongs);

    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _searching) _closeSearch();
      },
      child: Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      bottomNavigationBar: const MiniPlayerSlot(),
      appBar: AppBar(
        backgroundColor: AurumTheme.bgOf(context),
        titleSpacing: _searching ? 4 : null,
        title: _searching
            ? _LocalSearchField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (v) => setState(() => _query = v),
              )
            : Text(l10n.libraryLocalFiles,
                style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: Icon(
              _searching
                  ? Icons.arrow_back_ios_rounded
                  : Icons.arrow_back_ios_rounded,
              color: AurumTheme.textPrimaryOf(context)),
          onPressed: () {
            if (_searching) {
              _closeSearch();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: _searching
            ? [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: AurumTheme.textMutedOf(context)),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                  ),
              ]
            : [
                IconButton(
                  icon: Icon(Icons.search_rounded, color: AurumTheme.accentOf(context)),
                  onPressed: _openSearch,
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded, color: AurumTheme.accentOf(context)),
                  onPressed: () => lib.refresh(),
                ),
              ],
      ),
      body: lib.status == LibraryStatus.loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 48),
                child: AurumM3Loader()))
          : lib.status == LibraryStatus.noPermission
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AurumTheme.bgElevatedOf(context),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AurumTheme.accentOf(context).withOpacity(0.3)),
                        ),
                        child: Icon(Icons.folder_rounded,
                            color: AurumTheme.accentOf(context), size: 32),
                      ),
                      const SizedBox(height: 20),
                      Text(l10n.libraryPermissionRequired,
                          style: TextStyle(
                              color: AurumTheme.textPrimaryOf(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(l10n.libraryNeedsPermissionToReadMusic,
                          style: TextStyle(
                              color: AurumTheme.textMutedOf(context),
                              fontSize: 13)),
                      const SizedBox(height: 20),
                      AurumPressable(
                        onTap: () => lib.load(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: AurumTheme.accentGradientOf(context),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(l10n.homeGrantPermission,
                              style: TextStyle(
                                  color: AurumTheme.bg,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                )
              : lib.allSongs.isEmpty
                  ? Center(
                      child: Text(l10n.libraryNoLocalSongsFound,
                          style: TextStyle(
                              color: AurumTheme.textMutedOf(context))))
                  : filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              l10n.libraryLocalSearchNoResults(_query),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AurumTheme.textMutedOf(context)),
                            ),
                          ),
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 100),
                          cacheExtent: 1000,
                          itemCount: filtered.length,
                          itemExtent: _query.trim().isEmpty ? 86 : null,
                          itemBuilder: (_, i) => SongTile(
                              song: filtered[i],
                              queue: filtered,
                              index: i,
                              curatedQueue: true),
                        ),
    ),
    );
  }
}

class _LocalSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  const _LocalSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.12)
              : Colors.black.withOpacity(0.08),
          width: 0.7,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        autofocus: false,
        style: TextStyle(
            color: AurumTheme.textPrimaryOf(context),
            fontSize: 14,
            fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          isCollapsed: true,
          hintText: l10n.libraryLocalSearchHint,
          hintStyle:
              TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 14),
          border: InputBorder.none,
        ),
        textInputAction: TextInputAction.search,
      ),
    );
  }
}

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _DownloadsSessionGate.isInitialBuild = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _DownloadsSessionGate.isInitialBuild = false;
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final downloads = context.watch<DownloadProvider>();
    final inProgress = [...downloads.inProgress, ...downloads.failed];
    final completed = downloads.completed;
    final totalBytes = completed.fold<int>(
        0, (sum, d) => sum + (d.fileSizeBytes ?? 0));

    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      bottomNavigationBar: const MiniPlayerSlot(),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_rounded,
                        color: AurumTheme.textSecondaryOf(context), size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ShaderMask(
                  shaderCallback: (b) =>
                      AurumTheme.accentGradientOf(context).createShader(b),
                  child: Text(l10n.settingsDownloads,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
            ),
            if (completed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.sd_storage_rounded,
                        size: 14, color: AurumTheme.textMutedOf(context)),
                    const SizedBox(width: 6),
                    Text(
                      l10n.libraryDownloadsStorageSummary(
                          completed.length, _formatBytes(totalBytes)),
                      style: TextStyle(
                          color: AurumTheme.textMutedOf(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            _DownloadsTabRow(
              index: _tabIndex,
              inProgressCount: inProgress.length,
              onChanged: (i) {
                if (i == _tabIndex) return;
                AurumHaptics.selection();
                setState(() => _tabIndex = i);
              },
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AurumMotion.durationOrZero(AurumMotion.short2),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey(_tabIndex),
                  child: _tabIndex == 0
                      ? _DownloadedList(completed: completed)
                      : _InProgressList(items: inProgress),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadsTabRow extends StatelessWidget {
  final int index;
  final int inProgressCount;
  final ValueChanged<int> onChanged;
  const _DownloadsTabRow({
    required this.index,
    required this.inProgressCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: _DownloadsTab(
            icon: Icons.check_circle_outline_rounded,
            label: l10n.libraryDownloadsTabDownloaded,
            selected: index == 0,
            onTap: () => onChanged(0),
          ),
        ),
        Expanded(
          child: _DownloadsTab(
            icon: Icons.download_rounded,
            label: l10n.libraryDownloadsTabInProgress,
            selected: index == 1,
            badgeCount: inProgressCount,
            onTap: () => onChanged(1),
          ),
        ),
      ],
    );
  }
}

class _DownloadsTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;
  const _DownloadsTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? AurumTheme.accentOf(context)
        : AurumTheme.textMutedOf(context);
    return InkWell(
      onTap: onTap,
      splashColor: AurumTheme.accentOf(context).withValues(alpha: 0.06),
      highlightColor: AurumTheme.accentOf(context).withValues(alpha: 0.04),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600)),
                if (badgeCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AurumTheme.accentOf(context).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$badgeCount',
                        style: TextStyle(
                            color: AurumTheme.accentOf(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: AurumMotion.durationOrZero(AurumMotion.short2),
              height: 2.5,
              width: 64,
              decoration: BoxDecoration(
                color: selected ? AurumTheme.accentOf(context) : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadedList extends StatelessWidget {
  final List<DownloadItem> completed;
  const _DownloadedList({required this.completed});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (completed.isEmpty) {
      return _DownloadsEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: l10n.libraryNoDownloadsYet,
        message: l10n.libraryDownloadFromPlayerDesc,
      );
    }
    return ListView.builder(
      key: const PageStorageKey('downloads_downloaded'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
      cacheExtent: 1200,
      itemCount: completed.length,
      itemBuilder: (context, i) => _DownloadTileEntrance(
        key: ValueKey('dl_done_${completed[i].song.id}'),
        child: _DownloadTile(
          item: completed[i],
          queue: completed,
          queueIndex: i,
        ),
      ),
    );
  }
}

class _InProgressList extends StatelessWidget {
  final List<DownloadItem> items;
  const _InProgressList({required this.items});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (items.isEmpty) {
      return _DownloadsEmptyState(
        icon: Icons.download_rounded,
        title: l10n.libraryNoDownloadsYet,
        message: l10n.libraryDownloadFromPlayerDesc,
      );
    }
    return ListView.builder(
      key: const PageStorageKey('downloads_in_progress'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      cacheExtent: 1200,
      itemCount: items.length,
      itemBuilder: (context, i) => _DownloadTileEntrance(
        key: ValueKey('dl_prog_${items[i].song.id}'),
        child: _InProgressCard(item: items[i]),
      ),
    );
  }
}

class _DownloadsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _DownloadsEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AurumTheme.accentOf(context).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AurumTheme.accentOf(context).withOpacity(0.3)),
              ),
              child: Icon(icon, color: AurumTheme.accentOf(context), size: 36),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AurumTheme.textMutedOf(context),
                  fontSize: 13,
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _InProgressCard extends StatelessWidget {
  final DownloadItem item;
  const _InProgressCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final song = item.song;
    final dl = context.read<DownloadProvider>();
    final percent = (item.progress * 100).clamp(0, 100).toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AurumTheme.bgElevatedOf(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AurumArtwork(url: song.artworkUrl, size: 48, borderRadius: 8),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AurumTheme.textPrimaryOf(context),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      item.isFailed
                          ? l10n.libraryDownloadFailedTapRetry
                          : item.isPaused
                              ? l10n.libraryDownloadPaused
                              : '$percent%',
                      style: TextStyle(
                          color: item.isFailed
                              ? Colors.redAccent
                              : AurumTheme.accentOf(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _RoundIconButton(
                icon: item.isFailed
                    ? Icons.refresh_rounded
                    : item.isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                tooltip: item.isFailed
                    ? l10n.commonRetry
                    : item.isPaused
                        ? l10n.libraryDownloadResume
                        : l10n.libraryDownloadPause,
                onTap: () {
                  if (item.isFailed) {
                    dl.retry(song);
                  } else if (item.isPaused) {
                    dl.resumeDownload(song);
                  } else {
                    dl.pauseDownload(song.id);
                  }
                },
              ),
              const SizedBox(width: 8),
              _RoundIconButton(
                icon: Icons.close_rounded,
                tooltip: l10n.libraryDownloadCancel,
                onTap: () => item.isFailed
                    ? dl.dismissFailed(song.id)
                    : dl.cancelDownload(song.id),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: item.isFailed ? 0.0 : item.progress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AurumTheme.accentOf(context).withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(
                item.isPaused
                    ? AurumTheme.accentOf(context).withValues(alpha: 0.45)
                    : AurumTheme.accentOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AurumTheme.accentOf(context).withValues(alpha: 0.15),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: AurumTheme.accentOf(context), size: 18),
          ),
        ),
      ),
    );
  }
}

class _DownloadProgressRing extends StatelessWidget {
  final String artworkUrl;
  final double progress;
  const _DownloadProgressRing({required this.artworkUrl, required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Opacity(
              opacity: 0.55,
              child: AurumArtwork(url: artworkUrl, size: 48, borderRadius: 8),
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.black.withValues(alpha: 0.18),
            ),
          ),
          CustomPaint(
            size: const Size(30, 30),
            painter: _RingPainter(
              progress: progress.clamp(0.0, 1.0),
              trackColor: Colors.white.withValues(alpha: 0.25),
              progressColor: AurumTheme.accentOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 3) / 2;
    const strokeWidth = 2.6;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}

class _DownloadTileEntrance extends StatefulWidget {
  final Widget child;
  const _DownloadTileEntrance({super.key, required this.child});

  @override
  State<_DownloadTileEntrance> createState() => _DownloadTileEntranceState();
}

class _DownloadTileEntranceState extends State<_DownloadTileEntrance> {
  late final bool _skipAnimation;

  @override
  void initState() {
    super.initState();
    _skipAnimation = _DownloadsSessionGate.isInitialBuild;
  }

  @override
  Widget build(BuildContext context) {
    if (_skipAnimation) return widget.child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: AurumMotion.durationOrZero(AurumMotion.medium1),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

class _DownloadsSessionGate {
  static bool isInitialBuild = true;
}

class _DownloadTile extends StatelessWidget {
  final DownloadItem item;
  final List<DownloadItem>? queue;
  final int? queueIndex;
  const _DownloadTile({required this.item, this.queue, this.queueIndex});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final song = item.song;
    final isLight = Theme.of(context).brightness == Brightness.light;

    final isCurrentSong = context.select<PlayerProvider, bool>(
      (p) => p.currentSong?.id == song.id,
    );
    final isActuallyPlaying = context.select<PlayerProvider, bool>(
      (p) => p.isPlaying,
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: item.isDownloading
          ? _DownloadProgressRing(
              artworkUrl: song.artworkUrl,
              progress: item.progress,
            )
          : AurumStackedArtwork(
              url: song.artworkUrl,
              size: 48,
              borderRadius: 8,
              showNowPlaying: isCurrentSong,
              isPlaying: isActuallyPlaying,
            ),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: isCurrentSong ? AurumTheme.accentOf(context) : AurumTheme.textPrimaryOf(context),
              fontSize: 14,
              fontWeight: isCurrentSong ? FontWeight.w700 : FontWeight.w600)),
      subtitle: item.isDownloading
          ? Text(
              l10n.libraryDownloadingPercent((item.progress * 100).toStringAsFixed(0)),
              style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 12))
          : item.isFailed
              ? Text(l10n.libraryDownloadFailedTapRetry,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12))
              : Text(song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AurumTheme.textMutedOf(context), fontSize: 12)),
      trailing: item.isDownloading
          ? IconButton(
              icon: Icon(Icons.close_rounded,
                  color: AurumTheme.textMutedOf(context), size: 20),
              onPressed: () =>
                  context.read<DownloadProvider>().cancelDownload(song.id),
            )
          : PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded,
                  color: AurumTheme.textMutedOf(context), size: 20),
              color:
                  isLight ? AurumTheme.bgCardOf(context) : AurumTheme.darkBgCard,
              onSelected: (value) {
                final dl = context.read<DownloadProvider>();
                if (value == 'delete') {
                  dl.deleteDownload(song.id).then((success) {
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(AppLocalizations.of(context)!.libraryCouldNotDeleteFile)),
                      );
                    }
                  });
                } else if (value == 'retry') {
                  dl.retry(song);
                }
              },
              itemBuilder: (_) => [
                if (item.isFailed)
                  PopupMenuItem(value: 'retry', child: Text(l10n.commonRetry)),
                PopupMenuItem(
                    value: 'delete', child: Text(l10n.libraryRemoveDownload)),
              ],
            ),
      splashColor: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.06),
      focusColor: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.04),
      hoverColor: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.04),
      onTap: () {
        if (item.isFailed) {
          context.read<DownloadProvider>().retry(song);
        } else if (item.isCompleted) {
          final dl = context.read<DownloadProvider>();
          final offlineSong = dl.offlineSongFor(song.id) ?? song;

          final offlineQueue = (queue ?? [item])
              .map((d) => dl.offlineSongFor(d.song.id) ?? d.song)
              .toList();
          final resolvedIndex = queueIndex ?? 0;

          context.read<PlayerProvider>().playSong(
                offlineSong,
                queue: offlineQueue,
                index: resolvedIndex,
                curatedQueue: true,
              );
        }
      },
    );
  }
}

class _AlbumsScreen extends StatelessWidget {
  const _AlbumsScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final followed = context.watch<FollowedAlbumsProvider>().followed;

    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      bottomNavigationBar: const MiniPlayerSlot(),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        cacheExtent: 1200,
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            floating: true,
            snap: true,
            backgroundColor: AurumTheme.bgOf(context),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded,
                  color: AurumTheme.textSecondaryOf(context), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
              title: Row(
                children: [
                  const Icon(Icons.album_rounded,
                      color: Colors.deepPurple, size: 22),
                  const SizedBox(width: 8),
                  ShaderMask(
                    shaderCallback: (b) =>
                        AurumTheme.accentGradientOf(context).createShader(b),
                    child: Text(l10n.libraryAlbums,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
          if (followed.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.deepPurple.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.album_rounded,
                            color: Colors.deepPurple, size: 36),
                      ),
                      const SizedBox(height: 20),
                      Text(l10n.libraryNoAlbumsSavedYet,
                          style: TextStyle(
                              color: AurumTheme.textPrimaryOf(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(l10n.libraryAlbumsYouSaveAppearHere,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AurumTheme.textMutedOf(context),
                              fontSize: 13,
                              height: 1.5)),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _FollowedAlbumTile(album: followed[i]),
                  childCount: followed.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FollowedAlbumTile extends StatelessWidget {
  final Map<String, dynamic> album;
  const _FollowedAlbumTile({required this.album});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final id = (album['id'] ?? '').toString();
    final name = (album['name'] ?? '').toString();
    final artworkUrl = (album['artworkUrl'] ?? '').toString();
    final isMix = album['isMix'] == true;

    return RepaintBoundary(
      child: AurumPressable(
      onTap: () {
        if (isMix) {
          final songs =
              context.read<FollowedAlbumsProvider>().songsFor(id);
          AurumDepthRoute.to(
            context,
            MixScreen(
              mixId: id,
              mixName: name,
              artworkUrl: artworkUrl,
              emoji: '',
              songs: songs,
            ),
          );
        } else {
          AurumDepthRoute.to(
            context,
            AlbumScreen(albumId: id, albumName: name, artworkUrl: artworkUrl),
          );
        }
      },
      onLongPress: () {
        AurumHaptics.medium();
        _showUnsaveSheet(context, id, name, artworkUrl);
      },
      scaleAmount: 0.95,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Hero(
                tag: isMix ? 'mix_art_$id' : 'album_art_$id',
                flightShuttleBuilder: (context, animation, direction, from, to) {
                  return Material(
                    color: Colors.transparent,
                    child: ScaleTransition(scale: animation, child: to.widget),
                  );
                },
                child: Material(
                  color: Colors.transparent,
                  child: AurumArtwork(url: artworkUrl, size: 300, borderRadius: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.album_rounded,
                  size: 12, color: AurumTheme.accentOf(context).withOpacity(0.85)),
              const SizedBox(width: 4),
              Text(
                l10n.libraryAlbumTag,
                style: TextStyle(
                  color: AurumTheme.textMutedOf(context),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  void _showUnsaveSheet(
      BuildContext context, String id, String name, String artworkUrl) {
    final rootContext = context;
    final l10n = AppLocalizations.of(context)!;
    showAurumModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: AurumTheme.bgElevatedOf(rootContext),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AurumArtwork(url: artworkUrl, size: 44, borderRadius: 8),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(rootContext),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bookmark_remove_rounded,
                  color: Colors.redAccent),
              title: Text(l10n.libraryRemoveFromSavedAlbums),
              onTap: () {
                Navigator.pop(sheetContext);
                rootContext.read<FollowedAlbumsProvider>().toggleFollow(
                      albumId: id,
                      name: name,
                      artworkUrl: artworkUrl,
                    );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistsScreen extends StatefulWidget {
  const _ArtistsScreen();

  @override
  State<_ArtistsScreen> createState() => _ArtistsScreenState();
}

class _ArtistsScreenState extends State<_ArtistsScreen> {
  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  void _enterSelectMode(String firstId) {
    AurumHaptics.medium();
    setState(() {
      _selectMode = true;
      _selectedIds
        ..clear()
        ..add(firstId);
    });
  }

  void _toggleSelected(String id) {
    AurumHaptics.selection();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectMode = false;
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _confirmUnfollowSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showAurumModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.libraryUnfollowArtistsConfirm(count),
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: Text(AppLocalizations.of(context)!.commonCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: Text(AppLocalizations.of(context)!.libraryUnfollow),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    AurumHaptics.medium();
    final ids = List<String>.from(_selectedIds);
    _exitSelectMode();
    await context.read<FollowedArtistsProvider>().unfollowMany(ids);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final followed = context.watch<FollowedArtistsProvider>().followed;

    return PopScope(
      canPop: !_selectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectMode) _exitSelectMode();
      },
      child: Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      bottomNavigationBar: const MiniPlayerSlot(),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        cacheExtent: 1200,
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            floating: true,
            snap: true,
            backgroundColor: AurumTheme.bgOf(context),
            leading: IconButton(
              icon: Icon(
                _selectMode ? Icons.close_rounded : Icons.arrow_back_ios_rounded,
                color: AurumTheme.textSecondaryOf(context),
                size: 20,
              ),
              onPressed: () {
                if (_selectMode) {
                  AurumHaptics.light();
                  _exitSelectMode();
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            actions: _selectMode
                ? [
                    Builder(builder: (context) {
                      final allIds = followed.map((m) => (m['id'] ?? '').toString()).toSet();
                      final allSelected = allIds.isNotEmpty &&
                          _selectedIds.length == allIds.length;
                      return TextButton(
                        onPressed: () {
                          AurumHaptics.selection();
                          setState(() {
                            if (allSelected) {
                              _selectedIds.clear();
                            } else {
                              _selectedIds
                                ..clear()
                                ..addAll(allIds);
                            }
                          });
                        },
                        child: Text(
                          allSelected ? AppLocalizations.of(context)!.libraryDeselectAll : AppLocalizations.of(context)!.librarySelectAll,
                          style: TextStyle(
                            color: AurumTheme.accentOf(context),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }),
                    IconButton(
                      icon: Icon(
                        Icons.person_remove_outlined,
                        color: _selectedIds.isEmpty
                            ? AurumTheme.textMutedOf(context)
                            : Colors.redAccent,
                      ),
                      onPressed: _selectedIds.isEmpty ? null : _confirmUnfollowSelected,
                    ),
                    const SizedBox(width: 4),
                  ]
                : null,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
              title: _selectMode
                  ? Text(
                      AppLocalizations.of(context)!.librarySelectedCount(_selectedIds.length),
                      style: TextStyle(
                        color: AurumTheme.textPrimaryOf(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Row(
                      children: [
                        const Icon(Icons.person_rounded,
                            color: Colors.blueAccent, size: 22),
                        const SizedBox(width: 8),
                        ShaderMask(
                          shaderCallback: (b) =>
                              AurumTheme.accentGradientOf(context).createShader(b),
                          child: Text(l10n.libraryArtists,
                              style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ],
                    ),
            ),
          ),
          if (followed.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.person_rounded,
                            color: Colors.blueAccent, size: 36),
                      ),
                      const SizedBox(height: 20),
                      Text(l10n.libraryNoArtistsSavedYet,
                          style: TextStyle(
                              color: AurumTheme.textPrimaryOf(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(l10n.libraryArtistsYouFollowAppearHere,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AurumTheme.textMutedOf(context),
                              fontSize: 13,
                              height: 1.5)),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final artistId = (followed[i]['id'] ?? '').toString();
                    return _FollowedArtistTile(
                      artist: followed[i],
                      selectMode: _selectMode,
                      selected: _selectedIds.contains(artistId),
                      onEnterSelectMode: () => _enterSelectMode(artistId),
                      onToggleSelected: () => _toggleSelected(artistId),
                    );
                  },
                  childCount: followed.length,
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }
}

class _FollowedArtistTile extends StatelessWidget {
  final Map<String, dynamic> artist;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onEnterSelectMode;
  final VoidCallback? onToggleSelected;

  const _FollowedArtistTile({
    required this.artist,
    this.selectMode = false,
    this.selected = false,
    this.onEnterSelectMode,
    this.onToggleSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final id = (artist['id'] ?? '').toString();
    final name = (artist['name'] ?? '').toString();
    final imageUrl = (artist['imageUrl'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? AurumTheme.accentOf(context).withOpacity(0.12)
            : AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          splashColor: (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black)
              .withValues(alpha: 0.06),
          highlightColor: (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black)
              .withValues(alpha: 0.04),
          onTap: () {
            if (selectMode) {
              onToggleSelected?.call();
              return;
            }
            AurumHaptics.selection();
            AurumDepthRoute.to(
              context,
              ArtistScreen(artistId: id, artistName: name),
            );
          },
          onLongPress: () {
            if (selectMode) return;
            AurumHaptics.medium();
            onEnterSelectMode?.call();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AurumTheme.accentGradientOf(context),
                  ),
                  child: ClipOval(
                    child: AurumArtwork(url: imageUrl, size: 54, borderRadius: 27),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.check_circle_rounded,
                              size: 13, color: AurumTheme.accentOf(context).withOpacity(0.85)),
                          const SizedBox(width: 4),
                          Text(
                            l10n.libraryArtistTag,
                            style: TextStyle(
                              color: AurumTheme.textMutedOf(context),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (selectMode)
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected
                        ? AurumTheme.accentOf(context)
                        : AurumTheme.textMutedOf(context),
                    size: 24,
                  )
                else
                  IconButton(
                    icon: Icon(Icons.more_vert_rounded,
                        color: AurumTheme.textMutedOf(context)),
                    onPressed: () => _showUnfollowSheet(context, id, name, imageUrl),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showUnfollowSheet(
      BuildContext context, String id, String name, String imageUrl) {
    final rootContext = context;
    final l10n = AppLocalizations.of(context)!;
    showAurumModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: AurumTheme.bgElevatedOf(rootContext),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipOval(
                  child: AurumArtwork(url: imageUrl, size: 44, borderRadius: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(rootContext),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_remove_rounded,
                  color: Colors.redAccent),
              title: Text(l10n.libraryUnfollowArtist),
              onTap: () {
                Navigator.pop(sheetContext);
                rootContext.read<FollowedArtistsProvider>().toggleFollow(
                      artistId: id,
                      name: name,
                      imageUrl: imageUrl,
                    );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String message;
  const _ComingSoonScreen(
      {required this.title,
      required this.icon,
      required this.color,
      required this.message});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      bottomNavigationBar: const MiniPlayerSlot(),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        cacheExtent: 1200,
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            floating: true,
            snap: true,
            backgroundColor: AurumTheme.bgOf(context),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded,
                  color: AurumTheme.textSecondaryOf(context), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
              title: Row(
                children: [
                  Icon(icon, color: color, size: 22),
                  const SizedBox(width: 8),
                  ShaderMask(
                    shaderCallback: (b) =>
                        AurumTheme.accentGradientOf(context).createShader(b),
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Icon(icon, color: color, size: 36),
                    ),
                    const SizedBox(height: 20),
                    Text(l10n.libraryComingSoon,
                        style: TextStyle(
                            color: AurumTheme.textPrimaryOf(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AurumTheme.textMutedOf(context),
                            fontSize: 13,
                            height: 1.5)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
