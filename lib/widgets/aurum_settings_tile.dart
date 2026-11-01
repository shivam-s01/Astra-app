// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../theme/aurum_theme.dart';
import '../utils/aurum_motion.dart';
import 'aurum_pressable.dart';

class AurumSettingsTile extends StatelessWidget {
  const AurumSettingsTile._({
    required this.icon,
    this.customIcon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.onTap,
    this.trailing,
    this.isDanger = false,
  });

  final IconData? icon;
  final Widget? customIcon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool isDanger;

  factory AurumSettingsTile.switchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AurumSettingsTile._(
      icon: icon,
      title: title,
      subtitle: subtitle,
      iconColor: value ? AurumTheme.accentOf(context) : null,
      onTap: () => onChanged(!value),
      trailing: _AurumAnimatedSwitch(value: value, onChanged: onChanged),
    );
  }

  factory AurumSettingsTile.nav(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? customIcon,
    Color? iconColor,
  }) {
    return AurumSettingsTile._(
      icon: icon,
      customIcon: customIcon,
      title: title,
      subtitle: subtitle,
      iconColor: iconColor,
      onTap: onTap,
      trailing: Icon(Icons.chevron_right_rounded,
          color: AurumTheme.textMutedOf(context), size: 20),
    );
  }

  factory AurumSettingsTile.action(
    BuildContext context, {
    IconData? icon,
    Widget? customIcon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return AurumSettingsTile._(
      icon: icon,
      customIcon: customIcon,
      title: title,
      subtitle: subtitle,
      iconColor: iconColor,
      onTap: onTap,
      trailing: Icon(Icons.arrow_forward_ios_rounded,
          color: AurumTheme.textMutedOf(context), size: 14),
    );
  }

  factory AurumSettingsTile.danger(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return AurumSettingsTile._(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      isDanger: isDanger,
      trailing: Icon(Icons.chevron_right_rounded,
          color: AurumTheme.textMutedOf(context), size: 20),
    );
  }

  factory AurumSettingsTile.dropdown(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
    String Function(String)? optionLabel,
  }) {
    final label = optionLabel ?? (String o) => o;
    return AurumSettingsTile._(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: DropdownButton<String>(
        value: value,
        underline: const SizedBox(),
        dropdownColor: AurumTheme.bgCardOf(context),
        style: TextStyle(color: AurumTheme.accentOf(context), fontSize: 12, fontWeight: FontWeight.w600),
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: AurumTheme.accentOf(context), size: 18),
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(label(o)))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final danger = isDanger;
    final baseColor = danger ? Colors.redAccent : (iconColor ?? AurumTheme.accentOf(context));
    final leading = customIcon ??
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: baseColor.withOpacity(danger ? 0.1 : 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: baseColor, size: 18),
        );

    return AurumPressable(
      onTap: onTap,
      scaleAmount: 0.98,
      haptic: false,
      child: AnimatedContainer(
        duration: AurumMotion.durationOrZero(AurumMotion.short2),
        curve: AurumMotion.standard,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AurumTheme.bgCardOf(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: danger ? Colors.redAccent.withOpacity(0.3) : AurumTheme.dividerOf(context),
            width: danger ? 1 : 0.5,
          ),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: leading,
          title: Text(
            title,
            style: TextStyle(
              color: danger ? Colors.redAccent : AurumTheme.textPrimaryOf(context),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(subtitle, style: TextStyle(color: AurumTheme.textMutedOf(context), fontSize: 12)),
          trailing: trailing,
        ),
      ),
    );
  }
}

class _AurumAnimatedSwitch extends StatelessWidget {
  const _AurumAnimatedSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: AurumMotion.durationOrZero(AurumMotion.short2),
        curve: AurumMotion.standard,
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: value ? AurumTheme.accentOf(context) : AurumTheme.dividerOf(context),
        ),
        child: AnimatedAlign(
          duration: AurumMotion.durationOrZero(AurumMotion.short2),
          curve: AurumMotion.standard,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}

class AurumStaggerItem extends StatefulWidget {
  const AurumStaggerItem({
    super.key,
    required this.index,
    required this.child,
    this.stagger = const Duration(milliseconds: 40),
  });

  final int index;
  final Widget child;
  final Duration stagger;

  @override
  State<AurumStaggerItem> createState() => _AurumStaggerItemState();
}

class _AurumStaggerItemState extends State<AurumStaggerItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AurumMotion.medium2);
    _fade = CurvedAnimation(parent: _ctrl, curve: AurumMotion.standard);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: AurumMotion.standard));

    if (!AurumMotion.enabled) {
      _ctrl.value = 1;
    } else {
      final cappedIndex = widget.index > 6 ? 6 : widget.index;
      final delay = widget.stagger * cappedIndex;
      Future.delayed(delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
