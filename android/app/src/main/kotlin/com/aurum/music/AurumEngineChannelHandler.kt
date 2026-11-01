// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
class AurumEngineChannelHandler(context: Context, messenger: BinaryMessenger) {
    private val appContext: Context = context.applicationContext

    companion object {
        private const val METHOD_CHANNEL = "com.aurum.music/audio_engine"
        private const val EVENT_CHANNEL = "com.aurum.music/audio_engine_state"
        private const val ERROR_CHANNEL = "com.aurum.music/audio_engine_errors"
        private const val OUTPUT_DEVICES_EVENT_CHANNEL = "com.aurum.music/audio_output_devices"
        private const val MEDIA_VOLUME_EVENT_CHANNEL = "com.aurum.music/media_volume"
        private const val CAST_STATE_EVENT_CHANNEL = "com.aurum.music/cast_state"
        private const val CAST_ROUTES_EVENT_CHANNEL = "com.aurum.music/cast_routes"
        private const val OFFLOAD_EVENT_CHANNEL = "com.aurum.music/offload_status"
    }

    private val resolver = HybridStreamResolver(messenger)
    val engine: AurumAudioEngine = AurumMediaSessionService.sharedEngine
        ?: AurumAudioEngine(context.applicationContext, resolver)
    private val scope = CoroutineScope(Dispatchers.Main.immediate)
    private var stateJob: Job? = null
    private var errorSink: EventChannel.EventSink? = null
    private val callbackChannel = MethodChannel(messenger, METHOD_CHANNEL)

    init {
        AurumMediaSessionService.sharedEngine = engine

        engine.onPlaybackError = { message, silent ->
            errorSink?.success(mapOf("message" to message, "silent" to silent))
        }
        engine.onQueueChanged = {  }

        engine.onLikeToggleRequested = { songId ->
            callbackChannel.invokeMethod("onLikeToggleRequested", mapOf("songId" to songId))
        }

        callbackChannel.setMethodCallHandler(::onMethodCall)

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                stateJob = scope.launch {
                    engine.state.collect { s ->
                        sink.success(
                            mapOf(
                                "processingState" to s.processingState,
                                "playing" to s.playing,
                                "positionMs" to s.positionMs,
                                "bufferedPositionMs" to s.bufferedPositionMs,
                                "durationMs" to s.durationMs,
                                "currentIndex" to s.currentIndex,
                                "speed" to s.speed,
                                "queueIds" to s.queueIds,
                                "currentSongId" to s.currentSongId,
                                "liked" to s.liked,
                                "resolveTakingLong" to s.resolveTakingLong,
                            )
                        )
                    }
                }
            }
            override fun onCancel(args: Any?) { stateJob?.cancel(); stateJob = null }
        })

        EventChannel(messenger, ERROR_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) { errorSink = sink }
            override fun onCancel(args: Any?) { errorSink = null }
        })

        EventChannel(messenger, OFFLOAD_EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                engine.onOffloadStatus = { offloaded, encoding, sampleRate ->
                    sink.success(mapOf(
                        "offloaded" to offloaded,
                        "encoding" to encoding,
                        "sampleRate" to sampleRate,
                    ))
                }
            }
            override fun onCancel(args: Any?) { engine.onOffloadStatus = null }
        })

        EventChannel(messenger, OUTPUT_DEVICES_EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                engine.outputManager.onDevicesChanged = {
                    sink.success(mapOf(
                        "devices" to engine.outputManager.describeDevices(),
                        "supportsExplicitRouting" to engine.outputManager.supportsExplicitRouting(),
                    ))
                }
            }
            override fun onCancel(args: Any?) {
                engine.outputManager.onDevicesChanged = null
            }
        })

        EventChannel(messenger, MEDIA_VOLUME_EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                engine.outputManager.onVolumeChanged = {
                    val (level, max) = engine.outputManager.currentVolume()
                    sink.success(mapOf(
                        "volume" to level,
                        "max" to max,
                    ))
                }
            }
            override fun onCancel(args: Any?) {
                engine.outputManager.onVolumeChanged = null
            }
        })

        EventChannel(messenger, CAST_STATE_EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                engine.castManager.onStateChanged = {
                    sink.success(engine.castManager.describeState())
                }
                engine.castManager.startCastStateDiscovery()
                sink.success(engine.castManager.describeState())
            }
            override fun onCancel(args: Any?) {
                engine.castManager.onStateChanged = null
                engine.castManager.stopCastStateDiscovery()
            }
        })

        EventChannel(messenger, CAST_ROUTES_EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                engine.castManager.onRoutesChanged = { routes ->
                    sink.success(routes)
                }
                engine.castManager.startRouteDiscovery()
            }
            override fun onCancel(args: Any?) {
                engine.castManager.onRoutesChanged = null
                engine.castManager.stopRouteDiscovery()
            }
        })

        var castHandoffGeneration = 0

        engine.castManager.onSessionStarted = {
            val myGeneration = ++castHandoffGeneration
            val cp = engine.castManager.castPlayer
            if (cp != null) {
                scope.launch {
                    val fullQueue = engine.currentFullQueueForCast(resolver)
                    if (myGeneration != castHandoffGeneration) return@launch
                    val startIndex = engine.currentCastStartIndexInFullQueue()
                    val startPositionMs = engine.currentLocalPositionMs()
                    if (fullQueue.isNotEmpty()) {
                        val mediaItems = fullQueue.map { (song, url) ->
                            val relayedUrl = engine.castManager.relayUrlForCast(url)
                            engine.castManager.buildCastMediaItem(
                                mediaId = song.id,
                                streamUrl = relayedUrl,
                                title = song.title,
                                artist = song.artist,
                                artworkUrl = song.artworkUrl.ifEmpty { null },
                                originalUrlForMimeDetection = url,
                            )
                        }
                        if (myGeneration != castHandoffGeneration) return@launch
                        cp.setMediaItems(mediaItems, startIndex.coerceIn(0, mediaItems.size - 1), startPositionMs)
                        cp.prepare()
                        cp.play()
                    }
                }
                engine.pauseLocalForCastHandoff()
            }
            engine.refreshState()
        }

        engine.castManager.onSessionEnded = {
            ++castHandoffGeneration
            val lastCastPositionMs = engine.castManager.castPlayer?.currentPosition
            if (lastCastPositionMs != null && lastCastPositionMs > 0) {
                engine.seek(lastCastPositionMs)
            }
            engine.play()
            engine.refreshState()
        }
    }

    private fun parseSong(map: Map<*, *>): NativeSong = NativeSong(
        id = map["id"] as String,
        title = map["title"] as? String ?: "",
        artist = map["artist"] as? String ?: "",
        album = map["album"] as? String ?: "",
        artworkUrl = map["artworkUrl"] as? String ?: "",
        source = map["source"] as? String ?: "saavn",
        isLocal = map["isLocal"] as? Boolean ?: false,
        localPath = map["localPath"] as? String,
    )

    @Suppress("UNCHECKED_CAST")
    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "playQueue" -> {
                    val songs = (call.argument<List<Map<String, Any?>>>("songs") ?: emptyList()).map(::parseSong)
                    val startIndex = call.argument<Int>("startIndex") ?: 0
                    engine.playQueue(songs, startIndex)
                    result.success(null)
                }
                "refreshState" -> {
                    engine.refreshState()
                    result.success(null)
                }
                "playSong" -> {
                    engine.playSong(parseSong(call.argument<Map<String, Any?>>("song")!!))
                    result.success(null)
                }
                "addToQueue" -> {
                    val song = parseSong(call.argument<Map<String, Any?>>("song")!!)
                    scope.launch {
                        engine.addToQueue(song)
                        result.success(null)
                    }
                }
                "removeFromQueue" -> {
                    val index = call.argument<Int>("index") ?: -1
                    scope.launch {
                        engine.removeFromQueue(index)
                        result.success(null)
                    }
                }
                "moveQueueItem" -> {
                    val from = call.argument<Int>("from") ?: 0
                    val to = call.argument<Int>("to") ?: 0
                    scope.launch {
                        engine.moveQueueItem(from, to)
                        result.success(null)
                    }
                }
                "clearQueue" -> { engine.clearQueue(); result.success(null) }
                "deletePublicDownload" -> {
                    val pathOrUri = call.argument<String>("pathOrUri") ?: ""
                    result.success(AurumMediaStoreDownloads.delete(appContext, pathOrUri))
                }
                "play" -> { engine.play(); result.success(null) }
                "pause" -> { engine.pause(); result.success(null) }
                "stop" -> { engine.stop(); result.success(null) }
                "seek" -> {
                    engine.seek((call.argument<Number>("positionMs") ?: 0).toLong())
                    result.success(null)
                }
                "skipToNext" -> { engine.skipToNext(); result.success(null) }
                "skipToPrevious" -> { engine.skipToPrevious(); result.success(null) }
                "skipToQueueItem" -> {
                    scope.launch {
                        engine.skipToQueueItemAwaitable(call.argument<Int>("index") ?: 0)
                        result.success(null)
                    }
                }
                "setRepeatMode" -> {
                    engine.setRepeatMode(call.argument<String>("mode") ?: "none")
                    result.success(null)
                }
                "setShuffleMode" -> {
                    engine.setShuffleMode(call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                }
                "setJamHold" -> {
                    engine.jamHoldStart = call.argument<Boolean>("hold") ?: false
                    result.success(null)
                }
                "setJamBuffer" -> {
                    engine.jamBoostBuffer = call.argument<Boolean>("on") ?: false
                    result.success(null)
                }
                "setSpeed" -> {
                    engine.setSpeed((call.argument<Number>("speed") ?: 1.0).toFloat())
                    result.success(null)
                }
                "setBatterySaverActive" -> {
                    engine.setBatterySaverActive(call.argument<Boolean>("active") ?: false)
                    result.success(null)
                }
                "setDataSaverActive" -> {
                    engine.setDataSaverActive(call.argument<Boolean>("active") ?: false)
                    result.success(null)
                }
                "setCurrentSongLiked" -> {
                    engine.setCurrentSongLiked(call.argument<Boolean>("liked") ?: false)
                    AurumMediaSessionService.instance?.onLikedStateChanged()
                    result.success(null)
                }
                "setCrossfadeSeconds" -> {
                    engine.setCrossfadeSeconds(call.argument<Double>("seconds") ?: 0.0)
                    result.success(null)
                }
                "sleepAfterCurrentSong" -> { engine.sleepAfterCurrentSong(); result.success(null) }
                "sleepFadeOutAndPause" -> {
                    val fadeMs = (call.argument<Number>("fadeMs") ?: 8000).toLong()
                    engine.sleepFadeOutAndPause(fadeMs)
                    result.success(null)
                }
                "applyAudioEffects" -> {
                    val bassBoost = call.argument<Boolean>("bassBoost") ?: false
                    val volNorm = call.argument<Boolean>("volumeNormalization") ?: false
                    @Suppress("UNCHECKED_CAST")
                    val bandGainsMb = (call.argument<List<Any>>("bandGainsMb"))
                        ?.map { (it as Number).toInt() }
                    engine.effects.applySettings(bassBoost, volNorm, bandGainsMb)
                    result.success(null)
                }
                "getEqualizerBands" -> {
                    result.success(engine.effects.describeBands())
                }
                "applyPremiumSound" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    engine.effects.applyPremiumSound(enabled)
                    result.success(null)
                }
                "reportResolvedBitrate" -> {
                    val kbps = call.argument<Int>("kbps")
                    val songId = call.argument<String>("songId")
                    engine.reportResolvedBitrate(songId, kbps)
                    result.success(null)
                }
                "getPremiumSoundCapabilities" -> {
                    result.success(engine.effects.describeCapabilities())
                }
                "getAudioOutputDevices" -> {
                    result.success(mapOf(
                        "devices" to engine.outputManager.describeDevices(),
                        "supportsExplicitRouting" to engine.outputManager.supportsExplicitRouting(),
                    ))
                }
                "selectAudioOutputDevice" -> {
                    val deviceId = call.argument<Int>("deviceId")
                    if (deviceId == null) {
                        result.error("BAD_ARGS", "deviceId required", null)
                        return@onMethodCall
                    }
                    if (!engine.outputManager.supportsExplicitRouting()) {
                        result.success(false)
                        return@onMethodCall
                    }
                    val ok = engine.outputManager.selectDevice(deviceId)
                    result.success(ok)
                }
                "setForceSpeaker" -> {
                    val force = call.argument<Boolean>("force") ?: false
                    engine.outputManager.setForceSpeaker(force)
                    result.success(null)
                }
                "getEstimatedBandwidth" -> {
                    result.success(engine.getEstimatedBandwidthBitsPerSec())
                }
                "getMediaVolume" -> {
                    val am = appContext.getSystemService(Context.AUDIO_SERVICE)
                        as android.media.AudioManager
                    val current = am.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
                    val max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                    result.success(mapOf(
                        "volume" to current,
                        "max" to max,
                        "boostPercent" to engine.effects.currentVolumeBoostPercent(),
                    ))
                }
                "setMediaVolume" -> {
                    val level = call.argument<Int>("volume")
                    if (level == null) {
                        result.error("BAD_ARGS", "volume required", null)
                        return@onMethodCall
                    }
                    val am = appContext.getSystemService(Context.AUDIO_SERVICE)
                        as android.media.AudioManager
                    am.setStreamVolume(
                        android.media.AudioManager.STREAM_MUSIC,
                        level,
                        0,
                    )
                    result.success(null)
                }
                "setVolumeBoost" -> {
                    val percent = call.argument<Int>("percent")
                    if (percent == null) {
                        result.error("BAD_ARGS", "percent required", null)
                        return@onMethodCall
                    }
                    engine.effects.setVolumeBoost(percent)
                    result.success(null)
                }
                "getCastState" -> {
                    result.success(engine.castManager.describeState())
                }
                "endCastSession" -> {
                    val stopCasting = call.argument<Boolean>("stopCasting") ?: false
                    engine.castManager.endSession(stopCasting)
                    result.success(null)
                }
                "selectCastRoute" -> {
                    val routeId = call.argument<String>("routeId")
                    if (routeId == null) {
                        result.success(false)
                    } else {
                        result.success(engine.castManager.selectRoute(routeId))
                    }
                }
                "setPremiumSoundCompare" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    engine.effects.setPremiumSoundCompare(enabled)
                    result.success(null)
                }
                "exitPremiumSoundCompare" -> {
                    engine.effects.exitPremiumSoundCompare()
                    result.success(null)
                }
                "resolveForDownload" -> {
                    val song = parseSong(call.argument<Map<String, Any?>>("song")!!)
                    scope.launch {
                        val url = try {
                            resolver.resolve(song, forceRefresh = false)
                        } catch (e: Exception) {
                            null
                        }
                        result.success(url)
                    }
                }

                "saveDownloadToPublicMusic" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val displayName = call.argument<String>("displayName")
                    val mimeType = call.argument<String>("mimeType") ?: "audio/mpeg"
                    val artworkBytes = call.argument<ByteArray>("artworkBytes")
                    if (sourcePath == null || displayName == null) {
                        result.success(null)
                    } else {
                        scope.launch(Dispatchers.IO) {
                            val savedRef = AurumMediaStoreDownloads.saveToPublicMusic(
                                appContext,
                                java.io.File(sourcePath),
                                displayName,
                                mimeType,
                                artworkBytes,
                            )
                            result.success(savedRef)
                        }
                    }
                }
                "deletePublicDownload" -> {
                    val pathOrUri = call.argument<String>("pathOrUri")
                    if (pathOrUri == null) {
                        result.success(false)
                    } else {
                        scope.launch(Dispatchers.IO) {
                            result.success(AurumMediaStoreDownloads.delete(appContext, pathOrUri))
                        }
                    }
                }
                "publicDownloadExists" -> {
                    val pathOrUri = call.argument<String>("pathOrUri")
                    if (pathOrUri == null) {
                        result.success(false)
                    } else {
                        scope.launch(Dispatchers.IO) {
                            result.success(AurumMediaStoreDownloads.exists(appContext, pathOrUri))
                        }
                    }
                }

                "autoSleepGuardGetState" -> {
                    val isSignedIn = AuthStateBridge.isSignedIn
                    result.success(
                        mapOf(
                            "enabled" to AutoSleepGuard.isEnabled(appContext),
                            "durationHours" to AutoSleepGuard.durationHours(appContext, isSignedIn),
                            "isSignedIn" to isSignedIn,
                        )
                    )
                }
                "autoSleepGuardSetDurationHours" -> {
                    val hours = call.argument<Int>("hours") ?: 3
                    AutoSleepGuard.setDurationHours(appContext, hours)
                    result.success(null)
                }
                "autoSleepGuardSetEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    AutoSleepGuard.setEnabled(appContext, enabled)
                    result.success(null)
                }
                "autoSleepGuardSetSleepTimerActive" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    AutoSleepGuard.setSleepTimerActive(active)
                    result.success(null)
                }
                "autoSleepGuardSetSignedIn" -> {
                    val signedIn = call.argument<Boolean>("signedIn") ?: false
                    AuthStateBridge.isSignedIn = signedIn
                    result.success(null)
                }
                "autoSleepGuardRecordActivity" -> {
                    AutoSleepGuard.recordActivity(appContext)
                    result.success(null)
                }
                "autoSleepGuardPeekLastAutoPause" -> {
                    result.success(AutoSleepGuard.peekLastAutoPause(appContext))
                }
                "autoSleepGuardConsumeLastAutoPause" -> {
                    AutoSleepGuard.consumeLastAutoPause(appContext)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("AUDIO_ENGINE_ERROR", e.message, null)
        }
    }

    fun release() {
        stateJob?.cancel()
        engine.castManager.onStateChanged = null
        engine.castManager.stopCastStateDiscovery()
    }
}
