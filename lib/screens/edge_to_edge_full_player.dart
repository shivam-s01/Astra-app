// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:cached_network_image/cached_network_image.dart';

import '../providers/player_provider.dart';
import '../providers/favorites_provider.dart';
import '../models/song.dart';
import '../theme/aurum_theme.dart';
import '../utils/artwork_palette_cache.dart';
import '../widgets/aurum_seek_bar.dart';
import '../widgets/aurum_stream_quality_chip.dart';
import '../widgets/aurum_like_button.dart';
import '../widgets/aurum_play_pause_icon.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/audio_output_sheet.dart';
import '../widgets/jam_entry.dart';
import '../widgets/aurum_artwork.dart' show AurumArtwork;
import '../services/native_engine_bridge.dart'
    show MediaVolume, AudioOutputDevice, AudioOutputDeviceKind, AudioOutputDevices;
import '../utils/aurum_haptics.dart';
import '../utils/route_drag_dismiss.dart';
import '../utils/aurum_sheet.dart';
import '../l10n/generated/app_localizations.dart';
import '../widgets/premium_gate.dart';
import '../utils/aurum_transitions.dart';
import 'artist_screen.dart';
import 'full_player_screen.dart'
    show showAurumFullPlayerOptionsSheet, showSleepTimerForSong, showSongInfoDialog, AurumLyricsPage;
import 'settings_player_screen.dart' show SleepTimerService;

class EdgeToEdgeFullPlayer extends StatefulWidget {
  const EdgeToEdgeFullPlayer({super.key});

  @override
  State<EdgeToEdgeFullPlayer> createState() => _EdgeToEdgeFullPlayerState();
}

class _EdgeToEdgeFullPlayerState extends State<EdgeToEdgeFullPlayer> {
  late final RouteDragDismiss _routeDrag;
  static const double _routeDismissDistance = 120.0;
  static const double _routeDismissVelocity = 900.0;
  bool _lyricsOpen = false;

  _PanelPalette _panel = const _PanelPalette(
    top: Color(0xFF1E1B2E),
    mid: Color(0xFF17141F),
    bottom: Color(0xFF0C0A12),
    glow: Color(0xFF2A2440),
  );
  _PanelPalette _prevPanel = const _PanelPalette(
    top: Color(0xFF1E1B2E),
    mid: Color(0xFF17141F),
    bottom: Color(0xFF0C0A12),
    glow: Color(0xFF2A2440),
  );
  String? _paletteUrl;

  static const SystemUiOverlayStyle _immersiveStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  @override
  void initState() {
    super.initState();
    _routeDrag = RouteDragDismiss(context);
    SystemChrome.setSystemUIOverlayStyle(_immersiveStyle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SystemChrome.setSystemUIOverlayStyle(_immersiveStyle);
  }

  @override
  void dispose() {
    _routeDrag.cancel();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    if (!_routeDrag.isActive) {
      if (d.delta.dy <= 0) return;
      if (!_routeDrag.start()) return;
    }
    _routeDrag.update(d.delta.dy);
  }

  void _handleDragEnd(DragEndDetails d) {
    if (!_routeDrag.isActive) return;
    _routeDrag.end(
      velocityPxPerSec: d.velocity.pixelsPerSecond.dy,
      dismissDistance: _routeDismissDistance,
      dismissVelocity: _routeDismissVelocity,
    );
  }

  void _handleDragCancel() {
    _routeDrag.cancel();
  }

  Color _boostColor(
    Color c, {
    required double satBoost,
    required double valueTarget,
    required double valueMin,
    required double valueMax,
  }) {
    final hsv = HSVColor.fromColor(c);
    final sat = (hsv.saturation * satBoost).clamp(0.0, 1.0);
    final val = (hsv.value * 0.6 + valueTarget * 0.4).clamp(valueMin, valueMax);
    return hsv.withSaturation(sat).withValue(val).toColor();
  }

  _PanelPalette _paletteFrom(ArtworkPalette p) {
    final hueSource =
        p.gradientColors.isNotEmpty ? p.gradientColors.first : p.vibrant;

    final top = ensureContrastSafe(
      _boostColor(
        hueSource,
        satBoost: 1.25,
        valueTarget: 0.58,
        valueMin: 0.14,
        valueMax: 0.58,
      ),
      isLight: false,
    );
    final mid = ensureContrastSafe(
      _boostColor(
        Color.lerp(hueSource, p.darkMuted, 0.35)!,
        satBoost: 1.2,
        valueTarget: 0.40,
        valueMin: 0.09,
        valueMax: 0.40,
      ),
      isLight: false,
    );
    final bottom = ensureContrastSafe(
      _boostColor(
        Color.lerp(hueSource, p.darkMuted, 0.7)!,
        satBoost: 1.15,
        valueTarget: 0.20,
        valueMin: 0.04,
        valueMax: 0.22,
      ),
      isLight: false,
    );
    final glow = _boostColor(
      Color.lerp(hueSource, p.lightVibrant, 0.4)!,
      satBoost: 1.2,
      valueTarget: 0.85,
      valueMin: 0.5,
      valueMax: 0.95,
    );
    return _PanelPalette(top: top, mid: mid, bottom: bottom, glow: glow);
  }

  void _loadPaletteFor(String url) {
    if (url.isEmpty || url == _paletteUrl) return;
    _paletteUrl = url;

    final cached = ArtworkPaletteCache.peek(url);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _prevPanel = _panel;
          _panel = _paletteFrom(cached);
        });
      }
      return;
    }

    ArtworkPaletteCache.get(url).then((palette) {
      if (!mounted || _paletteUrl != url) return;
      setState(() {
        _prevPanel = _panel;
        _panel = _paletteFrom(palette);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, (String?, bool, bool, LoopMode, bool)>(
      selector: (_, p) => (
        p.currentSong?.id,
        p.isPlaying,
        p.isLoading,
        p.loopMode,
        p.shuffle,
      ),
      builder: (context, _, __) {
        final player = context.read<PlayerProvider>();
        final song = player.currentSong;
        if (song == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }

        _loadPaletteFor(song.artworkUrl);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: GestureDetector(
              onVerticalDragUpdate: _handleDragUpdate,
              onVerticalDragEnd: _handleDragEnd,
              onVerticalDragCancel: _handleDragCancel,
              child: LayoutBuilder(
                    builder: (context, constraints) {
                      final artHeight = constraints.maxHeight * 0.58;
                      return Stack(
                        children: [
                          TweenAnimationBuilder<Color?>(
                            key: ValueKey('glow_${_panel.hashCode}'),
                            tween: ColorTween(begin: _prevPanel.glow, end: _panel.glow),
                            duration: const Duration(milliseconds: 600),
                            builder: (context, glow, _) => Positioned(
                              top: -60,
                              left: -40,
                              right: -40,
                              height: artHeight + 160,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: const Alignment(0, -0.2),
                                      radius: 0.95,
                                      colors: [
                                        (glow ?? _panel.glow).withOpacity(0.55),
                                        (glow ?? _panel.glow).withOpacity(0.0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: artHeight,
                            child: _lyricsOpen
                                ? AurumArtwork(
                                    url: AurumArtwork.upgradeForFullPlayer(
                                        song.artworkUrl),
                                    size: double.infinity,
                                    borderRadius: 0,
                                    fadeIn: true,
                                  )
                                : Hero(
                                    tag: 'aurum_art_${song.id}',
                                    child: AurumArtwork(
                                      url: AurumArtwork.upgradeForFullPlayer(
                                          song.artworkUrl),
                                      size: double.infinity,
                                      borderRadius: 0,
                                      fadeIn: true,
                                    ),
                                  ),
                          ),

                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: MediaQuery.of(context).padding.top + 36,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.45),
                                      Colors.black.withOpacity(0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            top: artHeight - 280,
                            left: 0,
                            right: 0,
                            height: 280,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      _panel.top.withOpacity(0.06),
                                      _panel.top.withOpacity(0.20),
                                      _panel.top.withOpacity(0.45),
                                      _panel.top.withOpacity(0.78),
                                      _panel.top,
                                    ],
                                    stops: const [0.0, 0.35, 0.55, 0.72, 0.87, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            top: artHeight,
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey('mesh_${_panel.hashCode}'),
                              tween: Tween(begin: 0, end: 1),
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOut,
                              builder: (context, t, __) => DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color.lerp(_prevPanel.top, _panel.top, t)!,
                                      Color.lerp(_prevPanel.mid, _panel.mid, t)!,
                                      Color.lerp(_prevPanel.bottom, _panel.bottom, t)!,
                                    ],
                                    stops: const [0.0, 0.45, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 26),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  const Spacer(),
                                  _TitleRow(song: song),
                                  const SizedBox(height: 32),
                                  _ScrubBar(player: player, accent: _panel.glow),
                                  const SizedBox(height: 16),
                                  _TransportRow(
                                    player: player,
                                    accent: _panel.glow,
                                    prevAccent: _prevPanel.glow,
                                  ),
                                  const SizedBox(height: 26),
                                  _VolumeRow(player: player),
                                  const SizedBox(height: 32),
                                  _BottomIconRow(
                                    player: player,
                                    song: song,
                                    panel: _panel,
                                    onLyricsOpenChanged: (open) {
                                      if (!mounted) return;
                                      setState(() => _lyricsOpen = open);
                                    },
                                  ),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
            ),
          ),
        );
      },
    );
  }
}

class _PanelPalette {
  const _PanelPalette({
    required this.top,
    required this.mid,
    required this.bottom,
    required this.glow,
  });
  final Color top;
  final Color mid;
  final Color bottom;
  final Color glow;

  @override
  bool operator ==(Object other) =>
      other is _PanelPalette &&
      other.top == top &&
      other.mid == mid &&
      other.bottom == bottom &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(top, mid, bottom, glow);
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesProvider>(
      builder: (context, fav, _) {
        final isLiked = fav.isFavorite(song.id);
        return Row(
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
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openArtistFromPlayer(context, song),
                    child: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            _CircleIconButton(
              icon: Icons.more_vert_rounded,
              onTap: () => showAurumFullPlayerOptionsSheet(
                context,
                song,
                accentColor: AurumTheme.accentOf(context),
              ),
            ),
            const SizedBox(width: 14),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.14),
              ),
              alignment: Alignment.center,
              child: AurumLikeButton(
                isLiked: isLiked,
                onTap: () => fav.toggleFavorite(song),
                size: 20,
                unlikedColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AurumPressable(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.14),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AurumPressable(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.14),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 19),
      ),
    );
  }
}

class _ScrubBar extends StatelessWidget {
  const _ScrubBar({required this.player, required this.accent});
  final PlayerProvider player;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tint = Color.lerp(accent, Colors.white, 0.35)!;
    return AurumSeekBar(
      player: player,
      hPad: 4,
      activeColor: tint,
      inactiveColor: Colors.white.withOpacity(0.22),
      timeColor: Colors.white.withOpacity(0.75),
      centerLabel: AurumStreamQualityChip(player: player),
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.player,
    required this.accent,
    required this.prevAccent,
  });
  final PlayerProvider player;
  final Color accent;
  final Color prevAccent;

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, (bool, bool)>(
      selector: (_, p) => (p.isPlaying, p.isLoading),
      builder: (context, data, _) {
        final (isPlaying, isLoading) = data;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              iconSize: 34,
              icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white),
              onPressed: () {
                AurumHaptics.light();
                player.skipPrev();
              },
            ),
            GestureDetector(
              onTap: () {
                AurumHaptics.medium();
                player.togglePlay();
              },
              child: SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : AurumPlayPauseIcon(isPlaying: isPlaying, color: Colors.white, size: 34),
                ),
              ),
            ),
            IconButton(
              iconSize: 34,
              icon: const Icon(Icons.fast_forward_rounded, color: Colors.white),
              onPressed: () {
                AurumHaptics.light();
                player.skipNext().then((allowed) {
                  if (!allowed && context.mounted) {
                    PremiumGate.show(
                      context,
                      feature: AppLocalizations.of(context)!.fpUnlimitedSkipsFeature,
                      description: AppLocalizations.of(context)!.fpUnlimitedSkipsSignIn,
                      requiresLoginOnly: true,
                    );
                  }
                });
              },
            ),
          ],
        );
      },
    );
  }
}

class _VolumeRow extends StatefulWidget {
  const _VolumeRow({required this.player});
  final PlayerProvider player;

  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  int _level = 0;
  int _max = 15;
  bool _loaded = false;
  int? _fadeGen;
  bool _userDriving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mv = await widget.player.engine.getMediaVolume();
      if (!mounted) return;
      setState(() {
        _level = mv.level;
        _max = mv.max == 0 ? 15 : mv.max;
        _loaded = true;
      });
    } catch (_) {
    }
  }

  void _onChanged(double v) {
    _fadeGen = (_fadeGen ?? 0) + 1;
    final level = v.round();
    setState(() => _level = level);
    widget.player.engine.setMediaVolume(level);
  }

  Future<void> _fadeToMute() async {
    final gen = (_fadeGen ?? 0) + 1;
    _fadeGen = gen;
    AurumHaptics.light();
    setState(() => _userDriving = true);
    var v = _level;
    while (v > 0 && _fadeGen == gen && mounted) {
      v = (v - 1).clamp(0, _max);
      setState(() => _level = v);
      widget.player.engine.setMediaVolume(v);
      await Future.delayed(const Duration(milliseconds: 35));
    }
    if (mounted) setState(() => _userDriving = false);
  }

  void _jumpToMax() {
    _fadeGen = (_fadeGen ?? 0) + 1;
    AurumHaptics.light();
    setState(() => _level = _max);
    widget.player.engine.setMediaVolume(_max);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 20);
    return StreamBuilder<MediaVolume?>(
      stream: widget.player.engine.mediaVolumeStream,
      builder: (context, snapshot) {
        final live = snapshot.data;
        final level = (!_userDriving && live != null) ? live.level : _level;
        final max = (!_userDriving && live != null && live.max > 0) ? live.max : _max;
        return Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _fadeToMute,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  level == 0 ? Icons.volume_off_rounded : Icons.volume_mute_rounded,
                  color: Colors.white.withOpacity(0.7),
                  size: 20,
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.white.withOpacity(0.9),
                  inactiveTrackColor: Colors.white.withOpacity(0.22),
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: level.toDouble().clamp(0, max.toDouble()),
                  min: 0,
                  max: max.toDouble(),
                  onChangeStart: (_) => setState(() {
                    _level = level;
                    _max = max;
                    _userDriving = true;
                  }),
                  onChanged: _onChanged,
                  onChangeEnd: (_) => setState(() => _userDriving = false),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _jumpToMax,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.volume_up_rounded, color: Colors.white.withOpacity(0.7), size: 20),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BottomIconRow extends StatefulWidget {
  const _BottomIconRow({
    required this.player,
    required this.song,
    required this.panel,
    required this.onLyricsOpenChanged,
  });
  final PlayerProvider player;
  final Song song;
  final _PanelPalette panel;
  final ValueChanged<bool> onLyricsOpenChanged;

  @override
  State<_BottomIconRow> createState() => _BottomIconRowState();
}

class _BottomIconRowState extends State<_BottomIconRow> {
  AudioOutputDevices? _initialDevices;

  @override
  void initState() {
    super.initState();
    SleepTimerService.instance.addListener(_onSleepTick);
    widget.player.engine.getAudioOutputDevices().then((d) {
      if (mounted) setState(() => _initialDevices = d);
    });
  }

  @override
  void dispose() {
    SleepTimerService.instance.removeListener(_onSleepTick);
    super.dispose();
  }

  void _onSleepTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sleepActive = SleepTimerService.instance.isActive;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _RoundIconButton(
              icon: Icons.reorder_rounded,
              onTap: () => _openQueueSheet(context),
            ),
            const SizedBox(width: 10),
            _RoundIconButton(
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () => _openLyricsSheet(context),
            ),
            const SizedBox(width: 10),
            _RoundIconButton(
              icon: sleepActive ? Icons.bedtime_rounded : Icons.dark_mode_outlined,
              onTap: () => showSleepOrJamSheet(context, widget.player),
            ),
          ],
        ),
        StreamBuilder<AudioOutputDevices?>(
          stream: widget.player.engine.outputDevicesStream,
          builder: (context, snapshot) {
            final devices = snapshot.data ?? _initialDevices;
            AudioOutputDevice? selected;
            for (final d in devices?.devices ?? const <AudioOutputDevice>[]) {
              if (d.selected) {
                selected = d;
                break;
              }
            }
            final icon = switch (selected?.kind) {
              AudioOutputDeviceKind.bluetooth => Icons.bluetooth_audio_rounded,
              AudioOutputDeviceKind.wired => Icons.headphones_rounded,
              AudioOutputDeviceKind.usb => Icons.usb_rounded,
              AudioOutputDeviceKind.speaker => Icons.smartphone_rounded,
              _ => Icons.speaker_group_rounded,
            };
            final label = selected?.name ?? 'Speaker';
            return Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.14),
                borderRadius: BorderRadius.circular(19),
              ),
              child: GestureDetector(
                onTap: () => showAudioOutputSheet(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 110),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _openQueueSheet(BuildContext context) {
    AurumHaptics.light();
    final song = context.read<PlayerProvider>().currentSong;
    final panel = widget.panel;
    final sheetController = DraggableScrollableController();
    showAurumModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withAlpha(150),
      builder: (_) => DraggableScrollableSheet(
        controller: sheetController,
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.94,
        expand: false,
        snap: true,
        snapSizes: const [0.5, 0.82, 0.94],
        builder: (context, _) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [panel.top, panel.mid, panel.bottom],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: _EdgeToEdgeQueueSheetBody(
              sheetController: sheetController,
              currentSong: song,
              panel: panel,
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      sheetController.dispose();
    });
  }

  void _openLyricsSheet(BuildContext context) {
    AurumHaptics.light();
    widget.onLyricsOpenChanged(true);
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => _EdgeToEdgeImmersiveLyrics(
          song: widget.song,
          panel: widget.panel,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    ).then((_) => widget.onLyricsOpenChanged(false));
  }
}

class _EdgeToEdgeImmersiveLyrics extends StatefulWidget {
  const _EdgeToEdgeImmersiveLyrics({
    required this.song,
    required this.panel,
  });
  final Song song;
  final _PanelPalette panel;

  @override
  State<_EdgeToEdgeImmersiveLyrics> createState() => _EdgeToEdgeImmersiveLyricsState();
}

class _EdgeToEdgeImmersiveLyricsState extends State<_EdgeToEdgeImmersiveLyrics>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    AurumHaptics.light();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_controller.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [widget.panel.top, widget.panel.mid, widget.panel.bottom],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                if (widget.song.artworkUrl.isNotEmpty)
                  Opacity(
                    opacity: 0.35,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                      child: AurumArtwork(
                        url: widget.song.artworkUrl,
                        size: double.infinity,
                        borderRadius: 0,
                        isBlurredBackground: true,
                      ),
                    ),
                  ),
                DecoratedBox(decoration: BoxDecoration(color: Colors.black.withOpacity(0.38))),

                Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 16),
                    child: SafeArea(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                            child: Row(
                              children: [
                                Hero(
                                  tag: 'aurum_art_${widget.song.id}',
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: AurumArtwork(
                                      url: widget.song.artworkUrl,
                                      size: 52,
                                      borderRadius: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        widget.song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        widget.song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.7),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _CircleIconButton(
                                  icon: Icons.close_rounded,
                                  onTap: _close,
                                ),
                                const SizedBox(width: 10),
                                _CircleIconButton(
                                  icon: Icons.more_horiz_rounded,
                                  onTap: () => showAurumFullPlayerOptionsSheet(
                                    context,
                                    widget.song,
                                    accentColor: AurumTheme.accentOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Expanded(child: AurumLyricsPage(onDarkBackdrop: true)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EdgeToEdgeQueueSheetBody extends StatefulWidget {
  const _EdgeToEdgeQueueSheetBody({
    required this.sheetController,
    required this.currentSong,
    required this.panel,
  });

  final DraggableScrollableController sheetController;
  final Song? currentSong;
  final _PanelPalette panel;

  @override
  State<_EdgeToEdgeQueueSheetBody> createState() => _EdgeToEdgeQueueSheetBodyState();
}

class _EdgeToEdgeQueueSheetBodyState extends State<_EdgeToEdgeQueueSheetBody> {
  final ScrollController _listScrollController = ScrollController();

  List<Song> _localQueue = const [];
  int? _localCurrent;

  List<String>? _pendingTargetIds;
  DateTime? _pendingTargetSetAt;
  static const _pendingTargetTimeout = Duration(seconds: 3);

  bool _isDragging = false;
  List<Song>? _latestProviderQueue;
  int? _latestProviderCurrent;

  Future<void> _providerOps = Future<void>.value();
  void _enqueueProviderOp(Future<void> Function() op) {
    _providerOps = _providerOps.then((_) => op()).catchError((_) {});
  }

  void _commitPending() {
    _pendingTargetIds = _localQueue.map((s) => s.id).toList();
    _pendingTargetSetAt = DateTime.now();
  }

  void _syncFromProvider(List<Song> queue, int? current) {
    _latestProviderQueue = queue;
    _latestProviderCurrent = current;
    if (_isDragging) return;
    final pending = _pendingTargetIds;
    if (pending != null) {
      final setAt = _pendingTargetSetAt;
      final timedOut = setAt == null ||
          DateTime.now().difference(setAt) > _pendingTargetTimeout;
      var matches = queue.length >= pending.length;
      if (matches) {
        for (var i = 0; i < pending.length; i++) {
          if (queue[i].id != pending[i]) {
            matches = false;
            break;
          }
        }
      }
      if (!matches && !timedOut) return;
      _pendingTargetIds = null;
      _pendingTargetSetAt = null;
    }
    _localQueue = List<Song>.of(queue);
    _localCurrent = current;
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }
  final bool _reorderLocked = false;

  String _totalDuration(List<Song> queue) {
    final totalSeconds = queue.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.currentSong;
    final panel = widget.panel;
    return Selector<PlayerProvider,
        ({List<Song> queue, int? current, String sig})>(
      selector: (_, p) => (
        queue: p.queue,
        current: p.currentIndex,
        sig: p.queue.map((e) => e.id).join('|'),
      ),
      builder: (context, data, _) {
        _syncFromProvider(data.queue, data.current);
        final queue = _localQueue;
        final seenIds = <String, int>{};
        final tileKeys = List<Key>.generate(queue.length, (i) {
          final id = queue[i].id;
          final n = (seenIds[id] = (seenIds[id] ?? 0) + 1);
          return ValueKey('e2eq_${id}_$n');
        });
        return Column(
          children: [
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                if (!widget.sheetController.isAttached) return;
                final screenHeight = MediaQuery.of(context).size.height;
                if (screenHeight <= 0) return;
                final delta = -details.delta.dy / screenHeight;
                final next = (widget.sheetController.size + delta).clamp(0.5, 0.94);
                widget.sheetController.jumpTo(next);
              },
              onVerticalDragEnd: (details) {
                if (!widget.sheetController.isAttached) return;
                const stops = [0.5, 0.82, 0.94];
                final current = widget.sheetController.size;
                var nearest = stops.first;
                var bestDist = (current - nearest).abs();
                for (final s in stops.skip(1)) {
                  final dist = (current - s).abs();
                  if (dist < bestDist) {
                    bestDist = dist;
                    nearest = s;
                  }
                }
                widget.sheetController.animateTo(
                  nearest,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                color: Colors.transparent,
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (song != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AurumArtwork(
                        url: song.artworkUrl,
                        size: 64,
                        borderRadius: 12,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    Selector<FavoritesProvider, bool>(
                      selector: (_, f) => f.isFavorite(song.id),
                      builder: (context, isFav, _) => IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        onPressed: () {
                          AurumHaptics.light();
                          context.read<FavoritesProvider>().toggleFavorite(song);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 20),
                      onPressed: () {
                        if (song != null) {
                          showAurumFullPlayerOptionsSheet(context, song, accentColor: panel.glow);
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: Colors.white.withOpacity(0.75), size: 20),
                      onPressed: queue.isEmpty
                          ? null
                          : () async {
                              AurumHaptics.medium();
                              final player = context.read<PlayerProvider>();
                              final playingSong = player.currentSong;
                              final snapshot = List.of(player.queue);
                              for (var i = snapshot.length - 1; i >= 0; i--) {
                                if (identical(snapshot[i], playingSong)) continue;
                                final liveIndex = player.queue
                                    .indexWhere((s) => identical(s, snapshot[i]));
                                if (liveIndex != -1) {
                                  await player.removeFromQueue(liveIndex);
                                }
                              }
                            },
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        '${queue.length} songs  •  ${_totalDuration(queue)}',
                        style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Selector<PlayerProvider, (bool, LoopMode)>(
                selector: (_, p) => (p.shuffle, p.loopMode),
                builder: (context, data2, _) {
                  final (shuffleOn, loop) = data2;
                  return Row(
                    children: [
                      Expanded(
                        child: _QueueModeButton(
                          icon: Icons.shuffle_rounded,
                          active: shuffleOn,
                          panel: panel,
                          onTap: () {
                            AurumHaptics.light();
                            context.read<PlayerProvider>().toggleShuffle();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QueueModeButton(
                          icon: loop == LoopMode.one
                              ? Icons.repeat_one_rounded
                              : Icons.all_inclusive_rounded,
                          active: loop != LoopMode.off,
                          panel: panel,
                          onTap: () {
                            AurumHaptics.light();
                            context.read<PlayerProvider>().toggleLoop();
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Continue Playing',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Autoplaying similar music',
                    style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Divider(color: Colors.white.withOpacity(0.12), height: 1),
            Expanded(
              child: queue.isEmpty
                  ? Center(
                      child: Text(
                        'Queue is empty',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    )
                  : ReorderableListView.builder(
                      scrollController: _listScrollController,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      buildDefaultDragHandles: false,
                      itemCount: queue.length,
                      physics: const ClampingScrollPhysics(),
                      proxyDecorator: (child, index, animation) {
                        return Material(
                          type: MaterialType.transparency,
                          child: AnimatedBuilder(
                            animation: animation,
                            builder: (context, _) {
                              final t =
                                  Curves.easeOut.transform(animation.value);
                              return Transform.scale(
                                scale: 1.0 + (0.03 * t),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: t == 0
                                        ? const []
                                        : [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.35 * t),
                                              blurRadius: 16 * t,
                                              offset: Offset(0, 6 * t),
                                            ),
                                          ],
                                  ),
                                  child: child,
                                ),
                              );
                            },
                            child: child,
                          ),
                        );
                      },
                      onReorderStart: (_) {
                        _isDragging = true;
                        AurumHaptics.light();
                      },
                      onReorderEnd: (_) {
                        _isDragging = false;
                        final q = _latestProviderQueue;
                        if (_pendingTargetIds == null && q != null && mounted) {
                          setState(() => _syncFromProvider(
                              q, _latestProviderCurrent));
                        }
                      },
                      onReorder: (oldIndex, newIndex) {
                        if (_reorderLocked) return;
                        if (newIndex > oldIndex) newIndex -= 1;
                        if (oldIndex == newIndex) return;
                        if (oldIndex < 0 || oldIndex >= _localQueue.length) {
                          return;
                        }
                        AurumHaptics.light();
                        final player = context.read<PlayerProvider>();
                        final from = oldIndex;
                        final to = newIndex;
                        setState(() {
                          final item = _localQueue.removeAt(from);
                          final clampedTo = to.clamp(0, _localQueue.length);
                          _localQueue.insert(clampedTo, item);
                          final cur = _localCurrent ?? -1;
                          if (from == cur) {
                            _localCurrent = clampedTo;
                          } else if (from < cur && clampedTo >= cur) {
                            _localCurrent = cur - 1;
                          } else if (from > cur && clampedTo <= cur) {
                            _localCurrent = cur + 1;
                          }
                          _commitPending();
                        });
                        _enqueueProviderOp(() => player.moveQueueItem(from, to));
                      },
                      itemBuilder: (context, i) {
                        final s = queue[i];
                        final isCurrent = i == _localCurrent;
                        final row = Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isCurrent ? panel.glow.withOpacity(0.32) : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: AurumArtwork(
                                  url: s.artworkUrl,
                                  size: 52,
                                  borderRadius: 10,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    AurumHaptics.light();
                                    context.read<PlayerProvider>().skipToIndex(i);
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        s.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${s.artist} • ${s.durationString}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 18),
                                onPressed: () => _showQueueItemActions(
                                  context,
                                  song: s,
                                  index: i,
                                  isCurrent: isCurrent,
                                  accentColor: panel.glow,
                                ),
                              ),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {},
                                child: ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.drag_handle_rounded,
                                      color: Colors.white.withOpacity(0.85),
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (isCurrent) {
                          return KeyedSubtree(
                            key: tileKeys[i],
                            child: row,
                          );
                        }
                        return Dismissible(
                          key: tileKeys[i],
                          direction: DismissDirection.horizontal,
                          background: _dismissBackground(alignStart: true),
                          secondaryBackground: _dismissBackground(alignStart: false),
                          onDismissed: (_) {
                            AurumHaptics.medium();
                            var idx = _localQueue.indexWhere((x) => identical(x, s));
                            if (idx < 0) {
                              idx = _localQueue.indexWhere((x) => x.id == s.id);
                            }
                            if (idx < 0) return;
                            final player = context.read<PlayerProvider>();
                            setState(() {
                              _localQueue.removeAt(idx);
                              final cur = _localCurrent;
                              if (cur != null && idx < cur) {
                                _localCurrent = cur - 1;
                              }
                              _commitPending();
                            });
                            _enqueueProviderOp(() => player.removeFromQueue(idx));
                          },
                          child: row,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _dismissBackground({required bool alignStart}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      child: const Icon(Icons.delete_rounded, color: Colors.white, size: 22),
    );
  }

  void _showQueueItemActions(
    BuildContext context, {
    required Song song,
    required int index,
    required bool isCurrent,
    required Color accentColor,
  }) {
    AurumHaptics.light();
    showAurumModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withAlpha(150),
      builder: (sheetContext) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          color: AurumTheme.bgElevatedOf(context),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.skip_next_rounded, color: accentColor),
                  title: Text(song.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  subtitle: Text(song.artist,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withOpacity(0.6))),
                  dense: true,
                ),
                const Divider(color: Colors.white24, height: 1),
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded, color: Colors.white),
                  title: const Text('Play Next', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    if (isCurrent) return;
                    AurumHaptics.selection();
                    final p = context.read<PlayerProvider>();
                    await p.removeFromQueue(index);
                    await p.playNext(song);
                  },
                ),
                if (!isCurrent)
                  ListTile(
                    leading: const Icon(Icons.vertical_align_top_rounded, color: Colors.white),
                    title: const Text('Move to Top', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      AurumHaptics.selection();
                      final p = context.read<PlayerProvider>();
                      final target = p.currentIndex + 1;
                      p.moveQueueItem(index, index < target ? target - 1 : target);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded, color: Colors.white),
                  title: const Text('Song Info', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    showSongInfoDialog(context, song);
                  },
                ),
                if (!isCurrent)
                  ListTile(
                    leading: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent),
                    title: const Text('Remove from Queue', style: TextStyle(color: Colors.redAccent)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      AurumHaptics.medium();
                      context.read<PlayerProvider>().removeFromQueue(index);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueModeButton extends StatefulWidget {
  const _QueueModeButton({
    required this.icon,
    required this.active,
    required this.panel,
    required this.onTap,
  });
  final IconData icon;
  final bool active;
  final _PanelPalette panel;
  final VoidCallback onTap;

  @override
  State<_QueueModeButton> createState() => _QueueModeButtonState();
}

class _QueueModeButtonState extends State<_QueueModeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
    reverseDuration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 0.94)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut, reverseCurve: Curves.easeOutCubic));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      onTap: () {
        AurumHaptics.selection();
        widget.onTap();
      },
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 52,
          decoration: BoxDecoration(
            color: widget.active
                ? widget.panel.glow.withOpacity(0.38)
                : Colors.white.withOpacity(0.10),
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(scale: anim, child: child),
            ),
            child: Icon(
              widget.icon,
              key: ValueKey(widget.icon),
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

void _openArtistFromPlayer(BuildContext context, Song song) {
  final raw = song.artist.trim();
  if (raw.isEmpty) return;
  final lower = raw.toLowerCase();
  if (lower == 'unknown' || lower == '<unknown>' || lower == 'unknown artist') {
    return;
  }
  final first = raw
      .split(RegExp(r'\s*(?:,|&|;|\bfeat\.?\s|\bft\.?\s)\s*',
          caseSensitive: false))
      .first
      .trim();
  final name = first.isEmpty ? raw : first;
  final channel = song.artistChannelId;
  AurumHaptics.selection();
  AurumDepthRoute.to(
    context,
    ArtistScreen(
      artistId: (channel != null && channel.isNotEmpty) ? 'yt_$channel' : null,
      artistName: name,
    ),
  );
}
