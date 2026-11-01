// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../theme/aurum_theme.dart';
import '../providers/locale_provider.dart';
import '../widgets/aurum_pressable.dart';
import '../widgets/aurum_settings_tile.dart';
import '../widgets/aurum_loader.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_motion.dart';

class SettingsLanguageScreen extends StatefulWidget {
  const SettingsLanguageScreen({super.key});

  @override
  State<SettingsLanguageScreen> createState() => _SettingsLanguageScreenState();
}

class _SettingsLanguageScreenState extends State<SettingsLanguageScreen> {
  String? _switchingTo;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _select(Locale? locale) async {
    if (_switchingTo != null) return;
    AurumHaptics.selection();
    setState(() => _switchingTo = locale?.languageCode ?? 'system');
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    await context.read<LocaleProvider>().setLocale(locale);
    if (!mounted) return;
    setState(() => _switchingTo = null);
  }

  bool _matchesQuery(String nativeName, String? englishName, String code) {
    if (_query.isEmpty) return true;
    if (nativeName.toLowerCase().contains(_query)) return true;
    if (englishName != null && englishName.toLowerCase().contains(_query)) return true;
    if (code.toLowerCase().contains(_query)) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final localeProvider = context.watch<LocaleProvider>();
    final currentCode = localeProvider.locale?.languageCode;

    final showSystemDefault = _query.isEmpty;

    final matches = kSupportedLocales.where((locale) {
      final code = locale.languageCode;
      final native = kLocaleDisplayNames[code] ?? code;
      final english = kLocaleEnglishNames[code];
      return _matchesQuery(native, english, code);
    }).toList();

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
        title: Text(l10n.settingsLanguage,
            style: TextStyle(
                color: AurumTheme.textPrimaryOf(context),
                fontSize: 18,
                fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
            child: Text(
              l10n.settingsLanguageSubtitle,
              style: TextStyle(
                color: AurumTheme.textSecondaryOf(context),
                fontSize: 13,
              ),
            ),
          ),
          _LanguageSearchField(controller: _searchController),
          const SizedBox(height: 16),
          if (showSystemDefault) ...[
            AurumStaggerItem(
              index: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: AurumTheme.bgCardOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
                ),
                child: _LanguageRow(
                  flag: null,
                  fallbackIcon: Icons.smartphone_rounded,
                  label: l10n.settingsLanguageSystemDefault,
                  sublabel: null,
                  selected: currentCode == null,
                  loading: _switchingTo == 'system',
                  enabled: _switchingTo == null,
                  onTap: () => _select(null),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (matches.isEmpty)
            _NoResults(query: _searchController.text.trim())
          else
            AurumStaggerItem(
              index: showSystemDefault ? 1 : 0,
              child: Container(
                decoration: BoxDecoration(
                  color: AurumTheme.bgCardOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
                ),
                child: Column(
                  children: List.generate(matches.length, (i) {
                    final locale = matches[i];
                    final code = locale.languageCode;
                    final isLast = i == matches.length - 1;
                    return Column(
                      children: [
                        _LanguageRow(
                          flag: kLocaleFlags[code],
                          fallbackIcon: Icons.translate_rounded,
                          label: kLocaleDisplayNames[code] ?? code,
                          sublabel: kLocaleEnglishNames[code],
                          selected: currentCode == code,
                          loading: _switchingTo == code,
                          enabled: _switchingTo == null,
                          onTap: () => _select(locale),
                        ),
                        if (!isLast)
                          Divider(
                              color: AurumTheme.dividerOf(context),
                              height: 0.5,
                              indent: 68,
                              endIndent: 14),
                      ],
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LanguageSearchField extends StatelessWidget {
  const _LanguageSearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AurumTheme.dividerOf(context), width: 0.5),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, color: AurumTheme.textMutedOf(context), size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 14.5),
              cursorColor: AurumTheme.accentOf(context),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: l10n.commonSearch,
                hintStyle: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 14.5),
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: AurumMotion.durationOrZero(AurumMotion.short2),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
            child: controller.text.isEmpty
                ? const SizedBox(key: ValueKey('empty'), width: 14)
                : Padding(
                    key: const ValueKey('clear'),
                    padding: const EdgeInsets.only(right: 8),
                    child: AurumPressable(
                      onTap: () {
                        AurumHaptics.light();
                        controller.clear();
                      },
                      scaleAmount: 0.85,
                      child: Icon(Icons.close_rounded,
                          color: AurumTheme.textMutedOf(context), size: 18),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.travel_explore_rounded,
              color: AurumTheme.textMutedOf(context).withValues(alpha: 0.5), size: 32),
          const SizedBox(height: 12),
          Text(
            l10n.searchNoResultsFor(query),
            textAlign: TextAlign.center,
            style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.flag,
    required this.fallbackIcon,
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
  });

  final String? flag;
  final IconData fallbackIcon;
  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback onTap;
  final bool loading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AurumPressable(
      onTap: enabled ? onTap : () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AurumTheme.dividerOf(context).withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(9),
              ),
              child: flag != null
                  ? Text(flag!, style: const TextStyle(fontSize: 18, height: 1.1))
                  : Icon(fallbackIcon, size: 17, color: AurumTheme.textMutedOf(context)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: enabled
                          ? AurumTheme.textPrimaryOf(context)
                          : AurumTheme.textMutedOf(context),
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (sublabel != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      sublabel!,
                      style: TextStyle(
                        color: AurumTheme.textMutedOf(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: AurumMotion.durationOrZero(AurumMotion.short2),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: loading
                  ? const SizedBox(
                      key: ValueKey('loading'),
                      width: 20,
                      height: 20,
                      child: AurumMorphLoader(size: 20),
                    )
                  : selected
                      ? Icon(Icons.check_circle_rounded, key: const ValueKey('sel'), color: AurumTheme.accentOf(context), size: 22)
                      : Icon(Icons.circle_outlined,
                          key: const ValueKey('unsel'),
                          color: AurumTheme.textMutedOf(context).withValues(alpha: 0.4), size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
