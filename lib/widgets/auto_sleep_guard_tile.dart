// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import '../services/native_engine_bridge.dart';
import '../theme/aurum_theme.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_sheet.dart';
import '../l10n/generated/app_localizations.dart';
import '../utils/aurum_motion.dart';

class AutoSleepGuardTile extends StatefulWidget {
  const AutoSleepGuardTile({super.key});

  @override
  State<AutoSleepGuardTile> createState() => _AutoSleepGuardTileState();
}

class _AutoSleepGuardTileState extends State<AutoSleepGuardTile> {
  final NativeAudioEngine _engine = NativeAudioEngine();

  bool _loading = true;
  bool _enabled = true;
  int _durationHours = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await _engine.autoSleepGuardGetState();
    if (!mounted) return;
    setState(() {
      _enabled = state['enabled'] as bool? ?? true;
      _durationHours = state['durationHours'] as int? ?? 3;
      _loading = false;
    });
  }

  Future<void> _openSheet(BuildContext context) async {
    final result = await showAurumModalBottomSheet<_AutoSleepGuardResult>(
      context: context,
      backgroundColor: AurumTheme.bgCardOf(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AutoSleepGuardSheet(
        initialEnabled: _enabled,
        initialHours: _durationHours,
      ),
    );

    if (result == null || !mounted) return;

    if (result.enabled != _enabled) {
      setState(() => _enabled = result.enabled);
      await _engine.autoSleepGuardSetEnabled(result.enabled);
      if (!mounted) return;
    }
    if (result.hours != _durationHours) {
      setState(() => _durationHours = result.hours);
      await _engine.autoSleepGuardSetDurationHours(result.hours);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSignedIn = context.watch<AuthProvider>().isSignedIn;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AurumTheme.bgCardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSignedIn
              ? AurumTheme.accentOf(context).withOpacity(0.35)
              : AurumTheme.dividerOf(context),
          width: isSignedIn ? 1 : 0.5,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: AurumTheme.accentOf(context).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.bedtime_rounded, color: AurumTheme.accentOf(context), size: 18),
        ),
        title: Text(
          l10n.asgTileTitle,
          style: TextStyle(
            color: AurumTheme.textPrimaryOf(context),
            fontSize: 14, fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          !isSignedIn
              ? l10n.asgTileSubtitleSignedOut
              : (_enabled ? l10n.asgTileSubtitleOn(_durationHours) : l10n.asgTileSubtitleOff),
          style: TextStyle(
            color: isSignedIn ? AurumTheme.accentOf(context) : AurumTheme.textMutedOf(context),
            fontSize: 12,
          ),
        ),
        trailing: _loading
            ? SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AurumTheme.accentOf(context)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSignedIn)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AurumTheme.accentOf(context).withOpacity(_enabled ? 0.12 : 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _enabled ? l10n.asgTileAutomaticBadge : l10n.asgTileOffBadge,
                        style: TextStyle(
                          color: _enabled ? AurumTheme.accentOf(context) : AurumTheme.textMutedOf(context),
                          fontSize: 11, fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (isSignedIn) const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded,
                      color: AurumTheme.textMutedOf(context), size: 18),
                ],
              ),
        onTap: !isSignedIn
            ? () => _showSignInRequiredHint(context)
            : () => _openSheet(context),
      ),
    );
  }

  void _showSignInRequiredHint(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AurumHaptics.selection();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AurumTheme.bgCardOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          l10n.asgTileSubtitleSignedOut,
          style: TextStyle(color: AurumTheme.textPrimaryOf(context), fontSize: 13),
        ),
      ),
    );
  }
}

class _AutoSleepGuardResult {
  final bool enabled;
  final int hours;
  const _AutoSleepGuardResult(this.enabled, this.hours);
}

class _AutoSleepGuardSheet extends StatefulWidget {
  final bool initialEnabled;
  final int initialHours;
  const _AutoSleepGuardSheet({required this.initialEnabled, required this.initialHours});

  @override
  State<_AutoSleepGuardSheet> createState() => _AutoSleepGuardSheetState();
}

class _AutoSleepGuardSheetState extends State<_AutoSleepGuardSheet> {
  late bool _enabled = widget.initialEnabled;
  late int _selectedHours = widget.initialHours;
  bool _showSavedTick = false;

  void _flashSaved() {
    setState(() => _showSavedTick = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showSavedTick = false);
    });
  }

  void _selectMode(bool enabled) {
    if (_enabled == enabled) return;
    AurumHaptics.selection();
    setState(() => _enabled = enabled);
    _flashSaved();
  }

  void _selectHours(int hours) {
    if (_selectedHours == hours) return;
    AurumHaptics.light();
    setState(() => _selectedHours = hours);
    _flashSaved();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: AurumTheme.accentGradient,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.bedtime_rounded, color: Colors.black, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.asgSheetTitle,
                  style: TextStyle(
                    color: AurumTheme.textPrimaryOf(context),
                    fontSize: 17, fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AnimatedOpacity(
                  opacity: _showSavedTick ? 1 : 0,
                  duration: AurumMotion.durationOrZero(AurumMotion.medium1),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: AurumTheme.accentOf(context), size: 16),
                      const SizedBox(width: 4),
                      Text(l10n.asgSheetSaved,
                          style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              l10n.asgSheetBody,
              style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, color: AurumTheme.accentOf(context).withOpacity(0.8), size: 13),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.asgSheetPremiumHint,
                    style: TextStyle(
                      color: AurumTheme.accentOf(context).withOpacity(0.85),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              l10n.asgSheetModeLabel,
              style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            _ModeOption(
              selected: _enabled,
              title: l10n.asgSheetModeAutomatic,
              subtitle: l10n.asgSheetModeAutomaticDesc,
              onTap: () => _selectMode(true),
            ),
            const SizedBox(height: 8),
            _ModeOption(
              selected: !_enabled,
              title: l10n.asgSheetModeOff,
              subtitle: l10n.asgSheetModeOffDesc,
              onTap: () => _selectMode(false),
            ),
            const SizedBox(height: 20),
            AnimatedCrossFade(
              duration: AurumMotion.durationOrZero(AurumMotion.medium1),
              crossFadeState: _enabled ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.asgSheetDurationLabel,
                    style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [3, 5].map((h) {
                      final isSelected = _selectedHours == h;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _selectHours(h),
                          child: AnimatedContainer(
                            duration: AurumMotion.durationOrZero(AurumMotion.medium1),
                            margin: EdgeInsets.only(right: h == 3 ? 10 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: isSelected ? AurumTheme.accentOf(context).withOpacity(0.14) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? AurumTheme.accentOf(context) : AurumTheme.dividerOf(context),
                                width: isSelected ? 1.4 : 0.8,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              l10n.asgSheetHours(h),
                              style: TextStyle(
                                color: isSelected ? AurumTheme.accentOf(context) : AurumTheme.textPrimaryOf(context),
                                fontSize: 15,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              secondChild: const SizedBox.shrink(),
            ),
            SizedBox(height: _enabled ? 20 : 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AurumTheme.accentOf(context),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  AurumHaptics.light();
                  Navigator.of(context).pop(_AutoSleepGuardResult(_enabled, _selectedHours));
                },
                child: Text(l10n.asgSheetDone, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeOption({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AurumMotion.durationOrZero(AurumMotion.medium1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AurumTheme.accentOf(context).withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AurumTheme.accentOf(context).withOpacity(0.5) : AurumTheme.dividerOf(context),
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          children: [
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
                  Text(
                    title,
                    style: TextStyle(
                      color: AurumTheme.textPrimaryOf(context),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 11.5, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
