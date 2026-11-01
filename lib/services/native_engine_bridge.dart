// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import '../models/song.dart';
import 'api_service.dart';
import 'audio_prefs.dart';

class NativeEngineState {
  final String processingState;
  final bool playing;
  final Duration position;
  final Duration bufferedPosition;
  final Duration? duration;
  final int? currentIndex;
  final double speed;
  final List<String> queueIds;
  final String? currentSongId;
  final bool liked;
  final bool resolveTakingLong;

  const NativeEngineState({
    this.processingState = 'idle',
    this.playing = false,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.duration,
    this.currentIndex,
    this.speed = 1.0,
    this.queueIds = const [],
    this.currentSongId,
    this.liked = false,
    this.resolveTakingLong = false,
  });
}

class PlaybackErrorEvent {
  final String message;
  final bool silent;
  const PlaybackErrorEvent(this.message, this.silent);
}

class NativeAudioEngine {
  static NativeAudioEngine? _instance;
  factory NativeAudioEngine() => _instance ??= NativeAudioEngine._internal();

  static const MethodChannel _method = MethodChannel('com.aurum.music/audio_engine');
  static const EventChannel _stateEvents = EventChannel('com.aurum.music/audio_engine_state');
  static const EventChannel _errorEvents = EventChannel('com.aurum.music/audio_engine_errors');
  static const EventChannel _outputDeviceEvents =
      EventChannel('com.aurum.music/audio_output_devices');
  static const EventChannel _mediaVolumeEvents =
      EventChannel('com.aurum.music/media_volume');
  static const EventChannel _castStateEvents =
      EventChannel('com.aurum.music/cast_state');
  static const EventChannel _castRoutesEvents =
      EventChannel('com.aurum.music/cast_routes');
  static const EventChannel _offloadEvents =
      EventChannel('com.aurum.music/offload_status');

  static const MethodChannel _resolverChannel = MethodChannel('com.aurum.music/stream_resolver');
  static final Map<int, _ResolveJob> _inFlight = {};

  final _state = BehaviorSubject<NativeEngineState>.seeded(const NativeEngineState());
  final _errors = StreamController<PlaybackErrorEvent>.broadcast();
  final _outputDevices =
      BehaviorSubject<AudioOutputDevices?>.seeded(null);
  final _mediaVolume = BehaviorSubject<MediaVolume?>.seeded(null);
  CastState _lastCastState = const CastState();

  Stream<NativeEngineState> get stateStream => _state.stream;
  Stream<PlaybackErrorEvent> get errorStream => _errors.stream;
  Stream<AudioOutputDevices?> get outputDevicesStream => _outputDevices.stream;
  Stream<MediaVolume?> get mediaVolumeStream => _mediaVolume.stream;

  late final Stream<CastState> castStateStream = _castStateEvents
      .receiveBroadcastStream()
      .map(_parseCastState)
      .map((s) {
        _lastCastState = s;
        return s;
      });
  CastState get castState => _lastCastState;
  NativeEngineState get value => _state.value;

  late final Stream<OffloadStatus> offloadStatusStream = _offloadEvents
      .receiveBroadcastStream()
      .map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return OffloadStatus(
          offloaded: m['offloaded'] as bool? ?? false,
          encoding: m['encoding'] as int? ?? 0,
          sampleRate: m['sampleRate'] as int? ?? 0,
        );
      });

  StreamSubscription? _stateSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _outputDevicesSub;
  StreamSubscription? _mediaVolumeSub;

  void Function(String songId)? onLikeToggleRequested;

  NativeAudioEngine._internal() {
    _method.setMethodCallHandler(_handleEngineCallback);

    _resolverChannel.setMethodCallHandler(_handleResolverCall);

    _stateSub = _stateEvents.receiveBroadcastStream().listen((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      _state.add(NativeEngineState(
        processingState: m['processingState'] as String? ?? 'idle',
        playing: m['playing'] as bool? ?? false,
        position: Duration(milliseconds: (m['positionMs'] as num? ?? 0).toInt()),
        bufferedPosition: Duration(milliseconds: (m['bufferedPositionMs'] as num? ?? 0).toInt()),
        duration: (m['durationMs'] as num?) != null
            ? Duration(milliseconds: (m['durationMs'] as num).toInt())
            : null,
        currentIndex: m['currentIndex'] as int?,
        speed: (m['speed'] as num? ?? 1.0).toDouble(),
        queueIds: List<String>.from(m['queueIds'] as List? ?? const []),
        currentSongId: m['currentSongId'] as String?,
        liked: m['liked'] as bool? ?? false,
        resolveTakingLong: m['resolveTakingLong'] as bool? ?? false,
      ));
    }, onError: (Object e, StackTrace st) {
      debugPrint('[NativeAudioEngine] state event error (ignored, stream stays alive): $e');
    });

    _errorSub = _errorEvents.receiveBroadcastStream().listen((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      _errors.add(PlaybackErrorEvent(
        m['message'] as String? ?? 'Unknown playback error',
        m['silent'] as bool? ?? false,
      ));
    }, onError: (Object e, StackTrace st) {
      debugPrint('[NativeAudioEngine] error-event stream error (ignored): $e');
    });

    _outputDevicesSub =
        _outputDeviceEvents.receiveBroadcastStream().listen((raw) {
      _outputDevices.add(_parseOutputDevices(raw));
    }, onError: (Object e, StackTrace st) {
      debugPrint('[NativeAudioEngine] output-device stream error (ignored): $e');
    });

    _mediaVolumeSub =
        _mediaVolumeEvents.receiveBroadcastStream().listen((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      _mediaVolume.add(MediaVolume(
        level: m['volume'] as int? ?? 0,
        max: m['max'] as int? ?? 1,
      ));
    }, onError: (Object e, StackTrace st) {
      debugPrint('[NativeAudioEngine] media-volume stream error (ignored): $e');
    });
  }

  Stream<List<CastRoute>> get castRoutesStream =>
      _castRoutesEvents.receiveBroadcastStream().map(_parseCastRoutes);

  List<CastRoute> _parseCastRoutes(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => CastRoute(
              id: m['id'] as String? ?? '',
              name: m['name'] as String? ?? '',
              description: m['description'] as String?,
              selected: m['selected'] as bool? ?? false,
            ))
        .where((r) => r.id.isNotEmpty)
        .toList();
  }

  Future<bool> selectCastRoute(String routeId) async {
    final ok = await _method.invokeMethod('selectCastRoute', {'routeId': routeId});
    return ok as bool? ?? false;
  }

  Future<dynamic> _handleEngineCallback(MethodCall call) async {
    switch (call.method) {
      case 'onLikeToggleRequested':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final songId = args['songId'] as String?;
        if (songId != null) onLikeToggleRequested?.call(songId);
        return null;
      default:
        return null;
    }
  }

  Future<dynamic> _handleResolverCall(MethodCall call) async {
    switch (call.method) {
      case 'resolveStreamUrl':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final requestId = args['requestId'] as int;
        final song = _songFromArgs(args);
        final forceRefresh = args['forceRefresh'] as bool? ?? false;

        final completer = Completer<String?>();
        _inFlight[requestId] = _ResolveJob(completer);
        try {
          final result = await ApiService.resolveStreamUrl(song, forceRefresh: forceRefresh);
          if (_inFlight.containsKey(requestId)) completer.complete(result);
          if (result != null) {
            unawaited(_method.invokeMethod('reportResolvedBitrate', {
              'kbps': AudioPrefs.lastResolvedKbps,
              'songId': song.id,
            }).catchError((_) {}));
          }
        } catch (e) {
          if (_inFlight.containsKey(requestId)) completer.complete(null);
        } finally {
          _inFlight.remove(requestId);
          if (!completer.isCompleted) completer.complete(null);
        }
        return completer.future;

      case 'cancelResolve':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final requestId = args['requestId'] as int;
        _inFlight.remove(requestId);
        return null;

      case 'invalidateStream':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final song = _songFromArgs(args);
        ApiService.invalidateStream(song);
        return null;

      default:
        return null;
    }
  }

  Song _songFromArgs(Map<String, dynamic> args) {
    final sourceStr = args['source'] as String? ?? 'saavn';
    final source = SongSource.values.firstWhere(
      (s) => s.name == sourceStr,
      orElse: () => SongSource.saavn,
    );
    return Song(
      id: args['songId'] as String? ?? '',
      title: args['title'] as String? ?? '',
      artist: args['artist'] as String? ?? '',
      album: args['album'] as String? ?? '',
      artworkUrl: args['artworkUrl'] as String? ?? '',
      localPath: args['localPath'] as String?,
      source: source,
    );
  }

  Map<String, dynamic> _songToArgs(Song song) => {
        'id': song.id,
        'title': song.title,
        'artist': song.artist,
        'album': song.album,
        'artworkUrl': song.artworkUrl,
        'source': song.source.name,
        'isLocal': song.isLocal,
        'localPath': song.localPath,
      };

  Future<void> refreshState() => _method.invokeMethod('refreshState');

  Future<void> playQueue(List<Song> songs, int startIndex) => _method.invokeMethod(
        'playQueue',
        {'songs': songs.map(_songToArgs).toList(), 'startIndex': startIndex},
      );

  Future<void> playSong(Song song) => _method.invokeMethod('playSong', {'song': _songToArgs(song)});
  Future<void> addToQueue(Song song) => _method.invokeMethod('addToQueue', {'song': _songToArgs(song)});
  Future<void> removeFromQueue(int index) => _method.invokeMethod('removeFromQueue', {'index': index});
  Future<void> moveQueueItem(int from, int to) =>
      _method.invokeMethod('moveQueueItem', {'from': from, 'to': to});
  Future<void> clearQueue() => _method.invokeMethod('clearQueue');
  Future<void> play() => _method.invokeMethod('play');
  Future<void> pause() => _method.invokeMethod('pause');
  Future<void> stop() => _method.invokeMethod('stop');
  Future<void> seek(Duration pos) => _method.invokeMethod('seek', {'positionMs': pos.inMilliseconds});
  Future<void> skipToNext() => _method.invokeMethod('skipToNext');
  Future<void> skipToPrevious() => _method.invokeMethod('skipToPrevious');
  Future<void> skipToQueueItem(int index) => _method.invokeMethod('skipToQueueItem', {'index': index});
  Future<void> setRepeatMode(String mode) => _method.invokeMethod('setRepeatMode', {'mode': mode});
  Future<void> setShuffleMode(bool enabled) => _method.invokeMethod('setShuffleMode', {'enabled': enabled});
  Future<void> setSpeed(double speed) => _method.invokeMethod('setSpeed', {'speed': speed});
  Future<void> setJamHold(bool hold) => _method.invokeMethod('setJamHold', {'hold': hold});
  Future<void> setJamBuffer(bool on) => _method.invokeMethod('setJamBuffer', {'on': on});
  Future<void> setBatterySaverActive(bool active) =>
      _method.invokeMethod('setBatterySaverActive', {'active': active});
  Future<void> setDataSaverActive(bool active) =>
      _method.invokeMethod('setDataSaverActive', {'active': active});
  Future<void> setCurrentSongLiked(bool liked) =>
      _method.invokeMethod('setCurrentSongLiked', {'liked': liked});
  Future<void> setCrossfadeSeconds(double secs) =>
      _method.invokeMethod('setCrossfadeSeconds', {'seconds': secs});
  Future<void> sleepAfterCurrentSong() => _method.invokeMethod('sleepAfterCurrentSong');
  Future<bool> deletePublicDownload(String pathOrUri) async {
    final result = await _method.invokeMethod('deletePublicDownload', {'pathOrUri': pathOrUri});
    return result == true;
  }

  Future<void> sleepFadeOutAndPause({int fadeMs = 8000}) =>
      _method.invokeMethod('sleepFadeOutAndPause', {'fadeMs': fadeMs});

  Future<Map<String, dynamic>> autoSleepGuardGetState() async {
    final result = await _method.invokeMapMethod<String, dynamic>('autoSleepGuardGetState');
    return result ?? const {'enabled': true, 'durationHours': 3, 'isSignedIn': false};
  }

  Future<void> autoSleepGuardSetDurationHours(int hours) =>
      _method.invokeMethod('autoSleepGuardSetDurationHours', {'hours': hours});

  Future<void> autoSleepGuardSetEnabled(bool enabled) =>
      _method.invokeMethod('autoSleepGuardSetEnabled', {'enabled': enabled});

  Future<void> autoSleepGuardSetSleepTimerActive(bool active) =>
      _method.invokeMethod('autoSleepGuardSetSleepTimerActive', {'active': active});

  Future<void> autoSleepGuardSetSignedIn(bool signedIn) =>
      _method.invokeMethod('autoSleepGuardSetSignedIn', {'signedIn': signedIn});

  Future<void> autoSleepGuardRecordActivity() =>
      _method.invokeMethod('autoSleepGuardRecordActivity');

  Future<int?> autoSleepGuardPeekLastAutoPause() =>
      _method.invokeMethod<int>('autoSleepGuardPeekLastAutoPause');

  Future<void> autoSleepGuardConsumeLastAutoPause() =>
      _method.invokeMethod('autoSleepGuardConsumeLastAutoPause');

  Future<String?> resolveForDownload(Song song) async {
    try {
      final result = await _method.invokeMethod<String>(
        'resolveForDownload',
        {'song': _songToArgs(song)},
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> applyAudioEffects({
    required bool bassBoost,
    required bool volumeNormalization,
    List<double>? bandGainsDb,
  }) =>
      _method.invokeMethod('applyAudioEffects', {
        'bassBoost': bassBoost,
        'volumeNormalization': volumeNormalization,
        'bandGainsMb': bandGainsDb?.map((db) => (db * 100).round()).toList(),
      });

  Future<void> applyPremiumSound(bool enabled) =>
      _method.invokeMethod('applyPremiumSound', {'enabled': enabled});

  Future<void> setPremiumSoundCompare(bool enabled) =>
      _method.invokeMethod('setPremiumSoundCompare', {'enabled': enabled});

  Future<void> exitPremiumSoundCompare() =>
      _method.invokeMethod('exitPremiumSoundCompare');

  Future<AudioOutputDevices> getAudioOutputDevices() async {
    final raw = await _method.invokeMethod('getAudioOutputDevices');
    return _parseOutputDevices(raw) ??
        const AudioOutputDevices(devices: [], supportsExplicitRouting: false);
  }

  Future<bool> selectAudioOutputDevice(int deviceId) async {
    final ok = await _method
        .invokeMethod('selectAudioOutputDevice', {'deviceId': deviceId});
    return ok as bool? ?? false;
  }

  Future<void> setForceSpeaker(bool force) =>
      _method.invokeMethod('setForceSpeaker', {'force': force});

  Future<MediaVolume> getMediaVolume() async {
    final raw = await _method.invokeMethod('getMediaVolume');
    final m = Map<String, dynamic>.from(raw as Map);
    return MediaVolume(
      level: m['volume'] as int? ?? 0,
      max: m['max'] as int? ?? 1,
      boostPercent: m['boostPercent'] as int? ?? 100,
    );
  }

  Future<void> setMediaVolume(int level) =>
      _method.invokeMethod('setMediaVolume', {'volume': level});

  Future<void> setVolumeBoost(int percent) =>
      _method.invokeMethod('setVolumeBoost', {'percent': percent});

  Future<int> getEstimatedBandwidthKbps() async {
    try {
      final bitsPerSec = await _method.invokeMethod('getEstimatedBandwidth');
      final bits = (bitsPerSec as num?)?.toInt() ?? 0;
      if (bits <= 0) return 0;
      return bits ~/ 1000;
    } catch (_) {
      return 0;
    }
  }

  AudioOutputDevices? _parseOutputDevices(dynamic raw) {
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(raw as Map);
    final rawDevices = (m['devices'] as List? ?? const []);
    return AudioOutputDevices(
      devices: rawDevices.map((d) {
        final dm = Map<String, dynamic>.from(d as Map);
        return AudioOutputDevice(
          id: dm['id'] as int? ?? -1,
          name: dm['name'] as String? ?? 'Audio device',
          kind: AudioOutputDeviceKind.fromNative(dm['kind'] as String?),
          selected: dm['selected'] as bool? ?? false,
        );
      }).toList(),
      supportsExplicitRouting: m['supportsExplicitRouting'] as bool? ?? false,
    );
  }

  Future<CastState> getCastState() async {
    final raw = await _method.invokeMethod('getCastState');
    return _parseCastState(raw);
  }

  Future<void> endCastSession({bool stopCasting = false}) =>
      _method.invokeMethod('endCastSession', {'stopCasting': stopCasting});

  CastState _parseCastState(dynamic raw) {
    if (raw == null) return const CastState();
    final m = Map<String, dynamic>.from(raw as Map);
    return CastState(
      status: CastConnectionStatus.fromNative(m['state'] as String?),
      deviceName: m['deviceName'] as String?,
      supported: m['supported'] as bool? ?? false,
    );
  }

  Future<PremiumSoundCapabilities?> getPremiumSoundCapabilities() async {
    final raw = await _method.invokeMethod('getPremiumSoundCapabilities');
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(raw as Map);
    return PremiumSoundCapabilities(
      virtualizerSupported: m['virtualizerSupported'] as bool? ?? false,
      bassBoostSupported: m['bassBoostSupported'] as bool? ?? false,
      outputRoute: m['outputRoute'] as String? ?? 'UNKNOWN',
    );
  }

  Future<EqualizerBandInfo?> getEqualizerBands() async {
    final raw = await _method.invokeMethod('getEqualizerBands');
    if (raw == null) return null;
    final m = Map<String, dynamic>.from(raw as Map);
    return EqualizerBandInfo(
      bandCount: m['bandCount'] as int? ?? 0,
      minDb: ((m['minMb'] as num? ?? 0).toInt()) / 100.0,
      maxDb: ((m['maxMb'] as num? ?? 0).toInt()) / 100.0,
      centerFreqsHz: List<int>.from(m['centerFreqsHz'] as List? ?? const []),
    );
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    await _errorSub?.cancel();
    await _outputDevicesSub?.cancel();
    await _mediaVolumeSub?.cancel();
    await _state.close();
    await _errors.close();
    await _outputDevices.close();
    await _mediaVolume.close();
  }
}

class _ResolveJob {
  final Completer<String?> completer;
  _ResolveJob(this.completer);
}

class EqualizerBandInfo {
  final int bandCount;
  final double minDb;
  final double maxDb;
  final List<int> centerFreqsHz;

  const EqualizerBandInfo({
    required this.bandCount,
    required this.minDb,
    required this.maxDb,
    required this.centerFreqsHz,
  });
}

class PremiumSoundCapabilities {
  final bool virtualizerSupported;
  final bool bassBoostSupported;
  final String outputRoute;

  const PremiumSoundCapabilities({
    required this.virtualizerSupported,
    required this.bassBoostSupported,
    required this.outputRoute,
  });

  bool get fullySupported => virtualizerSupported && bassBoostSupported;
}

enum AudioOutputDeviceKind {
  speaker,
  wired,
  bluetooth,
  usb,
  unknown;

  static AudioOutputDeviceKind fromNative(String? kind) {
    switch (kind) {
      case 'speaker':
        return AudioOutputDeviceKind.speaker;
      case 'wired':
        return AudioOutputDeviceKind.wired;
      case 'bluetooth':
        return AudioOutputDeviceKind.bluetooth;
      case 'usb':
        return AudioOutputDeviceKind.usb;
      default:
        return AudioOutputDeviceKind.unknown;
    }
  }
}

class MediaVolume {
  final int level;
  final int max;
  final int boostPercent;

  const MediaVolume({
    required this.level,
    required this.max,
    this.boostPercent = 100,
  });
}

class AudioOutputDevice {
  final int id;
  final String name;
  final AudioOutputDeviceKind kind;
  final bool selected;

  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.selected,
  });
}

class AudioOutputDevices {
  final List<AudioOutputDevice> devices;
  final bool supportsExplicitRouting;

  const AudioOutputDevices({
    required this.devices,
    required this.supportsExplicitRouting,
  });
}

enum CastConnectionStatus {
  unavailable,
  available,
  connecting,
  connected;

  static CastConnectionStatus fromNative(String? state) {
    switch (state) {
      case 'AVAILABLE':
        return CastConnectionStatus.available;
      case 'CONNECTING':
        return CastConnectionStatus.connecting;
      case 'CONNECTED':
        return CastConnectionStatus.connected;
      default:
        return CastConnectionStatus.unavailable;
    }
  }
}

class CastState {
  final CastConnectionStatus status;
  final String? deviceName;
  final bool supported;

  const CastState({
    this.status = CastConnectionStatus.unavailable,
    this.deviceName,
    this.supported = false,
  });

  bool get isConnected => status == CastConnectionStatus.connected;
  bool get isConnecting => status == CastConnectionStatus.connecting;
}

class CastRoute {
  final String id;
  final String name;
  final String? description;
  final bool selected;

  const CastRoute({
    required this.id,
    required this.name,
    this.description,
    this.selected = false,
  });
}

class OffloadStatus {
  final bool offloaded;
  final int encoding;
  final int sampleRate;

  const OffloadStatus({
    required this.offloaded,
    required this.encoding,
    required this.sampleRate,
  });
}
