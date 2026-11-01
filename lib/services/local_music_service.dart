// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song.dart';

class LocalMusicService {
  static const _channel = MethodChannel('com.aurum.music/media_store');

  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    final audio = await Permission.audio.request();
    if (audio.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  static Future<bool> openAutostartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('openAutostartSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    if (await Permission.audio.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    return false;
  }

  static Future<List<Song>> scanLibrary() async {
    final granted = await hasPermission();
    if (!granted) {
      final result = await requestPermission();
      if (!result) return [];
    }

    try {
      final List<dynamic> raw =
          await _channel.invokeMethod('getSongs') ?? [];

      final songs = <Song>[];
      for (final item in raw) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final contentUri = map['contentUri']?.toString() ?? '';
          final dataPath   = map['localPath']?.toString() ?? '';
          final resolvedPath = dataPath.isNotEmpty ? dataPath : contentUri;

          final song = Song(
            id: map['id']?.toString() ?? '',
            title: _cleanTitle(map['title']?.toString() ?? ''),
            artist: _cleanArtist(map['artist']?.toString()),
            album: map['album']?.toString() ?? '',
            artworkUrl: map['artworkUrl']?.toString() ?? '',
            localPath: resolvedPath,
            duration: map['duration'] is int ? map['duration'] as int : null,
            source: SongSource.local,
          );
          if (song.id.isNotEmpty && song.localPath!.isNotEmpty) {
            songs.add(song);
          }
        } catch (_) {
          continue;
        }
      }
      return songs;
    } catch (_) {
      return [];
    }
  }

  static Future<List<SongSection>> scanLibrarySections(List<Song> songs) {
    if (songs.isEmpty) return Future.value([]);
    const unknownAlbum = '<unknown>';
    final byAlbum = <String, List<Song>>{};
    final untagged = <Song>[];
    for (final song in songs) {
      final album = song.album.trim();
      if (album.isEmpty || album == unknownAlbum) {
        untagged.add(song);
      } else {
        (byAlbum[album] ??= []).add(song);
      }
    }

    final sections = <SongSection>[];
    final leftovers = <Song>[...untagged];
    byAlbum.forEach((album, albumSongs) {
      if (albumSongs.length > 1) {
        sections.add(SongSection(title: album, songs: albumSongs));
      } else {
        leftovers.addAll(albumSongs);
      }
    });

    sections.sort((a, b) => b.songs.length.compareTo(a.songs.length));

    if (leftovers.isNotEmpty) {
      sections.add(SongSection(title: 'Device Songs', songs: leftovers));
    }

    return Future.value(sections);
  }

  static String _cleanTitle(String raw) {
    return raw
        .replaceAll(RegExp(r'\.(mp3|m4a|flac|wav|aac|ogg)$',
            caseSensitive: false), '')
        .replaceAll(RegExp(r'^\d+[.\-_\s]+'), '')
        .trim();
  }

  static String _cleanArtist(String? raw) {
    if (raw == null || raw.isEmpty || raw == '<unknown>') return 'Unknown';
    return raw.trim();
  }
}
