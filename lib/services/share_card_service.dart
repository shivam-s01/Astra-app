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
  const ShareMeta(this.title, this.artist, this.art);
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

  static String? songLink(Song s) {
    if (s.isLocal || s.id.isEmpty || s.source == SongSource.local) return null;
    final src = s.source == SongSource.youtube ? 'yt' : 'sv';
    return Uri(
      scheme: 'https',
      host: host,
      pathSegments: ['s', src, s.id],
      queryParameters: {'d': _encodeMeta(s)},
    ).toString();
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

  /// Picks 4 lines starting at the most repeated line (usually the chorus).
  static List<int> defaultPick(List<String> lines) {
    if (lines.isEmpty) return const [];
    final count = <String, int>{};
    String key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    for (final l in lines) {
      count[key(l)] = (count[key(l)] ?? 0) + 1;
    }
    var start = (lines.length * 0.3).floor();
    var best = 1;
    for (var i = 0; i < lines.length; i++) {
      final c = count[key(lines[i])] ?? 1;
      if (c > best && lines[i].length > 12) {
        best = c;
        start = i;
      }
    }
    final end = (start + 4).clamp(0, lines.length);
    final from = (end - 4).clamp(0, lines.length);
    return [for (var i = from; i < end; i++) i];
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
