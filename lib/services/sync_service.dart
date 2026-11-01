// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/song.dart';
import '../providers/playlist_provider.dart';
import '../providers/followed_artists_provider.dart';
import '../providers/followed_albums_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/recently_played_provider.dart';

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _uid => _client.auth.currentUser?.id;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  bool get _canSync => _uid != null;

  Future<void> pushPlaylist(AurumPlaylist pl) async {
    if (!_canSync) return;
    try {
      await _client.from('playlists').upsert({
        'id': pl.id,
        'user_id': _uid,
        'data': pl.toJson(),
        'updated_at': pl.updatedAt.toUtc().toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] pushPlaylist error: $e');
    }
  }

  Future<void> pushPlaylistDeleted(String playlistId) async {
    if (!_canSync) return;
    final uid = _uid!;
    try {
      await _client
          .from('playlists')
          .delete()
          .eq('id', playlistId)
          .eq('user_id', uid);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] pushPlaylistDeleted error: $e');
    }
  }

  Future<void> pushFollowedArtist(Map<String, dynamic> artist) async {
    if (!_canSync) return;
    try {
      await _client.from('followed_artists').upsert({
        'artist_id': artist['id'],
        'user_id': _uid,
        'data': artist,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] pushFollowedArtist error: $e');
    }
  }

  Future<void> pushUnfollowedArtist(String artistId) async {
    if (!_canSync) return;
    final uid = _uid!;
    try {
      await _client
          .from('followed_artists')
          .delete()
          .eq('artist_id', artistId)
          .eq('user_id', uid);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] pushUnfollowedArtist error: $e');
    }
  }

  Future<void> pushFollowedAlbum(Map<String, dynamic> album) async {
    if (!_canSync) return;
    try {
      await _client.from('followed_albums').upsert({
        'album_id': album['id'],
        'user_id': _uid,
        'data': album,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] pushFollowedAlbum error: $e');
    }
  }

  Future<void> pushUnfollowedAlbum(String albumId) async {
    if (!_canSync) return;
    final uid = _uid!;
    try {
      await _client
          .from('followed_albums')
          .delete()
          .eq('album_id', albumId)
          .eq('user_id', uid);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] pushUnfollowedAlbum error: $e');
    }
  }

  Future<void> pushFavorite(Song song) async {
    if (!_canSync) return;
    try {
      await _client.from('favorites').upsert({
        'song_id': song.id,
        'user_id': _uid,
        'data': song.toJson(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] pushFavorite error: $e');
    }
  }

  Future<void> pushUnfavorite(String songId) async {
    if (!_canSync) return;
    final uid = _uid!;
    try {
      await _client
          .from('favorites')
          .delete()
          .eq('song_id', songId)
          .eq('user_id', uid);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] pushUnfavorite error: $e');
    }
  }

  Future<void> pushHistoryEntry(Song song, int playedAtMs) async {
    if (!_canSync) return;
    try {
      await _client.from('history').upsert({
        'song_id': song.id,
        'user_id': _uid,
        'data': song.toJson(),
        'played_at': DateTime.fromMillisecondsSinceEpoch(playedAtMs)
            .toUtc()
            .toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] pushHistoryEntry error: $e');
    }
  }

  Future<void> clearRemoteHistory() async {
    if (!_canSync) return;
    final uid = _uid!;
    try {
      await _client.from('history').delete().eq('user_id', uid);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] clearRemoteHistory error: $e');
    }
  }

  Future<void> syncAll({
    required PlaylistProvider playlists,
    required FollowedArtistsProvider followedArtists,
    required FollowedAlbumsProvider followedAlbums,
    required FavoritesProvider favorites,
    RecentlyPlayedProvider? history,
  }) async {
    final uid = _uid;
    if (uid == null || _isSyncing) return;
    _isSyncing = true;
    try {
      await Future.wait([
        _syncPlaylists(uid, playlists),
        _syncFollowedArtists(uid, followedArtists),
        _syncFollowedAlbums(uid, followedAlbums),
        _syncFavorites(uid, favorites),
        if (history != null) _syncHistory(uid, history),
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncService] syncAll error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncPlaylists(String uid, PlaylistProvider provider) async {
    final remoteRows =
        await _client.from('playlists').select().eq('user_id', uid);

    final localById = {for (final p in provider.playlists) p.id: p};

    DateTime stampOf(Map<String, dynamic> row, Map<String, dynamic> data) {
      final inner = data['updatedAt'];
      if (inner is String) {
        final t = DateTime.tryParse(inner);
        if (t != null) return t;
      }
      return DateTime.parse(row['updated_at'] as String);
    }

    final toPull = <AurumPlaylist>[];
    final remoteStamp = <String, DateTime>{};
    for (final row in remoteRows) {
      try {
        final id = row['id'] as String;
        final data = Map<String, dynamic>.from(row['data'] as Map);
        final remoteUpdatedAt = stampOf(row, data);
        remoteStamp[id] = remoteUpdatedAt;
        final local = localById[id];
        if (local == null || remoteUpdatedAt.isAfter(local.updatedAt)) {
          toPull.add(AurumPlaylist.fromJson(data));
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[SyncService] bad playlist row skipped: $e');
      }
    }
    if (toPull.isNotEmpty) {
      await provider.upsertManyFromRemote(toPull);
    }
    final pulledIds = {for (final p in toPull) p.id};

    for (final local in provider.playlists) {
      if (pulledIds.contains(local.id)) continue;
      final remoteUpdatedAt = remoteStamp[local.id];
      if (remoteUpdatedAt == null || local.updatedAt.isAfter(remoteUpdatedAt)) {
        await _client.from('playlists').upsert({
          'id': local.id,
          'user_id': uid,
          'data': local.toJson(),
          'updated_at': local.updatedAt.toUtc().toIso8601String(),
        });
      }
    }
  }

  Future<void> _syncFollowedArtists(
      String uid, FollowedArtistsProvider provider) async {
    final remoteRows =
        await _client.from('followed_artists').select().eq('user_id', uid);

    final remoteIds = <String>{};
    for (final row in remoteRows) {
      final data = Map<String, dynamic>.from(row['data'] as Map);
      remoteIds.add(row['artist_id'] as String);
      if (!provider.isFollowing(data['id'] as String)) {
        await provider.followFromRemote(
          artistId: data['id'] as String,
          name: data['name'] as String? ?? '',
          imageUrl: data['imageUrl'] as String? ?? '',
        );
      }
    }

    for (final artist in provider.followed) {
      final id = artist['id'] as String;
      if (!remoteIds.contains(id)) {
        await _client.from('followed_artists').upsert({
          'artist_id': id,
          'user_id': uid,
          'data': artist,
        });
      }
    }
  }

  Future<void> _syncFollowedAlbums(
      String uid, FollowedAlbumsProvider provider) async {
    final remoteRows =
        await _client.from('followed_albums').select().eq('user_id', uid);

    final remoteIds = <String>{};
    for (final row in remoteRows) {
      final data = Map<String, dynamic>.from(row['data'] as Map);
      remoteIds.add(row['album_id'] as String);
      if (!provider.isFollowing(data['id'] as String)) {
        await provider.followFromRemote(
          albumId: data['id'] as String,
          name: data['name'] as String? ?? '',
          artworkUrl: data['artworkUrl'] as String? ?? '',
        );
      }
    }

    for (final album in provider.followed) {
      final id = album['id'] as String;
      if (!remoteIds.contains(id)) {
        await _client.from('followed_albums').upsert({
          'album_id': id,
          'user_id': uid,
          'data': album,
        });
      }
    }
  }

  Future<void> _syncFavorites(String uid, FavoritesProvider provider) async {
    final remoteRows =
        await _client.from('favorites').select().eq('user_id', uid);

    final remoteIds = <String>{};
    for (final row in remoteRows) {
      final data = Map<String, dynamic>.from(row['data'] as Map);
      final songId = row['song_id'] as String;
      remoteIds.add(songId);
      if (!provider.isFavorite(songId)) {
        await provider.addFromRemote(data);
      }
    }

    for (final song in provider.favorites) {
      if (!remoteIds.contains(song.id)) {
        await _client.from('favorites').upsert({
          'song_id': song.id,
          'user_id': uid,
          'data': song.toJson(),
        });
      }
    }
  }

  Future<void> _syncHistory(String uid, RecentlyPlayedProvider provider) async {
    final remoteRows =
        await _client.from('history').select().eq('user_id', uid);

    final remoteById = <String, Map<String, dynamic>>{
      for (final row in remoteRows) row['song_id'] as String: row,
    };

    for (final row in remoteRows) {
      final data = Map<String, dynamic>.from(row['data'] as Map);
      final playedAt = DateTime.parse(row['played_at'] as String);
      await provider.upsertFromRemote(
        Song.fromJson(data),
        playedAt.millisecondsSinceEpoch,
      );
    }

    for (final song in provider.history) {
      final localPlayedAt = provider.playedAtFor(song.id);
      if (localPlayedAt == null) continue;
      final remote = remoteById[song.id];
      final remotePlayedAt = remote != null
          ? DateTime.parse(remote['played_at'] as String).millisecondsSinceEpoch
          : null;
      if (remotePlayedAt == null || localPlayedAt > remotePlayedAt) {
        await pushHistoryEntry(song, localPlayedAt);
      }
    }
  }
}
