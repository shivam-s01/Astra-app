// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../models/artist.dart';
import '../providers/player_provider.dart';
import '../services/api_service.dart';
import '../theme/aurum_theme.dart';
import '../widgets/aurum_artwork.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/aurum_snack.dart';
import '../widgets/mini_player_slot.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_transitions.dart';
import 'package:provider/provider.dart';
import 'album_screen.dart';

class ArtistAllAlbumsScreen extends StatelessWidget {
  final String artistName;
  final String title;
  final List<ArtistAlbum> albums;

  const ArtistAllAlbumsScreen({
    super.key,
    required this.artistName,
    required this.title,
    required this.albums,
  });

  @override
  Widget build(BuildContext context) {
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
                title,
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
          if (albums.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  title,
                  style:
                      TextStyle(color: AurumTheme.textMutedOf(context)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _ArtistAlbumGridTile(album: albums[i]),
                  childCount: albums.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArtistAlbumGridTile extends StatefulWidget {
  final ArtistAlbum album;
  const _ArtistAlbumGridTile({required this.album});

  @override
  State<_ArtistAlbumGridTile> createState() => _ArtistAlbumGridTileState();
}

class _ArtistAlbumGridTileState extends State<_ArtistAlbumGridTile> {
  bool _loading = false;

  Future<void> _playAlbum() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final result =
          await ApiService.fetchAlbumSongsWithArtwork(widget.album.id);
      if (!mounted) return;
      if (result.songs.isEmpty) {
        AurumSnack.show(context, 'Could not load songs for this album');
        return;
      }
      final player = context.read<PlayerProvider>();
      player.playSong(result.songs.first,
          queue: result.songs, index: 0, curatedQueue: true);
    } catch (_) {
      if (mounted) {
        AurumSnack.show(context, 'Could not load songs for this album');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;
    return RepaintBoundary(
      child: AurumPressable(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AurumArtwork(
                    url: album.artworkUrl,
                    size: 300,
                    borderRadius: 10,
                  ),
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        AurumHaptics.light();
                        _playAlbum();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.45),
                        ),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (album.year != null) ...[
              const SizedBox(height: 2),
              Text(
                album.year!,
                style: TextStyle(
                  color: AurumTheme.textMutedOf(context),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
