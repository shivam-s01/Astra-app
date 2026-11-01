// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:aurum_music/widgets/aurum_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/player_provider.dart';
import '../theme/aurum_theme.dart';
import '../widgets/song_tile.dart';
import '../widgets/aurum_empty_state.dart';
import '../widgets/mini_player_slot.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_sheet.dart';

class LikedScreen extends StatefulWidget {
  const LikedScreen({super.key});

  @override
  State<LikedScreen> createState() => _LikedScreenState();
}

class _LikedScreenState extends State<LikedScreen> {
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

  Future<void> _confirmUnlikeSelected() async {
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
              count == 1 ? 'Unlike this song?' : 'Unlike $count songs?',
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
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('Unlike'),
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
    await context.read<FavoritesProvider>().removeMany(ids);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
        cacheExtent: 600,
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
                AurumHaptics.light();
                if (_selectMode) {
                  _exitSelectMode();
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            actions: _selectMode
                ? [
                    Consumer<FavoritesProvider>(
                      builder: (context, fav, _) {
                        final allSelected = fav.favorites.isNotEmpty &&
                            _selectedIds.length == fav.favorites.length;
                        return TextButton(
                          onPressed: () {
                            AurumHaptics.selection();
                            setState(() {
                              if (allSelected) {
                                _selectedIds.clear();
                              } else {
                                _selectedIds
                                  ..clear()
                                  ..addAll(fav.favorites.map((s) => s.id));
                              }
                            });
                          },
                          child: Text(
                            allSelected ? 'Deselect all' : 'Select all',
                            style: TextStyle(
                              color: AurumTheme.accentOf(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: _selectedIds.isEmpty
                            ? AurumTheme.textMutedOf(context)
                            : Colors.redAccent,
                      ),
                      onPressed: _selectedIds.isEmpty ? null : _confirmUnlikeSelected,
                    ),
                    const SizedBox(width: 4),
                  ]
                : null,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(52, 0, 16, 16),
              title: _selectMode
                  ? Text(
                      '${_selectedIds.length} selected',
                      style: TextStyle(
                        color: AurumTheme.textPrimaryOf(context),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Row(
                      children: [
                        const Icon(Icons.favorite_rounded, color: Color(0xFFE1306C), size: 22),
                        const SizedBox(width: 8),
                        ShaderMask(
                          shaderCallback: (b) => AurumTheme.accentGradient.createShader(b),
                          child: Text(l10n.libraryLikedSongs, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ],
                    ),
            ),
          ),
          Consumer<FavoritesProvider>(
            builder: (context, fav, _) {
              if (fav.isLoading) {
                return SliverFillRemaining(
                  child: Center(child: AurumMorphLoader(size: 56, contained: true)),
                );
              }

              if (fav.favorites.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: AurumEmptyState(
                      icon: Icons.favorite_border_rounded,
                      title: l10n.likedNoSongsYet,
                      subtitle: l10n.likedTapToSave,
                    ),
                  ),
                );
              }

              final songs = fav.favorites;
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Row(
                          children: [
                            Text(l10n.librarySongsCount(songs.length), style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 13)),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                AurumHaptics.medium();
                                final player = context.read<PlayerProvider>();
                                player.playSong(songs[0], queue: songs, index: 0, curatedQueue: true);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                decoration: BoxDecoration(
                                  gradient: AurumTheme.accentGradient,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.play_arrow_rounded, color: AurumTheme.bgOf(context), size: 18),
                                  const SizedBox(width: 4),
                                  Text(l10n.commonPlayAll, style: TextStyle(color: AurumTheme.bgOf(context), fontSize: 13, fontWeight: FontWeight.w700)),
                                ]),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    if (index == songs.length + 1) {
                      return const SizedBox(height: 100);
                    }
                    final songIndex = index - 1;
                    final song = songs[songIndex];
                    final isSelected = _selectedIds.contains(song.id);
                    final tile = SongTile(
                      song: song,
                      queue: songs,
                      index: songIndex,
                      curatedQueue: true,
                      onLongPressOverride:
                          _selectMode ? null : () => _enterSelectMode(song.id),
                    );
                    if (!_selectMode) {
                      return tile;
                    }
                    return Stack(
                      children: [
                        IgnorePointer(child: tile),
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _toggleSelected(song.id),
                              child: Row(
                                children: [
                                  const SizedBox(width: 16),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    width: 58,
                                    height: 58,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: isSelected
                                          ? Colors.black.withOpacity(0.55)
                                          : Colors.transparent,
                                    ),
                                    alignment: Alignment.center,
                                    child: AnimatedScale(
                                      duration: const Duration(milliseconds: 150),
                                      scale: isSelected ? 1.0 : 0.0,
                                      curve: Curves.easeOutBack,
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AurumTheme.accentOf(context),
                                        ),
                                        child: Icon(
                                          Icons.check_rounded,
                                          color: AurumTheme.bgOf(context),
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  childCount: songs.length + 2,
                ),
              );
            },
          ),
        ],
      ),
    ),
    );
  }
}
