// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'audio_prefs.dart';
import 'recommendation_engine.dart';

const String _ytWorkerBase = 'https://aurum-worker.shivamsharma962122.workers.dev';

const int _kMinViewsForBrowse = 100000;

int? _safeViewCount(yt.Video v) {
  try {
    return v.engagement.viewCount;
  } catch (_) {
    return null;
  }
}

bool _isBrowseQuality(yt.Video v) {
  final views = _safeViewCount(v);
  if (views == null || views < _kMinViewsForBrowse) return false;
  if (RecommendationEngine.isLowQualityUpload(v.title)) return false;
  return true;
}

String _clean(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

String _hqArtwork(String url) {
  if (url.isEmpty) return '';
  return url
      .replaceAll('150x150', '500x500')
      .replaceAll('50x50', '500x500');
}

String _bestYtThumbnail(yt.ThumbnailSet thumbnails) {
  if (AudioPrefs.dataSaverActiveNotifier.value &&
      thumbnails.mediumResUrl.isNotEmpty) {
    return thumbnails.mediumResUrl;
  }
  if (thumbnails.highResUrl.isNotEmpty) return thumbnails.highResUrl;
  if (thumbnails.mediumResUrl.isNotEmpty) return thumbnails.mediumResUrl;
  return thumbnails.lowResUrl;
}

class BrowseTrack {
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final int?   durationMs;
  final bool   isFromYoutube;

  const BrowseTrack({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkUrl,
    this.durationMs,
    this.isFromYoutube = false,
  });

  String get resolveQuery => '$title $artist';

  factory BrowseTrack.fromSaavn(Map<String, dynamic> j) {
    final rawImage = j['image'];
    final artwork = _hqArtwork(
      rawImage is List
          ? ((rawImage.lastWhere((e) => e is Map, orElse: () => {}) as Map)['url'] ?? '').toString()
          : (rawImage ?? '').toString(),
    );
    final durationSec = int.tryParse(j['duration']?.toString() ?? '');
    final albumField = j['album'];
    final albumStr = albumField is Map
        ? (albumField['name'] ?? '').toString()
        : (albumField ?? '').toString();
    return BrowseTrack(
      trackId:    (j['id'] ?? j['song_id'] ?? '').toString(),
      title:      _clean((j['song'] ?? j['name'] ?? j['title'] ?? 'Unknown').toString()),
      artist:     _clean((j['primary_artists'] ?? j['singers'] ?? j['artist'] ?? 'Unknown').toString()),
      album:      _clean(albumStr),
      artworkUrl: artwork,
      durationMs: durationSec != null ? durationSec * 1000 : null,
    );
  }
}

class BrowseAlbum {
  final String collectionId;
  final String name;
  final String artist;
  final String artworkUrl;
  final int?   trackCount;
  final String? releaseYear;
  final bool   isFromYoutube;

  const BrowseAlbum({
    required this.collectionId,
    required this.name,
    required this.artist,
    required this.artworkUrl,
    this.trackCount,
    this.releaseYear,
    this.isFromYoutube = false,
  });

  factory BrowseAlbum.fromSaavn(Map<String, dynamic> j) {
    final artwork = _hqArtwork(
      (j['image'] is List
          ? (j['image'] as List).lastWhere(
              (e) => e is Map, orElse: () => {})['url'] ?? ''
          : j['image']?.toString() ?? ''),
    );
    return BrowseAlbum(
      collectionId: (j['id'] ?? '').toString(),
      name:         _clean((j['name'] ?? j['title'] ?? 'Unknown').toString()),
      artist:       _clean((j['artists']?['primary']?.isNotEmpty == true
                      ? (j['artists']['primary'] as List).map((a) => a['name']).join(', ')
                      : j['primary_artists'] ?? 'Unknown').toString()),
      artworkUrl:   artwork,
      trackCount:   int.tryParse(j['songCount']?.toString() ?? ''),
      releaseYear:  j['year']?.toString(),
    );
  }
}

class BrowseArtist {
  final String artistId;
  final String name;
  final String? genre;
  final String  imageUrl;
  final bool    isFromYoutube;
  final String? channelId;

  const BrowseArtist({
    required this.artistId,
    required this.name,
    this.genre,
    this.imageUrl = '',
    this.isFromYoutube = false,
    this.channelId,
  });

  factory BrowseArtist.fromSaavn(Map<String, dynamic> j) {
    final rawImage = j['image'];
    final artwork = _hqArtwork(
      rawImage is List
          ? ((rawImage.lastWhere((e) => e is Map, orElse: () => {}) as Map)['url']
                  ?? (rawImage.lastWhere((e) => e is Map, orElse: () => {}) as Map)['link']
                  ?? '').toString()
          : (rawImage ?? '').toString(),
    );
    return BrowseArtist(
      artistId: (j['id'] ?? '').toString(),
      name:     _clean((j['name'] ?? j['title'] ?? 'Unknown').toString()),
      genre:    null,
      imageUrl: artwork,
    );
  }

  BrowseArtist copyWith({String? imageUrl, bool? isFromYoutube}) => BrowseArtist(
    artistId: artistId,
    name: name,
    genre: genre,
    imageUrl: imageUrl ?? this.imageUrl,
    isFromYoutube: isFromYoutube ?? this.isFromYoutube,
    channelId: channelId,
  );
}

class BrowseService {
  static final _client = http.Client();

  static Future<BrowseSearchResult> search(String query) async {
    if (query.trim().isEmpty) return BrowseSearchResult.empty();
    final q = query.trim();

    final ytClient = yt.YoutubeExplode();
    List<BrowseTrack> tracks;
    List<BrowseAlbum> albums;
    List<BrowseArtist> artists;
    try {
      final artistsFuture = _ytArtistFallback(q);
      tracks  = await _ytTracksFor(q, ytClient);
      albums  = await _ytAlbumFallback(q, ytClient);
      artists = await artistsFuture;
    } finally {
      ytClient.close();
    }

    if (artists.isNotEmpty) {
      artists = await Future.wait(artists.map(_withArtistPhoto));
    }

    BrowseAlbum? topAlbum;
    List<BrowseTrack> topAlbumTracks = const [];
    if (albums.isNotEmpty) {
      String norm(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9\s]'), '');
      final qNorm = norm(q);
      for (final a in albums) {
        final aNorm = norm(a.name);
        if (aNorm.isEmpty || qNorm.isEmpty) continue;
        final isStrongMatch = aNorm == qNorm || aNorm.startsWith(qNorm) || qNorm.startsWith(aNorm);
        if (isStrongMatch) {
          topAlbum = a;
          break;
        }
      }
      if (topAlbum != null) {
        try {
          topAlbumTracks = await albumTracks(topAlbum.collectionId, isFromYoutube: true)
              .timeout(const Duration(seconds: 6), onTimeout: () => <BrowseTrack>[]);
        } catch (_) {
          topAlbumTracks = const [];
        }
      }
    }

    return BrowseSearchResult(
      tracks: tracks,
      albums: albums,
      artists: artists,
      topAlbum: topAlbumTracks.isNotEmpty ? topAlbum : null,
      topAlbumTracks: topAlbumTracks,
    );
  }

  static Future<BrowseArtist> _withArtistPhoto(BrowseArtist artist) async {
    if (artist.imageUrl.isNotEmpty) return artist;
    final ytThumb = await _ytThumbnailFor('${artist.name} singer');
    if (ytThumb.isNotEmpty) return artist.copyWith(imageUrl: ytThumb);
    return artist;
  }

  static Future<List<BrowseArtist>> _ytArtistFallback(String query) async {
    try {
      final uri = Uri.parse(
        '$_ytWorkerBase/api/yt-music-search?query=${Uri.encodeComponent(query)}&limit=25',
      );
      final resp = await _client.get(uri).timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data['success'] != true) return [];
      final results = (data['data']?['results'] as List?) ?? [];

      final seen = <String>{};
      final out = <BrowseArtist>[];
      for (final r in results) {
        if (r is! Map) continue;
        final name = _clean((r['artist'] ?? '').toString());
        if (name.isEmpty || !_isRealArtist(name) || seen.contains(name.toLowerCase())) continue;
        final rawChannelId = r['artistChannelId'];
        final channelId = rawChannelId is String ? rawChannelId.trim() : null;
        seen.add(name.toLowerCase());
        out.add(BrowseArtist(
          artistId: channelId?.isNotEmpty == true ? channelId! : name,
          name: name,
          imageUrl: (r['image'] ?? '').toString(),
          isFromYoutube: true,
          channelId: channelId?.isNotEmpty == true ? channelId : null,
        ));
        if (out.length >= 8) break;
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static const List<String> _officialAlbumChannelMarkers = [
    't-series', 'zee music', 'sony music', 'saregama', 'tips official',
    'tips music', 'speed records', 'desi music factory', 'shemaroo',
    'venus', 'eros now music', 'yrf', 'jjust music', 'white hill music',
    'times music', 'muzik one', 'goldmines', 'ultra music', 'divo',
    'universal music', 'sony music south', 'aditya music', 'lahari music',
    'think music', 'zee music south', 'wave music', 'atlantic records',
    'republic records', 'columbia records', 'interscope', 'def jam',
  ];

  static bool _isOfficialAlbumChannel(String channelName) {
    final c = channelName.toLowerCase();
    return _officialAlbumChannelMarkers.any((m) => c.contains(m));
  }

  static Future<List<BrowseAlbum>> _ytAlbumFallback(String query, yt.YoutubeExplode ytClient, {int count = 6}) async {
    try {
      final results = await ytClient.search.search('$query song')
          .then((list) => list.toList())
          .timeout(const Duration(seconds: 8), onTimeout: () => <yt.Video>[]);

      final qualified = results.where((v) =>
          _isBrowseQuality(v) && !RecommendationEngine.isInherentVariant(v.title)).toList();

      final channelOrder = <String>[];
      final channelBest = <String, yt.Video>{};
      final channelTitles = <String, List<String>>{};
      for (final v in qualified) {
        final channel = v.author.trim();
        if (channel.isEmpty) continue;
        final key = channel.toLowerCase();
        final titlesSoFar = channelTitles.putIfAbsent(key, () => []);
        var isDupWithinChannel = false;
        for (final seen in titlesSoFar) {
          if (RecommendationEngine.isSameSongSmart(v.title, seen)) { isDupWithinChannel = true; break; }
        }
        if (isDupWithinChannel) continue;
        titlesSoFar.add(v.title);
        if (!channelBest.containsKey(key)) {
          channelOrder.add(key);
          channelBest[key] = v;
        }
      }

      channelOrder.sort((a, b) {
        final aOfficial = _isOfficialAlbumChannel(a) ? 0 : 1;
        final bOfficial = _isOfficialAlbumChannel(b) ? 0 : 1;
        return aOfficial.compareTo(bOfficial);
      });

      final out = <BrowseAlbum>[];
      for (final key in channelOrder) {
        if (out.length >= count) break;
        final v = channelBest[key]!;
        final thumb = _bestYtThumbnail(v.thumbnails);
        final trackCount = channelTitles[key]?.length;
        out.add(BrowseAlbum(
          collectionId: v.author.trim(),
          name: _clean(v.title),
          artist: _clean(v.author),
          artworkUrl: thumb,
          trackCount: trackCount,
          isFromYoutube: true,
        ));
      }

      if (out.isEmpty) {
        final fallbackChannelOrder = <String>[];
        final fallbackChannelBest = <String, yt.Video>{};
        final fallbackChannelTitles = <String, List<String>>{};
        for (final v in results) {
          final channel = v.author.trim();
          if (channel.isEmpty) continue;
          final key = channel.toLowerCase();
          final titlesSoFar = fallbackChannelTitles.putIfAbsent(key, () => []);
          var isDupWithinChannel = false;
          for (final seen in titlesSoFar) {
            if (RecommendationEngine.isSameSongSmart(v.title, seen)) { isDupWithinChannel = true; break; }
          }
          if (isDupWithinChannel) continue;
          titlesSoFar.add(v.title);
          if (!fallbackChannelBest.containsKey(key)) {
            fallbackChannelOrder.add(key);
            fallbackChannelBest[key] = v;
          }
        }
        for (final key in fallbackChannelOrder) {
          if (out.length >= count) break;
          final v = fallbackChannelBest[key]!;
          final thumb = _bestYtThumbnail(v.thumbnails);
          out.add(BrowseAlbum(
            collectionId: v.author.trim(),
            name: _clean(v.title),
            artist: _clean(v.author),
            artworkUrl: thumb,
            trackCount: fallbackChannelTitles[key]?.length,
            isFromYoutube: true,
          ));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static const int _kMaxBrowseTracks = 15;

  static Future<List<BrowseTrack>> _ytTracksFor(String query, [yt.YoutubeExplode? sharedClient]) async {
    final ytClient = sharedClient ?? yt.YoutubeExplode();
    try {
      final results = await ytClient.search.search(query)
          .then((list) => list.toList())
          .timeout(const Duration(seconds: 8), onTimeout: () => <yt.Video>[]);

      final accepted = <yt.Video>[];
      final acceptedTitles = <String>[];
      for (final v in results) {
        if (accepted.length >= _kMaxBrowseTracks) break;
        if (!_isBrowseQuality(v)) continue;
        var isDup = false;
        for (final seen in acceptedTitles) {
          if (RecommendationEngine.isSameSongSmart(v.title, seen)) { isDup = true; break; }
        }
        if (isDup) continue;
        acceptedTitles.add(v.title);
        accepted.add(v);
      }
      if (accepted.isEmpty) {
        final acceptedFallback = <String>[];
        for (final v in results) {
          if (accepted.length >= _kMaxBrowseTracks) break;
          var isDup = false;
          for (final seen in acceptedFallback) {
            if (RecommendationEngine.isSameSongSmart(v.title, seen)) { isDup = true; break; }
          }
          if (isDup) continue;
          acceptedFallback.add(v.title);
          accepted.add(v);
        }
      }

      return accepted.map((v) {
        final thumb = _bestYtThumbnail(v.thumbnails);
        return BrowseTrack(
          trackId: v.id.value,
          title: _clean(v.title),
          artist: _clean(v.author),
          album: '',
          artworkUrl: thumb,
          durationMs: v.duration?.inMilliseconds,
          isFromYoutube: true,
        );
      }).toList();
    } catch (_) {
      return [];
    } finally {
      if (sharedClient == null) ytClient.close();
    }
  }

  static Future<String> _ytThumbnailFor(String query) async {
    try {
      final uri = Uri.parse('https://www.youtube.com/results')
          .replace(queryParameters: {'search_query': query});
      final res = await _client
          .get(uri, headers: {'User-Agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final match = RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"').firstMatch(res.body);
        if (match != null) {
          return 'https://i.ytimg.com/vi/${match.group(1)}/hqdefault.jpg';
        }
      }
    } catch (_) {}
    return '';
  }

  static const _labelBlacklist = {
    't-series', 'tips official', 'tips', 'zee music company', 'zee music',
    'sony music', 'sony music entertainment', 'saregama', 'venus',
    'venus music', 'eros now music', 'speed records', 'white hill music',
    'desi music factory', 'jjust music', 'times music', 'universal music',
    '90\'s gaane', 'bollywood hits', 'filmi gaane', 'various artists',
    'unknown', 'unknown artist',
  };

  static bool _isRealArtist(String name) {
    final lower = name.toLowerCase().trim();
    if (lower.isEmpty) return false;
    if (_labelBlacklist.contains(lower)) return false;
    if (lower.contains('music company') || lower.contains('records')) return false;
    return true;
  }

  static final RegExp _albumTitleNoise = RegExp(
    r'\b(full\s*(video)?\s*song|official\s*(video|audio|music\s*video)?|'
    r'lyrical\s*video?|lyric\s*video?|audio\s*(song)?|video\s*song|'
    r'hd|4k|new|latest|title\s*track)\b',
    caseSensitive: false,
  );

  static String _albumSearchQuery(String rawTitle, String collectionId) {
    final parts = rawTitle.split(RegExp(r'[|]'));
    String candidate = parts.length > 1 ? parts.last : rawTitle;
    candidate = candidate.replaceAll(_albumTitleNoise, ' ');
    candidate = candidate
        .replaceAll(RegExp(r'[\-_()\[\]:]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (candidate.length < 3) {
      candidate = collectionId;
    }
    return '$candidate songs';
  }

  static Future<List<BrowseTrack>> albumTracks(
    String collectionId, {
    bool isFromYoutube = true,
    String? albumTitle,
  }) async {
    final query = (albumTitle != null && albumTitle.isNotEmpty)
        ? _albumSearchQuery(albumTitle, collectionId)
        : '$collectionId songs';
    final tracks = await _ytTracksFor(query);
    if (tracks.length <= 1 && collectionId.isNotEmpty) {
      final channelTracks = await _ytTracksFor('$collectionId songs');
      if (channelTracks.length > tracks.length) return channelTracks;
    }
    return tracks;
  }

  static Future<List<BrowseTrack>> artistTopSongs(
    String artistName, {
    bool isFromYoutube = true,
    String? channelId,
  }) async {
    if (channelId != null && channelId.isNotEmpty) {
      try {
        final uri = Uri.parse(
          '$_ytWorkerBase/api/yt-artist?id=${Uri.encodeComponent(channelId)}&limit=200',
        );
        final resp = await _client.get(uri).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data['success'] == true) {
            final results = (data['data']?['results'] as List?) ?? [];
            final rawArtistName = data['artistName'];
            final resolvedArtistName = rawArtistName is String ? rawArtistName.trim() : null;
            final tracks = results
                .whereType<Map<String, dynamic>>()
                .map((r) {
                  final rawArtist = _clean((r['artist'] ?? '').toString());
                  return BrowseTrack(
                    trackId: (r['videoId'] ?? '').toString(),
                    title: _clean((r['title'] ?? '').toString()),
                    artist: rawArtist.isNotEmpty
                        ? rawArtist
                        : (resolvedArtistName?.isNotEmpty == true ? resolvedArtistName! : artistName),
                    album: _clean((r['album'] ?? '').toString()),
                    artworkUrl: (r['image'] ?? '').toString(),
                    durationMs: r['duration'] is int ? (r['duration'] as int) * 1000 : null,
                    isFromYoutube: true,
                  );
                })
                .where((t) => t.trackId.isNotEmpty && t.title.isNotEmpty)
                .toList();
            if (tracks.isNotEmpty) return tracks;
          }
        }
      } catch (_) {
      }
    }
    return _ytTracksFor('$artistName top songs');
  }

  static void dispose() => _client.close();
}

class BrowseSearchResult {
  final List<BrowseTrack>  tracks;
  final List<BrowseAlbum>  albums;
  final List<BrowseArtist> artists;
  final BrowseAlbum? topAlbum;
  final List<BrowseTrack> topAlbumTracks;

  const BrowseSearchResult({
    required this.tracks,
    required this.albums,
    required this.artists,
    this.topAlbum,
    this.topAlbumTracks = const [],
  });

  factory BrowseSearchResult.empty() => const BrowseSearchResult(
    tracks: [], albums: [], artists: [],
  );

  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty;
}
