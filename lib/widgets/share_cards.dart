import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/song.dart';
import '../utils/artwork_palette_cache.dart';

/// Fixed 360x640 canvas, captured at 3x = 1080x1920.
const double kShareCardW = 360;
const double kShareCardH = 640;
const String _font = 'Roboto';

enum ShareCardStyle { solid, dark, lyrics }

class ShareCardData {
  final Song song;
  final ImageProvider? art;
  final ArtworkPalette palette;
  final List<String> lyricLines;
  const ShareCardData(this.song, this.art, this.palette,
      {this.lyricLines = const []});
}

/// Wraps every card so it renders identically on every phone: fixed
/// direction, no accessibility text scaling, fixed font.
Widget buildShareCard(ShareCardStyle style, ShareCardData d) {
  return Builder(
    builder: (context) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: _font, decoration: TextDecoration.none),
          child: switch (style) {
            ShareCardStyle.solid => _SolidCard(d),
            ShareCardStyle.dark => _DarkCard(d),
            ShareCardStyle.lyrics => _LyricsCard(d),
          },
        ),
      ),
    ),
  );
}

/// Vivid but readable colour from the artwork, like Spotify's share cards.
Color solidColorFor(ArtworkPalette p) {
  final hsl = HSLColor.fromColor(p.vibrant);
  final sat = hsl.saturation < 0.12 ? hsl.saturation : hsl.saturation.clamp(0.30, 0.62).toDouble();
  return hsl.withSaturation(sat).withLightness(hsl.lightness.clamp(0.26, 0.50).toDouble()).toColor();
}

Color onColorFor(Color bg) {
  double ratio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
  const dark = Color(0xFF121212);
  return ratio(bg, Colors.white) >= ratio(bg, dark) ? Colors.white : dark;
}

TextStyle _title(Color c, double size) => TextStyle(
      fontFamily: _font,
      color: c,
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.16,
      letterSpacing: -0.7,
      decoration: TextDecoration.none,
    );

TextStyle _sub(Color c, double size, {FontWeight w = FontWeight.w600}) => TextStyle(
      fontFamily: _font,
      color: c,
      fontSize: size,
      fontWeight: w,
      height: 1.25,
      decoration: TextDecoration.none,
    );

class _Art extends StatelessWidget {
  final ShareCardData d;
  final double size;
  final double radius;
  const _Art(this.d, this.size, this.radius);

  @override
  Widget build(BuildContext context) {
    final art = d.art;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: art == null
            ? DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [solidColorFor(d.palette), d.palette.darkMuted],
                  ),
                ),
                child: Icon(Icons.music_note_rounded,
                    size: size * 0.34, color: Colors.white70),
              )
            : Image(image: art, fit: BoxFit.cover, filterQuality: FilterQuality.high),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final Color color;
  const _Wordmark(this.color);

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/astra_wordmark.png',
        height: 16,
        color: color,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.high,
      );
}

/// The Astra "code": play button + waveform bars unique to each song.
class _Code extends StatelessWidget {
  final String seed;
  final Color on;
  final Color bg;
  const _Code(this.seed, this.on, this.bg);

  List<double> _bars() {
    var h = seed.hashCode & 0x7fffffff;
    final out = <double>[];
    for (var i = 0; i < 34; i++) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      final env = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(i / 34 * 6.9 + 1));
      out.add((0.25 + 0.75 * ((h % 1000) / 1000) * env).clamp(0.16, 1.0));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: on, shape: BoxShape.circle),
            child: Icon(Icons.play_arrow_rounded, color: bg, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (final v in _bars())
                  Expanded(
                    child: Center(
                      child: Container(
                        height: 38 * v,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: on,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SolidBg extends StatelessWidget {
  final Color color;
  final Widget child;
  const _SolidBg(this.color, this.child);

  @override
  Widget build(BuildContext context) => SizedBox(
        width: kShareCardW,
        height: kShareCardH,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x14FFFFFF), Color(0x00000000), Color(0x1F000000)],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 34, 32, 34),
              child: child,
            ),
          ),
        ),
      );
}

// 1. Solid: artwork colour, left-aligned type, Astra code at the bottom.
class _SolidCard extends StatelessWidget {
  final ShareCardData d;
  const _SolidCard(this.d);

  @override
  Widget build(BuildContext context) {
    final bg = solidColorFor(d.palette);
    final on = onColorFor(bg);
    return _SolidBg(
      bg,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Wordmark(on),
          const SizedBox(height: 26),
          Center(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(color: Color(0x70000000), blurRadius: 40, spreadRadius: -12, offset: Offset(0, 24)),
                ],
              ),
              child: _Art(d, 296, 8),
            ),
          ),
          const SizedBox(height: 34),
          Text(d.song.title,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: _title(on, 30)),
          const SizedBox(height: 8),
          Text(d.song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _sub(on.withAlpha(189), 17)),
          const Spacer(),
          _Code(d.song.id + d.song.title, on, bg),
        ],
      ),
    );
  }
}

// 2. Dark: flat near-black, left-aligned, artwork colour only in the Astra code.
class _DarkCard extends StatelessWidget {
  final ShareCardData d;
  const _DarkCard(this.d);

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF121212);
    final accent = solidColorFor(d.palette);
    final bar = Color.lerp(accent, Colors.white, 0.35)!;
    return SizedBox(
      width: kShareCardW,
      height: kShareCardH,
      child: ColoredBox(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 34, 32, 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Wordmark(Colors.white),
              const SizedBox(height: 26),
              Center(child: _Art(d, 296, 8)),
              const SizedBox(height: 34),
              Text(d.song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _title(Colors.white, 30)),
              const SizedBox(height: 8),
              Text(d.song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sub(Colors.white.withAlpha(166), 17)),
              const Spacer(),
              _Code(d.song.id + d.song.title, bar, bg),
            ],
          ),
        ),
      ),
    );
  }
}

// 3. Lyrics: the lines you picked, big.
class _LyricsCard extends StatelessWidget {
  final ShareCardData d;
  const _LyricsCard(this.d);

  @override
  Widget build(BuildContext context) {
    final bg = solidColorFor(d.palette);
    final on = onColorFor(bg);
    return _SolidBg(
      bg,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Wordmark(on),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 296,
                  child: Text(
                    d.lyricLines.join('\n'),
                    style: _title(on, 31).copyWith(height: 1.22, letterSpacing: -0.8),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              _Art(d, 54, 7),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(d.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sub(on, 15, w: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(d.song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _sub(on.withAlpha(184), 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
