// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/aurum_theme.dart';
import '../services/native_engine_bridge.dart';
import '../services/audio_prefs.dart';
import '../providers/recently_played_provider.dart';
import '../providers/source_provider.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/auto_sleep_guard_tile.dart';
import '../widgets/battery_saver_mode_tile.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_sheet.dart';
import '../utils/aurum_transitions.dart';
import 'island_customize_screen.dart';
import '../widgets/aurum_settings_tile.dart' show AurumStaggerItem;

class SleepTimerService extends ChangeNotifier {
  SleepTimerService._();
  static final SleepTimerService instance = SleepTimerService._();

  Timer? _timer;
  DateTime? _endsAt;
  bool _finishSong = false;
  bool _fadeOut = true;
  NativeAudioEngine? _engine;

  void _notify() => notifyListeners();

  bool get isActive => _timer != null && _timer!.isActive;
  Duration get remaining => isActive ? _endsAt!.difference(DateTime.now()) : Duration.zero;

  bool get lastFadeOutChoice => _fadeOut;

  void start({
    required int minutes,
    required bool finishSong,
    required NativeAudioEngine? engine,
    bool fadeOut = true,
  }) {
    cancel();
    _finishSong = finishSong;
    _fadeOut = fadeOut;
    _engine = engine;
    _endsAt = DateTime.now().add(Duration(minutes: minutes));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _notify();
      if (DateTime.now().isAfter(_endsAt!)) {
        _onExpire();
      }
    });
    _engine?.autoSleepGuardSetSleepTimerActive(true);
    _notify();
  }

  void cancel() {
    final wasActive = isActive;
    _timer?.cancel();
    _timer = null;
    _endsAt = null;
    if (wasActive) {
      _engine?.autoSleepGuardSetSleepTimerActive(false);
    }
    _notify();
  }

  void _onExpire() {
    _timer?.cancel();
    _timer = null;
    _endsAt = null;
    _engine?.autoSleepGuardSetSleepTimerActive(false);
    if (_finishSong) {
      _engine?.sleepAfterCurrentSong();
    } else if (_fadeOut) {
      _engine?.sleepFadeOutAndPause(fadeMs: 8000);
    } else {
      _engine?.pause();
    }
    _notify();
  }
}

class SettingsPlayerScreen extends StatefulWidget {
  final NativeAudioEngine? audioEngine;
  final bool highlightQuality;
  const SettingsPlayerScreen({
    super.key,
    this.audioEngine,
    this.highlightQuality = false,
  });
  @override
  State<SettingsPlayerScreen> createState() => _SettingsPlayerScreenState();
}

class _SettingsPlayerScreenState extends State<SettingsPlayerScreen>
    with SingleTickerProviderStateMixin {
  String _streamQuality = 'Auto';
  bool _dataSaver = false;
  bool _gapless = true;
  String _castIconVisibility = 'auto';
  double _playbackSpeed = 1.0;
  bool _keepQueue = true;
  bool _stopOnSwipe = false;
  bool _islandEnabled = false;
  bool _pauseOnCall = true;
  bool _duckOnNotifications = false;
  bool _shakeToSkip = false;
  bool _swipeToChange = true;
  double _historyDuration = 50;

  double _crossfadeDuration = 0.0;
  bool _volumeNormalization = false;
  bool _bassBoost = false;
  bool _premiumSound = false;
  PremiumSoundCapabilities? _premiumSoundCaps;

  bool _sleepTimerFinishSong = false;
  bool _sleepTimerFadeOut = true;
  String _hapticIntensity = 'light';

  bool _loaded = false;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _qualityTileKey = GlobalKey();
  late final AnimationController _qualityPulseCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _qualityPulse = CurvedAnimation(
    parent: _qualityPulseCtrl,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreen('Settings Player');
    _load();
    _loadPremiumSoundCaps();
    SleepTimerService.instance.addListener(_onTimerTick);
    if (widget.highlightQuality) {
      _waitForLoadThenHighlight();
    }
  }

  Future<void> _waitForLoadThenHighlight() async {
    while (mounted && !_loaded) {
      await Future.delayed(const Duration(milliseconds: 16));
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _highlightQualityTile());
  }

  Future<void> _highlightQualityTile() async {
    if (!mounted) return;
    final tileContext = _qualityTileKey.currentContext;
    if (tileContext == null || !_scrollController.hasClients) return;
    await Scrollable.ensureVisible(
      tileContext,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
    if (!mounted) return;
    await _qualityPulseCtrl.forward();
    if (!mounted) return;
    await _qualityPulseCtrl.reverse();
    if (!mounted) return;
    await _qualityPulseCtrl.forward();
    if (!mounted) return;
    await _qualityPulseCtrl.reverse();
  }

  Future<void> _loadPremiumSoundCaps() async {
    final caps = await widget.audioEngine?.getPremiumSoundCapabilities();
    if (mounted && caps != null) setState(() => _premiumSoundCaps = caps);
  }

  @override
  void dispose() {
    SleepTimerService.instance.removeListener(_onTimerTick);
    _scrollController.dispose();
    _qualityPulseCtrl.dispose();
    super.dispose();
  }

  void _onTimerTick() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final savedQuality = p.getString('stream_quality') ?? 'Auto';
    if (!mounted) return;
    setState(() {
      _streamQuality       = savedQuality;
      _dataSaver           = p.getBool('data_saver') ?? false;
      _gapless             = p.getBool('gapless') ?? true;
      _castIconVisibility  = p.getString('cast_icon_visibility') ?? 'auto';
      _playbackSpeed       = p.getDouble('playback_speed') ?? 1.0;
      _keepQueue           = p.getBool('keep_queue') ?? true;
      _stopOnSwipe         = p.getBool('stop_on_swipe') ?? false;
      _islandEnabled       = p.getBool('island_enabled') ?? false;
      _pauseOnCall         = p.getBool('pause_on_call') ?? true;
      _duckOnNotifications = p.getBool('duck_on_notifications') ?? false;
      _shakeToSkip         = p.getBool('shake_to_skip') ?? false;
      _swipeToChange       = p.getBool('swipe_to_change') ?? true;
      _historyDuration     = (p.getInt('history_duration') ?? 50).toDouble();
      _crossfadeDuration   = p.getDouble('crossfade_duration') ?? 0.0;
      _volumeNormalization = p.getBool('volume_normalization') ?? false;
      _bassBoost           = p.getBool('bass_boost') ?? false;
      _premiumSound        = p.getBool('premium_sound') ?? false;
      _sleepTimerFinishSong = p.getBool('sleep_timer_finish_song') ?? false;
      _sleepTimerFadeOut = p.getBool('sleep_timer_fade_out') ?? true;
      _hapticIntensity = AurumHaptics.intensity;
      _loaded = true;
    });
  }

  Future<void> _save(String key, dynamic value) async {
    final p = await SharedPreferences.getInstance();
    if (value is bool)   await p.setBool(key, value);
    if (value is double) await p.setDouble(key, value);
    if (value is int)    await p.setInt(key, value);
    if (value is String) await p.setString(key, value);
  }

  static const _qualityKeys = ['Auto', 'Low', 'DataSaver', 'Medium', 'High'];
  List<(String key, String label, String subtitle, bool locked)> _qualityOptions(AppLocalizations l10n) => [
    ('Auto',   l10n.spQualityAuto,   l10n.spQualityAutoDesc,   false),
    ('Low',    l10n.spQualityLow,    l10n.spQualityLowDesc,    false),
    ('DataSaver', l10n.spQualityDataSaver, l10n.spQualityDataSaverDesc, false),
    ('Medium', l10n.spQualityMedium, l10n.spQualityMediumDesc, false),
    ('High',   l10n.spQualityHigh,   l10n.spQualityHighDesc,   false),
  ];

  Widget _streamQualityTile(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      key: _qualityTileKey,
      animation: _qualityPulse,
      builder: (context, child) {
        final pulseColor = AurumTheme.accentOf(context);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AurumTheme.bgCardOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Color.lerp(
                AurumTheme.dividerOf(context),
                pulseColor,
                _qualityPulse.value,
              )!,
              width: 0.5 + _qualityPulse.value * 1.2,
            ),
            boxShadow: _qualityPulse.value > 0
                ? [
                    BoxShadow(
                      color: pulseColor.withOpacity(0.35 * _qualityPulse.value),
                      blurRadius: 20,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                    color: AurumTheme.accentOf(context).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.high_quality_rounded, color: AurumTheme.accentOf(context), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.spStreamQuality,
                        style: TextStyle(
                            color: AurumTheme.textPrimaryOf(context),
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    Text(l10n.spStreamQualitySubtitle,
                        style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 4),
          ..._qualityOptions(l10n).map((opt) {
            final (key, label, subtitle, _) = opt;
            final selected = _streamQuality == key;
            return AurumPressable(
              scaleAmount: 0.985,
              haptic: false,
              onTap: () {
                AurumHaptics.selection();
                setState(() => _streamQuality = key);
                _save('stream_quality', key);
                AudioPrefs.setStreamQuality(key);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AurumTheme.accentOf(context).withOpacity(0.08)
                      : Colors.transparent,
                ),
                child: Row(children: [
                  Icon(
                    selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: selected ? AurumTheme.accentOf(context) : AurumTheme.textMutedOf(context),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                              color: AurumTheme.textPrimaryOf(context),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            )),
                        Text(subtitle,
                            style: TextStyle(
                              color: AurumTheme.textMutedOf(context),
                              fontSize: 11.5,
                            )),
                        if (key == 'DataSaver' && selected) ...[
                          const SizedBox(height: 3),
                          Text(l10n.spQualityDataSaverDescExpanded,
                              style: TextStyle(
                                color: AurumTheme.textMutedOf(context).withOpacity(0.85),
                                fontSize: 11,
                                height: 1.35,
                              )),
                        ],
                      ],
                    ),
                  ),
                ]),
              ),
            );
          }),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
  Future<void> _notifyEngine() async {
    final p = await SharedPreferences.getInstance();
    final bandGains = List.generate(10, (i) => p.getDouble('eq_band_$i') ?? 0.0);
    await widget.audioEngine?.applyAudioEffects(
      bassBoost: _bassBoost,
      volumeNormalization: _volumeNormalization,
      bandGainsDb: bandGains,
    );
  }

  Widget _premiumSoundTile(BuildContext context, AppLocalizations l10n) {
    final value = _premiumSound;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: value
            ? LinearGradient(
                colors: [
                  AurumTheme.accentOf(context).withOpacity(0.16),
                  AurumTheme.accentOf(context).withOpacity(0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: value ? null : AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? AurumTheme.accentOf(context).withOpacity(0.5) : AurumTheme.dividerOf(context),
          width: value ? 1 : 0.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: AurumTheme.accentGradientOf(context),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.spa_rounded, color: Colors.black, size: 19),
        ),
        title: Text(l10n.spPremiumSound,
            style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 15, fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.spPremiumSoundSubtitle,
                  style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12, height: 1.3)),
              if (value && _premiumSoundCaps != null && !_premiumSoundCaps!.fullySupported)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l10n.spPremiumSoundPartialSupport,
                    style: TextStyle(color: AurumTheme.accentOf(context).withOpacity(0.85), fontSize: 11, height: 1.3),
                  ),
                ),
            ],
          ),
        ),
        trailing: Switch(
          value: value,
          activeColor: AurumTheme.accentOf(context),
          onChanged: (v) async {
            setState(() => _premiumSound = v);
            await _save('premium_sound', v);
            await widget.audioEngine?.applyPremiumSound(v);
            if (v) await _loadPremiumSoundCaps();
          },
        ),
      ),
    );
  }

  void _showSleepTimerSheet(BuildContext context) {
    showAurumModalBottomSheet(
      context: context,
      backgroundColor: AurumTheme.bgCardOf(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SleepTimerSheet(
        engine: widget.audioEngine,
        finishSong: _sleepTimerFinishSong,
        fadeOut: _sleepTimerFadeOut,
        onFinishSongChanged: (v) {
          setState(() => _sleepTimerFinishSong = v);
          _save('sleep_timer_finish_song', v);
        },
        onFadeOutChanged: (v) {
          setState(() => _sleepTimerFadeOut = v);
          _save('sleep_timer_fade_out', v);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final timer = SleepTimerService.instance;

    if (!_loaded) {
      return Scaffold(
        backgroundColor: AurumTheme.bgOf(context),
        appBar: _appBar(context, l10n.settingsPlayerAudio),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      appBar: _appBar(context, l10n.settingsPlayerAudio),
      body: ListView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [

          AurumStaggerItem(index: 0, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionLabel(context, l10n.spPlayback),
          _streamQualityTile(context),
          Consumer<SourceProvider>(
            builder: (context, sourceProvider, _) => _switchTile(context,
                icon: Icons.wifi_off_rounded,
                title: l10n.spOfflineMode,
                subtitle: l10n.spOfflineModeSubtitle,
                value: sourceProvider.isOfflineModeEnabled,
                onChanged: (v) {
                  AurumHaptics.selection();
                  sourceProvider.setOfflineMode(v);
                }),
          ),
          _switchTile(context,
              icon: Icons.data_saver_on_rounded,
              title: l10n.spDataSaver,
              subtitle: l10n.spDataSaverSubtitle,
              value: _dataSaver,
              onChanged: (v) {
                setState(() => _dataSaver = v);
                _save('data_saver', v);
                AudioPrefs.setDataSaver(v);
              }),

          const AutoSleepGuardTile(),

          const BatterySaverModeTile(),

          _switchTile(context,
              icon: Icons.remove_done_rounded,
              title: l10n.spGaplessPlayback,
              subtitle: l10n.spGaplessPlaybackSubtitle,
              value: _gapless,
              onChanged: (v) {
                setState(() => _gapless = v);
                _save('gapless', v);
                AudioPrefs.gapless = v;
              }),
          _dropdownTile(context,
              icon: Icons.cast_rounded,
              title: l10n.spShowCastIcon,
              subtitle: l10n.spShowCastIconSubtitle,
              value: _castIconVisibilityLabel(l10n, _castIconVisibility),
              options: [
                _castIconVisibilityLabel(l10n, 'auto'),
                _castIconVisibilityLabel(l10n, 'always'),
                _castIconVisibilityLabel(l10n, 'hidden'),
              ],
              onChanged: (label) {
                if (label == null) return;
                final key = _castIconVisibilityKeyFromLabel(l10n, label);
                AurumHaptics.selection();
                setState(() => _castIconVisibility = key);
                _save('cast_icon_visibility', key);
                AudioPrefs.setCastIconVisibility(key);
              }),

          _buildSpeedSlider(context),

          _buildCrossfadeSlider(context),

          _premiumSoundTile(context, l10n),

          _switchTile(context,
              icon: Icons.equalizer_rounded,
              title: l10n.spVolumeNormalization,
              subtitle: l10n.spVolumeNormalizationSubtitle,
              value: _volumeNormalization,
              onChanged: (v) async {
                setState(() => _volumeNormalization = v);
                await _save('volume_normalization', v);
                await _notifyEngine();
              }),

          _switchTile(context,
              icon: Icons.surround_sound_rounded,
              title: l10n.spBassBoost,
              subtitle: l10n.spBassBoostSubtitle,
              value: _bassBoost,
              onChanged: (v) async {
                setState(() => _bassBoost = v);
                await _save('bass_boost', v);
                await _notifyEngine();
              }),

          ])),
          AurumStaggerItem(index: 1, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 16),
          _sectionLabel(context, l10n.spSleepTimer),
          _buildSleepTimerTile(context, timer),
          ])),

          AurumStaggerItem(index: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 16),
          _sectionLabel(context, l10n.spEqualizer),
          _navTile(context,
              icon: Icons.graphic_eq_rounded,
              title: l10n.spEqualizerTitle,
              subtitle: l10n.spEqualizerSubtitle,
              onTap: () => Navigator.of(context)
                  .push(_slideRoute(EqualizerScreen(audioEngine: widget.audioEngine)))),
          ])),

          AurumStaggerItem(index: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 16),
          _sectionLabel(context, l10n.spBehavior),
          _switchTile(context,
              icon: Icons.queue_music_rounded,
              title: l10n.spKeepQueue,
              subtitle: l10n.spKeepQueueSubtitle,
              value: _keepQueue,
              onChanged: (v) {
                setState(() => _keepQueue = v);
                _save('keep_queue', v);
              }),
          _switchTile(context,
              icon: Icons.clear_all_rounded,
              title: l10n.spStopOnSwipe,
              subtitle: l10n.spStopOnSwipeSubtitle,
              value: _stopOnSwipe,
              onChanged: (v) async {
                setState(() => _stopOnSwipe = v);
                await _save('stop_on_swipe', v);
                await AudioPrefs.setStopOnSwipe(v);
              }),
          _navTile(context,
              icon: Icons.blur_circular_rounded,
              title: l10n.spDynamicIsland,
              subtitle: _islandEnabled ? l10n.spIslandCustomizeSubtitle : l10n.spDynamicIslandSubtitle,
              onTap: () async {
                await Navigator.of(context).push(
                  AurumPageRoute(builder: (_) => const IslandCustomizeScreen()),
                );
                if (mounted) await _load();
              }),
          _switchTile(context,
              icon: Icons.call_rounded,
              title: l10n.spPauseOnCall,
              subtitle: l10n.spPauseOnCallSubtitle,
              value: _pauseOnCall,
              onChanged: (v) {
                setState(() => _pauseOnCall = v);
                _save('pause_on_call', v);
                AudioPrefs.setPauseOnCall(v);
              }),
          _switchTile(context,
              icon: Icons.notifications_active_rounded,
              title: l10n.spDuckNotifications,
              subtitle: l10n.spDuckNotificationsSubtitle,
              value: _duckOnNotifications,
              onChanged: (v) {
                setState(() => _duckOnNotifications = v);
                _save('duck_on_notifications', v);
                AudioPrefs.setDuckOnNotifications(v);
              }),
          _switchTile(context,
              icon: Icons.vibration_rounded,
              title: l10n.spShakeToSkip,
              subtitle: l10n.spShakeToSkipSubtitle,
              value: _shakeToSkip,
              onChanged: (v) async {
                setState(() => _shakeToSkip = v);
                await _save('shake_to_skip', v);
                await AudioPrefs.setShakeToSkip(v);
              }),
          _switchTile(context,
              icon: Icons.swipe_rounded,
              title: l10n.spSwipeToChange,
              subtitle: l10n.spSwipeToChangeSubtitle,
              value: _swipeToChange,
              onChanged: (v) {
                setState(() => _swipeToChange = v);
                _save('swipe_to_change', v);
                AudioPrefs.setSwipeToChange(v);
              }),
          _dropdownTile(context,
              icon: Icons.vibration_rounded,
              title: l10n.spHapticIntensity,
              subtitle: l10n.spHapticIntensitySubtitle,
              value: _hapticIntensityLabel(l10n, _hapticIntensity),
              options: [
                _hapticIntensityLabel(l10n, 'off'),
                _hapticIntensityLabel(l10n, 'light'),
                _hapticIntensityLabel(l10n, 'strong'),
              ],
              onChanged: (label) {
                if (label == null) return;
                final key = _hapticIntensityKeyFromLabel(l10n, label);
                setState(() => _hapticIntensity = key);
                AurumHaptics.setIntensity(key);
                AurumHaptics.medium();
              }),

          _buildHistorySlider(context),
          ])),
        ],
      ),
    );
  }

  Widget _buildSpeedSlider(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AurumTheme.accentOf(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.speed_rounded, color: AurumTheme.accentOf(context), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l10n.spPlaybackSpeed,
                    style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 14, fontWeight: FontWeight.w500)),
                Text(l10n.spPlaybackSpeedSubtitle,
                    style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AurumTheme.accentOf(context).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _playbackSpeed == 1.0 ? l10n.spNormal : '${_playbackSpeed}×',
                  style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Slider(
              value: _playbackSpeed,
              min: 0.25, max: 2.0, divisions: 7,
              onChanged: (v) => setState(() => _playbackSpeed = v),
              onChangeEnd: (v) async {
                await _save('playback_speed', v);
                await widget.audioEngine?.setSpeed(v);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['0.25×','0.5×','0.75×','1×','1.25×','1.5×','1.75×','2×']
                  .map((l) => Text(l, style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 9)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrossfadeSlider(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AurumTheme.accentOf(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.compare_arrows_rounded, color: AurumTheme.accentOf(context), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l10n.spCrossfade,
                    style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 14, fontWeight: FontWeight.w500)),
                Text(l10n.spCrossfadeSubtitle,
                    style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AurumTheme.accentOf(context).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _crossfadeDuration == 0 ? l10n.spOff : '${_crossfadeDuration.toInt()}s',
                  style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Slider(
              value: _crossfadeDuration,
              min: 0, max: 12, divisions: 12,
              onChanged: (v) => setState(() => _crossfadeDuration = v),
              onChangeEnd: (v) async {
                await _save('crossfade_duration', v);
                await widget.audioEngine?.setCrossfadeSeconds(v);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ['Off','1s','2s','3s','4s','5s','6s','7s','8s','9s','10s','11s','12s']
                  .map((l) => Text(l, style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 9)))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepTimerTile(BuildContext context, SleepTimerService timer) {
    final l10n = AppLocalizations.of(context)!;
    final isActive = timer.isActive;
    final remaining = timer.remaining;
    final mm = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AurumTheme.accentOf(context).withOpacity(0.5) : AurumTheme.dividerOf(context),
          width: isActive ? 1 : 0.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: isActive ? AurumTheme.accentOf(context).withOpacity(0.15) : AurumTheme.accentOf(context).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.bedtime_rounded, color: AurumTheme.accentOf(context), size: 18),
        ),
        title: Text(
          isActive ? l10n.spSleepTimerActive : l10n.spSleepTimerTitle,
          style: TextStyle(
            color: AurumTheme.textPrimaryOf(context),
            fontSize: 14, fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          isActive ? l10n.spSleepTimerStopsIn('$mm:$ss') : l10n.spSleepTimerSetSubtitle,
          style: TextStyle(
            color: isActive ? AurumTheme.accentOf(context) : AurumTheme.textMutedOf(context),
            fontSize: 12,
          ),
        ),
        trailing: isActive
            ? GestureDetector(
                onTap: () => SleepTimerService.instance.cancel(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Text(l10n.spCancel,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              )
            : Icon(Icons.chevron_right_rounded, color: AurumTheme.textMutedOf(context), size: 20),
        onTap: isActive ? null : () => _showSleepTimerSheet(context),
      ),
    );
  }

  Widget _buildHistorySlider(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(children: [
          Row(children: [
            Text(l10n.spHistoryDuration,
                style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(l10n.spHistorySongsCount(10 + (_historyDuration / 100.0 * 190).round()),
                style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          Slider(
            value: _historyDuration,
            min: 10, max: 100, divisions: 9,
            onChanged: (v) {
              setState(() => _historyDuration = v);
              _save('history_duration', v.toInt());
              context.read<RecentlyPlayedProvider>()
                  .trimToLimit((10 + (v / 100.0 * 190).round()).clamp(10, 200));
            },
          ),
        ]),
      ),
    );
  }
}

class SleepTimerSheet extends StatefulWidget {
  final NativeAudioEngine? engine;
  final bool finishSong;
  final bool fadeOut;
  final ValueChanged<bool> onFinishSongChanged;
  final ValueChanged<bool> onFadeOutChanged;

  const SleepTimerSheet({
    required this.engine,
    required this.finishSong,
    this.fadeOut = true,
    required this.onFinishSongChanged,
    required this.onFadeOutChanged,
  });

  @override
  State<SleepTimerSheet> createState() => SleepTimerSheetState();
}

class SleepTimerSheetState extends State<SleepTimerSheet> {
  int _selectedMinutes = 30;
  late bool _finishSong;
  late bool _fadeOut;

  bool _customMode = false;
  final TextEditingController _customController = TextEditingController();
  final FocusNode _customFocusNode = FocusNode();
  String? _customError;

  static const _presets = [5, 10, 15, 20, 30, 45, 60, 90];
  static const int _maxCustomMinutes = 600;

  @override
  void initState() {
    super.initState();
    _finishSong = widget.finishSong;
    _fadeOut = widget.fadeOut;
  }

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  String _formatMinutes(int min) {
    if (min < 60) return '${min}m';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  void _enterCustomMode() {
    AurumHaptics.selection();
    setState(() {
      _customMode = true;
      _customError = null;
      _customController.text = _selectedMinutes.toString();
      _customController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _customController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _customFocusNode.requestFocus();
    });
  }

  void _confirmCustomMinutes() {
    final l10n = AppLocalizations.of(context)!;
    final raw = _customController.text.trim();
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      setState(() => _customError = l10n.spSleepTimerInvalidDuration);
      return;
    }
    if (parsed > _maxCustomMinutes) {
      setState(() => _customError =
          l10n.spSleepTimerMaxDuration(_maxCustomMinutes));
      return;
    }
    AurumHaptics.light();
    setState(() {
      _selectedMinutes = parsed;
      _customMode = false;
      _customError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isCustomPreset = !_presets.contains(_selectedMinutes);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 20, 20, 36 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: AurumTheme.dividerOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(l10n.spSleepTimerSheetTitle,
                style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(l10n.spSleepTimerSheetSubtitle,
                style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 13)),
            const SizedBox(height: 20),

            if (!_customMode) ...[
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  ..._presets.map((min) {
                    final sel = !isCustomPreset && _selectedMinutes == min;
                    return _DurationChip(
                      label: _formatMinutes(min),
                      selected: sel,
                      onTap: () {
                        AurumHaptics.selection();
                        setState(() => _selectedMinutes = min);
                      },
                    );
                  }),
                  _DurationChip(
                    label: isCustomPreset
                        ? _formatMinutes(_selectedMinutes)
                        : l10n.spSleepTimerCustom,
                    selected: isCustomPreset,
                    icon: Icons.edit_rounded,
                    onTap: _enterCustomMode,
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AurumTheme.bgOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _customError != null
                        ? Colors.redAccent.withOpacity(0.6)
                        : AurumTheme.accentOf(context).withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customController,
                        focusNode: _customFocusNode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        maxLength: 3,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: TextStyle(
                          color: AurumTheme.textPrimaryOf(context),
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          counterText: '',
                          hintText: '30',
                          hintStyle: TextStyle(
                            color: AurumTheme.textMutedOf(context).withOpacity(0.4),
                          ),
                        ),
                        onChanged: (_) {
                          if (_customError != null) {
                            setState(() => _customError = null);
                          }
                        },
                        onSubmitted: (_) => _confirmCustomMinutes(),
                      ),
                    ),
                    Text(l10n.spSleepTimerMinutesUnit,
                        style: TextStyle(
                          color: AurumTheme.textMutedOf(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        )),
                  ],
                ),
              ),
              if (_customError != null) ...[
                const SizedBox(height: 6),
                Text(_customError!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        _customFocusNode.unfocus();
                        setState(() {
                          _customMode = false;
                          _customError = null;
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: AurumTheme.textMutedOf(context),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(l10n.commonCancel,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirmCustomMinutes,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AurumTheme.accentOf(context),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(l10n.spSleepTimerSetDuration,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AurumTheme.bgOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l10n.spSleepTimerFadeOut,
                          style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 14, fontWeight: FontWeight.w500)),
                      Text(l10n.spSleepTimerFadeOutSubtitle,
                          style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12)),
                    ]),
                  ),
                  Switch(
                    value: _fadeOut,
                    onChanged: (v) {
                      AurumHaptics.selection();
                      setState(() => _fadeOut = v);
                      widget.onFadeOutChanged(v);
                    },
                    activeColor: AurumTheme.accentOf(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: AurumTheme.bgOf(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l10n.spFinishCurrentSong,
                          style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 14, fontWeight: FontWeight.w500)),
                      Text(l10n.spFinishCurrentSongSubtitle,
                          style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12)),
                    ]),
                  ),
                  Switch(
                    value: _finishSong,
                    onChanged: (v) {
                      AurumHaptics.selection();
                      setState(() => _finishSong = v);
                      widget.onFinishSongChanged(v);
                    },
                    activeColor: AurumTheme.accentOf(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _customMode
                    ? null
                    : () {
                        AurumHaptics.medium();
                        SleepTimerService.instance.start(
                          minutes: _selectedMinutes,
                          finishSong: _finishSong,
                          fadeOut: _fadeOut,
                          engine: widget.engine,
                        );
                        Navigator.pop(context);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AurumTheme.accentOf(context),
                  disabledBackgroundColor: AurumTheme.accentOf(context).withOpacity(0.3),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Text(
                  l10n.spStartTimer(_formatMinutes(_selectedMinutes)),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (SleepTimerService.instance.isActive) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    AurumHaptics.medium();
                    SleepTimerService.instance.cancel();
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    l10n.spCancelActiveTimer,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DurationChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  const _DurationChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AurumTheme.accentOf(context).withOpacity(0.15) : AurumTheme.bgOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AurumTheme.accentOf(context).withOpacity(0.6) : AurumTheme.dividerOf(context),
            width: selected ? 1 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13,
                  color: selected ? AurumTheme.accentOf(context) : AurumTheme.textSecondaryOf(context)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? AurumTheme.accentOf(context) : AurumTheme.textSecondaryOf(context),
                fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EqualizerScreen extends StatefulWidget {
  final NativeAudioEngine? audioEngine;
  const EqualizerScreen({this.audioEngine});
  @override
  State<EqualizerScreen> createState() => EqualizerScreenState();
}

class EqualizerScreenState extends State<EqualizerScreen> {
  static const _bands = ['32Hz','64Hz','125Hz','250Hz','500Hz','1kHz','2kHz','4kHz','8kHz','16kHz'];
  static const _presets = {
    'Flat':       [0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0],
    'Rock':       [4.0,3.0,1.0,0.0,-1.0,-1.0,0.0,2.0,3.0,4.0],
    'Pop':        [-1.0,0.0,2.0,3.0,3.0,2.0,1.0,0.0,-1.0,-2.0],
    'Jazz':       [3.0,2.0,1.0,2.0,-1.0,-1.0,0.0,1.0,2.0,3.0],
    'Bass Boost': [6.0,5.0,4.0,2.0,0.0,0.0,0.0,0.0,0.0,0.0],
    'Vocal':      [-2.0,-1.0,0.0,2.0,4.0,4.0,3.0,2.0,1.0,0.0],
    'Electronic': [5.0,4.0,1.0,0.0,-2.0,1.0,0.0,2.0,4.0,5.0],
  };

  static const _bandFreqsHz = [32,64,125,250,500,1000,2000,4000,8000,16000];

  final ValueNotifier<List<double>> _valuesNotifier =
      ValueNotifier<List<double>>(List.filled(10, 0.0));
  final ValueNotifier<String> _presetNotifier = ValueNotifier<String>('Flat');
  final ValueNotifier<double> _bassBoostNotifier = ValueNotifier<double>(0.0);

  bool _loaded = false;

  List<double> get _values => _valuesNotifier.value;
  String get _selectedPreset => _presetNotifier.value;
  double get _bassBoostPercent => _bassBoostNotifier.value;

  static const double _kBassBoostSubBassMaxDb = 4.0;
  static const double _kBassBoostBassMaxDb = 3.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _valuesNotifier.dispose();
    _presetNotifier.dispose();
    _bassBoostNotifier.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    _presetNotifier.value = p.getString('eq_preset') ?? 'Flat';
    _valuesNotifier.value = List.generate(10, (i) => p.getDouble('eq_band_$i') ?? 0.0);
    _bassBoostNotifier.value = (p.getDouble('eq_bass_boost_percent') ?? 0.0).clamp(0.0, 100.0);
    setState(() => _loaded = true);
  }

  List<double> _effectiveBandGains() {
    final values = _values;
    final percent = _bassBoostPercent;
    if (percent <= 0) return values;
    final fraction = percent / 100.0;
    final out = List<double>.from(values);
    out[0] = (out[0] + _kBassBoostSubBassMaxDb * fraction).clamp(-12.0, 12.0);
    out[1] = (out[1] + _kBassBoostBassMaxDb * fraction).clamp(-12.0, 12.0);
    return out;
  }

  Future<void> _saveValues() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('eq_preset', _selectedPreset);
    final values = _values;
    for (int i = 0; i < 10; i++) {
      await p.setDouble('eq_band_$i', values[i]);
    }
    await p.setDouble('eq_bass_boost_percent', _bassBoostPercent);
    final bassBoostToggle = p.getBool('bass_boost') ?? false;
    final volNorm = p.getBool('volume_normalization') ?? false;
    await widget.audioEngine?.applyAudioEffects(
      bassBoost: bassBoostToggle,
      volumeNormalization: volNorm,
      bandGainsDb: _effectiveBandGains(),
    );
  }

  void _applyPreset(String name) {
    AurumHaptics.selection();
    _presetNotifier.value = name;
    _valuesNotifier.value = List<double>.from(_presets[name]!);
    _saveValues();
  }

  void _resetAll() {
    AurumHaptics.light();
    _bassBoostNotifier.value = 0.0;
    _applyPreset('Flat');
  }

  void _onBassBoostChanged(double v) {
    _bassBoostNotifier.value = v;
  }

  void _onBandChanged(int i, double v) {
    final next = List<double>.from(_valuesNotifier.value);
    next[i] = v;
    _valuesNotifier.value = next;
    if (_presetNotifier.value != 'Custom') _presetNotifier.value = 'Custom';
  }

  void _openPresetSheet(BuildContext context) {
    AurumHaptics.light();
    showAurumModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (_) => _PresetSheet(
        presets: _presets.keys.toList(),
        selected: _selectedPreset,
        onSelect: (name) {
          Navigator.pop(context);
          _applyPreset(name);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (!_loaded) {
      return Scaffold(
        backgroundColor: AurumTheme.bgOf(context),
        appBar: AppBar(
          backgroundColor: AurumTheme.bgOf(context),
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: AurumTheme.textPrimaryOf(context), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(l10n.spEqualizerTitle,
              style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: AurumTheme.bgOf(context),
      appBar: AppBar(
        backgroundColor: AurumTheme.bgOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AurumTheme.textPrimaryOf(context), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(l10n.spEqualizerTitle,
            style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 18, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: _resetAll,
            child: Text(l10n.spEqReset,
                style: TextStyle(color: AurumTheme.textSecondaryOf(context), fontSize: 14)),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _sectionLabel(context, l10n.spEqPresets),
          ValueListenableBuilder<String>(
            valueListenable: _presetNotifier,
            builder: (context, preset, _) => _PresetSelector(
              selected: preset,
              onTap: () => _openPresetSheet(context),
            ),
          ),

          const SizedBox(height: 22),

          _sectionLabel(context, 'BASS BOOST'),
          ValueListenableBuilder<double>(
            valueListenable: _bassBoostNotifier,
            builder: (context, percent, _) => _BassBoostCard(
              percent: percent,
              onChanged: _onBassBoostChanged,
              onChangeEnd: (_) => _saveValues(),
            ),
          ),

          const SizedBox(height: 22),

          _sectionLabel(context, l10n.spEq10Band),
          ListenableBuilder(
            listenable: Listenable.merge([_valuesNotifier, _bassBoostNotifier]),
            builder: (context, _) => _EqResponseGraph(
              bandFreqsHz: _bandFreqsHz,
              values: _effectiveBandGains(),
              onDragBand: _onBandChanged,
              onDragEnd: (_) => _saveValues(),
            ),
          ),

          const SizedBox(height: 10),

          ValueListenableBuilder<List<double>>(
            valueListenable: _valuesNotifier,
            builder: (context, values, _) => _EqBandList(
              bands: _bands,
              values: values,
              onChanged: _onBandChanged,
              onChangeEnd: (_) => _saveValues(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetSelector extends StatelessWidget {
  final String selected;
  final VoidCallback onTap;
  const _PresetSelector({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AurumPressable(
      scaleAmount: 0.98,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected,
                style: TextStyle(
                  color: AurumTheme.textPrimaryOf(context),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                color: AurumTheme.textMutedOf(context), size: 20),
          ],
        ),
      ),
    );
  }
}

class _PresetSheet extends StatelessWidget {
  final List<String> presets;
  final String selected;
  final ValueChanged<String> onSelect;
  const _PresetSheet({
    required this.presets,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AurumTheme.dividerOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: Row(
                children: [
                  Text('PRESET',
                      style: TextStyle(
                          color: AurumTheme.accentOf(context),
                          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            ...presets.map((name) {
              final sel = name == selected;
              return InkWell(
                onTap: () => onSelect(name),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(name,
                            style: TextStyle(
                              color: sel ? AurumTheme.accentOf(context) : AurumTheme.textPrimaryOf(context),
                              fontSize: 15,
                              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                            )),
                      ),
                      if (sel)
                        Icon(Icons.check_rounded, color: AurumTheme.accentOf(context), size: 18),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _BassBoostCard extends StatelessWidget {
  final double percent;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  const _BassBoostCard({
    required this.percent,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AurumTheme.accentOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add extra low-end punch',
                  style: TextStyle(
                    color: AurumTheme.textMutedOf(context),
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(
                '${percent.round()}%',
                style: TextStyle(
                  color: percent > 0 ? accent : AurumTheme.textMutedOf(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 1),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: accent,
              inactiveTrackColor: AurumTheme.dividerOf(context),
              thumbColor: accent,
              overlayColor: accent.withOpacity(0.12),
            ),
            child: Slider(
              value: percent,
              min: 0, max: 100,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _EqResponseGraph extends StatefulWidget {
  final List<int> bandFreqsHz;
  final List<double> values;
  final void Function(int index, double value)? onDragBand;
  final void Function(int index)? onDragEnd;
  const _EqResponseGraph({
    required this.bandFreqsHz,
    required this.values,
    this.onDragBand,
    this.onDragEnd,
  });

  @override
  State<_EqResponseGraph> createState() => _EqResponseGraphState();
}

class _EqResponseGraphState extends State<_EqResponseGraph> {
  int? _activeBand;

  static const double _minDb = -12;
  static const double _maxDb = 12;

  double _xFor(int freqHz, double width) {
    final minLog = math.log(32);
    final maxLog = math.log(16000);
    final t = (math.log(freqHz) - minLog) / (maxLog - minLog);
    return t.clamp(0.0, 1.0) * width;
  }

  int _nearestBandIndex(double touchX, double width) {
    int best = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < widget.bandFreqsHz.length; i++) {
      final d = (_xFor(widget.bandFreqsHz[i], width) - touchX).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  double _dbForY(double y, double height) {
    final t = 1.0 - (y / height);
    return (_minDb + t.clamp(0.0, 1.0) * (_maxDb - _minDb)).clamp(_minDb, _maxDb);
  }

  void _handleTouch(Offset local, Size size, {required bool isEnd}) {
    if (widget.onDragBand == null) return;
    if (isEnd) {
      if (_activeBand != null) widget.onDragEnd?.call(_activeBand!);
      setState(() => _activeBand = null);
      return;
    }
    final band = _activeBand ?? _nearestBandIndex(local.dx, size.width);
    final db = _dbForY(local.dy, size.height);
    setState(() => _activeBand = band);
    widget.onDragBand!(band, (db * 2).round() / 2);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AurumTheme.accentOf(context);
    return RepaintBoundary(
      child: Container(
        height: 120,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: widget.onDragBand == null
                  ? null
                  : (d) => _handleTouch(d.localPosition, size, isEnd: false),
              onPanUpdate: widget.onDragBand == null
                  ? null
                  : (d) => _handleTouch(d.localPosition, size, isEnd: false),
              onPanEnd: widget.onDragBand == null
                  ? null
                  : (_) => _handleTouch(Offset.zero, size, isEnd: true),
              child: CustomPaint(
                size: Size.infinite,
                painter: _EqCurvePainter(
                  freqs: widget.bandFreqsHz,
                  values: widget.values,
                  gridColor: AurumTheme.dividerOf(context),
                  curveColor: accent,
                  isDark: isDark,
                  activeBand: _activeBand,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EqCurvePainter extends CustomPainter {
  final List<int> freqs;
  final List<double> values;
  final Color gridColor;
  final Color curveColor;
  final bool isDark;
  final int? activeBand;

  _EqCurvePainter({
    required this.freqs,
    required this.values,
    required this.gridColor,
    required this.curveColor,
    required this.isDark,
    this.activeBand,
  });

  static const double _minDb = -12;
  static const double _maxDb = 12;

  double _xFor(int freqHz, double width) {
    final minLog = math.log(32);
    final maxLog = math.log(16000);
    final t = (math.log(freqHz) - minLog) / (maxLog - minLog);
    return t.clamp(0.0, 1.0) * width;
  }

  double _yFor(double db, double height) {
    final t = (db - _minDb) / (_maxDb - _minDb);
    return height - t.clamp(0.0, 1.0) * height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final zeroPaint = Paint()
      ..color = gridColor.withOpacity(isDark ? 0.9 : 1.0)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), zeroPaint);
    canvas.drawLine(Offset(0, h * 0.15), Offset(w, h * 0.15), gridPaint);
    canvas.drawLine(Offset(0, h * 0.85), Offset(w, h * 0.85), gridPaint);

    final points = <Offset>[];
    for (int i = 0; i < freqs.length && i < values.length; i++) {
      points.add(Offset(_xFor(freqs[i], w), _yFor(values[i], h)));
    }
    if (points.isEmpty) return;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? i : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : i + 1];
      final cp1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final cp2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }

    final curvePaint = Paint()
      ..color = curveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, curvePaint);

    final nodePaint = Paint()..color = curveColor;
    for (int i = 0; i < points.length; i++) {
      final isActive = i == activeBand;
      if (isActive) {
        final haloPaint = Paint()..color = curveColor.withOpacity(0.18);
        canvas.drawCircle(points[i], 8, haloPaint);
      }
      canvas.drawCircle(points[i], isActive ? 3.5 : 2.5, nodePaint);
    }
  }

  @override
  bool shouldRepaint(_EqCurvePainter old) =>
      !_listEquals(old.values, values) ||
      old.gridColor != gridColor ||
      old.curveColor != curveColor ||
      old.isDark != isDark ||
      old.activeBand != activeBand;

  static bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _EqBandList extends StatelessWidget {
  final List<String> bands;
  final List<double> values;
  final void Function(int index, double value) onChanged;
  final void Function(double value) onChangeEnd;
  const _EqBandList({
    required this.bands,
    required this.values,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AurumTheme.accentOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: Column(
        children: List.generate(bands.length, (i) {
          final v = values[i];
          return SizedBox(
            height: 34,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    bands[i],
                    style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 11.5),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 1),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: v == 0 ? AurumTheme.textMutedOf(context) : accent,
                      inactiveTrackColor: AurumTheme.dividerOf(context),
                      thumbColor: v == 0 ? AurumTheme.textMutedOf(context) : accent,
                      overlayColor: accent.withOpacity(0.12),
                    ),
                    child: Slider(
                      value: v,
                      min: -12, max: 12, divisions: 48,
                      onChanged: (val) => onChanged(i, val),
                      onChangeEnd: onChangeEnd,
                    ),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} dB',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: v == 0 ? AurumTheme.textMutedOf(context) : accent,
                      fontSize: 11, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

AppBar _appBar(BuildContext context, String title, {List<Widget>? actions}) =>
    AppBar(
      backgroundColor: AurumTheme.bgOf(context),
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: AurumTheme.textPrimaryOf(context), size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(title,
          style: TextStyle(
              color: AurumTheme.textPrimaryOf(context),
              fontSize: 18, fontWeight: FontWeight.w600)),
      actions: actions,
    );

Widget _sectionLabel(BuildContext context, String label) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(label,
          style: TextStyle(
              color: AurumTheme.accentOf(context),
              fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
    );

Widget _switchTile(BuildContext context,
    {required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged}) =>
    Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: value ? AurumTheme.accentOf(context).withOpacity(0.12) : AurumTheme.bgOf(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              color: value ? AurumTheme.accentOf(context) : AurumTheme.textMutedOf(context),
              size: 18),
        ),
        title: Text(title,
            style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12)),
        trailing: Switch(value: value, onChanged: onChanged, activeColor: AurumTheme.accentOf(context)),
      ),
    );

String _castIconVisibilityLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case 'always':
      return l10n.spCastIconAlways;
    case 'hidden':
      return l10n.spCastIconHidden;
    default:
      return l10n.spCastIconAuto;
  }
}

String _castIconVisibilityKeyFromLabel(AppLocalizations l10n, String label) {
  if (label == l10n.spCastIconAlways) return 'always';
  if (label == l10n.spCastIconHidden) return 'hidden';
  return 'auto';
}

String _hapticIntensityLabel(AppLocalizations l10n, String key) {
  switch (key) {
    case 'off':
      return l10n.spHapticOff;
    case 'strong':
      return l10n.spHapticStrong;
    default:
      return l10n.spHapticLight;
  }
}

String _hapticIntensityKeyFromLabel(AppLocalizations l10n, String label) {
  if (label == l10n.spHapticOff) return 'off';
  if (label == l10n.spHapticStrong) return 'strong';
  return 'light';
}

Widget _dropdownTile(BuildContext context,
    {required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged}) =>
    Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: AurumTheme.accentOf(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AurumTheme.accentOf(context), size: 18),
        ),
        title: Text(title,
            style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12)),
        trailing: DropdownButton<String>(
          value: value,
          underline: const SizedBox(),
          dropdownColor: AurumTheme.bgCardOf(context),
          style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 13, fontWeight: FontWeight.w600),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: AurumTheme.accentOf(context), size: 18),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
        ),
      ),
    );

Widget _navTile(BuildContext context,
    {required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap}) =>
    Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: AurumTheme.accentOf(context).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AurumTheme.accentOf(context), size: 18),
        ),
        title: Text(title,
            style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12)),
        trailing: Icon(Icons.chevron_right_rounded,
            color: AurumTheme.textMutedOf(context), size: 20),
      ),
    );

PageRouteBuilder _slideRoute(Widget screen) => PageRouteBuilder(
      pageBuilder: (_, animation, __) => screen,
      transitionsBuilder: (context, animation, __, child) {
        final tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic));
        return ColoredBox(
          color: AurumTheme.bgOf(context),
          child: SlideTransition(position: animation.drive(tween), child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 280),
    );
