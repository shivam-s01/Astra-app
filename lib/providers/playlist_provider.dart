// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import '../services/analytics_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song.dart';
import '../services/sync_service.dart';
import '../services/api_service.dart';

class AurumPlaylist {
  final String id;
  String name;
  String description;
  List<Song> songs;
  final DateTime createdAt;
  DateTime updatedAt;
  String? customCoverPath;

  int sortOrder;

  List<String> tags;

  bool isYtSynced;

  bool isPinned;
  DateTime? pinnedAt;

  AurumPlaylist({
    required this.id,
    required this.name,
    this.description = '',
    List<Song>? songs,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.customCoverPath,
    this.sortOrder = 0,
    List<String>? tags,
    this.isYtSynced = false,
    this.isPinned = false,
    this.pinnedAt,
  })  : songs = songs ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        tags = tags ?? [];

  int get songCount => songs.length;

  int get totalDurationSeconds =>
      songs.fold(0, (sum, s) => sum + (s.duration ?? 0));

  String get totalDurationString {
    final secs = totalDurationSeconds;
    if (secs == 0) return '';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m} min';
  }

  bool get hasCustomCover =>
      customCoverPath != null && customCoverPath!.isNotEmpty;

  String? get coverArt {
    if (hasCustomCover) return customCoverPath;
    return songs.isNotEmpty ? songs.first.artworkUrl : null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'songs': songs.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'customCoverPath': customCoverPath,
        'sortOrder': sortOrder,
        'tags': tags,
        'isYtSynced': isYtSynced,
        'isPinned': isPinned,
        'pinnedAt': pinnedAt?.toUtc().toIso8601String(),
      };

  factory AurumPlaylist.fromJson(Map<String, dynamic> json) {
    return AurumPlaylist(
      id: json['id'] as String,
      name: json['name'] as String,
      description: (json['description'] as String?) ?? '',
      songs: (json['songs'] as List<dynamic>? ?? [])
          .map((e) => Song.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      customCoverPath: json['customCoverPath'] as String?,
      sortOrder: (json['sortOrder'] as int?) ?? 0,
      tags: (json['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      isYtSynced: (json['isYtSynced'] as bool?) ?? false,
      isPinned: (json['isPinned'] as bool?) ?? false,
      pinnedAt: json['pinnedAt'] is String
          ? DateTime.tryParse(json['pinnedAt'] as String)
          : null,
    );
  }
}

class PlaylistProvider extends ChangeNotifier {
  static const _boxName = 'aurum_playlists';
  final Completer<Box<Map>> _boxReady = Completer<Box<Map>>();
  Box<Map>? _box;
  List<AurumPlaylist> _playlists = [];
  bool _isLoading = true;

  List<AurumPlaylist> get playlists => List.unmodifiable(_playlists);
  bool get isLoading => _isLoading;
  int get count => _playlists.length;

  Future<void> init() async {
    if (_boxReady.isCompleted) return;
    final box = await Hive.openBox<Map>(_boxName);
    _box = box;
    _boxReady.complete(box);
    _playlists = box.values
        .map((m) => AurumPlaylist.fromJson(Map<String, dynamic>.from(m)))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _isLoading = false;
    notifyListeners();
  }

  Future<AurumPlaylist> createPlaylist({
    required String name,
    String description = '',
    Song? initialSong,
  }) async {
    final playlist = AurumPlaylist(
      id: _generateId(),
      name: name.trim().isEmpty ? 'My Playlist' : name.trim(),
      description: description.trim(),
      songs: initialSong != null ? [initialSong] : [],
      sortOrder: _nextSortOrder(),
    );
    _playlists.insert(0, playlist);
    await _persist(playlist);
    AnalyticsService.instance.logPlaylistCreate(playlist.name);
    notifyListeners();
    return playlist;
  }

  Future<void> renamePlaylist(String id, String newName,
      {String? newDescription}) async {
    final pl = _findById(id);
    if (pl == null) return;
    pl.name = newName.trim().isEmpty ? pl.name : newName.trim();
    if (newDescription != null) pl.description = newDescription.trim();
    pl.updatedAt = DateTime.now();
    await _persist(pl);
    _sortByUpdated();
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    final pl = _findById(id);
    if (pl != null && pl.hasCustomCover) {
      final coverFile = File(pl.customCoverPath!);
      if (await coverFile.exists()) {
        try {
          await coverFile.delete();
        } catch (_) {
        }
      }
    }
    _playlists.removeWhere((p) => p.id == id);
    final box = _box ?? await _boxReady.future;
    await box.delete(id);
    unawaited(SyncService.instance.pushPlaylistDeleted(id));
    notifyListeners();
  }

  Future<bool> addSong(String playlistId, Song song) async {
    final pl = _findById(playlistId);
    if (pl == null) return false;
    if (pl.songs.any((s) => s.id == song.id)) return false;
    pl.songs.add(song);
    AnalyticsService.instance.logPlaylistAdd(song);
    pl.updatedAt = DateTime.now();
    await _persist(pl);
    _sortByUpdated();
    notifyListeners();
    return true;
  }

  Future<void> removeSong(String playlistId, String songId) async {
    final pl = _findById(playlistId);
    if (pl == null) return;
    pl.songs.removeWhere((s) => s.id == songId);
    pl.updatedAt = DateTime.now();
    await _persist(pl);
    notifyListeners();
  }

  Future<void> removeSongs(String playlistId, Set<String> songIds) async {
    if (songIds.isEmpty) return;
    final pl = _findById(playlistId);
    if (pl == null) return;
    pl.songs.removeWhere((s) => songIds.contains(s.id));
    pl.updatedAt = DateTime.now();
    await _persist(pl);
    notifyListeners();
  }

  Future<void> reorderSong(
      String playlistId, int oldIndex, int newIndex) async {
    final pl = _findById(playlistId);
    if (pl == null) return;
    if (oldIndex < newIndex) newIndex -= 1;
    final song = pl.songs.removeAt(oldIndex);
    pl.songs.insert(newIndex, song);
    pl.updatedAt = DateTime.now();
    unawaited(_persist(pl));
    notifyListeners();
  }

  Future<void> reorderPlaylist(int oldIndex, int newIndex) async {
    final all = customOrdered();
    final pinnedCount = all.where((p) => p.isPinned).length;
    if (oldIndex < pinnedCount || oldIndex >= all.length) return;
    final ordered = all.sublist(pinnedCount);
    final from = oldIndex - pinnedCount;
    var to = newIndex - pinnedCount;
    if (to < 0) to = 0;
    if (from < to) to -= 1;
    if (to >= ordered.length) to = ordered.length - 1;
    if (to < 0) return;
    final moved = ordered.removeAt(from);
    ordered.insert(to, moved);
    final now = DateTime.now();
    final changed = <AurumPlaylist>[];
    for (var i = 0; i < ordered.length; i++) {
      if (ordered[i].sortOrder != i) {
        ordered[i].sortOrder = i;
        ordered[i].updatedAt = now;
        changed.add(ordered[i]);
      }
    }
    notifyListeners();
    for (final pl in changed) {
      unawaited(Future(() => _persist(pl)));
    }
  }

  List<AurumPlaylist> customOrdered() {
    final list = List<AurumPlaylist>.from(_playlists);
    list.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      final d = b.createdAt.compareTo(a.createdAt);
      if (d != 0) return d;
      return a.id.compareTo(b.id);
    });
    return pinnedFirst(list);
  }

  static List<AurumPlaylist> pinnedFirst(List<AurumPlaylist> input) {
    final pinned = input.where((p) => p.isPinned).toList()
      ..sort((a, b) => (b.pinnedAt ?? b.createdAt)
          .compareTo(a.pinnedAt ?? a.createdAt));
    if (pinned.isEmpty) return List<AurumPlaylist>.from(input);
    final rest = input.where((p) => !p.isPinned);
    return [...pinned, ...rest];
  }

  List<AurumPlaylist> get pinnedPlaylists =>
      pinnedFirst(_playlists).where((p) => p.isPinned).toList();

  Future<void> setPinned(String playlistId, bool pinned) async {
    final pl = _findById(playlistId);
    if (pl == null || pl.isPinned == pinned) return;
    pl.isPinned = pinned;
    pl.pinnedAt = pinned ? DateTime.now() : null;
    pl.updatedAt = DateTime.now();
    notifyListeners();
    unawaited(Future(() => _persist(pl)));
  }

  Future<PinResult> pinByName(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const PinResult(PinStatus.notFound);
    AurumPlaylist? target;
    for (final p in _playlists) {
      if (p.name.trim().toLowerCase() == q) {
        target = p;
        break;
      }
    }
    if (target == null) {
      final partial =
          _playlists.where((p) => p.name.toLowerCase().contains(q)).toList();
      if (partial.isEmpty) return const PinResult(PinStatus.notFound);
      if (partial.length > 1) return const PinResult(PinStatus.ambiguous);
      target = partial.first;
    }
    if (target.isPinned) return PinResult(PinStatus.alreadyPinned, target);
    await setPinned(target.id, true);
    return PinResult(PinStatus.pinned, target);
  }

  int _nextSortOrder() => _playlists.isEmpty
      ? 0
      : (_playlists.map((p) => p.sortOrder).reduce((a, b) => a > b ? a : b) + 1);

  List<String> get allTags {
    final set = <String>{};
    for (final pl in _playlists) {
      set.addAll(pl.tags);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> setTags(String playlistId, List<String> newTags) async {
    final pl = _findById(playlistId);
    if (pl == null) return;
    pl.tags = newTags.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().toList();
    pl.updatedAt = DateTime.now();
    unawaited(_persist(pl));
    notifyListeners();
  }

  Future<void> renameTagEverywhere(String oldTag, String newTag) async {
    final trimmed = newTag.trim();
    if (trimmed.isEmpty) return;
    var changed = false;
    for (final pl in _playlists) {
      final idx = pl.tags.indexOf(oldTag);
      if (idx != -1) {
        pl.tags[idx] = trimmed;
        pl.tags = pl.tags.toSet().toList();
        pl.updatedAt = DateTime.now();
        unawaited(_persistLocalOnly(pl));
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> deleteTagEverywhere(String tag) async {
    var changed = false;
    for (final pl in _playlists) {
      if (pl.tags.remove(tag)) {
        pl.updatedAt = DateTime.now();
        unawaited(_persistLocalOnly(pl));
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  List<AurumPlaylist> byTag(String tag) =>
      customOrdered().where((p) => p.tags.contains(tag)).toList();

  Future<void> setCoverImage(String playlistId, String pickedFilePath) async {
    final pl = _findById(playlistId);
    if (pl == null) return;

    final docsDir = await getApplicationDocumentsDirectory();
    final coversDir = Directory('${docsDir.path}/playlist_covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    if (pl.hasCustomCover) {
      final oldFile = File(pl.customCoverPath!);
      if (await oldFile.exists()) {
        try {
          await oldFile.delete();
        } catch (_) {
        }
      }
    }

    final ext = pickedFilePath.split('.').last;
    final destPath =
        '${coversDir.path}/${pl.id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File(pickedFilePath).copy(destPath);

    pl.customCoverPath = destPath;
    pl.updatedAt = DateTime.now();
    unawaited(_persist(pl));
    _sortByUpdated();
    notifyListeners();
  }

  Future<void> clearCoverImage(String playlistId) async {
    final pl = _findById(playlistId);
    if (pl == null || !pl.hasCustomCover) return;

    final oldFile = File(pl.customCoverPath!);
    if (await oldFile.exists()) {
      try {
        await oldFile.delete();
      } catch (_) {
      }
    }

    pl.customCoverPath = null;
    pl.updatedAt = DateTime.now();
    unawaited(_persist(pl));
    notifyListeners();
  }

  Future<AurumPlaylist?> importYtPlaylist(String playlistUrlOrId,
      {String? name}) async {
    final songs = await ApiService.fetchYtPlaylistSongs(playlistUrlOrId);
    if (songs.isEmpty) return null;

    final playlist = AurumPlaylist(
      id: _generateId(),
      name: (name == null || name.trim().isEmpty)
          ? 'Imported Playlist'
          : name.trim(),
      songs: songs,
      sortOrder: _nextSortOrder(),
      isYtSynced: true,
    );
    _playlists.insert(0, playlist);
    await _persist(playlist);
    notifyListeners();
    return playlist;
  }

  Future<AurumPlaylist> addImportedPlaylist({
    required String name,
    required List<Song> songs,
    bool youtubeSynced = false,
  }) async {
    final seen = <String>{};
    final unique = <Song>[];
    for (final s in songs) {
      if (s.id.isNotEmpty && seen.add(s.id)) unique.add(s);
    }
    final playlist = AurumPlaylist(
      id: _generateId(),
      name: name.trim().isEmpty ? 'Imported Playlist' : name.trim(),
      songs: unique,
      sortOrder: _nextSortOrder(),
      isYtSynced: youtubeSynced,
    );
    _playlists.insert(0, playlist);
    await _persist(playlist);
    AnalyticsService.instance.logPlaylistCreate(playlist.name);
    notifyListeners();
    return playlist;
  }

  AurumPlaylist? getById(String id) => _findById(id);

  bool isSongInPlaylist(String playlistId, String songId) {
    final pl = _findById(playlistId);
    return pl?.songs.any((s) => s.id == songId) ?? false;
  }

  List<String> playlistsContaining(String songId) => _playlists
      .where((p) => p.songs.any((s) => s.id == songId))
      .map((p) => p.id)
      .toList();

  AurumPlaylist? _findById(String id) {
    try {
      return _playlists.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistLocalOnly(AurumPlaylist pl) async {
    final box = _box ?? await _boxReady.future;
    await box.put(pl.id, pl.toJson());
  }

  Future<void> _persist(AurumPlaylist pl) async {
    await _persistLocalOnly(pl);
    unawaited(SyncService.instance.pushPlaylist(pl));
  }

  void _sortByUpdated() {
    _playlists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> upsertFromRemote(AurumPlaylist pl) async {
    final existing = _findById(pl.id);
    if (existing != null) _playlists.remove(existing);
    _playlists.add(pl);
    _sortByUpdated();
    await _persistLocalOnly(pl);
    notifyListeners();
  }

  Future<void> upsertManyFromRemote(List<AurumPlaylist> incoming) async {
    if (incoming.isEmpty) return;
    for (final pl in incoming) {
      final existing = _findById(pl.id);
      if (existing != null) _playlists.remove(existing);
      _playlists.add(pl);
    }
    _sortByUpdated();
    final box = _box ?? await _boxReady.future;
    await box.putAll({for (final pl in incoming) pl.id: pl.toJson()});
    notifyListeners();
  }

  String _generateId() =>
      'pl_${DateTime.now().millisecondsSinceEpoch}_${_playlists.length}';

  Future<void> clearAll() async {
    final box = _box ?? await _boxReady.future;
    await box.clear();
    _playlists = [];
    notifyListeners();
  }
}

enum PinStatus { pinned, alreadyPinned, notFound, ambiguous }

class PinResult {
  final PinStatus status;
  final AurumPlaylist? playlist;
  const PinResult(this.status, [this.playlist]);
}
