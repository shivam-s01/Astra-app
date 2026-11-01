// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/aurum_theme.dart';

enum AurumThemeMode { dark, light, amoled, system, dynamic }

class ThemeProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const _key       = 'aurum_theme_mode';
  static const _fontKey   = 'font_style';
  static const _accentKey = 'accent_color';
  static const _btnColorKey = 'player_button_colors';
  static const _sliderStyleKey = 'player_slider_style';
  static const _fullPlayerStyleKey = 'full_player_style';
  static const _colorPresetKey = 'aurum_color_preset';

  AurumThemeMode _mode      = AurumThemeMode.dark;
  String         _fontStyle = 'Default';
  Color          _accentColor = AurumTheme.accent;
  AurumColorPreset _colorPreset = AurumColorPreset.midnight;
  String         _playerButtonColorMode = 'Primary';
  String         _playerSliderStyle = 'Waveform';
  String         _fullPlayerStyle = 'Edge to Edge';

  AurumThemeMode get mode      => _mode;
  String         get fontStyle => _fontStyle;

  Color get accentColor {
    final preset = effectivePreset;
    if (preset == AurumColorPreset.none) return _accentColor;
    final data = AurumColorPresetCatalog.forId(preset);
    if (data == null) return _accentColor;
    return data.accentFor(_resolvedBrightness);
  }

  Brightness get _resolvedBrightness {
    switch (themeMode) {
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }
  }

  AurumColorPreset get colorPreset => _colorPreset;

  bool get dynamicOverridesPreset =>
      _mode == AurumThemeMode.dynamic && _dynamicDark != null;

  AurumColorPreset get effectivePreset =>
      dynamicOverridesPreset ? AurumColorPreset.none : _colorPreset;

  String get playerButtonColorMode => _playerButtonColorMode;

  String get playerSliderStyle => _playerSliderStyle;

  String get fullPlayerStyle => _fullPlayerStyle;

  ColorScheme? _dynamicLight;
  ColorScheme? _dynamicDark;

  ColorScheme? get dynamicLight => _dynamicLight;
  ColorScheme? get dynamicDark  => _dynamicDark;

  bool get isDynamicAvailable =>
      _mode == AurumThemeMode.dynamic && _dynamicDark != null;

  void updateDynamicSchemes(ColorScheme? light, ColorScheme? dark) {
    if (light == _dynamicLight && dark == _dynamicDark) return;
    _dynamicLight = light;
    _dynamicDark = dark;
    if (_mode == AurumThemeMode.dynamic) notifyListeners();
  }

  ThemeMode get themeMode {
    switch (_mode) {
      case AurumThemeMode.system:  return ThemeMode.system;
      case AurumThemeMode.light:   return ThemeMode.light;
      case AurumThemeMode.dynamic:
        final platformBrightness =
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        final isDark = platformBrightness != Brightness.light ||
            _dynamicDark == null;
        return isDark ? ThemeMode.dark : ThemeMode.light;
      default:
        return ThemeMode.dark;
    }
  }

  bool get isAmoled => _mode == AurumThemeMode.amoled;
  bool get isDynamic => _mode == AurumThemeMode.dynamic;

  bool isDarkOf(BuildContext context) {
    if (themeMode == ThemeMode.dark) return true;
    if (themeMode == ThemeMode.light) return false;
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return platformBrightness == Brightness.dark;
  }

  static SharedPreferences? _early;

  static Future<void> primeEarly() async {
    try {
      _early = await SharedPreferences.getInstance();
    } catch (_) {}
  }

  ThemeProvider() {
    final early = _early;
    if (early != null) _applyPrefs(early);
    _load();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (_mode == AurumThemeMode.system || _mode == AurumThemeMode.dynamic) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _applyPrefs(p);
    notifyListeners();
  }

  void _applyPrefs(SharedPreferences p) {
    final val = p.getString(_key);
    final presetVal = p.getString(_colorPresetKey);
    if (val != null) {
      _mode = AurumThemeMode.values.firstWhere(
        (e) => e.name == val,
        orElse: () => AurumThemeMode.dark,
      );
      _colorPreset = presetVal == null
          ? AurumColorPreset.none
          : AurumColorPreset.values.firstWhere(
              (e) => e.name == presetVal,
              orElse: () => AurumColorPreset.none,
            );
    } else if (presetVal == null) {
      if (p.getBool('onboarding_complete') ?? false) {
        _mode = AurumThemeMode.system;
        _colorPreset = AurumColorPreset.none;
      } else {
        _mode = AurumThemeMode.dark;
        _colorPreset = AurumColorPreset.midnight;
        p.setString(_key, AurumThemeMode.dark.name);
        p.setString(_colorPresetKey, AurumColorPreset.midnight.name);
      }
    } else {
      _mode = AurumThemeMode.dark;
      _colorPreset = AurumColorPreset.values.firstWhere(
        (e) => e.name == presetVal,
        orElse: () => AurumColorPreset.none,
      );
    }
    _fontStyle = p.getString(_fontKey) ?? 'Default';
    final accentInt = p.getInt(_accentKey);
    if (accentInt != null) _accentColor = Color(accentInt);
    _playerButtonColorMode = p.getString(_btnColorKey) ?? _playerButtonColorMode;
    _playerSliderStyle = p.getString(_sliderStyleKey) ?? _playerSliderStyle;
    _fullPlayerStyle = p.getString(_fullPlayerStyleKey) ?? _fullPlayerStyle;
  }

  Future<void> setMode(AurumThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, mode.name);
  }

  Future<void> setColorPreset(AurumColorPreset preset) async {
    _colorPreset = preset;
    if (_mode == AurumThemeMode.dynamic) _mode = AurumThemeMode.system;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_colorPresetKey, preset.name);
    await p.setString(_key, _mode.name);
  }

  Future<void> setPlayerButtonColorMode(String mode) async {
    _playerButtonColorMode = mode;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_btnColorKey, mode);
  }

  Future<void> setPlayerSliderStyle(String style) async {
    _playerSliderStyle = style;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_sliderStyleKey, style);
  }

  Future<void> setFullPlayerStyle(String style) async {
    _fullPlayerStyle = style;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_fullPlayerStyleKey, style);
  }

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setInt(_accentKey, color.value);
  }

  Future<void> setFontStyle(String style) async {
    _fontStyle = style;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_fontKey, style);
  }

  TextTheme resolvedTextTheme(TextTheme base) {
    switch (_fontStyle) {
      case 'Rounded':
        return GoogleFonts.nunitoTextTheme(base);
      case 'Mono':
        return GoogleFonts.robotoMonoTextTheme(base);
      case 'Sans':
        return GoogleFonts.manropeTextTheme(base);
      case 'Serif':
        return GoogleFonts.playfairDisplayTextTheme(base);
      default:
        return base;
    }
  }

  String? get resolvedFontFamily {
    switch (_fontStyle) {
      case 'Rounded':
        return GoogleFonts.nunito().fontFamily;
      case 'Mono':
        return GoogleFonts.robotoMono().fontFamily;
      case 'Sans':
        return GoogleFonts.manrope().fontFamily;
      case 'Serif':
        return GoogleFonts.playfairDisplay().fontFamily;
      default:
        return null;
    }
  }

  List<String>? get resolvedFontFamilyFallback {
    switch (_fontStyle) {
      case 'Rounded':
        return GoogleFonts.nunito().fontFamilyFallback;
      case 'Mono':
        return GoogleFonts.robotoMono().fontFamilyFallback;
      case 'Sans':
        return GoogleFonts.manrope().fontFamilyFallback;
      case 'Serif':
        return GoogleFonts.playfairDisplay().fontFamilyFallback;
      default:
        return null;
    }
  }
}
