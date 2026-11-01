// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

class _DynamicMarker extends ThemeExtension<_DynamicMarker> {
  const _DynamicMarker();
  @override
  _DynamicMarker copyWith() => this;
  @override
  _DynamicMarker lerp(ThemeExtension<_DynamicMarker>? other, double t) => this;
}

class _PresetMarker extends ThemeExtension<_PresetMarker> {
  final Color accentLight;
  final Color accentDark;
  final Color? textMuted;
  final Color? textSecondary;
  final Color? bgSurface;
  final Color? bgElevated;
  const _PresetMarker({
    required this.accentLight,
    required this.accentDark,
    this.textMuted,
    this.textSecondary,
    this.bgSurface,
    this.bgElevated,
  });

  @override
  _PresetMarker copyWith({
    Color? accentLight,
    Color? accentDark,
    Color? textMuted,
    Color? textSecondary,
    Color? bgSurface,
    Color? bgElevated,
  }) =>
      _PresetMarker(
        accentLight: accentLight ?? this.accentLight,
        accentDark: accentDark ?? this.accentDark,
        textMuted: textMuted ?? this.textMuted,
        textSecondary: textSecondary ?? this.textSecondary,
        bgSurface: bgSurface ?? this.bgSurface,
        bgElevated: bgElevated ?? this.bgElevated,
      );

  static Color? _l(Color? a, Color? b, double t) =>
      (a != null && b != null) ? Color.lerp(a, b, t) : (b ?? a);

  @override
  _PresetMarker lerp(ThemeExtension<_PresetMarker>? other, double t) {
    if (other is! _PresetMarker) return this;
    return _PresetMarker(
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      accentDark: Color.lerp(accentDark, other.accentDark, t)!,
      textMuted: _l(textMuted, other.textMuted, t),
      textSecondary: _l(textSecondary, other.textSecondary, t),
      bgSurface: _l(bgSurface, other.bgSurface, t),
      bgElevated: _l(bgElevated, other.bgElevated, t),
    );
  }
}

enum AurumColorPreset {
  none,
  ocean,
  forest,
  sunset,
  midnight,
  aurora,
}

class AurumPresetPalette {
  final Color accent;
  final Color accentLight;
  final Color accentDark;
  final Color background;
  final Color surface;
  final Color elevated;
  final Color surfaceVariant;
  final Color onBackground;
  final Color textSecondary;
  final Color textMuted;
  final Color divider;

  const AurumPresetPalette({
    required this.accent,
    required this.accentLight,
    required this.accentDark,
    required this.background,
    required this.surface,
    required this.elevated,
    required this.surfaceVariant,
    required this.onBackground,
    required this.textSecondary,
    required this.textMuted,
    required this.divider,
  });
}

class AurumColorPresetData {
  final String displayName;
  final String subtitle;
  final AurumPresetPalette dark;
  final AurumPresetPalette light;

  const AurumColorPresetData({
    required this.displayName,
    required this.subtitle,
    required this.dark,
    required this.light,
  });

  AurumPresetPalette paletteFor(Brightness b) =>
      b == Brightness.dark ? dark : light;

  Color accentFor(Brightness b) => paletteFor(b).accent;
  Color accentLightFor(Brightness b) => paletteFor(b).accentLight;

  Color get accent => dark.accent;
}

class AurumColorPresetCatalog {
  static const Map<AurumColorPreset, AurumColorPresetData> presets = {
    AurumColorPreset.ocean: AurumColorPresetData(
      displayName: 'Ocean',
      subtitle: 'Deep sea blues',
      dark: AurumPresetPalette(
        accent: Color(0xFF22B8E0),
        accentLight: Color(0xFF7DD8F0),
        accentDark: Color(0xFF0C7FA8),
        background: Color(0xFF0C141A),
        surface: Color(0xFF111E27),
        elevated: Color(0xFF172733),
        surfaceVariant: Color(0xFF1D313F),
        onBackground: Color(0xFFE6EEF4),
        textSecondary: Color(0xFFB6C4CD),
        textMuted: Color(0xFF9AABB7),
        divider: Color(0xFF253B4B),
      ),
      light: AurumPresetPalette(
        accent: Color(0xFF0B7BA6),
        accentLight: Color(0xFF3CB4DC),
        accentDark: Color(0xFF075F82),
        background: Color(0xFFF1F5F9),
        surface: Color(0xFFFCFDFD),
        elevated: Color(0xFFEAF1F5),
        surfaceVariant: Color(0xFFE3ECF3),
        onBackground: Color(0xFF131B20),
        textSecondary: Color(0xFF3F4950),
        textMuted: Color(0xFF58626A),
        divider: Color(0xFFD3E0E9),
      ),
    ),
    AurumColorPreset.forest: AurumColorPresetData(
      displayName: 'Forest',
      subtitle: 'Pine & moss',
      dark: AurumPresetPalette(
        accent: Color(0xFF5BC48F),
        accentLight: Color(0xFF9ADDB8),
        accentDark: Color(0xFF2F8A5E),
        background: Color(0xFF0F1813),
        surface: Color(0xFF15231C),
        elevated: Color(0xFF1C2E26),
        surfaceVariant: Color(0xFF23392F),
        onBackground: Color(0xFFE9F1ED),
        textSecondary: Color(0xFFBBC9C2),
        textMuted: Color(0xFF9FB1A9),
        divider: Color(0xFF2C4439),
      ),
      light: AurumPresetPalette(
        accent: Color(0xFF2A7A54),
        accentLight: Color(0xFF4FAE80),
        accentDark: Color(0xFF1D5C3E),
        background: Color(0xFFF3F7F5),
        surface: Color(0xFFFCFDFC),
        elevated: Color(0xFFEDF3F0),
        surfaceVariant: Color(0xFFE6EFEB),
        onBackground: Color(0xFF161D1A),
        textSecondary: Color(0xFF434C48),
        textMuted: Color(0xFF5C6661),
        divider: Color(0xFFD8E4DE),
      ),
    ),
    AurumColorPreset.sunset: AurumColorPresetData(
      displayName: 'Sunset',
      subtitle: 'Dusk plum & coral',
      dark: AurumPresetPalette(
        accent: Color(0xFFF0765A),
        accentLight: Color(0xFFFFB08F),
        accentDark: Color(0xFFC2456E),
        background: Color(0xFF180E12),
        surface: Color(0xFF24141A),
        elevated: Color(0xFF2F1B22),
        surfaceVariant: Color(0xFF3A222B),
        onBackground: Color(0xFFF2E8EC),
        textSecondary: Color(0xFFCABAC0),
        textMuted: Color(0xFFB39EA6),
        divider: Color(0xFF462B35),
      ),
      light: AurumPresetPalette(
        accent: Color(0xFFC9482F),
        accentLight: Color(0xFFEE8566),
        accentDark: Color(0xFFA8365A),
        background: Color(0xFFFAF0F4),
        surface: Color(0xFFFDFCFC),
        elevated: Color(0xFFF6E9EE),
        surfaceVariant: Color(0xFFF4E1E8),
        onBackground: Color(0xFF211218),
        textSecondary: Color(0xFF523D45),
        textMuted: Color(0xFF6B565E),
        divider: Color(0xFFEBD1DA),
      ),
    ),
    AurumColorPreset.midnight: AurumColorPresetData(
      displayName: 'Midnight',
      subtitle: 'Deep violet',
      dark: AurumPresetPalette(
        accent: Color(0xFF9D7BFF),
        accentLight: Color(0xFFC0AAFF),
        accentDark: Color(0xFF7152D6),
        background: Color(0xFF0F0D19),
        surface: Color(0xFF171325),
        elevated: Color(0xFF1E1931),
        surfaceVariant: Color(0xFF251F3D),
        onBackground: Color(0xFFEAE7F3),
        textSecondary: Color(0xFFBCB8CC),
        textMuted: Color(0xFFA19CB5),
        divider: Color(0xFF2E2848),
      ),
      light: AurumPresetPalette(
        accent: Color(0xFF6544D6),
        accentLight: Color(0xFF9378F0),
        accentDark: Color(0xFF4B30AE),
        background: Color(0xFFF3F1F9),
        surface: Color(0xFFFCFCFD),
        elevated: Color(0xFFEDEBF5),
        surfaceVariant: Color(0xFFE6E3F2),
        onBackground: Color(0xFF16141F),
        textSecondary: Color(0xFF433F4F),
        textMuted: Color(0xFF5C5969),
        divider: Color(0xFFD8D4E8),
      ),
    ),
    AurumColorPreset.aurora: AurumColorPresetData(
      displayName: 'Aurora',
      subtitle: 'Teal glow',
      dark: AurumPresetPalette(
        accent: Color(0xFF3FE0C5),
        accentLight: Color(0xFF86F2E0),
        accentDark: Color(0xFF1AA891),
        background: Color(0xFF0C181B),
        surface: Color(0xFF112327),
        elevated: Color(0xFF162F34),
        surfaceVariant: Color(0xFF1C3A40),
        onBackground: Color(0xFFE6F2F4),
        textSecondary: Color(0xFFB6CACE),
        textMuted: Color(0xFF99B2B8),
        divider: Color(0xFF24454C),
      ),
      light: AurumPresetPalette(
        accent: Color(0xFF0B7F70),
        accentLight: Color(0xFF2FB5A0),
        accentDark: Color(0xFF075C51),
        background: Color(0xFFF1F7F9),
        surface: Color(0xFFFCFDFD),
        elevated: Color(0xFFEAF3F5),
        surfaceVariant: Color(0xFFE3F0F3),
        onBackground: Color(0xFF131E20),
        textSecondary: Color(0xFF3F4D50),
        textMuted: Color(0xFF58676A),
        divider: Color(0xFFD3E5E9),
      ),
    ),
  };

  static AurumColorPresetData? forId(AurumColorPreset id) => presets[id];
}

class AurumTheme {
  static const Color accent      = Color(0xFF9B7EDE);
  static const Color accentLight = Color(0xFFB69FEE);
  static const Color accentDark  = Color(0xFF7A5FC4);

  static const Color darkBg          = Color(0xFF13121C);
  static const Color darkBgCard      = Color(0xFF1B1927);
  static const Color darkBgElevated  = Color(0xFF201E2E);
  static const Color darkBgSurface   = Color(0xFF272433);
  static const Color darkTextPrimary = Color(0xFFF0EBD8);
  static const Color darkTextSecondary = Color(0xFF8A8A9A);
  static const Color darkTextMuted   = Color(0xFF4A4A5E);
  static const Color darkDivider     = Color(0xFF2E2B3C);

  static const Color amoledBg          = Color(0xFF000000);
  static const Color amoledBgCard      = Color(0xFF0A0A0A);
  static const Color amoledBgElevated  = Color(0xFF0F0F0F);
  static const Color amoledBgSurface   = Color(0xFF141414);
  static const Color amoledDivider     = Color(0xFF1A1A1A);

  static const Color lightBg           = Color(0xFFF5F3ED);
  static const Color lightBgSurface    = Color(0xFFEEEBE2);
  static const Color lightBgElevated   = Color(0xFFF2F0E8);
  static const Color lightBgCard       = Color(0xFFF9F7F1);
  static const Color lightTextPrimary  = Color(0xFF1A1610);
  static const Color lightTextSecondary = Color(0xFF6B6456);
  static const Color lightTextMuted    = Color(0xFFAA9F8E);
  static const Color lightDivider      = Color(0xFFE0D8C8);

  static const Color bg           = darkBg;
  static const Color bgCard       = darkBgCard;
  static const Color bgElevated   = darkBgElevated;
  static const Color bgSurface    = darkBgSurface;
  static const Color textPrimary  = darkTextPrimary;
  static const Color textSecondary = darkTextSecondary;
  static const Color textMuted    = darkTextMuted;
  static const Color divider      = darkDivider;

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentDark, accent, accentLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient accentGradientOf(BuildContext context) => LinearGradient(
    colors: [accentDarkOf(context), accentOf(context), accentLightOf(context)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient bgGradient = LinearGradient(
    colors: [darkBg, darkBgCard],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static ThemeData get theme      => _dark();
  static ThemeData get darkTheme  => _dark();
  static ThemeData get amoledTheme => _amoled();
  static ThemeData get lightTheme => _light();

  static ThemeData presetTheme(AurumColorPreset preset,
          {Brightness brightness = Brightness.dark}) =>
      brightness == Brightness.dark
          ? _dark(preset: preset)
          : _light(preset: preset);

  static ThemeData amoledPresetTheme(AurumColorPreset preset) =>
      _amoled(preset: preset);

  static ThemeData _dark({AurumColorPreset preset = AurumColorPreset.none}) {
    final p = AurumColorPresetCatalog.forId(preset)?.dark;
    return _build(
      brightness: Brightness.dark,
      bg: p?.background ?? darkBg,
      bgCard: p?.surface ?? darkBgCard,
      bgSurface: p?.surfaceVariant ?? darkBgSurface,
      textPrimary: p?.onBackground ?? darkTextPrimary,
      textMuted: p?.textMuted ?? darkTextMuted,
      divider: p?.divider ?? darkDivider,
      navBar: p?.surface ?? darkBgCard,
      preset: p,
    );
  }

  static ThemeData _amoled({AurumColorPreset preset = AurumColorPreset.none}) {
    final p = AurumColorPresetCatalog.forId(preset)?.dark;
    return _build(
      brightness: Brightness.dark,
      bg: amoledBg,
      bgCard: amoledBgCard,
      bgSurface: amoledBgSurface,
      textPrimary: darkTextPrimary,
      textMuted: darkTextMuted,
      divider: amoledDivider,
      navBar: amoledBgCard,
      preset: p,
      presetAccentOnly: true,
    );
  }

  static ThemeData _light({AurumColorPreset preset = AurumColorPreset.none}) {
    final p = AurumColorPresetCatalog.forId(preset)?.light;
    return _build(
      brightness: Brightness.light,
      bg: p?.background ?? lightBg,
      bgCard: p?.surface ?? lightBgCard,
      bgSurface: p?.surfaceVariant ?? lightBgSurface,
      textPrimary: p?.onBackground ?? lightTextPrimary,
      textMuted: p?.textMuted ?? lightTextMuted,
      divider: p?.divider ?? lightDivider,
      navBar: p?.surface ?? lightBgCard,
      preset: p,
    );
  }

  static ThemeData dynamicTheme(ColorScheme dynamic) {
    final isLight = dynamic.brightness == Brightness.light;

    Color enrich(Color c, {required double lightness, required double maxSat}) {
      final hsl = HSLColor.fromColor(c);
      return hsl
          .withSaturation(hsl.saturation.clamp(0.0, maxSat))
          .withLightness(lightness.clamp(0.0, 1.0))
          .toColor();
    }

    Color punchUpAccent(Color c, {required double lightness, required double minSat}) {
      final hsl = HSLColor.fromColor(c);
      final sat = hsl.saturation < minSat ? minSat : hsl.saturation;
      return hsl.withSaturation(sat).withLightness(lightness).toColor();
    }

    final bg = isLight
        ? enrich(dynamic.surface, lightness: 0.99, maxSat: 0.03)
        : dynamic.surface;
    final bgCard = isLight
        ? enrich(dynamic.surfaceContainer, lightness: 0.96, maxSat: 0.04)
        : dynamic.surfaceContainer;
    final bgSurface = isLight
        ? enrich(dynamic.surfaceContainerHigh, lightness: 0.93, maxSat: 0.05)
        : dynamic.surfaceContainerHigh;
    final bgElevated = isLight
        ? enrich(dynamic.surfaceContainerHighest, lightness: 0.90, maxSat: 0.06)
        : dynamic.surfaceContainerHighest;

    final textMuted = isLight
        ? enrich(dynamic.onSurfaceVariant, lightness: 0.38, maxSat: 0.10)
        : dynamic.onSurfaceVariant;
    final divider = isLight
        ? enrich(dynamic.outlineVariant, lightness: 0.72, maxSat: 0.06)
        : dynamic.outlineVariant;

    final accentPrimary = isLight
        ? punchUpAccent(dynamic.primary, lightness: 0.46, minSat: 0.45)
        : dynamic.primary;
    final accentSecondary = isLight
        ? punchUpAccent(dynamic.secondary, lightness: 0.58, minSat: 0.30)
        : dynamic.secondary;

    final enrichedScheme = dynamic.copyWith(
      primary: accentPrimary,
      onPrimary: isLight ? Colors.white : dynamic.onPrimary,
      secondary: accentSecondary,
      onSecondary: isLight ? Colors.white : dynamic.onSecondary,
      surfaceContainerHighest: bgElevated,
      surfaceContainerHigh: bgSurface,
      onSurfaceVariant: textMuted,
      outlineVariant: divider,
    );

    return _build(
      brightness: dynamic.brightness,
      bg: bg,
      bgCard: bgCard,
      bgSurface: bgSurface,
      textPrimary: dynamic.onSurface,
      textMuted: textMuted,
      divider: divider,
      navBar: bgCard,
      dynamicScheme: enrichedScheme,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color bgCard,
    required Color bgSurface,
    required Color textPrimary,
    required Color textMuted,
    required Color divider,
    required Color navBar,
    ColorScheme? dynamicScheme,
    AurumPresetPalette? preset,
    bool presetAccentOnly = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final primary   = dynamicScheme?.primary ?? preset?.accent ?? accent;
    final secondary = dynamicScheme?.secondary ?? preset?.accentLight ?? accentLight;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      canvasColor: Colors.transparent,
      colorScheme: (dynamicScheme ?? ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: bg,
        secondary: secondary,
        onSecondary: bg,
        surface: bgCard,
        onSurface: textPrimary,
        background: bg,
        onBackground: textPrimary,
        error: Colors.redAccent,
        onError: Colors.white,
      )).copyWith(
        surface: bgCard,
        onSurface: textPrimary,
        background: bg,
        onBackground: textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: bgCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 4,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 8,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bgCard,
        modalBackgroundColor: bgCard,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withAlpha(115),
        shadowColor: Colors.transparent,
        elevation: 8,
        modalElevation: 8,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(bgCard),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(4),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(bgCard),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(4),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: bgSurface,
        thumbColor: primary,
        overlayColor: primary.withOpacity(0.2),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return isDark ? darkTextMuted : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withOpacity(0.5);
          }
          return isDark ? bgSurface : divider;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return divider;
        }),
      ),
      iconTheme: IconThemeData(
        color: dynamicScheme != null
            ? textMuted
            : (preset != null && !presetAccentOnly
                ? preset.textSecondary
                : (isDark ? darkTextSecondary : lightTextSecondary)),
      ),
      dividerColor: divider,
      cardColor: bgCard,
      extensions: [
        if (dynamicScheme != null) const _DynamicMarker(),
        if (preset != null && dynamicScheme == null)
          _PresetMarker(
            accentLight: preset.accentLight,
            accentDark: preset.accentDark,
            textMuted: presetAccentOnly ? null : preset.textMuted,
            textSecondary: presetAccentOnly ? null : preset.textSecondary,
            bgSurface: presetAccentOnly ? null : preset.surfaceVariant,
            bgElevated: presetAccentOnly ? null : preset.elevated,
          ),
      ],
    );
  }

  static Color bgOf(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color bgCardOf(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  static Color textPrimaryOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;

  static Color textSecondaryOf(BuildContext context) {
    final presetSecondary =
        Theme.of(context).extension<_PresetMarker>()?.textSecondary;
    if (presetSecondary != null) return presetSecondary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkTextSecondary : lightTextSecondary;
  }

  static Color textMutedOf(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final presetMuted = Theme.of(context).extension<_PresetMarker>()?.textMuted;
    if (presetMuted != null) return presetMuted;
    if (_isDynamic(context)) return scheme.onSurfaceVariant;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkTextMuted : lightTextMuted;
  }

  static Color dividerOf(BuildContext context) =>
      Theme.of(context).dividerColor;

  static Color bgElevatedOf(BuildContext context) {
    final presetElevated =
        Theme.of(context).extension<_PresetMarker>()?.bgElevated;
    if (presetElevated != null) return presetElevated;
    if (_isDynamic(context)) return Theme.of(context).colorScheme.surfaceContainerHighest;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkBgElevated : lightBgElevated;
  }

  static Color bgSurfaceOf(BuildContext context) {
    final presetSurface =
        Theme.of(context).extension<_PresetMarker>()?.bgSurface;
    if (presetSurface != null) return presetSurface;
    if (_isDynamic(context)) return Theme.of(context).colorScheme.surfaceContainerHigh;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkBgSurface : lightBgSurface;
  }

  static bool _isDynamic(BuildContext context) =>
      Theme.of(context).extension<_DynamicMarker>() != null;

  static Color accentOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  static Color accentLightOf(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.extension<_DynamicMarker>() != null) {
      return theme.colorScheme.secondary;
    }
    return theme.extension<_PresetMarker>()?.accentLight ?? accentLight;
  }

  static Color accentDarkOf(BuildContext context) {
    final presetDark = Theme.of(context).extension<_PresetMarker>()?.accentDark;
    if (presetDark != null) return presetDark;
    if (Theme.of(context).extension<_DynamicMarker>() == null) return accentDark;
    final hsl = HSLColor.fromColor(Theme.of(context).colorScheme.primary);
    return hsl.withLightness((hsl.lightness - 0.15).clamp(0.0, 1.0)).toColor();
  }

  static BoxDecoration cardDecorationOf(BuildContext context) => BoxDecoration(
    color: bgCardOf(context),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: dividerOf(context), width: 0.5),
  );

  static BoxDecoration accentCardDecorationOf(BuildContext context) => BoxDecoration(
    color: bgCardOf(context),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: accent.withOpacity(0.3), width: 0.5),
    boxShadow: [
      BoxShadow(
        color: accent.withOpacity(0.08),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: bgCard,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: divider, width: 0.5),
  );

  static BoxDecoration get accentCardDecoration => BoxDecoration(
    color: bgCard,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: accent.withOpacity(0.3), width: 0.5),
    boxShadow: [
      BoxShadow(
        color: accent.withOpacity(0.08),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}
