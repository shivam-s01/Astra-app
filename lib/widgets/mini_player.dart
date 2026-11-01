// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/favorites_provider.dart';
import '../l10n/generated/app_localizations.dart';
import 'aurum_like_button.dart';
import 'premium_gate.dart';
import '../models/song.dart';
import '../theme/aurum_theme.dart';
import '../utils/artwork_palette_cache.dart';
import 'aurum_artwork.dart';
import 'aurum_glass.dart';
import 'aurum_pressable.dart';
import 'aurum_play_pause_icon.dart';
import '../screens/home_screen.dart' show pushFullPlayer;
import '../utils/aurum_haptics.dart';
import '../services/audio_prefs.dart';
import '../utils/aurum_motion.dart';
import '../services/aurum_image_cache.dart';

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerVis {
  final bool visible;
  final Song? song;
  const _MiniPlayerVis(this.visible, this.song);

  @override
  bool operator ==(Object other) =>
      other is _MiniPlayerVis && other.visible == visible && other.song == song;

  @override
  int get hashCode => Object.hash(visible, song);
}

class _MiniPlayerState extends State<MiniPlayer> with WidgetsBindingObserver {
  double _dragY = 0;
  bool _dragging = false;

  Color? _tintColor;
  String? _tintForUrl;

  void _syncTintForSong(Song? song) {
    final url = song?.artworkUrl;
    if (url == _tintForUrl) return;
    _tintForUrl = url;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _tintColor = null);
      return;
    }
    final cached = ArtworkPaletteCache.peek(url);
    if (cached != null) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      if (mounted) {
        setState(() => _tintColor = ensureContrastSafe(
            isDark ? cached.darkMuted : cached.lightVibrant,
            isLight: !isDark));
      }
      return;
    }
    ArtworkPaletteCache.get(url).then((p) {
      if (!mounted || _tintForUrl != url) return;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      setState(() => _tintColor =
          ensureContrastSafe(isDark ? p.darkMuted : p.lightVibrant, isLight: !isDark));
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final song = context.read<PlayerProvider>().currentSong;
    final url = song?.artworkUrl;
    if (url != null && url.isNotEmpty) {
      final cached = ArtworkPaletteCache.peek(url);
      if (cached != null) {
        final isDark = WidgetsBinding.instance.platformDispatcher
                .platformBrightness ==
            Brightness.dark;
        _tintColor =
            ensureContrastSafe(isDark ? cached.darkMuted : cached.lightVibrant,
                isLight: !isDark);
        _tintForUrl = url;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onDragCancel() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _dragY = 0;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive ||
            state == AppLifecycleState.detached) &&
        _dragging &&
        mounted) {
      setState(() {
        _dragging = false;
        _dragY = 0;
      });
    }
  }

  static const double _dismissThreshold = 110.0;
  static const double _openThreshold = -60.0;

  double _totalMovement = 0;
  double _maxDragY = 0;
  double _minDragY = 0;

  void _onDragStart(DragStartDetails d) {
    _totalMovement = 0;
    _maxDragY = 0;
    _minDragY = 0;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _totalMovement += d.delta.dy.abs();
    setState(() {
      _dragging = true;
      _dragY = (_dragY + d.delta.dy).clamp(-120.0, 160.0);
      if (_dragY > _maxDragY) _maxDragY = _dragY;
      if (_dragY < _minDragY) _minDragY = _dragY;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final y = _dragY;
    final wasBasicallyATap = _totalMovement < 8 && velocity.abs() < 200;
    setState(() {
      _dragging = false;
      _dragY = 0;
    });

    if (wasBasicallyATap) {
      _openFullPlayer();
      return;
    }
    final wentMeaningfullyDown = _maxDragY > 40;
    final wentMeaningfullyUp = _minDragY < -40;
    if (!wentMeaningfullyDown &&
        (_minDragY < _openThreshold || (velocity < -400 && y <= 0))) {
      _openFullPlayer();
      return;
    }
    if (!wentMeaningfullyUp &&
        (_maxDragY > _dismissThreshold || velocity > 400)) {
      AurumHaptics.medium();
      final player = context.read<PlayerProvider>();
      player.pause();
      player.dismissMiniPlayer();
    }
  }

  void _openFullPlayer() {
    AurumHaptics.light();

    final artworkUrl = context.read<PlayerProvider>().currentSong?.artworkUrl;
    if (artworkUrl != null &&
        artworkUrl.isNotEmpty &&
        !artworkUrl.startsWith('content://') &&
        !artworkUrl.startsWith('/') &&
        !artworkUrl.startsWith('file://')) {
      precacheImage(
        CachedNetworkImageProvider(artworkUrl, maxWidth: 220, cacheManager: AurumImageCache()),
        context,
      ).catchError((_) {
      });
    }

    pushFullPlayer(context);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, _MiniPlayerVis>(
      selector: (_, p) => _MiniPlayerVis(p.miniPlayerVisible, p.currentSong),
      builder: (context, vis, _) {
        final player = context.read<PlayerProvider>();
        if (!vis.visible || vis.song == null) {
          return const SizedBox.shrink();
        }

        final currentSong = vis.song;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncTintForSong(currentSong);
        });

        final frac = (_dragY.abs() / 160.0).clamp(0.0, 1.0);
        final translateY = _dragging ? _dragY.clamp(-60.0, 200.0) : 0.0;

        return GestureDetector(
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          onVerticalDragCancel: _onDragCancel,
          child: Transform.translate(
            offset: Offset(0, translateY),
            child: _NoLayerPassthrough(
              child: ValueListenableBuilder<String>(
                valueListenable: AudioPrefs.navBarStyleNotifier,
                builder: (context, navStyle, _) {
                  final docked = navStyle == 'Docked';
                  return Padding(
                padding: docked
                    ? const EdgeInsets.fromLTRB(6, 0, 6, 3)
                    : const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: ValueListenableBuilder<bool>(
                  valueListenable: AudioPrefs.liquidGlassEnabledNotifier,
                  builder: (context, glassOnForClip, clipChild) => _ClipIf(
                    clip: docked && !glassOnForClip,
                    borderRadius: BorderRadius.circular(10),
                    child: clipChild!,
                  ),
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(
                        begin: _tintColor ?? const Color(0xFF1A1714),
                        end: _tintColor ?? const Color(0xFF1A1714)),
                    duration: AurumMotion.durationOrZero(AurumMotion.long2),
                    curve: AurumMotion.standard,
                    builder: (context, animatedTint, _) {
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      const fallback = Color(0xFF1A1714);
                      final baseTint = animatedTint ?? fallback;
                      return ValueListenableBuilder<bool>(
                          valueListenable: AudioPrefs.liquidGlassEnabledNotifier,
                          builder: (context, glassOn, _) {
                            final blurSigma =
                                glassOn ? AudioPrefs.glassMiniSigma : 0.0;
                            final isTopRoute =
                                ModalRoute.of(context)?.isCurrent ?? true;
                            final effectiveBlurSigma =
                                isTopRoute ? blurSigma : 0.0;
                            final solidBg = baseTint;
                            final useGlass = effectiveBlurSigma > 0;
                            final Color onColor = useGlass
                                ? (isDark ? Colors.white : Colors.black)
                                : (solidBg.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white);
                            final innerContent = _miniPlayerContent(
                                context, player,
                                onTint: onColor,
                                compact: docked);
                            final barRadius = docked
                                ? BorderRadius.circular(10)
                                : const BorderRadius.vertical(
                                    top: Radius.circular(20),
                                  );
                            return SizedBox(
                              height: docked ? 60 : 68,
                              child: AurumGlass(
                                sigma: effectiveBlurSigma,
                                borderRadius: barRadius,
                                isDark: isDark,
                                tintColor: solidBg,
                                useTintInGlass: false,
                                child: innerContent,
                              ),
                            );
                          },
                        );
                    },
                  ),
                ),
              );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _miniPlayerContent(BuildContext context, PlayerProvider player,
      {required Color onTint, bool compact = false}) {
    final song = player.currentSong!;
    final secondaryOnTint = onTint.withValues(alpha: 0.72);
    final artSize = compact ? 38.0 : 44.0;
    final artRadius = compact ? 8.0 : 10.0;
    final titleSize = compact ? 13.0 : 13.0;
    final artistSize = compact ? 11.0 : 11.0;
    final gapAfterArt = compact ? 10.0 : 12.0;
    final gapBeforeControls = compact ? 8.0 : 8.0;
    final controlSize = compact ? 22.0 : 22.0;
    final controlGap = compact ? 14.0 : 4.0;
    return Column(
      children: [
        _MiniProgressBar(player: player, squareTop: compact),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
            child: Row(
              children: [
                AurumArtwork(
                  url: song.artworkUrl,
                  size: artSize,
                  borderRadius: artRadius,
                ),
                SizedBox(width: gapAfterArt),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        song.title,
                        style: TextStyle(
                          color: onTint,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: compact ? 1 : 2),
                      Text(
                        song.artist,
                        style: TextStyle(
                          color: secondaryOnTint,
                          fontSize: artistSize,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: gapBeforeControls),
                if (compact) ...[
                  _PlayBtn(player: player, compact: true),
                  SizedBox(width: controlGap),
                  Selector<FavoritesProvider, bool>(
                    selector: (_, f) => f.isFavorite(song.id),
                    builder: (context, isLiked, _) => SizedBox(
                      width: 36,
                      height: 36,
                      child: FittedBox(
                        child: AurumLikeButton(
                          isLiked: isLiked,
                          size: 20,
                          likedColor: AurumTheme.accentOf(context),
                          unlikedColor: secondaryOnTint,
                          haptic: false,
                          onTap: () {
                            final l10n = AppLocalizations.of(context)!;
                            PremiumGate.guard(
                              context,
                              feature: l10n.fpLikeSongsFeature,
                              description: l10n.fpLikeSongsSignIn,
                              requiresLoginOnly: true,
                              onAllowed: () {
                                isLiked
                                    ? AurumHaptics.selection()
                                    : AurumHaptics.medium();
                                context
                                    .read<FavoritesProvider>()
                                    .toggleFavorite(song);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  _ControlBtn(
                    icon: Icons.skip_previous_rounded,
                    onTap: () {
                      AurumHaptics.selection();
                      player.skipPrev();
                    },
                    size: controlSize,
                    color: secondaryOnTint,
                  ),
                  SizedBox(width: controlGap),
                  _PlayBtn(player: player, compact: false),
                  SizedBox(width: controlGap),
                  _ControlBtn(
                    icon: Icons.skip_next_rounded,
                    onTap: () {
                      AurumHaptics.selection();
                      player.skipNext();
                    },
                    size: controlSize,
                    color: secondaryOnTint,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniProgressBar extends StatelessWidget {
  final PlayerProvider player;
  final bool squareTop;
  const _MiniProgressBar({required this.player, this.squareTop = false});

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, double>(
      selector: (_, p) => p.progress,
      builder: (context, progress, _) => ClipRRect(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(squareTop ? 10 : 28)),
        child: RepaintBoundary(
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(AurumTheme.accentOf(context)),
            minHeight: 2,
          ),
        ),
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  final PlayerProvider player;
  final bool compact;
  const _PlayBtn({required this.player, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final accent = context.watch<ThemeProvider>().accentColor;
    final btnSize = compact ? 34.0 : 36.0;
    final iconSize = compact ? 18.0 : 20.0;
    return Selector<PlayerProvider, ({bool isLoading, bool isPlaying})>(
      selector: (_, p) => (isLoading: p.isLoading, isPlaying: p.isPlaying),
      builder: (context, state, _) {
        if (state.isLoading) {
          return Opacity(
            opacity: 0.35,
            child: SizedBox(
              width: btnSize,
              height: btnSize,
              child:
                  Icon(Icons.play_arrow_rounded, color: accent, size: iconSize + 6),
            ),
          );
        }
        return AurumPressable(
          scaleAmount: 0.88,
          haptic: false,
          onTap: () {
            AurumHaptics.heavy();
            player.togglePlay();
          },
          child: Container(
            width: btnSize,
            height: btnSize,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
            ),
            child: AurumPlayPauseIcon(
              isPlaying: state.isPlaying,
              color: accent.computeLuminance() > 0.5 ? Colors.black : Colors.white,
              size: iconSize,
            ),
          ),
        );
      },
    );
  }
}

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final Color? color;

  const _ControlBtn({
    required this.icon,
    required this.onTap,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AurumPressable(
      scaleAmount: 0.82,
      haptic: false,
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          icon,
          color: color ?? AurumTheme.textSecondaryOf(context),
          size: size,
        ),
      ),
    );
  }
}

class _NoLayerPassthrough extends StatelessWidget {
  final Widget child;
  const _NoLayerPassthrough({required this.child});
  @override
  Widget build(BuildContext context) => child;
}

class _ClipIf extends StatelessWidget {
  final bool clip;
  final BorderRadius borderRadius;
  final Widget child;
  const _ClipIf({
    required this.clip,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => clip
      ? ClipRRect(borderRadius: borderRadius, child: child)
      : child;
}
