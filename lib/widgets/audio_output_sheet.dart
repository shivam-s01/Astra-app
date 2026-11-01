// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/aurum_theme.dart';
import '../providers/player_provider.dart';
import '../models/song.dart';
import '../services/native_engine_bridge.dart';
import '../services/audio_prefs.dart';
import '../services/stream_quality_store.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_sheet.dart';
import '../screens/settings_player_screen.dart' show SettingsPlayerScreen;
import '../utils/aurum_transitions.dart';
import 'aurum_artwork.dart';

Future<void> showAudioOutputSheet(BuildContext context) async {
  AurumHaptics.light();
  final isLight = Theme.of(context).brightness == Brightness.light;
  await showAurumModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor:
        isLight ? AurumTheme.lightBgCard : AurumTheme.darkBgElevated,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _AudioOutputSheet(),
  );
}

class _AudioOutputSheet extends StatefulWidget {
  const _AudioOutputSheet();

  @override
  State<_AudioOutputSheet> createState() => _AudioOutputSheetState();
}

class _AudioOutputSheetState extends State<_AudioOutputSheet> {
  AudioOutputDevices? _devices;
  StreamSubscription<AudioOutputDevices?>? _devSub;
  bool _loading = true;
  int? _pendingDeviceId;

  int? _volume;
  int _maxVolume = 15;
  int _boostPercent = 100;
  bool _isDragging = false;
  Timer? _volumeDebounce;
  Timer? _boostDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _loadVolume();
    _devSub = context
        .read<PlayerProvider>()
        .engine
        .outputDevicesStream
        .skip(1)
        .listen((d) {
      if (d != null && mounted) setState(() => _devices = d);
    });
  }

  @override
  void dispose() {
    _devSub?.cancel();
    _volumeDebounce?.cancel();
    _boostDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final engine = context.read<PlayerProvider>().engine;
    final devices = await engine.getAudioOutputDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
    });
  }

  Future<void> _loadVolume() async {
    final engine = context.read<PlayerProvider>().engine;
    final mv = await engine.getMediaVolume();
    if (!mounted) return;
    setState(() {
      _volume = mv.level;
      _maxVolume = mv.max > 0 ? mv.max : 1;
      _boostPercent = mv.boostPercent;
    });
  }

  void _onSliderChanged(double fraction) {
    final clamped = fraction.clamp(0.0, 2.0);
    if (clamped <= 1.0) {
      final newVolume = (clamped * _maxVolume).round();
      setState(() {
        _volume = newVolume;
        if (_boostPercent != 100) _boostPercent = 100;
      });
      _volumeDebounce?.cancel();
      _volumeDebounce = Timer(const Duration(milliseconds: 40), () {
        final v = _volume;
        if (v == null) return;
        final engine = context.read<PlayerProvider>().engine;
        engine.setMediaVolume(v);
        engine.setVolumeBoost(100);
      });
    } else {
      final newBoost = (100 + (clamped - 1.0) * 100).round();
      setState(() {
        _volume = _maxVolume;
        _boostPercent = newBoost;
      });
      _volumeDebounce?.cancel();
      _volumeDebounce = Timer(const Duration(milliseconds: 40), () {
        final v = _volume;
        if (v == null) return;
        context.read<PlayerProvider>().engine.setMediaVolume(v);
      });
      _boostDebounce?.cancel();
      _boostDebounce = Timer(const Duration(milliseconds: 40), () {
        context.read<PlayerProvider>().engine.setVolumeBoost(_boostPercent);
      });
    }
  }

  String _qualityLabel(AppLocalizations l10n) {
    final song = context.read<PlayerProvider>().currentSong;
    if (song != null && song.isLocal) {
      final codec = StreamQualityStore.instance.codecFor(song);
      return codec != null ? 'Local · $codec' : 'Local file';
    }
    final resolved = (song != null && song.source == SongSource.youtube)
        ? null
        : AudioPrefs.lastResolvedKbps;
    switch (AudioPrefs.streamQuality) {
      case 'High':
        return '320 kbps';
      case 'Medium':
        return 'Up to 160 kbps';
      case 'Low':
        return '48-96 kbps';
      case 'DataSaver':
        return resolved != null
            ? '${l10n.spQualityDataSaver} · $resolved kbps'
            : l10n.spQualityDataSaver;
      default:
        return resolved != null
            ? '${l10n.spQualityAuto} · $resolved kbps'
            : l10n.spQualityAuto;
    }
  }

  Future<void> _onSelect(AudioOutputDevice device) async {
    if (_pendingDeviceId != null) return;
    final engine = context.read<PlayerProvider>().engine;
    final supportsRouting = _devices?.supportsExplicitRouting ?? false;
    final l10n = AppLocalizations.of(context)!;

    if (!supportsRouting) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.audioOutputAutoRoutingNotice),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
      return;
    }

    setState(() => _pendingDeviceId = device.id);
    AurumHaptics.selection();
    final ok = await engine.selectAudioOutputDevice(device.id);
    if (!mounted) return;
    setState(() => _pendingDeviceId = null);

    if (ok) {
      setState(() {
        final current = _devices;
        if (current != null) {
          _devices = AudioOutputDevices(
            supportsExplicitRouting: current.supportsExplicitRouting,
            devices: current.devices
                .map((d) => AudioOutputDevice(
                      id: d.id,
                      name: d.name,
                      kind: d.kind,
                      selected: d.id == device.id,
                    ))
                .toList(),
          );
        }
      });
      if (mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.audioOutputSwitchFailed),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  IconData _iconFor(AudioOutputDeviceKind kind) {
    switch (kind) {
      case AudioOutputDeviceKind.speaker:
        return Icons.smartphone_rounded;
      case AudioOutputDeviceKind.wired:
        return Icons.headphones_rounded;
      case AudioOutputDeviceKind.bluetooth:
        return Icons.bluetooth_audio_rounded;
      case AudioOutputDeviceKind.usb:
        return Icons.usb_rounded;
      case AudioOutputDeviceKind.unknown:
        return Icons.speaker_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final engine = context.read<PlayerProvider>().engine;
    context.select<PlayerProvider, String>((p) => p.currentSong?.id ?? '');

    return StreamBuilder<AudioOutputDevices?>(
      stream: engine.outputDevicesStream,
      builder: (context, snapshot) {
        final devices = _devices;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Selector<PlayerProvider, String>(
                        selector: (_, p) => p.currentSong?.artworkUrl ?? '',
                        builder: (context, artworkUrl, _) {
                          return AurumArtwork(
                            url: artworkUrl,
                            size: 44,
                            borderRadius: 10,
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Selector<PlayerProvider, (String?, String)>(
                          selector: (_, p) => (p.currentSong?.id, p.currentSong?.title ?? ''),
                          builder: (context, data, _) {
                            final (songId, title) = data;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(l10n.audioOutputPickerTitle,
                                    style: TextStyle(
                                        color: AurumTheme.textMutedOf(
                                            context),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600)),
                                if (songId != null) ...[
                                  const SizedBox(height: 2),
                                  Text(title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AurumTheme.textPrimaryOf(
                                              context),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                    color: AurumTheme.textMutedOf(context).withOpacity(0.1),
                    height: 1),
                StreamBuilder<MediaVolume?>(
                  stream: engine.mediaVolumeStream,
                  builder: (context, volSnapshot) {
                    final live = volSnapshot.data;
                    final effectiveVolume =
                        (!_isDragging && live != null) ? live.level : _volume;
                    final effectiveMax =
                        (!_isDragging && live != null && live.max > 0)
                            ? live.max
                            : _maxVolume;
                    final fraction = (() {
                      final hw = (effectiveVolume ?? 0) /
                          (effectiveMax <= 0 ? 1 : effectiveMax);
                      final boost = (_boostPercent - 100) / 100.0;
                      return (hw + boost).clamp(0.0, 2.0);
                    })();
                    return _VolumeRow(
                      fraction: fraction,
                      boosted: _boostPercent > 100,
                      onChanged: _onSliderChanged,
                      onDragStart: () => setState(() => _isDragging = true),
                      onDragEnd: () => setState(() => _isDragging = false),
                    );
                  },
                ),
                Divider(
                    color: AurumTheme.textMutedOf(context).withOpacity(0.1),
                    height: 1),
                if (_loading && devices == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                        child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AurumTheme.accentOf(context)))),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight:
                            MediaQuery.of(context).size.height * 0.5),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: devices?.devices.length ?? 0,
                      itemBuilder: (_, i) {
                        final d = devices!.devices[i];
                        final isPending = _pendingDeviceId == d.id;
                        return ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: d.selected
                                  ? AurumTheme.accentOf(context).withOpacity(0.15)
                                  : AurumTheme.textMutedOf(context)
                                      .withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_iconFor(d.kind),
                                color: d.selected
                                    ? AurumTheme.accentOf(context)
                                    : AurumTheme.textMutedOf(context),
                                size: 20),
                          ),
                          title: Text(d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: d.selected
                                      ? AurumTheme.accentOf(context)
                                      : AurumTheme.textPrimaryOf(context),
                                  fontSize: 14,
                                  fontWeight: d.selected
                                      ? FontWeight.w700
                                      : FontWeight.w600)),
                          trailing: isPending
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AurumTheme.accentOf(context)))
                              : d.selected
                                  ? Icon(Icons.check_circle_rounded,
                                      color: AurumTheme.accentOf(context), size: 22)
                                  : null,
                          onTap: () => _onSelect(d),
                        );
                      },
                    ),
                  ),
                if (!_loading &&
                    devices != null &&
                    !devices.supportsExplicitRouting)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text(
                      l10n.audioOutputAutoRoutingNotice,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AurumTheme.textMutedOf(context),
                          fontSize: 11.5,
                          height: 1.4),
                    ),
                  ),
                Divider(
                    color: AurumTheme.textMutedOf(context).withOpacity(0.1),
                    height: 1),
                _SheetInfoRow(
                  icon: Icons.high_quality_rounded,
                  label: 'Quality',
                  value: _qualityLabel(l10n),
                  onTap: () {
                    AurumHaptics.selection();
                    final rootNavigator =
                        Navigator.of(context, rootNavigator: true);
                    Navigator.pop(context);
                    rootNavigator.push(
                      AurumDepthRoute(
                        builder: (_) =>
                            const SettingsPlayerScreen(highlightQuality: true),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VolumeRow extends StatelessWidget {
  final double fraction;
  final bool boosted;
  final ValueChanged<double> onChanged;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const _VolumeRow({
    required this.fraction,
    required this.boosted,
    required this.onChanged,
    this.onDragStart,
    this.onDragEnd,
  });

  IconData get _icon {
    if (fraction <= 0) return Icons.volume_off_rounded;
    if (boosted) return Icons.volume_up_rounded;
    if (fraction < 0.5) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final muted = AurumTheme.textMutedOf(context);
    final accent = AurumTheme.accentOf(context);
    final boostColor = Color.lerp(accent, const Color(0xFFFFC94A), 0.5)!;
    final trackColor = boosted ? boostColor : accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          Icon(_icon, color: boosted ? boostColor : muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 2,
                    height: 10,
                    decoration: BoxDecoration(
                      color: muted.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: trackColor,
                    inactiveTrackColor: muted.withOpacity(0.18),
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    thumbColor: trackColor,
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 16),
                    overlayColor: trackColor.withOpacity(0.18),
                  ),
                  child: Slider(
                    value: fraction.clamp(0.0, 2.0),
                    min: 0.0,
                    max: 2.0,
                    onChanged: onChanged,
                    onChangeStart: onDragStart == null
                        ? null
                        : (_) => onDragStart!(),
                    onChangeEnd:
                        onDragEnd == null ? null : (_) => onDragEnd!(),
                  ),
                ),
              ],
            ),
          ),
          if (boosted) ...[
            const SizedBox(width: 8),
            Text(
              '${(100 + (fraction - 1.0).clamp(0.0, 1.0) * 100).round()}%',
              style: TextStyle(
                color: boostColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _SheetInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AurumTheme.textPrimaryOf(context);
    final muted = AurumTheme.textMutedOf(context);
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        children: [
          Icon(icon, color: muted, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          Text(value,
              style: TextStyle(
                  color: AurumTheme.accentOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: muted, size: 18),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: row,
    );
  }
}
