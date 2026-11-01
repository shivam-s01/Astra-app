// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'analytics_service.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LyricsViewMode {
  inline,

  fullscreen,
}

class LyricsStyle {
  final String position;
  final double textSize;
  final double lineSpacing;

  const LyricsStyle({
    this.position = 'Left',
    this.textSize = 26.0,
    this.lineSpacing = 1.25,
  });

  LyricsStyle copyWith({String? position, double? textSize, double? lineSpacing}) =>
      LyricsStyle(
        position: position ?? this.position,
        textSize: textSize ?? this.textSize,
        lineSpacing: lineSpacing ?? this.lineSpacing,
      );
}

class AudioPrefs {
  AudioPrefs._();

  static String streamQuality = 'Auto';

  static bool dataSaver = false;

  static final ValueNotifier<bool> dataSaverActiveNotifier =
      ValueNotifier<bool>(false);

  static int? lastResolvedKbps;

  static bool pauseOnCall = true;

  static bool duckOnNotifications = false;

  static bool notifShowPrev = true;

  static bool notifCompact = false;

  static bool showMediaNotif = true;

  static bool showArtworkNotif = true;

  static bool gapless = true;

  static bool incognito = false;

  static final ValueNotifier<bool> backAnimationsNotifier =
      ValueNotifier<bool>(true);
  static bool get backAnimations => backAnimationsNotifier.value;

  static final ValueNotifier<bool> scrollAnimationsNotifier =
      ValueNotifier<bool>(true);
  static bool get scrollAnimations => scrollAnimationsNotifier.value;

  static final ValueNotifier<String> artworkShapeNotifier =
      ValueNotifier<String>('Rounded');
  static String get artworkShape => artworkShapeNotifier.value;

  static final ValueNotifier<LyricsStyle> lyricsStyleNotifier =
      ValueNotifier<LyricsStyle>(const LyricsStyle());

  static final ValueNotifier<bool> showLyricsOnPlayerNotifier =
      ValueNotifier<bool>(true);

  static final ValueNotifier<LyricsViewMode> lyricsViewModeNotifier =
      ValueNotifier<LyricsViewMode>(LyricsViewMode.inline);

  static final ValueNotifier<String> castIconVisibilityNotifier =
      ValueNotifier<String>('auto');

  static final ValueNotifier<bool> swipeToChangeNotifier =
      ValueNotifier<bool>(true);

  static final ValueNotifier<bool> shakeToSkipNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<bool> stopOnSwipeNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<bool> islandEnabledNotifier =
      ValueNotifier<bool>(false);

  static double swipeSensitivity = 50.0;

  static final ValueNotifier<String> playerBgStyleNotifier =
      ValueNotifier<String>('Blur');

  static final ValueNotifier<bool> dynamicPlayerColorNotifier =
      ValueNotifier<bool>(true);

  static final ValueNotifier<bool> showBlurredBgNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<double> navBarBlurSigmaNotifier =
      ValueNotifier<double>(18.0);

  static final ValueNotifier<double> miniPlayerBlurSigmaNotifier =
      ValueNotifier<double>(12.0);

  static final ValueNotifier<bool> liquidGlassEnabledNotifier =
      ValueNotifier<bool>(false);
  static const double glassNavSigma = 18.0;
  static const double glassMiniSigma = 12.0;

  static final ValueNotifier<String> navBarStyleNotifier =
      ValueNotifier<String>('Docked');

  static final ValueNotifier<bool> batterySaverEnabledNotifier =
      ValueNotifier<bool>(true);

  static final ValueNotifier<int> batterySaverThresholdNotifier =
      ValueNotifier<int>(20);

  static final ValueNotifier<bool> batterySaverActiveNotifier =
      ValueNotifier<bool>(false);

  static final ValueNotifier<int?> batteryLevelNotifier =
      ValueNotifier<int?>(null);

  static bool hideListenStats = false;

  static bool isPremium = false;

  static bool isSignedIn = false;

  static const _kStreamQuality = 'stream_quality';
  static const _kDataSaver     = 'data_saver';
  static const _kPauseOnCall   = 'pause_on_call';
  static const _kDuckNotif     = 'duck_on_notifications';
  static const _kIncognito     = 'incognito_mode';
  static const _kBackAnim      = 'back_animations';
  static const _kScrollAnim    = 'scroll_animations';
  static const _kArtworkShape  = 'artwork_shape';
  static const _kLyricsPos     = 'lyrics_text_position';
  static const _kLyricsSize    = 'lyrics_text_size';
  static const _kLyricsSpacing = 'lyrics_line_spacing';
  static const _kShowLyricsOnPlayer = 'show_lyrics_on_player';
  static const _kLyricsViewMode = 'lyrics_view_mode';
  static const _kSwipeChange   = 'swipe_to_change';
  static const _kShakeToSkip   = 'shake_to_skip';
  static const _kStopOnSwipe   = 'stop_on_swipe';
  static const _kIslandEnabled = 'island_enabled';
  static const _kSwipeSens     = 'swipe_sensitivity';
  static const _kDynamicColor  = 'dynamic_player_color';
  static const _kShowBlurBg    = 'show_blurred_bg';
  static const _kNavBarBlur    = 'nav_bar_blur_sigma';
  static const _kLiquidGlass   = 'liquid_glass_enabled';
  static const _kNavBarStyle   = 'nav_bar_style';
  static const _kMiniPlayerBlur = 'mini_player_blur_sigma';
  static const _kPlayerBgStyle = 'player_bg_style';
  static const _kMiniPlayerBg  = 'mini_player_bg_style';
  static const _kBgGradAnim    = 'bg_gradient_animation';
  static const _kEnableAnim    = 'enable_animations';
  static const _kHideStats     = 'hide_listen_stats';
  static const _kNotifShowPrev = 'notif_show_prev';
  static const _kNotifStyle    = 'notif_style';
  static const _kShowMediaNotif   = 'show_media_notif';
  static const _kShowArtworkNotif = 'show_artwork_notif';
  static const _kGapless          = 'gapless';
  static const _kCastIconVisibility = 'cast_icon_visibility';
  static const _kBatterySaverEnabled   = 'battery_saver_enabled';
  static const _kBatterySaverThreshold = 'battery_saver_threshold';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    streamQuality       = p.getString(_kStreamQuality) ?? streamQuality;
    dataSaver           = p.getBool(_kDataSaver) ?? dataSaver;
    pauseOnCall         = p.getBool(_kPauseOnCall) ?? pauseOnCall;
    duckOnNotifications = p.getBool(_kDuckNotif) ?? duckOnNotifications;
    incognito           = p.getBool(_kIncognito) ?? incognito;
    backAnimationsNotifier.value = p.getBool(_kBackAnim) ?? backAnimationsNotifier.value;
    scrollAnimationsNotifier.value = p.getBool(_kScrollAnim) ?? scrollAnimationsNotifier.value;
    artworkShapeNotifier.value = p.getString(_kArtworkShape) ?? artworkShape;
    lyricsStyleNotifier.value = LyricsStyle(
      position:    p.getString(_kLyricsPos) ?? lyricsStyleNotifier.value.position,
      textSize:    p.getDouble(_kLyricsSize) ?? lyricsStyleNotifier.value.textSize,
      lineSpacing: p.getDouble(_kLyricsSpacing) ?? lyricsStyleNotifier.value.lineSpacing,
    );
    swipeToChangeNotifier.value = p.getBool(_kSwipeChange) ?? swipeToChangeNotifier.value;
    showLyricsOnPlayerNotifier.value =
        p.getBool(_kShowLyricsOnPlayer) ?? showLyricsOnPlayerNotifier.value;
    lyricsViewModeNotifier.value = LyricsViewMode.values[
        p.getInt(_kLyricsViewMode) ?? lyricsViewModeNotifier.value.index];
    shakeToSkipNotifier.value = p.getBool(_kShakeToSkip) ?? shakeToSkipNotifier.value;
    stopOnSwipeNotifier.value = p.getBool(_kStopOnSwipe) ?? stopOnSwipeNotifier.value;
    islandEnabledNotifier.value = p.getBool(_kIslandEnabled) ?? islandEnabledNotifier.value;
    unawaited(pushStopOnSwipeToNative(stopOnSwipeNotifier.value));
    swipeSensitivity = p.getDouble(_kSwipeSens) ?? swipeSensitivity;
    dynamicPlayerColorNotifier.value = p.getBool(_kDynamicColor) ?? dynamicPlayerColorNotifier.value;
    showBlurredBgNotifier.value = p.getBool(_kShowBlurBg) ?? showBlurredBgNotifier.value;
    liquidGlassEnabledNotifier.value =
        p.getBool(_kLiquidGlass) ?? liquidGlassEnabledNotifier.value;
    navBarStyleNotifier.value = 'Docked';
    playerBgStyleNotifier.value = p.getString(_kPlayerBgStyle) ?? playerBgStyleNotifier.value;
    miniPlayerBgStyleNotifier.value = p.getString(_kMiniPlayerBg) ?? miniPlayerBgStyleNotifier.value;
    bgGradientAnimationNotifier.value = p.getBool(_kBgGradAnim) ?? bgGradientAnimationNotifier.value;
    enableAnimationsNotifier.value = p.getBool(_kEnableAnim) ?? enableAnimationsNotifier.value;
    batterySaverEnabledNotifier.value =
        p.getBool(_kBatterySaverEnabled) ?? batterySaverEnabledNotifier.value;
    batterySaverThresholdNotifier.value =
        p.getInt(_kBatterySaverThreshold) ?? batterySaverThresholdNotifier.value;
    hideListenStats     = p.getBool(_kHideStats) ?? hideListenStats;
    notifShowPrev       = p.getBool(_kNotifShowPrev) ?? notifShowPrev;
    notifCompact        = (p.getString(_kNotifStyle) ?? 'Expanded') == 'Compact';
    showMediaNotif      = p.getBool(_kShowMediaNotif) ?? showMediaNotif;
    showArtworkNotif    = p.getBool(_kShowArtworkNotif) ?? showArtworkNotif;
    gapless             = p.getBool(_kGapless) ?? gapless;
    castIconVisibilityNotifier.value =
        p.getString(_kCastIconVisibility) ?? castIconVisibilityNotifier.value;
    _recomputeDataSaverActive();
  }

  static Future<void> primeDataSaverEarly() async {
    final p = await SharedPreferences.getInstance();
    streamQuality = p.getString(_kStreamQuality) ?? streamQuality;
    dataSaver     = p.getBool(_kDataSaver) ?? dataSaver;
    _recomputeDataSaverActive();
  }

  static Future<void> setStreamQuality(String v) async {
    streamQuality = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kStreamQuality, v);
    _recomputeDataSaverActive();
  }

  static Future<void> setDataSaver(bool v) async {
    dataSaver = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDataSaver, v);
    _recomputeDataSaverActive();
  }

  static void _recomputeDataSaverActive() {
    final shouldBeActive = dataSaver || streamQuality == 'DataSaver';
    if (dataSaverActiveNotifier.value != shouldBeActive) {
      dataSaverActiveNotifier.value = shouldBeActive;
    }
  }

  static Future<void> setPauseOnCall(bool v) async {
    pauseOnCall = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPauseOnCall, v);
  }

  static Future<void> setDuckOnNotifications(bool v) async {
    duckOnNotifications = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDuckNotif, v);
  }

  static Future<void> setIncognito(bool v) async {
    incognito = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kIncognito, v);
    AnalyticsService.instance.setCollection(!v);
  }

  static Future<void> setBackAnimations(bool v) async {
    backAnimationsNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBackAnim, v);
  }

  static Future<void> setScrollAnimations(bool v) async {
    scrollAnimationsNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kScrollAnim, v);
  }

  static Future<void> setArtworkShape(String v) async {
    artworkShapeNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kArtworkShape, v);
  }

  static Future<void> setLyricsPosition(String v) async {
    lyricsStyleNotifier.value = lyricsStyleNotifier.value.copyWith(position: v);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLyricsPos, v);
  }

  static Future<void> setLyricsTextSize(double v) async {
    lyricsStyleNotifier.value = lyricsStyleNotifier.value.copyWith(textSize: v);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kLyricsSize, v);
  }

  static Future<void> setLyricsLineSpacing(double v) async {
    lyricsStyleNotifier.value = lyricsStyleNotifier.value.copyWith(lineSpacing: v);
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kLyricsSpacing, v);
  }

  static Future<void> setShowLyricsOnPlayer(bool v) async {
    showLyricsOnPlayerNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowLyricsOnPlayer, v);
  }

  static Future<void> setLyricsViewMode(LyricsViewMode v) async {
    lyricsViewModeNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kLyricsViewMode, v.index);
  }

  static Future<void> setCastIconVisibility(String v) async {
    castIconVisibilityNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCastIconVisibility, v);
  }

  static Future<void> setSwipeToChange(bool v) async {
    swipeToChangeNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSwipeChange, v);
  }

  static Future<void> setShakeToSkip(bool v) async {
    shakeToSkipNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShakeToSkip, v);
  }

  static const _nativeChannel = MethodChannel('com.aurum.music/media_store');

  static Future<void> setStopOnSwipe(bool v) async {
    stopOnSwipeNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kStopOnSwipe, v);
    await pushStopOnSwipeToNative(v);
  }

  static Future<void> pushStopOnSwipeToNative(bool v) async {
    try {
      await _nativeChannel.invokeMethod('setStopOnTaskRemoved', {'value': v});
    } catch (_) {}
  }

  static Future<bool> setIslandEnabled(bool v) async {
    if (v) {
      final hasPermission = await checkOverlayPermission();
      if (!hasPermission) {
        await requestOverlayPermission();
        return false;
      }
    }
    islandEnabledNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kIslandEnabled, v);
    if (v) {
      await startIslandOverlay();
    } else {
      await stopIslandOverlay();
    }
    return true;
  }

  static Future<bool> checkOverlayPermission() async {
    try {
      return await _nativeChannel.invokeMethod<bool>('checkOverlayPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _nativeChannel.invokeMethod('requestOverlayPermission');
    } catch (_) {}
  }

  static Future<void> startIslandOverlay() async {
    try {
      await _nativeChannel.invokeMethod('startIslandOverlay');
    } catch (_) {}
  }

  static Future<void> stopIslandOverlay() async {
    try {
      await _nativeChannel.invokeMethod('stopIslandOverlay');
    } catch (_) {}
  }

  static Future<void> updateIslandCustomization() async {
    try {
      await _nativeChannel.invokeMethod('updateIslandCustomization');
    } catch (_) {}
  }

  static Future<void> pushHighRefreshRateToNative(bool v) async {
    try {
      await _nativeChannel.invokeMethod('setHighRefreshRate', {'enabled': v});
    } catch (_) {}
  }

  static Future<void> setSwipeSensitivity(double v) async {
    swipeSensitivity = v;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kSwipeSens, v);
  }

  static Future<void> setDynamicPlayerColor(bool v) async {
    dynamicPlayerColorNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kDynamicColor, v);
  }

  static Future<void> setShowBlurredBg(bool v) async {
    showBlurredBgNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowBlurBg, v);
  }

  static Future<void> setLiquidGlassEnabled(bool v) async {
    liquidGlassEnabledNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kLiquidGlass, v);
  }

  static Future<void> setNavBarBlurSigma(double v) async {
    navBarBlurSigmaNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kNavBarBlur, v);
  }

  static Future<void> setMiniPlayerBlurSigma(double v) async {
    miniPlayerBlurSigmaNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kMiniPlayerBlur, v);
  }

  static Future<void> setNavBarStyle(String v) async {
    navBarStyleNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNavBarStyle, v);
  }

  static Future<void> setPlayerBgStyle(String v) async {
    playerBgStyleNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPlayerBgStyle, v);
  }

  static String get effectivePlayerBgStyle =>
      batterySaverActiveNotifier.value ? 'Solid' : playerBgStyleNotifier.value;

  static final ValueNotifier<String> miniPlayerBgStyleNotifier =
      ValueNotifier<String>('Follow Theme');

  static final ValueNotifier<bool> bgGradientAnimationNotifier =
      ValueNotifier<bool>(true);

  static final ValueNotifier<bool> enableAnimationsNotifier =
      ValueNotifier<bool>(true);

  static Future<void> setMiniPlayerBgStyle(String v) async {
    miniPlayerBgStyleNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMiniPlayerBg, v);
  }

  static Future<void> setBgGradientAnimation(bool v) async {
    bgGradientAnimationNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBgGradAnim, v);
  }

  static Future<void> setEnableAnimations(bool v) async {
    enableAnimationsNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnableAnim, v);
  }

  static Future<void> setBatterySaverEnabled(bool v) async {
    batterySaverEnabledNotifier.value = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kBatterySaverEnabled, v);
    if (!v) {
      batterySaverActiveNotifier.value = false;
    } else {
      _reevaluateBatterySaver();
    }
  }

  static Future<void> setBatterySaverThreshold(int v) async {
    final clamped = v == 15 ? 15 : 20;
    batterySaverThresholdNotifier.value = clamped;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kBatterySaverThreshold, clamped);
    _reevaluateBatterySaver();
  }

  static void Function()? _batterySaverReevaluateHook;
  static void registerBatterySaverReevaluateHook(void Function() hook) {
    _batterySaverReevaluateHook = hook;
  }
  static void _reevaluateBatterySaver() => _batterySaverReevaluateHook?.call();

  static Future<void> setHideListenStats(bool v) async {
    hideListenStats = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHideStats, v);
  }

  static int? _cachedBandwidthKbps;
  static DateTime? _bandwidthCachedAt;
  static const _bandwidthTtl = Duration(seconds: 5);
  static const _bandwidthChannel = MethodChannel('com.aurum.music/audio_engine');

  static bool _bandwidthRefreshInFlight = false;

  static void _refreshBandwidthEstimateIfStale() {
    final now = DateTime.now();
    final isStale = _bandwidthCachedAt == null ||
        now.difference(_bandwidthCachedAt!) > _bandwidthTtl;
    if (!isStale || _bandwidthRefreshInFlight) return;

    _bandwidthRefreshInFlight = true;
    _bandwidthChannel.invokeMethod('getEstimatedBandwidth').then((raw) {
      final bits = (raw as num?)?.toInt() ?? 0;
      _cachedBandwidthKbps = bits > 0 ? bits ~/ 1000 : 0;
      _bandwidthCachedAt = DateTime.now();
    }).catchError((_) {
    }).whenComplete(() {
      _bandwidthRefreshInFlight = false;
    });
  }

  static List<String> _smartSaverOrder({
    required bool allow320,
    required List<String> unknownFallback,
  }) {
    _refreshBandwidthEstimateIfStale();
    final kbps = _cachedBandwidthKbps;

    if (kbps == null || kbps <= 0) return unknownFallback;

    if (kbps < 50) {
      return const ['48kbps', '96kbps'];
    }
    if (kbps <= 150) {
      return const ['96kbps', '160kbps', '48kbps'];
    }
    return allow320
        ? const ['96kbps', '48kbps', '160kbps', '320kbps']
        : const ['96kbps', '48kbps', '160kbps'];
  }

  static List<String> qualityOrder() {
    const allow320 = true;

    if (dataSaver) {
      return _smartSaverOrder(
        allow320: allow320,
        unknownFallback: const ['96kbps', '48kbps', '160kbps', '320kbps', '12kbps'],
      );
    }

    switch (streamQuality) {
      case 'Low':
        return const ['48kbps', '96kbps'];
      case 'DataSaver':
        return _smartSaverOrder(
          allow320: allow320,
          unknownFallback: allow320
              ? const ['96kbps', '48kbps', '160kbps', '320kbps']
              : const ['96kbps', '48kbps', '160kbps'],
        );
      case 'Medium':
        return const ['160kbps', '96kbps'];
      case 'High':
      case 'Auto':
      default:
        return allow320
            ? const ['320kbps', '160kbps', '96kbps', '48kbps', '12kbps']
            : const ['160kbps', '96kbps', '48kbps', '12kbps'];
    }
  }
}
