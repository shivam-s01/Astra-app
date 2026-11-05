import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/song.dart';
import '../services/api_service.dart';
import '../services/share_card_service.dart';
import '../theme/aurum_theme.dart';
import '../utils/artwork_palette_cache.dart';
import '../utils/aurum_haptics.dart';
import '../utils/aurum_sheet.dart';
import 'share_cards.dart';

Future<void> showShareSongSheet(BuildContext context, Song song) {
  return showAurumModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ShareSongSheet(song: song),
  );
}

class ShareSongSheet extends StatefulWidget {
  final Song song;
  const ShareSongSheet({super.key, required this.song});

  @override
  State<ShareSongSheet> createState() => _ShareSongSheetState();
}

class _ShareSongSheetState extends State<ShareSongSheet> {
  final Map<ShareCardStyle, GlobalKey> _keys = {
    for (final s in ShareCardStyle.values) s: GlobalKey(),
  };
  PageController? _pc;
  int _index = 0;
  ImageProvider? _art;
  ArtworkPalette? _palette;
  bool _ready = false;
  List<String> _lyrics = const [];
  List<int> _picked = const [];
  bool _busy = false;
  bool _copied = false;
  bool _disposed = false;

  List<ShareCardStyle> get _styles => [
        ShareCardStyle.solid,
        ShareCardStyle.dark,
        if (_lyrics.isNotEmpty) ShareCardStyle.lyrics,
      ];

  ShareCardStyle get _current =>
      _styles[_index.clamp(0, _styles.length - 1)];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _loadLyrics();
    });
  }

  Future<void> _load() async {
    final song = widget.song;
    ArtworkPalette palette = const ArtworkPalette(
      vibrant: Color(0xFF6B4FD1),
      dominant: Color(0xFF241F38),
      darkMuted: Color(0xFF120F24),
      lightVibrant: Color(0xFF9B7EDE),
    );
    ImageProvider? art;
    try {
      art = await ShareCardService.resolveArt(song.artworkUrl);
    } catch (_) {}
    if (_disposed || !mounted) return;
    if (art != null) {
      try {
        await precacheImage(art, context, onError: (_, __) {});
      } catch (_) {}
    }
    try {
      if (song.artworkUrl.isNotEmpty) {
        palette = await ArtworkPaletteCache.get(song.artworkUrl)
            .timeout(const Duration(seconds: 4));
      }
    } catch (_) {}
    if (_disposed || !mounted) return;
    setState(() {
      _art = art;
      _palette = palette;
      _ready = true;
    });
  }

  Future<void> _loadLyrics() async {
    try {
      final r = await ApiService.fetchSyncedLyrics(widget.song)
          .timeout(const Duration(seconds: 5));
      if (_disposed || !mounted || !r.hasAny) return;
      final lines = ShareCardService.lyricLines(r);
      if (lines.length < 4) return;
      setState(() {
        _lyrics = lines;
        _picked = ShareCardService.defaultPick(lines);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _pc?.dispose();
    super.dispose();
  }

  ShareCardData get _data => ShareCardData(
        widget.song,
        _art,
        _palette!,
        lyricLines: [for (final i in _picked) _lyrics[i]],
      );

  String _caption() {
    final l10n = AppLocalizations.of(context)!;
    final text = l10n.fpShareText(widget.song.artist, widget.song.title);
    final link = ShareCardService.songLink(widget.song);
    return link == null ? text : '$text\n$link';
  }

  Future<void> _shareCard() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    AurumHaptics.light();
    final caption = _caption();
    try {
      await WidgetsBinding.instance.endOfFrame;
      final file = await ShareCardService.capture(_keys[_current]!);
      await ShareCardService.shareCard(file, caption, widget.song.title);
    } catch (_) {
      try {
        await ShareCardService.shareText(caption, widget.song.title);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLink() async {
    AurumHaptics.light();
    try {
      await ShareCardService.shareText(_caption(), widget.song.title);
    } catch (_) {}
  }

  Future<void> _copy() async {
    final link = ShareCardService.songLink(widget.song) ?? _caption();
    await Clipboard.setData(ClipboardData(text: link));
    AurumHaptics.selection();
    if (!mounted) return;
    setState(() => _copied = true);
    Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _editLines(Color fg, Color fgSoft, Color bg) async {
    final sel = <int>{..._picked};
    await showAurumModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Container(
          height: MediaQuery.sizeOf(ctx).height * 0.62,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Text('Choose up to 5 lines',
                  style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _lyrics.length,
                  itemBuilder: (_, i) {
                    final on = sel.contains(i);
                    return InkWell(
                      onTap: () {
                        AurumHaptics.selection();
                        setM(() {
                          if (on) {
                            if (sel.length > 1) sel.remove(i);
                          } else if (sel.length < 5) {
                            sel.add(i);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(_lyrics[i],
                                  style: TextStyle(
                                    color: on ? fg : fgSoft,
                                    fontSize: 16,
                                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                                  )),
                            ),
                            if (on)
                              Icon(Icons.check_circle_rounded, color: fg, size: 22),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: fg,
                      foregroundColor: bg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    child: const Text('Done',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _picked = sel.toList()..sort());
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final bg = isLight ? AurumTheme.lightBgCard : const Color(0xFF16151F);
    final fg = isLight ? AurumTheme.lightTextPrimary : Colors.white;
    final fgSoft = isLight ? AurumTheme.lightTextSecondary : Colors.white60;
    final accent = Theme.of(context).colorScheme.primary;
    final size = MediaQuery.sizeOf(context);

    final double cardH =
        math.min(size.height * 0.54, size.height - 360).clamp(240.0, 480.0).toDouble();
    final cardW = cardH * kShareCardW / kShareCardH;
    _pc ??= PageController(viewportFraction: (cardW + 20) / size.width);
    final styles = _styles;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: fgSoft.withAlpha(90),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: cardH + 8,
              child: !_ready
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                      ),
                    )
                  : PageView.builder(
                      controller: _pc,
                      itemCount: styles.length,
                      onPageChanged: (i) {
                        AurumHaptics.selection();
                        setState(() => _index = i);
                      },
                      itemBuilder: (_, i) {
                        final active = i == _index;
                        final style = styles[i];
                        return Center(
                          child: AnimatedScale(
                            scale: active ? 1 : 0.9,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            child: AnimatedOpacity(
                              opacity: active ? 1 : 0.55,
                              duration: const Duration(milliseconds: 220),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SizedBox(
                                  width: cardW,
                                  height: cardH,
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: RepaintBoundary(
                                      key: _keys[style],
                                      child: SizedBox(
                                        width: kShareCardW,
                                        height: kShareCardH,
                                        child: buildShareCard(style, _data),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(styles.length, (i) {
                final on = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: on ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: on ? fg : fgSoft.withAlpha(90),
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: !_ready || _busy ? null : _shareCard,
                  style: FilledButton.styleFrom(
                    backgroundColor: fg,
                    foregroundColor: bg,
                    disabledBackgroundColor: fg.withAlpha(60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  child: _busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: bg),
                        )
                      : const Text('Share'),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                if (_ready && _current == ShareCardStyle.lyrics)
                  _SoftButton('Choose lines', fgSoft, () => _editLines(fg, fgSoft, bg)),
                _SoftButton('Link only', fgSoft, _shareLink),
                _SoftButton(_copied ? 'Copied' : 'Copy link', fgSoft, _copy),
              ],
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SoftButton(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14)),
      );
}
