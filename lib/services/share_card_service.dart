import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/lyrics.dart';
import '../models/song.dart';
import '../widgets/aurum_artwork.dart';
import 'aurum_image_cache.dart';

const MethodChannel _mediaStore = MethodChannel('com.aurum.music/media_store');

class ShareMeta {
  final String title;
  final String artist;
  final String art;
  final String src;
  final String id;
  const ShareMeta(this.title, this.artist, this.art, {this.src = '', this.id = ''});
}

class ShareCardService {
  ShareCardService._();

  static const String host = 'astra.mmusic.workers.dev';

  static String _clip(String s, int n) => s.length <= n ? s : s.substring(0, n);

  /// Compact, opaque token (deflate + base64url) so the link in chat stays
  /// short and tidy instead of a wall of %-escapes.
  static String _encodeMeta(Song s) {
    final art = s.artworkUrl.startsWith('http')
        ? AurumArtwork.upgradeForFullPlayer(s.artworkUrl)
            .replaceFirst(RegExp(r'^https://'), '')
        : '';
    final raw = '${_clip(s.title, 120)}\n${_clip(s.artist, 120)}\n$art';
    final bytes = ZLibCodec(level: 9).encode(utf8.encode(raw));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static ShareMeta? decodeMeta(String token) {
    try {
      final padded = token + '=' * ((4 - token.length % 4) % 4);
      final raw = utf8.decode(ZLibCodec().decode(base64Url.decode(padded)));
      final p = raw.split('\n');
      if (p.length < 2) return null;
      return ShareMeta(p[0], p[1], p.length > 2 ? p[2] : '');
    } catch (_) {
      return null;
    }
  }

  static final Map<String, String> _linkCache = {};

  static String _srcOf(Song s) => s.source == SongSource.youtube ? 'yt' : 'sv';

  /// Short link like https://astra.mmusic.workers.dev/s/Ab3dE9xK. The site keeps
  /// the song details; if it cannot be reached we fall back to a longer
  /// self-contained link so sharing never fails.
  static Future<String?> songLink(Song s) async {
    if (s.isLocal || s.id.isEmpty || s.source == SongSource.local) return null;
    final key = '${_srcOf(s)}:${s.id}';
    final cached = _linkCache[key];
    if (cached != null) return cached;
    final short = await _createShort(s);
    if (short != null) {
      _linkCache[key] = short;
      return short;
    }
    return _longLink(s);
  }

  static String _longLink(Song s) => Uri(
        scheme: 'https',
        host: host,
        pathSegments: ['s', _srcOf(s), s.id],
        queryParameters: {'d': _encodeMeta(s)},
      ).toString();

  static Future<Map<String, dynamic>?> _json(String method, Uri uri,
      [Map<String, dynamic>? body]) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = method == 'POST' ? await c.postUrl(uri) : await c.getUrl(uri);
      req.headers.contentType = ContentType.json;
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(await res.transform(utf8.decoder).join());
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static Future<String?> _createShort(Song s) async {
    final art = s.artworkUrl.startsWith('http')
        ? AurumArtwork.upgradeForFullPlayer(s.artworkUrl)
        : '';
    final j = await _json('POST', Uri.https(host, '/api/public/share'), {
      'src': _srcOf(s),
      'id': s.id,
      't': _clip(s.title, 150),
      'a': _clip(s.artist, 150),
      'i': art,
    });
    final code = j?['code'];
    if (code is! String || !RegExp(r'^[A-Za-z0-9]{6,12}$').hasMatch(code)) return null;
    return 'https://$host/s/$code';
  }

  /// Opens a short link: asks the site which song it points to.
  static Future<ShareMeta?> resolveCode(String code) async {
    if (!RegExp(r'^[A-Za-z0-9]{6,12}$').hasMatch(code)) return null;
    final j = await _json('GET', Uri.https(host, '/api/public/share', {'code': code}));
    if (j == null) return null;
    final src = j['src'], id = j['id'];
    if (src is! String || id is! String) return null;
    return ShareMeta('${j['t'] ?? ''}', '${j['a'] ?? ''}', '${j['i'] ?? ''}', src: src, id: id);
  }

  static Future<ImageProvider?> resolveArt(String url) async {
    if (url.isEmpty) return null;
    if (url.startsWith('content://')) {
      try {
        final b = await _mediaStore
            .invokeMethod<Uint8List>('getAlbumArt', {'uri': url});
        if (b == null || b.isEmpty) return null;
        return MemoryImage(b);
      } catch (_) {
        return null;
      }
    }
    if (url.startsWith('/') || url.startsWith('file://')) {
      final p = url.startsWith('file://') ? url.replaceFirst('file://', '') : url;
      return File(p).existsSync() ? FileImage(File(p)) : null;
    }
    if (url.startsWith('http')) {
      return CachedNetworkImageProvider(
        AurumArtwork.upgradeForFullPlayer(url),
        cacheManager: AurumImageCache(),
      );
    }
    return null;
  }

  // ── lyrics helpers ────────────────────────────────────────────────

  static List<String> lyricLines(LyricsResult r) {
    final raw = r.hasSynced
        ? r.synced!.map((l) => l.text)
        : (r.plain ?? '').split('\n');
    final out = <String>[];
    for (final l in raw) {
      final t = l.trim();
      if (t.isEmpty) continue;
      if (RegExp(r'^[\[\(].*[\]\)]$').hasMatch(t)) continue;
      out.add(t);
    }
    return out;
  }

  static String _lineKey(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  /// Picks up to 4 different lines starting at the most repeated line
  /// (usually the chorus). Lines that repeat are skipped, so the card never
  /// shows the same sentence twice.
  static List<int> defaultPick(List<String> lines) {
    if (lines.isEmpty) return const [];
    final count = <String, int>{};
    for (final l in lines) {
      final k = _lineKey(l);
      count[k] = (count[k] ?? 0) + 1;
    }
    var start = (lines.length * 0.3).floor();
    var best = 1;
    for (var i = 0; i < lines.length; i++) {
      final c = count[_lineKey(lines[i])] ?? 1;
      if (c > best && lines[i].length > 12) {
        best = c;
        start = i;
      }
    }
    final seen = <String>{};
    final out = <int>[];
    for (var i = start; i < lines.length && out.length < 4; i++) {
      if (seen.add(_lineKey(lines[i]))) out.add(i);
    }
    // not enough lines after `start`: fill from the beginning
    for (var i = 0; i < start && out.length < 4; i++) {
      if (seen.add(_lineKey(lines[i]))) out.add(i);
    }
    out.sort();
    return out;
  }

  // ── capture & share ───────────────────────────────────────────────

  static Future<File> capture(GlobalKey key) async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 3.0);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    final dir = await getTemporaryDirectory();
    _cleanup(dir);
    final f = File(
        '${dir.path}/astra_share_${DateTime.now().millisecondsSinceEpoch}.png');
    await f.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    return f;
  }

  static void _cleanup(Directory dir) {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 2));
      for (final e in dir.listSync()) {
        if (e is File &&
            e.path.contains('astra_share_') &&
            e.statSync().modified.isBefore(cutoff)) {
          e.deleteSync();
        }
      }
    } catch (_) {}
  }

  static Future<void> shareCard(File png, String caption, String subject) {
    return Share.shareXFiles(
      [XFile(png.path, mimeType: 'image/png')],
      text: caption,
      subject: subject,
    );
  }

  static Future<void> shareText(String caption, String subject) {
    return Share.share(caption, subject: subject);
  }
}
