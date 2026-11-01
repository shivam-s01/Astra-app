// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../models/song.dart';
import '../theme/aurum_theme.dart';
import '../widgets/song_tile.dart';
import '../widgets/mini_player_slot.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_haptics.dart';

class ArtistAllSongsScreen extends StatelessWidget {
  final String artistName;
  final List<Song> songs;
  final ValueListenable<List<Song>>? liveSongs;

  const ArtistAllSongsScreen({
    super.key,
    required this.artistName,
    required this.songs,
    this.liveSongs,
  });

  @override
  Widget build(BuildContext context) {
    final live = liveSongs;
    if (live == null) return _buildPage(context, songs);
    return ValueListenableBuilder<List<Song>>(
      valueListenable: live,
      builder: (context, list, _) =>
          _buildPage(context, list.length > songs.length ? list : songs),
    );
  }

  Widget _buildPage(BuildContext context, List<Song> songs) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      bottomNavigationBar: const MiniPlayerSlot(),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        cacheExtent: 600,
        slivers: [
          SliverAppBar(
            expandedHeight: 96,
            floating: true,
            snap: true,
            pinned: true,
            backgroundColor: AurumTheme.bgOf(context),
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded,
                  color: AurumTheme.textSecondaryOf(context), size: 20),
              onPressed: () {
                AurumHaptics.light();
                Navigator.pop(context);
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(52, 0, 20, 16),
              title: Text(
                artistName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          if (songs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  l10n.asPopular,
                  style:
                      TextStyle(color: AurumTheme.textMutedOf(context)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => SongTile(
                    song: songs[i],
                    queue: songs,
                    index: i,
                    curatedQueue: true,
                  ),
                  childCount: songs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
