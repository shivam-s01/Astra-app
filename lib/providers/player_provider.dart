// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;
import 'package:just_audio/just_audio.dart' show LoopMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song.dart';
import '../models/lyrics.dart';
import '../services/native_engine_bridge.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/audio_prefs.dart';
import '../services/recommendation_engine.dart';
import '../utils/artwork_palette_cache.dart';
import 'recently_played_provider.dart';
import 'favorites_provider.dart';

class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final NativeAudioEngine        _engine;
  final RecentlyPlayedProvider? _recentlyPlayed;
  FavoritesProvider? _favorites;

  bool immersiveLyricsWasOpen = false;

  void updateFavorites(FavoritesProvider favorites) {
    if (identical(_favorites, favorites)) return;
    _favoritesSub?.cancel();
    _favorites = favorites;

    _isSongLikedLookup = (song) => favorites.isFavorite(song.id);
    _onLikeToggleRequested = (song) => favorites.toggleFavorite(song);

    _favoritesSub = _FavoritesListener(favorites, () {
      final song = currentSong;
      if (song != null) {
        _engine.setCurrentSongLiked(favorites.isFavorite(song.id));
      }
    });

    final song = currentSong;
    if (song != null) {
      _engine.setCurrentSongLiked(favorites.isFavorite(song.id));
    }
  }

  bool Function(Song song)? _isSongLikedLookup;
  Future<void> Function(Song song)? _onLikeToggleRequested;

  _FavoritesListener? _favoritesSub;

  NativeAudioEngine get handler => _engine;
  NativeAudioEngine get engine => _engine;

  bool     _isPlaying      = false;
  bool     _isLoading      = false;
  bool     _resolveTakingLong = false;
  Duration _position       = Duration.zero;
  Duration _duration       = Duration.zero;
  Duration _buffered       = Duration.zero;
  LoopMode _loopMode       = LoopMode.off;
  bool     _shuffle        = false;
  bool     _showFullPlayer = false;

  Timer? _localPositionTicker;

  Duration? _justSeekedFromPosition;
  Duration? _justSeekedToPosition;
  DateTime? _justSeekedAt;
  static const _seekGuardWindow = Duration(milliseconds: 900);

  Timer? _loadingWatchdog;
  bool _refreshRequestedForCurrentStuck = false;

  void _startLoadingWatchdog() {
    if (!_isAppInForeground) return;
    _loadingWatchdog ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_isLoading) {
        _refreshRequestedForCurrentStuck = false;
        return;
      }
      final setAt = _expectedSongIdSetAt;
      if (setAt == null) return;
      final stuckFor = DateTime.now().difference(setAt);
      if (stuckFor > const Duration(seconds: 6) && !_refreshRequestedForCurrentStuck) {
        _refreshRequestedForCurrentStuck = true;
        _engine.refreshState();
      }
      if (stuckFor > const Duration(seconds: 10)) {
        _isLoading = false;
        _expectedSongId = null;
        _expectedSongIdSetAt = null;
        _refreshRequestedForCurrentStuck = false;
        notifyListeners();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _engine.refreshState();
      _isAppInForeground = true;
      if (_isPlaying) _startLocalPositionTicker();
      if (_isLoading) _startLoadingWatchdog();
      return;
    }
    _isAppInForeground = false;
    _stopLocalPositionTicker();
    _loadingWatchdog?.cancel();
    _loadingWatchdog = null;
  }

  bool _isAppInForeground = true;

  void _startLocalPositionTicker() {
    if (!_isAppInForeground) return;
    if (_localPositionTicker?.isActive == true) return;
    _localPositionTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_isPlaying) return;
      final next = _position + const Duration(milliseconds: 500);
      _position = (_duration > Duration.zero && next > _duration) ? _duration : next;
      notifyListeners();
    });
  }

  void _stopLocalPositionTicker() {
    _localPositionTicker?.cancel();
    _localPositionTicker = null;
  }

  bool _isBuildingInitialQueue = false;
  bool get isBuildingQueue => _isBuildingInitialQueue;
  bool _isAutoExtendingQueue = false;
  Timer? _indexDebounce;
  int?   _lastHandledIndex;

  Timer? _skipDebounce;
  int? _skipDebounceTargetIndex;
  static const Duration _skipDebounceWindow = Duration(milliseconds: 60);

  List<Song> _queue = [];
  int _currentIndex = 0;
  Song? _currentSong;

  Song? _interruptedByNetworkSong;
  Duration _interruptedByNetworkPosition = Duration.zero;

  void markInterruptedByNetworkLoss() {
    if (_currentSong == null || (_currentSong?.isLocal ?? true)) return;
    _interruptedByNetworkSong = _currentSong;
    _interruptedByNetworkPosition = _position;
  }

  Future<void> resumeAfterReconnect() async {
    final song = _interruptedByNetworkSong;
    if (song == null) return;
    final pos = _interruptedByNetworkPosition;
    _interruptedByNetworkSong = null;
    _interruptedByNetworkPosition = Duration.zero;
    try {
      await playSong(song, queue: _queue.isNotEmpty ? _queue : null,
          index: _queue.isNotEmpty ? _currentIndex : null);
      if (pos > Duration.zero) {
        await seekTo(pos);
      }
    } catch (e) {
      debugPrint('[Aurum] resumeAfterReconnect failed: $e');
    }
  }

  int _uiPlaySession = 0;

  String? _expectedSongId;
  DateTime? _expectedSongIdSetAt;
  static const Duration _expectedSongIdTimeout = Duration(seconds: 3);

  DateTime? _dismissedUntil;
  static const Duration _dismissSuppressWindow = Duration(milliseconds: 700);

  String? _playbackError;
  String? get playbackError => _playbackError;
  Song? _lastFailedSong;
  Song? get lastFailedSong => _lastFailedSong;
  void clearPlaybackError() {
    _playbackError = null;
    _lastFailedSong = null;
    notifyListeners();
  }

  String? _lastPlaybackError;
  String? get lastPlaybackError => _lastPlaybackError;

  void Function(String error, {bool silent})? onPlaybackError;

  void Function()? onResolveTakingLong;

  static const int _kFreeSkipLimit = 6;
  static const Duration _kSkipWindow = Duration(hours: 1);
  static const String _kSkipsUsedPrefKey = 'free_skip_count';
  static const String _kSkipWindowStartPrefKey = 'free_skip_window_start_ms';

  int _skipsUsed = 0;
  DateTime _skipWindowStart = DateTime.now();
  bool _skipStatePersistLoaded = false;

  Future<void> _loadPersistedSkipState() async {
    if (_skipStatePersistLoaded) return;
    _skipStatePersistLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final storedCount = p.getInt(_kSkipsUsedPrefKey);
      final storedWindowStartMs = p.getInt(_kSkipWindowStartPrefKey);
      if (storedCount != null && storedWindowStartMs != null) {
        _skipsUsed = _skipsUsed > 0 ? (_skipsUsed + storedCount) : storedCount;
        _skipWindowStart = DateTime.fromMillisecondsSinceEpoch(storedWindowStartMs);
        _resetWindowIfExpired();
        _persistSkipState();
        notifyListeners();
      }
    } catch (_) {
    }
  }

  Future<void> _persistSkipState() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kSkipsUsedPrefKey, _skipsUsed);
      await p.setInt(_kSkipWindowStartPrefKey, _skipWindowStart.millisecondsSinceEpoch);
    } catch (_) {
    }
  }

  int? get freeSkipsRemaining {
    if (AudioPrefs.isSignedIn) return null;
    _resetWindowIfExpired();
    return (_kFreeSkipLimit - _skipsUsed).clamp(0, _kFreeSkipLimit);
  }

  bool get skipLimitReached {
    if (AudioPrefs.isSignedIn) return false;
    _resetWindowIfExpired();
    return _skipsUsed >= _kFreeSkipLimit;
  }

  void _resetWindowIfExpired() {
    if (DateTime.now().difference(_skipWindowStart) >= _kSkipWindow) {
      _skipsUsed = 0;
      _skipWindowStart = DateTime.now();
      _persistSkipState();
    }
  }

  void _recordSkip() {
    if (!AudioPrefs.isSignedIn) {
      _resetWindowIfExpired();
      _skipsUsed++;
      _persistSkipState();
      notifyListeners();
    }
  }

  Song?   _lastTrackedSong;
  bool    _completionFired = false;
  bool    _earlySkipArmed  = false;
  int     _listenMaxSec    = 0;
  bool    _replayArmed     = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  PlayerProvider(this._engine, {RecentlyPlayedProvider? recentlyPlayedProvider})
      : _recentlyPlayed = recentlyPlayedProvider {
    _loadPersistedSkipState();

    WidgetsBinding.instance.addObserver(this);

    _subs.add(_engine.errorStream.listen((event) {
      _lastPlaybackError = event.message;
      onPlaybackError?.call(event.message, silent: event.silent);
      notifyListeners();
    }));

    _subs.add(_engine.stateStream.listen(_onEngineState));

    _startLoadingWatchdog();

    _engine.onLikeToggleRequested = (songId) async {
      Song? song;
      for (final s in _queue) {
        if (s.id == songId) { song = s; break; }
      }
      song ??= (_currentSong?.id == songId) ? _currentSong : null;
      if (song == null) return;
      await _onLikeToggleRequested?.call(song);
      final liked = _isSongLikedLookup?.call(song) ?? false;
      await _engine.setCurrentSongLiked(liked);
    };
  }

  void _onEngineState(NativeEngineState state) {
    if (_dismissedUntil != null) {
      if (DateTime.now().isBefore(_dismissedUntil!)) {
        return;
      }
      _dismissedUntil = null;
    }
    if (_expectedSongId != null &&
        _expectedSongIdSetAt != null &&
        DateTime.now().difference(_expectedSongIdSetAt!) > _expectedSongIdTimeout) {
      _expectedSongId = null;
      _expectedSongIdSetAt = null;
    }
    _isPlaying = state.playing;
    if (_isPlaying) {
      _startLocalPositionTicker();
    } else {
      _stopLocalPositionTicker();
    }
    final isStaleForLoading =
        _expectedSongId != null && state.currentSongId != _expectedSongId;
    if (!isStaleForLoading) {
      _isLoading = state.processingState == 'loading' ||
          state.processingState == 'buffering';
    }
    if (!isStaleForLoading) {
      _onPosition(state.position);
      _buffered = state.bufferedPosition;
      if (state.duration != null) _duration = state.duration!;
    }

    if (state.resolveTakingLong && !_resolveTakingLong) {
      onResolveTakingLong?.call();
    }
    _resolveTakingLong = state.resolveTakingLong;

    final isStaleForQueue =
        _expectedSongId != null && !state.queueIds.contains(_expectedSongId);
    if (!isStaleForQueue && !_queueMatchesIds(state.queueIds)) {
      _queue = _reconcileQueue(state.queueIds);
    }

    final newIndex = state.currentIndex ?? _currentIndex;
    Song? resolvedSong;
    if (state.currentSongId != null) {
      for (final s in _queue) {
        if (s.id == state.currentSongId) {
          resolvedSong = s;
          break;
        }
      }
      resolvedSong ??= Song(
        id: state.currentSongId!,
        title: _currentSong?.id == state.currentSongId ? _currentSong!.title : '',
        artist: _currentSong?.id == state.currentSongId ? _currentSong!.artist : '',
        album: '',
        artworkUrl: '',
        source: _currentSong?.id == state.currentSongId
            ? _currentSong!.source
            : SongSource.saavn,
      );
    }
    resolvedSong ??= (state.currentSongId != null &&
            _queue.isNotEmpty &&
            newIndex >= 0 &&
            newIndex < _queue.length)
        ? _queue[newIndex]
        : _currentSong;

    final isConfirmedSwitch =
        _expectedSongId == null || state.currentSongId == _expectedSongId;
    if (!isConfirmedSwitch) {
      notifyListeners();
      return;
    }
    if (_expectedSongId != null && state.currentSongId == _expectedSongId) {
      _expectedSongId = null;
      _expectedSongIdSetAt = null;
    }

    final _prevSongIdForPaletteWarm = _currentSong?.id;
    _currentSong = resolvedSong;
    _currentIndex = newIndex;

    if (_currentSong != null &&
        _currentSong!.id != _prevSongIdForPaletteWarm &&
        _currentSong!.artworkUrl.isNotEmpty) {
      ArtworkPaletteCache.warm(_currentSong!.artworkUrl);
    }

    if (_miniPlayerDismissed) {
      final differentSongStarted =
          _currentSong != null && _currentSong!.id != _miniPlayerDismissedSongId;
      final sameSongResumed = _currentSong != null &&
          _currentSong!.id == _miniPlayerDismissedSongId &&
          state.playing;
      if (differentSongStarted || sameSongResumed) {
        _miniPlayerDismissed = false;
        _miniPlayerDismissedSongId = null;
      }
    }

    if (state.currentIndex != null && state.currentIndex != _lastHandledIndex) {
      _indexDebounce?.cancel();
      final idx = state.currentIndex!;
      final reportedId = state.currentSongId;
      _indexDebounce = Timer(const Duration(milliseconds: 150), () {
        if (idx == _lastHandledIndex) return;
        final q = _queue;
        if (idx < 0 || idx >= q.length) return;
        if (reportedId != null && q[idx].id != reportedId) return;
        if (_currentSong != null && q[idx].id != _currentSong!.id) return;
        _lastHandledIndex = idx;
        _onSongChanged(idx);
        _maybeExtendQueue(idx);
      });
    }

    notifyListeners();
  }

  bool _queueMatchesIds(List<String> ids) {
    if (_queue.length != ids.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (_queue[i].id != ids[i]) return false;
    }
    return true;
  }

  List<Song> _reconcileQueue(List<String> ids) {
    final byId = {for (final s in _queue) s.id: s};
    return ids.map((id) => byId[id]).whereType<Song>().toList();
  }

  void _onSongChanged(int index) {
    final q = _queue;
    if (q.isEmpty || index >= q.length) return;
    final song = q[index];

    final prevTracked = _lastTrackedSong;
    if (prevTracked != null && prevTracked.id != song.id && _listenMaxSec > 0) {
      AnalyticsService.instance.logSongListened(prevTracked, _listenMaxSec);
    }
    _listenMaxSec = 0;

    _lastTrackedSong  = song;
    _completionFired  = false;
    _earlySkipArmed   = song.source != SongSource.local;
    _replayArmed      = false;

    _rp?.addPlay(song);

    final liked = _isSongLikedLookup?.call(song) ?? false;
    _engine.setCurrentSongLiked(liked);

    _prewarmUpcoming(index);
  }

  static const int _prewarmWindow = 5;
  static const int _prewarmWindowDataSaver = 0;

  void _prewarmUpcoming(int fromIndex) {
    final q = _queue;
    if (q.isEmpty) return;
    final window = AudioPrefs.dataSaverActiveNotifier.value
        ? _prewarmWindowDataSaver
        : _prewarmWindow;
    final end = (fromIndex + 1 + window).clamp(0, q.length);
    for (var i = fromIndex + 1; i < end; i++) {
      ApiService.prewarmYtStream(q[i], essential: true);
    }
  }

  void _onPosition(Duration pos) {
    final seekedFrom = _justSeekedFromPosition;
    final seekedTo = _justSeekedToPosition;
    final seekedAt = _justSeekedAt;
    if (seekedFrom != null && seekedTo != null && seekedAt != null) {
      final withinGuardWindow =
          DateTime.now().difference(seekedAt) <= _seekGuardWindow;
      if (withinGuardWindow) {
        final closeToOrigin = (pos - seekedFrom).inMilliseconds.abs() <= 400;
        final farFromTarget = (pos - seekedTo).inMilliseconds.abs() > 400;
        if (closeToOrigin && farFromTarget) {
          return;
        }
      } else {
        _justSeekedFromPosition = null;
        _justSeekedToPosition = null;
        _justSeekedAt = null;
      }
    }

    _position = pos;
    if (pos.inSeconds > _listenMaxSec) _listenMaxSec = pos.inSeconds;

    final song = _lastTrackedSong;
    if (song == null || song.source == SongSource.local) return;

    final posSeconds  = pos.inSeconds;
    final durSeconds  = _duration.inSeconds;

    if (_earlySkipArmed && posSeconds >= 15) {
      _earlySkipArmed = false;
    }

    if (!_completionFired && durSeconds > 10 && posSeconds > 0) {
      final pct = posSeconds / durSeconds;
      if (pct >= 0.80) {
        _completionFired = true;
        _rp?.notifyCompletion(song);
      }
    }

    if (!_replayArmed && durSeconds > 10) {
      if (posSeconds / durSeconds > 0.30) _replayArmed = true;
    }
    if (_replayArmed && posSeconds <= 5) {
      _replayArmed = false;
      _rp?.notifyReplay(song);
    }
  }

  void _fireEarlySkipIfArmed() {
    final song = _lastTrackedSong;
    if (song == null) return;
    if (_earlySkipArmed) {
      _earlySkipArmed = false;
      _rp?.notifySkip(song);
    }
  }

  Future<void> _maybeExtendQueue(int index) async {
    final q = _queue;
    if (q.isEmpty) return;

    final remaining = q.length - 1 - index;
    if (q.length < 2 || remaining > 8 || _isAutoExtendingQueue || _isBuildingInitialQueue) return;
    if (index >= q.length) return;

    _isAutoExtendingQueue = true;
    try {
      final current = q[index];
      Song anchor = current;
      if (anchor.source == SongSource.local) {
        for (int i = index - 1; i >= 0; i--) {
          if (q[i].source != SongSource.local) {
            anchor = q[i];
            break;
          }
        }
        if (anchor.source == SongSource.local) return;
      }

      final existingIds = <String>{
        ...q.map((s) => s.id),
        ...RecommendationEngine.sessionRecentIds,
      };

      final nextSongs = await ApiService.getAutoQueue(
        anchor,
        limit: 30,
        existingQueueIds: existingIds,
      );

      final currentQueueIds = _queue.map((s) => s.id).toSet();
      final currentQueueTitles = _queue.map((s) => _normTitleForDedup(s.title)).toSet();
      final currentQueueRawTitles = _queue.map((s) => s.title).toList();
      final toAdd = <Song>[];
      for (final s in nextSongs) {
        if (currentQueueIds.contains(s.id)) continue;
        final tk = _normTitleForDedup(s.title);
        if (currentQueueTitles.contains(tk)) continue;
        var isDup = false;
        for (final rawTitle in currentQueueRawTitles) {
          if (RecommendationEngine.isSameSongSmart(s.title, rawTitle)) { isDup = true; break; }
        }
        if (isDup) continue;
        currentQueueTitles.add(tk);
        currentQueueRawTitles.add(s.title);
        toAdd.add(s);
      }

      final cleanToAdd = await ApiService.enrichWithCleanMetadata(toAdd);

      final addedCount = await _appendUniqueSongs(cleanToAdd);

      if (addedCount > 0) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[_maybeExtendQueue] failed: $e');
    } finally {
      _isAutoExtendingQueue = false;
    }
  }

  bool     get isPlaying      => _isPlaying;
  bool     get isLoading      => _isLoading;
  bool     get resolveTakingLong => _resolveTakingLong;
  Duration get position       => _position;
  Duration get duration       => _duration;
  Duration get buffered       => _buffered;

  bool get hasPlaybackBuffer =>
      _buffered - _position > const Duration(milliseconds: 500);
  LoopMode get loopMode       => _loopMode;
  bool     get shuffle        => _shuffle;
  bool     get showFullPlayer => _showFullPlayer;
  Song? get currentSong {
    final s = _currentSong;
    if (s == null) return null;
    if (s.id.trim().isEmpty && s.title.trim().isEmpty) return null;
    return s;
  }

  List<Song> get queue        => _queue;
  int      get currentIndex   => _currentIndex;
  bool     get hasSong        => currentSong != null;

  String get debugSeekBarState =>
      'expectedSongId=$_expectedSongId currentSongId=${_currentSong?.id} '
      'isPlaying=$_isPlaying isLoading=$_isLoading '
      'position=${_position.inMilliseconds}ms duration=${_duration.inMilliseconds}ms '
      'localTickerActive=${_localPositionTicker?.isActive == true}';

  bool _miniPlayerDismissed = false;
  String? _miniPlayerDismissedSongId;
  bool get miniPlayerVisible => hasSong && !_miniPlayerDismissed;

  void dismissMiniPlayer() {
    _miniPlayerDismissed = true;
    _miniPlayerDismissedSongId = _currentSong?.id;
    notifyListeners();
  }

  void clearMiniPlayerDismissed() {
    if (!_miniPlayerDismissed) return;
    _miniPlayerDismissed = false;
    _miniPlayerDismissedSongId = null;
    notifyListeners();
  }

  double get progress {
    if (_duration.inMilliseconds == 0) return 0.0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
  }

  String get positionString => _formatDuration(_position);
  String get durationString => _formatDuration(_duration);

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final h = d.inHours.toString();
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> playSong(Song song, {List<Song>? queue, int? index, bool curatedQueue = false}) async {
    _dismissedUntil = null;
    _lastHandledIndex = null;
    _indexDebounce?.cancel();
    _uiPlaySession++;
    final mySession = _uiPlaySession;

    if (song.artworkUrl.isNotEmpty) {
      ArtworkPaletteCache.warm(song.artworkUrl);
    }

    final isFullyOfflineQueue =
        queue != null && queue.isNotEmpty && queue.every((s) => s.isLocal);

    if (isFullyOfflineQueue) {
      _queue = List<Song>.from(queue);
      final resolvedIndex = index ?? queue.indexWhere((s) => s.id == song.id).clamp(0, queue.length - 1);
      _currentIndex = resolvedIndex.clamp(0, _queue.length - 1);
      _currentSong = _queue[_currentIndex];
      _expectedSongId = _currentSong!.id;
      _expectedSongIdSetAt = DateTime.now();
      _position = Duration.zero;
      _duration = Duration.zero;
      _isLoading = true;
      notifyListeners();
      _prewarmUpcoming(_currentIndex);
      try {
        await _engine.playQueue(_queue, _currentIndex).timeout(const Duration(seconds: 8));
      } catch (e) {
        if (mySession != _uiPlaySession) return;
        _isLoading = false;
        _expectedSongId = null;
        _expectedSongIdSetAt = null;
        _lastFailedSong = song;
        _playbackError = 'Couldn\'t play "${song.title}". Tap to retry.';
        notifyListeners();
        return;
      }
      return;
    }

    if (curatedQueue && queue != null && queue.isNotEmpty && index != null) {
      _queue = List<Song>.from(queue);
      _currentIndex = index.clamp(0, _queue.length - 1);
      _currentSong = _queue[_currentIndex];
      _expectedSongId = _currentSong!.id;
      _expectedSongIdSetAt = DateTime.now();
      _position = Duration.zero;
      _duration = Duration.zero;
      _isLoading = true;
      notifyListeners();
      _prewarmUpcoming(_currentIndex);
      try {
        await _engine.playQueue(_queue, _currentIndex).timeout(const Duration(seconds: 8));
      } catch (e) {
        if (mySession != _uiPlaySession) return;
        _isLoading = false;
        _expectedSongId = null;
        _expectedSongIdSetAt = null;
        _lastFailedSong = song;
        _playbackError = 'Couldn\'t play "${song.title}". Tap to retry.';
        notifyListeners();
        return;
      }
      if (mySession != _uiPlaySession) return;
      if (_queue.length - _currentIndex <= 8 && song.source != SongSource.local) {
        _buildInitialSmartQueue(song, alreadyInQueue: _queue.map((s) => s.id).toSet(), sessionId: mySession);
      }
      return;
    }

    if (queue != null && index != null) {
      _queue = [song];
      _currentIndex = 0;
      _currentSong = song;
      _expectedSongId = song.id;
      _expectedSongIdSetAt = DateTime.now();
      _position = Duration.zero;
      _duration = Duration.zero;
      _isLoading = true;
      notifyListeners();

      _prewarmUpcoming(_currentIndex);

      try {
        await _engine.playQueue(_queue, _currentIndex).timeout(const Duration(seconds: 8));
      } catch (e) {
        if (mySession != _uiPlaySession) return;
        _isLoading = false;
        _expectedSongId = null;
        _expectedSongIdSetAt = null;
        _lastFailedSong = song;
        _playbackError = 'Couldn\'t play "${song.title}". Tap to retry.';
        notifyListeners();
        return;
      }
      if (mySession != _uiPlaySession) return;
      if (song.source != SongSource.local) {
        _buildInitialSmartQueue(song, alreadyInQueue: queue.map((s) => s.id).toSet(), sessionId: mySession);
      }
    } else {
      _queue = [song];
      _currentIndex = 0;
      _currentSong = song;
      _expectedSongId = song.id;
      _expectedSongIdSetAt = DateTime.now();
      _position = Duration.zero;
      _duration = Duration.zero;
      _isLoading = true;
      notifyListeners();

      try {
        await _engine.playSong(song).timeout(const Duration(seconds: 8));
      } catch (e) {
        if (mySession != _uiPlaySession) return;
        _isLoading = false;
        _expectedSongId = null;
        _expectedSongIdSetAt = null;
        _lastFailedSong = song;
        _playbackError = 'Couldn\'t play "${song.title}". Tap to retry.';
        notifyListeners();
        return;
      }
      if (mySession != _uiPlaySession) return;
      if (song.source != SongSource.local) {
        _buildInitialSmartQueue(song, alreadyInQueue: {song.id}, sessionId: mySession);
      }
    }
    notifyListeners();
  }

  ({Song song, Set<String> alreadyInQueue, int sessionId})? _pendingQueueBuild;

  Future<void> _buildInitialSmartQueue(
    Song song, {
    required Set<String> alreadyInQueue,
    required int sessionId,
    bool isRetry = false,
  }) async {
    if (sessionId != _uiPlaySession) return;
    if (_isBuildingInitialQueue) {
      _pendingQueueBuild = (song: song, alreadyInQueue: alreadyInQueue, sessionId: sessionId);
      return;
    }
    _isBuildingInitialQueue = true;
    try {
      await RecommendationEngine.load();
      if (sessionId != _uiPlaySession) return;
      final queuedTitles = <String>{
        _normTitleForDedup(song.title),
        for (final s in _queue) _normTitleForDedup(s.title),
      };
      final queuedRawTitles = <String>[
        song.title,
        for (final s in _queue) s.title,
      ];
      final phase1 = await ApiService.getAutoQueue(song, limit: 20, existingQueueIds: alreadyInQueue);
      if (sessionId != _uiPlaySession) return;
      if (phase1.isNotEmpty) {
        final currentIds = _queue.map((s) => s.id).toSet();
        final toAdd = <Song>[];
        for (final s in phase1) {
          if (currentIds.contains(s.id)) continue;
          final tk = _normTitleForDedup(s.title);
          if (queuedTitles.contains(tk)) continue;
          var isDup = false;
          for (final rawTitle in queuedRawTitles) {
            if (RecommendationEngine.isSameSongSmart(s.title, rawTitle)) { isDup = true; break; }
          }
          if (isDup) continue;
          queuedTitles.add(tk);
          queuedRawTitles.add(s.title);
          toAdd.add(s);
        }
        final cleanToAdd = await ApiService.enrichWithCleanMetadata(toAdd);
        if (sessionId != _uiPlaySession) return;
        await _appendUniqueSongs(cleanToAdd, sessionId: sessionId);
        if (sessionId != _uiPlaySession) return;
        alreadyInQueue.addAll(cleanToAdd.map((s) => s.id));
        notifyListeners();
      }
      final phase2 = await ApiService.getAutoQueue(song, limit: 60, existingQueueIds: {
        ...alreadyInQueue, ...RecommendationEngine.sessionRecentIds,
      });
      if (sessionId != _uiPlaySession) return;
      if (phase2.isNotEmpty) {
        final currentIds = _queue.map((s) => s.id).toSet();
        final toAdd = <Song>[];
        for (final s in phase2) {
          if (currentIds.contains(s.id)) continue;
          final tk = _normTitleForDedup(s.title);
          if (queuedTitles.contains(tk)) continue;
          var isDup = false;
          for (final rawTitle in queuedRawTitles) {
            if (RecommendationEngine.isSameSongSmart(s.title, rawTitle)) { isDup = true; break; }
          }
          if (isDup) continue;
          queuedTitles.add(tk);
          queuedRawTitles.add(s.title);
          toAdd.add(s);
        }
        final cleanToAdd = await ApiService.enrichWithCleanMetadata(toAdd);
        if (sessionId != _uiPlaySession) return;
        await _appendUniqueSongs(cleanToAdd, sessionId: sessionId);
        if (sessionId != _uiPlaySession) return;
        notifyListeners();
      }
    } catch (e, st) {
      debugPrint('[_buildInitialSmartQueue] failed for "${song.title}": $e\n$st');
      if (sessionId == _uiPlaySession && !isRetry) {
        Future.delayed(const Duration(seconds: 2), () {
          if (sessionId != _uiPlaySession) return;
          if (_isBuildingInitialQueue) return;
          unawaited(_buildInitialSmartQueue(song, alreadyInQueue: alreadyInQueue, sessionId: sessionId, isRetry: true));
        });
      }
    } finally {
      _isBuildingInitialQueue = false;
      if (sessionId == _uiPlaySession) notifyListeners();
      final pending = _pendingQueueBuild;
      _pendingQueueBuild = null;
      if (pending != null && pending.sessionId == _uiPlaySession) {
        unawaited(_buildInitialSmartQueue(
          pending.song,
          alreadyInQueue: pending.alreadyInQueue,
          sessionId: pending.sessionId,
        ));
      }
    }
  }

  static String _normTitleForDedup(String title) {
    final clean = title
        .toLowerCase()
        .replaceAll(RegExp(r'\b(remix|lofi|lo[- ]?fi|slowed|reverb|nightcore|cover|'
                           r'karaoke|instrumental|bass[ -]?boost(?:ed)?|8d|sped[- ]?up|'
                           r'reprise|mashup|acoustic|unplugged|official|audio|video|'
                           r'lyric(?:s)?|full song|hd|4k)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
    return clean.substring(0, clean.length.clamp(0, 30));
  }

  Future<void> restoreQueueSilently(List<Song> queue, int index) async {
    _queue = List<Song>.from(queue);
    _currentIndex = index.clamp(0, queue.isEmpty ? 0 : queue.length - 1);
    _currentSong = queue.isNotEmpty ? queue[_currentIndex] : null;
    _lastHandledIndex = _currentSong != null ? _currentIndex : null;
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (_isPlaying) {
      _isPlaying = false;
      notifyListeners();
      await _engine.pause();
    } else {
      _isPlaying = true;
      bool resolved = false;
      unawaited(Future.delayed(const Duration(milliseconds: 120), () {
        if (!resolved && _isPlaying) {
          _isLoading = true;
          notifyListeners();
        }
      }));
      try {
        await _engine.play().timeout(const Duration(seconds: 8));
        resolved = true;
        if (_isLoading) {
          _isLoading = false;
          notifyListeners();
        }
      } catch (e) {
        resolved = true;
        _isLoading = false;
        _playbackError = 'Couldn\'t resume playback. Tap to retry.';
        notifyListeners();
      }
      unawaited(_engine.autoSleepGuardRecordActivity());
    }
  }

  Future<void> seek(double ratio) async {
    if (_duration == Duration.zero) return;
    final pos = Duration(milliseconds: (_duration.inMilliseconds * ratio).round());
    _justSeekedFromPosition = _position;
    _justSeekedToPosition = pos;
    _justSeekedAt = DateTime.now();
    _position = pos;
    notifyListeners();
    await _engine.seek(pos);
    unawaited(_engine.autoSleepGuardRecordActivity());
  }

  Future<void> seekTo(Duration pos) {
    _justSeekedFromPosition = _position;
    _justSeekedToPosition = pos;
    _justSeekedAt = DateTime.now();
    _position = pos;
    notifyListeners();
    unawaited(_engine.autoSleepGuardRecordActivity());
    return _engine.seek(pos);
  }

  Future<bool> skipNext() async {
    if (skipLimitReached) return false;
    _dismissedUntil = null;
    unawaited(_engine.autoSleepGuardRecordActivity());
    _recordSkip();
    _fireEarlySkipIfArmed();

    if (!_shuffle && _currentIndex + 1 < _queue.length) {
      _currentIndex += 1;
      _currentSong = _queue[_currentIndex];
      _lastHandledIndex = null;
      _expectedSongId = _currentSong!.id;
      _expectedSongIdSetAt = DateTime.now();
      _position = Duration.zero;
      _duration = Duration.zero;
      if (_currentSong!.artworkUrl.isNotEmpty) {
        ArtworkPaletteCache.warm(_currentSong!.artworkUrl);
      }
      notifyListeners();
      _scheduleSkipFlush(_currentIndex);
    } else {
      _skipDebounce?.cancel();
      _skipDebounce = null;
      _skipDebounceTargetIndex = null;
      final myExpectedId = _expectedSongId;
      try {
        await _engine.skipToNext().timeout(const Duration(seconds: 4));
      } catch (e) {
        if (_expectedSongId == myExpectedId) {
          _expectedSongId = null;
          _expectedSongIdSetAt = null;
          notifyListeners();
        }
      }
    }
    return true;
  }

  Future<void> skipPrev() async {
    _dismissedUntil = null;
    unawaited(_engine.autoSleepGuardRecordActivity());
    if (!_shuffle && _currentIndex - 1 >= 0) {
      _currentIndex -= 1;
      _currentSong = _queue[_currentIndex];
      _lastHandledIndex = null;
      _expectedSongId = _currentSong!.id;
      _expectedSongIdSetAt = DateTime.now();
      _position = Duration.zero;
      _duration = Duration.zero;
      if (_currentSong!.artworkUrl.isNotEmpty) {
        ArtworkPaletteCache.warm(_currentSong!.artworkUrl);
      }
      notifyListeners();
      _scheduleSkipFlush(_currentIndex);
    } else {
      _skipDebounce?.cancel();
      _skipDebounce = null;
      _skipDebounceTargetIndex = null;
      final myExpectedId = _expectedSongId;
      try {
        await _engine.skipToPrevious().timeout(const Duration(seconds: 4));
      } catch (e) {
        if (_expectedSongId == myExpectedId) {
          _expectedSongId = null;
          _expectedSongIdSetAt = null;
          notifyListeners();
        }
      }
    }
  }

  void _scheduleSkipFlush(int targetIndex) {
    _skipDebounceTargetIndex = targetIndex;
    _skipDebounce?.cancel();
    _skipDebounce = Timer(_skipDebounceWindow, () => _flushSkip());
  }

  Future<void> _flushSkip() async {
    final targetIndex = _skipDebounceTargetIndex;
    _skipDebounceTargetIndex = null;
    if (targetIndex == null) return;
    final myExpectedId = _expectedSongId;
    try {
      await _engine.skipToQueueItem(targetIndex).timeout(const Duration(seconds: 4));
    } catch (e) {
      if (_expectedSongId == myExpectedId) {
        _expectedSongId = null;
        _expectedSongIdSetAt = null;
        notifyListeners();
      }
    }
  }

  bool _isDuplicateInQueue(Song song) {
    if (_queue.any((s) => s.id == song.id)) return true;
    final tk = _normTitleForDedup(song.title);
    for (final s in _queue) {
      if (_normTitleForDedup(s.title) == tk) return true;
      if (RecommendationEngine.isSameSongSmart(song.title, s.title)) return true;
    }
    return false;
  }

  final List<Song> _pendingAppend = [];

  bool _isDuplicateIncludingPending(Song song) {
    if (_isDuplicateInQueue(song)) return true;
    final tk = _normTitleForDedup(song.title);
    for (final s in _pendingAppend) {
      if (s.id == song.id) return true;
      if (_normTitleForDedup(s.title) == tk) return true;
      if (RecommendationEngine.isSameSongSmart(song.title, s.title)) return true;
    }
    return false;
  }

  Future<int> _appendUniqueSongs(List<Song> songs, {int? sessionId}) async {
    var added = 0;
    for (final song in songs) {
      if (sessionId != null && sessionId != _uiPlaySession) break;
      if (_isDuplicateIncludingPending(song)) continue;
      _pendingAppend.add(song);
      try {
        await _engine.addToQueue(song);
        _queue.add(song);
        added++;
      } finally {
        _pendingAppend.remove(song);
      }
    }
    return added;
  }

  Future<void> addToQueue(Song song) async {
    if (await _appendUniqueSongs([song]) == 0) return;
    notifyListeners();
  }

  Future<int> addSongsToQueue(List<Song> songs) async {
    final added = await _appendUniqueSongs(songs);
    if (added > 0) notifyListeners();
    return added;
  }

  Future<void> playNext(Song song) async {
    if (_isDuplicateInQueue(song)) return;
    await _engine.addToQueue(song);
    _queue.add(song);
    final from = _queue.length - 1;
    final to = (_currentIndex + 1).clamp(0, _queue.length - 1);
    if (from != to) {
      await _engine.moveQueueItem(from, to);
      final moved = _queue.removeAt(from);
      _queue.insert(to, moved);
      final pending = _skipDebounceTargetIndex;
      if (pending != null && pending >= to) {
        _skipDebounceTargetIndex = pending + 1;
      }
    }
    notifyListeners();
  }

  Future<void> removeFromQueue(int index) async {
    final removedId =
        (index >= 0 && index < _queue.length) ? _queue[index].id : null;
    await _engine.removeFromQueue(index);
    final alreadyApplied = removedId != null &&
        !(index >= 0 && index < _queue.length && _queue[index].id == removedId);

    if (!alreadyApplied && index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      if (index < _currentIndex) {
        _currentIndex -= 1;
      }
    }

    if (index >= 0) {
      final pending = _skipDebounceTargetIndex;
      if (pending != null) {
        if (index == pending) {
          _skipDebounce?.cancel();
          _skipDebounce = null;
          _skipDebounceTargetIndex = null;
        } else if (index < pending) {
          _skipDebounceTargetIndex = pending - 1;
        }
      }
    }
    notifyListeners();
  }

  Future<void> moveQueueItem(int from, int to) async {
    final movedId =
        (from >= 0 && from < _queue.length) ? _queue[from].id : null;
    await _engine.moveQueueItem(from, to);

    if (from >= 0 && from < _queue.length || movedId != null) {
      final target = to.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
      final alreadyApplied = movedId != null &&
          from != target &&
          target < _queue.length &&
          _queue[target].id == movedId;

      if (!alreadyApplied && from >= 0 && from < _queue.length) {
        final item = _queue.removeAt(from);
        final clampedTo = to.clamp(0, _queue.length);
        _queue.insert(clampedTo, item);

        if (from == _currentIndex) {
          _currentIndex = clampedTo;
        } else if (from < _currentIndex && clampedTo >= _currentIndex) {
          _currentIndex -= 1;
        } else if (from > _currentIndex && clampedTo <= _currentIndex) {
          _currentIndex += 1;
        }
      }

      final pending = _skipDebounceTargetIndex;
      if (pending != null) {
        if (from == pending) {
          _skipDebounceTargetIndex = target;
        } else if (from < pending && target >= pending) {
          _skipDebounceTargetIndex = pending - 1;
        } else if (from > pending && target <= pending) {
          _skipDebounceTargetIndex = pending + 1;
        }
      }
    }
    notifyListeners();
  }

  Future<void> skipToIndex(int index) async {
    _dismissedUntil = null;
    if (!_shuffle && index >= 0 && index < _queue.length) {
      _currentIndex = index;
      _currentSong = _queue[index];
      _lastHandledIndex = null;
      _expectedSongId = _currentSong!.id;
      _expectedSongIdSetAt = DateTime.now();
      _position = Duration.zero;
      _duration = Duration.zero;
      if (_currentSong!.artworkUrl.isNotEmpty) {
        ArtworkPaletteCache.warm(_currentSong!.artworkUrl);
      }
      notifyListeners();
      _scheduleSkipFlush(index);
      return;
    }
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      _currentSong = _queue[index];
      _lastHandledIndex = null;
      _expectedSongId = _currentSong!.id;
      _expectedSongIdSetAt = DateTime.now();
      _position = Duration.zero;
      _duration = Duration.zero;
      if (_currentSong!.artworkUrl.isNotEmpty) {
        ArtworkPaletteCache.warm(_currentSong!.artworkUrl);
      }
      notifyListeners();
      _scheduleSkipFlush(index);
      return;
    }
    _skipDebounce?.cancel();
    _skipDebounce = null;
    _skipDebounceTargetIndex = null;
    final myExpectedId = _expectedSongId;
    try {
      await _engine.skipToQueueItem(index).timeout(const Duration(seconds: 4));
    } catch (e) {
      if (_expectedSongId == myExpectedId) {
        _expectedSongId = null;
        _expectedSongIdSetAt = null;
      }
    }
    notifyListeners();
  }

  Future<void> toggleLoop() async {
    final next = _loopMode == LoopMode.off
        ? LoopMode.all
        : _loopMode == LoopMode.all
            ? LoopMode.one
            : LoopMode.off;
    _loopMode = next;
    await _engine.setRepeatMode(
      next == LoopMode.off ? 'none' : next == LoopMode.one ? 'one' : 'all',
    );
    notifyListeners();
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    await _engine.setShuffleMode(_shuffle);
    notifyListeners();
  }

  void openFullPlayer() {
    _showFullPlayer = true;
    notifyListeners();
  }

  void closeFullPlayer() {
    _showFullPlayer = false;
    notifyListeners();
  }

  Future<void> pause() => _engine.pause();
  Future<void> stop() => _engine.stop();

  Future<void> stopAndClear() async {
    _dismissedUntil = DateTime.now().add(_dismissSuppressWindow);
    _skipDebounce?.cancel();
    _skipDebounce = null;
    _skipDebounceTargetIndex = null;
    _expectedSongId = null;
    _expectedSongIdSetAt = null;
    try {
      await _engine.stop();
      await _engine.clearQueue();
    } catch (e) {
      debugPrint('[Aurum] stopAndClear native call failed: $e');
    }
    _queue = [];
    _currentSong = null;
    _currentIndex = 0;
    _lastHandledIndex = null;
    _lastTrackedSong = null;
    _completionFired = false;
    _earlySkipArmed = false;
    _replayArmed = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isLoading = false;
    _isPlaying = false;
    _dismissedUntil = DateTime.now().add(_dismissSuppressWindow);
    notifyListeners();
  }

  Future<String?> fetchLyrics() async {
    final song = currentSong;
    if (song == null) return null;
    return ApiService.fetchLyrics(song);
  }

  Future<LyricsResult> fetchSyncedLyrics({Song? forSong}) async {
    final song = forSong ?? currentSong;
    if (song == null) return const LyricsResult();
    return ApiService.fetchSyncedLyrics(song);
  }

  void updateRecentlyPlayed(RecentlyPlayedProvider rp) {
    _latestRecentlyPlayed = rp;
  }

  RecentlyPlayedProvider? _latestRecentlyPlayed;

  RecentlyPlayedProvider? get _rp => _latestRecentlyPlayed ?? _recentlyPlayed;

  Future<RealPlaybackResult> runRealPlaybackTest(Song song) async {
    String? capturedError;
    final sub = _engine.errorStream.listen((e) => capturedError = e.message);
    try {
      await _engine.playSong(song).timeout(const Duration(seconds: 8));
      await Future.delayed(const Duration(seconds: 3));
      final ok = capturedError == null && _isPlaying;
      return RealPlaybackResult(
        success: ok,
        positionMs: _position.inMilliseconds,
        processingState: _isLoading ? 'buffering' : (ok ? 'ready' : 'idle'),
        errorMessage: capturedError,
      );
    } catch (e) {
      return RealPlaybackResult(
        success: false,
        positionMs: 0,
        processingState: 'error',
        errorMessage: e.toString(),
      );
    } finally {
      await sub.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _indexDebounce?.cancel();
    _skipDebounce?.cancel();
    _loadingWatchdog?.cancel();
    _stopLocalPositionTicker();
    for (final sub in _subs) sub.cancel();
    _favoritesSub?.cancel();
    _engine.onLikeToggleRequested = null;
    super.dispose();
  }
}

class _FavoritesListener {
  final FavoritesProvider _favorites;
  final VoidCallback _callback;

  _FavoritesListener(this._favorites, this._callback) {
    _favorites.addListener(_callback);
  }

  void cancel() => _favorites.removeListener(_callback);
}
