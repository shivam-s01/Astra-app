// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.app.ActivityManager
import android.content.Context
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.cast.CastPlayer
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class NativeEngineState(
    val processingState: String = "idle",
    val playing: Boolean = false,
    val positionMs: Long = 0,
    val bufferedPositionMs: Long = 0,
    val durationMs: Long? = null,
    val currentIndex: Int? = null,
    val speed: Float = 1f,
    val queueIds: List<String> = emptyList(),
    val currentSongId: String? = null,
    val error: String? = null,
    val liked: Boolean = false,
    val resolveTakingLong: Boolean = false,
)

class AurumAudioEngine(
    private val context: Context,
    private val resolver: StreamResolver,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val skipMutex = Mutex()

    private val queueMutex = Mutex()

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private val loadControl: androidx.media3.exoplayer.LoadControl = run {
        val sharedAllocator = androidx.media3.exoplayer.upstream.DefaultAllocator(
            true, androidx.media3.common.C.DEFAULT_BUFFER_SEGMENT_SIZE
        )
        val normal = DefaultLoadControl.Builder()
            .setAllocator(sharedAllocator)
            .setBufferDurationsMs(15_000, 30_000, 3_000, 5_000)
            .setTargetBufferBytes(-1)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(60_000, true)
            .build()
        val saver = DefaultLoadControl.Builder()
            .setAllocator(sharedAllocator)
            .setBufferDurationsMs(60_000, 240_000, 3_000, 5_000)
            .setTargetBufferBytes(-1)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(20_000, true)
            .build()
        val jam = DefaultLoadControl.Builder()
            .setAllocator(sharedAllocator)
            .setBufferDurationsMs(40_000, 120_000, 4_000, 8_000)
            .setTargetBufferBytes(-1)
            .setPrioritizeTimeOverSizeThresholds(true)
            .setBackBuffer(20_000, true)
            .build()
        java.lang.reflect.Proxy.newProxyInstance(
            androidx.media3.exoplayer.LoadControl::class.java.classLoader,
            arrayOf<Class<*>>(androidx.media3.exoplayer.LoadControl::class.java),
        ) { proxy, method, args ->
            val callArgs = args ?: emptyArray<Any?>()
            when {
                method.declaringClass == Any::class.java -> when (method.name) {
                    "equals" -> proxy === callArgs.firstOrNull()
                    "hashCode" -> System.identityHashCode(proxy)
                    else -> "AurumSwitchableLoadControl"
                }
                method.returnType == Void.TYPE -> {
                    try {
                        method.invoke(normal, *callArgs)
                        method.invoke(saver, *callArgs)
                        method.invoke(jam, *callArgs)
                    } catch (e: java.lang.reflect.InvocationTargetException) {
                        throw e.targetException
                    }
                    null
                }
                else -> try {
                    method.invoke(if (dataSaverActive) saver else if (jamBoostBuffer) jam else normal, *callArgs)
                } catch (e: java.lang.reflect.InvocationTargetException) {
                    throw e.targetException
                }
            }
        } as androidx.media3.exoplayer.LoadControl
    }

    private val trackSelector = DefaultTrackSelector(context).apply {
        setParameters(
            buildUponParameters()
                .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, true)
        )
    }

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private val bandwidthMeter: DefaultBandwidthMeter by lazy {
        DefaultBandwidthMeter.Builder(context).build()
    }

    fun getEstimatedBandwidthBitsPerSec(): Long = bandwidthMeter.bitrateEstimate

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private val countingTransferListener = object : androidx.media3.datasource.TransferListener {
        private val perTransfer = java.util.IdentityHashMap<Any, Long>()

        override fun onTransferInitializing(
            source: androidx.media3.datasource.DataSource,
            dataSpec: androidx.media3.datasource.DataSpec,
            isNetwork: Boolean,
        ) = bandwidthMeter.onTransferInitializing(source, dataSpec, isNetwork)

        override fun onTransferStart(
            source: androidx.media3.datasource.DataSource,
            dataSpec: androidx.media3.datasource.DataSpec,
            isNetwork: Boolean,
        ) {
            bandwidthMeter.onTransferStart(source, dataSpec, isNetwork)
            if (isNetwork) synchronized(perTransfer) { perTransfer[source] = 0L }
        }

        override fun onBytesTransferred(
            source: androidx.media3.datasource.DataSource,
            dataSpec: androidx.media3.datasource.DataSpec,
            isNetwork: Boolean,
            bytesTransferred: Int,
        ) {
            bandwidthMeter.onBytesTransferred(source, dataSpec, isNetwork, bytesTransferred)
            if (isNetwork) synchronized(perTransfer) {
                perTransfer[source] = (perTransfer[source] ?: 0L) + bytesTransferred
            }
        }

        override fun onTransferEnd(
            source: androidx.media3.datasource.DataSource,
            dataSpec: androidx.media3.datasource.DataSpec,
            isNetwork: Boolean,
        ) {
            bandwidthMeter.onTransferEnd(source, dataSpec, isNetwork)
            if (!isNetwork) return
            val bytes = synchronized(perTransfer) { perTransfer.remove(source) } ?: return
            if (bytes >= 32 * 1024) {
                try {
                    AurumDiagnosticLog.logEvent(
                        "data",
                        String.format(java.util.Locale.US, "%.2f MB, dataSaver=%b, song=%s",
                            bytes / 1048576.0, dataSaverActive, queueSongs.getOrNull(currentIndex)?.id ?: "?"),
                    )
                } catch (_: Throwable) {}
            }
        }
    }

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun createHttpFactory() = DefaultHttpDataSource.Factory()
        .setConnectTimeoutMs(20_000)
        .setReadTimeoutMs(20_000)
        .setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36")
        .setTransferListener(countingTransferListener)

    private fun createUpstreamFactory() = DefaultDataSource.Factory(context, createHttpFactory())

    private val cachedMediaSourceFactory = DefaultMediaSourceFactory(createUpstreamFactory())

    init {
        Thread {
            try {
                context.cacheDir.listFiles()
                    ?.filter { it.name.startsWith("aurum_stream_cache") }
                    ?.forEach { it.deleteRecursively() }
                context.getSharedPreferences("aurum_last_stream_urls", Context.MODE_PRIVATE)
                    .edit().clear().apply()
            } catch (_: Exception) {}
        }.start()
    }

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun buildAudioOffloadPreferences() =
        androidx.media3.common.TrackSelectionParameters.AudioOffloadPreferences.Builder()
            .setAudioOffloadMode(
                androidx.media3.common.TrackSelectionParameters.AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_ENABLED
            )
            .setIsGaplessSupportRequired(true)
            .setIsSpeedChangeSupportRequired(false)
            .build()

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private val premiumProcessor = PremiumSoundProcessor()

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private val aurumRenderersFactory: androidx.media3.exoplayer.RenderersFactory =
        object : androidx.media3.exoplayer.DefaultRenderersFactory(context) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean,
            ): androidx.media3.exoplayer.audio.AudioSink? {
                return androidx.media3.exoplayer.audio.DefaultAudioSink.Builder(context)
                    .setEnableFloatOutput(enableFloatOutput)
                    .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                    .setAudioProcessors(arrayOf<androidx.media3.common.audio.AudioProcessor>(premiumProcessor))
                    .setAudioTrackBufferSizeProvider(
                        androidx.media3.exoplayer.audio.DefaultAudioTrackBufferSizeProvider.Builder()
                            .setMinPcmBufferDurationUs(500_000)
                            .build()
                    )
                    .build()
            }
        }

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    val player: ExoPlayer = ExoPlayer.Builder(context, aurumRenderersFactory)
        .setLoadControl(loadControl)
        .setTrackSelector(trackSelector)
        .setMediaSourceFactory(cachedMediaSourceFactory)
        .setAudioAttributes(
            androidx.media3.common.AudioAttributes.Builder()
                .setUsage(androidx.media3.common.C.USAGE_MEDIA)
                .setContentType(androidx.media3.common.C.AUDIO_CONTENT_TYPE_MUSIC)
                .build(),
             false,
        )
        .setHandleAudioBecomingNoisy(true)
        .setWakeMode(androidx.media3.common.C.WAKE_MODE_NETWORK)
        .build()
        .also { p ->
            p.trackSelectionParameters = p.trackSelectionParameters
                .buildUpon()
                .setAudioOffloadPreferences(buildAudioOffloadPreferences())
                .build()

            p.preloadConfiguration = ExoPlayer.PreloadConfiguration(20_000_000L)

            p.skipSilenceEnabled = false

            p.setPauseAtEndOfMediaItems(false)

            p.setSeekParameters(androidx.media3.exoplayer.SeekParameters.CLOSEST_SYNC)
        }
        .also { p ->
            p.addAnalyticsListener(object : androidx.media3.exoplayer.analytics.AnalyticsListener {
                override fun onAudioTrackInitialized(
                    eventTime: androidx.media3.exoplayer.analytics.AnalyticsListener.EventTime,
                    audioTrackConfig: androidx.media3.exoplayer.audio.AudioSink.AudioTrackConfig,
                ) {
                    if (BuildConfig.DEBUG) {
                        android.util.Log.i("AurumAudioEngine", "[offload-check] AudioTrack init — offload=${audioTrackConfig.offload} " +
                            "encoding=${audioTrackConfig.encoding} sampleRate=${audioTrackConfig.sampleRate} " +
                            "channelConfig=${audioTrackConfig.channelConfig}")
                    }
                    AurumDiagnosticLog.logOffload(
                        audioTrackConfig.offload,
                        audioTrackConfig.encoding,
                        audioTrackConfig.sampleRate,
                        currentSong()?.id,
                    )
                    onOffloadStatus?.invoke(
                        audioTrackConfig.offload,
                        audioTrackConfig.encoding,
                        audioTrackConfig.sampleRate,
                    )
                }
            })
        }

    private val audioManager: AudioManager by lazy {
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    private var duckedForTransientFocusLoss = false
    private var pausedForTransientFocusLoss = false
    private var pausedForSustainedFocusLoss = false
    private var preduckVolume = 1f
    private var volumeFadeJob: Job? = null

    private fun fadeVolumeTo(target: Float, durationMs: Long = 220L) {
        cancelAllVolumeFades()
        volumeFadeJob = scope.launch {
            val start = player.volume
            if (start == target) return@launch
            val steps = 12
            val stepDelay = durationMs / steps
            for (i in 1..steps) {
                val t = i / steps.toFloat()
                player.volume = start + (target - start) * t
                delay(stepDelay)
            }
            player.volume = target
        }
    }

    private val focusChangeListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                hasAudioFocus = false
                cancelAllVolumeFades()
                if (duckedForTransientFocusLoss) {
                    player.volume = preduckVolume
                    duckedForTransientFocusLoss = false
                }
                if (player.isPlaying) {
                    pausedForSustainedFocusLoss = true
                    player.pause()
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                hasAudioFocus = false
                cancelAllVolumeFades()
                if (duckedForTransientFocusLoss) {
                    player.volume = preduckVolume
                    duckedForTransientFocusLoss = false
                }
                if (player.isPlaying) {
                    pausedForTransientFocusLoss = true
                    player.pause()
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                if (player.isPlaying) {
                    preduckVolume = player.volume
                    duckedForTransientFocusLoss = true
                    fadeVolumeTo(preduckVolume * 0.85f)
                }
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasAudioFocus = true
                if (duckedForTransientFocusLoss) {
                    fadeVolumeTo(preduckVolume)
                    duckedForTransientFocusLoss = false
                }
                if (pausedForTransientFocusLoss) {
                    if (!userPaused) player.play()
                    pausedForTransientFocusLoss = false
                }
                pausedForSustainedFocusLoss = false
            }
        }
    }

    private var focusRequest: AudioFocusRequest? = null

    private var hasAudioFocus = false

    private var focusPreHandledForThisStart = false

    private fun requestAudioFocus(): Boolean {
        if (hasAudioFocus) return true
        val attrs = android.media.AudioAttributes.Builder()
            .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attrs)
            .setWillPauseWhenDucked(false)
            .setOnAudioFocusChangeListener(focusChangeListener)
            .build()
        focusRequest = request
        val granted = audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        hasAudioFocus = granted
        return granted
    }

    private fun ensureFocusBeforePlay() {
        val isFreshFocusGrab = !hasAudioFocus
        requestAudioFocus()
        if (isFreshFocusGrab) {
            focusPreHandledForThisStart = true
            fadeVolumeTo(1f, durationMs = 60L)
        }
    }

    private fun abandonAudioFocus() {
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        hasAudioFocus = false
    }

    private var offloadDisabledForEffects = false

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun disableOffloadForEffects() {
        if (offloadDisabledForEffects) return
        offloadDisabledForEffects = true
        try {
            player.trackSelectionParameters = player.trackSelectionParameters
                .buildUpon()
                .setAudioOffloadPreferences(
                    androidx.media3.common.TrackSelectionParameters.AudioOffloadPreferences.Builder()
                        .setAudioOffloadMode(
                            androidx.media3.common.TrackSelectionParameters.AudioOffloadPreferences.AUDIO_OFFLOAD_MODE_DISABLED
                        )
                        .build()
                )
                .build()
        } catch (e: Exception) {
            _log("disableOffloadForEffects failed: ${e.message}")
        }
    }

    private val bitrateBySongId = LinkedHashMap<String, Int>()
    private var bitrateAppliedForSongId: String? = null

    fun reportResolvedBitrate(songId: String?, kbps: Int?) {
        if (songId == null) {
            effects.reportSourceBitrate(kbps)
            return
        }
        bitrateBySongId[songId] = kbps ?: 0
        while (bitrateBySongId.size > 64) {
            bitrateBySongId.remove(bitrateBySongId.keys.first())
        }
        if (songId == currentSong()?.id) applyBitrateForCurrentSong(force = true)
    }

    private fun applyBitrateForCurrentSong(force: Boolean = false) {
        val id = currentSong()?.id
        if (!force && id == bitrateAppliedForSongId) return
        bitrateAppliedForSongId = id
        val kbps = id?.let { bitrateBySongId[it] }?.takeIf { it > 0 }
        effects.reportSourceBitrate(kbps)
    }

    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    val effects: AurumAudioEffects = AurumAudioEffects(player, context, premiumProcessor)

    private val _state = MutableStateFlow(NativeEngineState())
    val state: StateFlow<NativeEngineState> = _state

    var onPlaybackError: ((String, Boolean) -> Unit)? = null
    var onQueueChanged: (() -> Unit)? = null

    var onOffloadStatus: ((Boolean, Int, Int) -> Unit)? = null

    var onLikeToggleRequested: ((String) -> Unit)? = null

    private var playSessionId = 0
    private var queueSongs: List<NativeSong> = emptyList()
    private var currentIndex = 0
    private var isLoadingNewSong = false
    private var splicingInProgress = false
    private var restoredSilently = false

    @Volatile private var batterySaverActive = false

    @Volatile private var dataSaverActive = false
    @Volatile var jamBoostBuffer: Boolean = false

    private val isLowRamDevice: Boolean =
        (context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager)
            ?.isLowRamDevice ?: false

    private val priorityForwardWindow: Int
        get() = if (batterySaverActive || isLowRamDevice || dataSaverActive) PRIORITY_FORWARD_WINDOW_SAVER else PRIORITY_FORWARD_WINDOW_NORMAL

    private val effectivePacedDelayMs: Long
        get() = if (dataSaverActive) PACED_RESOLVE_DELAY_MS_DATA_SAVER else PACED_RESOLVE_DELAY_MS

    fun setBatterySaverActive(active: Boolean) {
        batterySaverActive = active
    }

    fun setDataSaverActive(active: Boolean) {
        dataSaverActive = active
        YoutubeSaverResolver.active = active
    }

    private var isResolving = false
    private var resolveTakingLong = false

    @Volatile var jamHoldStart: Boolean = false
    private var userPaused = false

    private var liveMediaIds: MutableList<String> = mutableListOf()

    private var fadeJob: Job? = null
    private fun cancelAllVolumeFades() {
        fadeJob?.cancel()
        volumeFadeJob?.cancel()
        sleepFadeJob?.cancel()
    }
    private var idleWatchdogJob: Job? = null
    private var bufferingWatchdogJob: Job? = null
    private var currentSongLiked = false
    private var crossfadeSecs = 0.0
    private var stopAfterCurrentSong = false
    private var sleepFadeJob: Job? = null

    companion object {
        private const val PRIORITY_FORWARD_WINDOW_NORMAL = 1
        private const val PRIORITY_FORWARD_WINDOW_SAVER = 1
        private const val PRIORITY_BACKWARD_WINDOW = 1
        private const val PACED_RESOLVE_DELAY_MS = 5000L
        private const val PACED_RESOLVE_DELAY_MS_DATA_SAVER = 60000L
        private const val DATA_SAVER_MAX_RESOLVE_ATTEMPTS = 6
        private const val DATA_SAVER_SLOW_RETRY_MS = 30_000L

        private const val RESOLVE_HARD_CAP_MS = 26_000L
        private const val RESOLVE_HARD_CAP_YOUTUBE_MS = 38_000L

        private fun hardCapFor(song: NativeSong): Long =
            if (song.source == "youtube") RESOLVE_HARD_CAP_YOUTUBE_MS else RESOLVE_HARD_CAP_MS

        private const val RESOLVE_WARNING_THRESHOLD_MS = 20_000L

        private fun retryBackoffMs(attempt: Int): Long =
            2_000L * minOf(attempt + 1, 4)
    }

    init {
        effects.onEffectsAboutToAttach = { disableOffloadForEffects() }
        registerReconnectListener()
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                pushState()
                if (playbackState == Player.STATE_IDLE) handleIdleEvent()
                if (playbackState == Player.STATE_BUFFERING) {
                    startBufferingWatchdog()
                } else {
                    bufferingWatchdogJob?.cancel()
                    bufferingWatchdogJob = null
                }
            }
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                pushState()
                updateTickerState(isPlaying)
                if (isPlaying) {
                    if (focusPreHandledForThisStart) {
                        focusPreHandledForThisStart = false
                    } else {
                        val isFreshFocusGrab = !hasAudioFocus
                        if (isFreshFocusGrab) {
                            cancelAllVolumeFades()
                            player.volume = 0f
                        }
                        requestAudioFocus()
                        if (isFreshFocusGrab) {
                            fadeVolumeTo(1f, durationMs = 60L)
                        }
                    }
                } else if (!pausedForTransientFocusLoss && !pausedForSustainedFocusLoss) {
                    abandonAudioFocus()
                }
            }
            override fun onPlayerError(error: PlaybackException) = pushState()
            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                reason: Int,
            ) {
                if (reason == Player.DISCONTINUITY_REASON_AUTO_TRANSITION) {
                    handleCurrentIndexChanged(newPosition.mediaItemIndex)
                }
                if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                    val reportedPos = newPosition.positionMs
                    if (pendingSeekTargetMs < 0 ||
                        kotlin.math.abs(reportedPos - pendingSeekTargetMs) <= seekSettleToleranceMs) {
                        pendingSeekTargetMs = -1L
                    }
                    pushState()
                }
            }
            override fun onMediaItemTransition(
                mediaItem: androidx.media3.common.MediaItem?,
                reason: Int,
            ) {
                handleCurrentIndexChanged(player.currentMediaItemIndex)
            }
        })
    }

    private var tickerJob: Job? = null

    private var seekGeneration = 0L
    private var pendingSeekGeneration = 0L
    private var pendingSeekTargetMs = -1L
    private var pendingSeekIssuedAt = 0L
    private val seekSettleToleranceMs = 350L
    private val seekSettleTimeoutMs = 1500L

    private fun updateTickerState(isPlaying: Boolean) {
        if (isPlaying) {
            startPositionTicker()
        } else {
            tickerJob?.cancel()
            tickerJob = null
        }
    }

    private fun startPositionTicker() {
        if (tickerJob?.isActive == true) return
        pushState()
        tickerJob = scope.launch {
            var last = -1L
            while (isActive) {
                val awaitingSeek = pendingSeekTargetMs >= 0 &&
                    pendingSeekGeneration == seekGeneration
                delay(if (awaitingSeek) 100 else 1000)

                val pos = player.currentPosition

                if (pendingSeekTargetMs >= 0 && pendingSeekGeneration == seekGeneration) {
                    val settled = kotlin.math.abs(pos - pendingSeekTargetMs) <= seekSettleToleranceMs
                    val timedOut = System.currentTimeMillis() - pendingSeekIssuedAt > seekSettleTimeoutMs
                    if (!settled && !timedOut) {
                        continue
                    }
                    pendingSeekTargetMs = -1L
                }

                if (pos != last) { last = pos; pushState() }
            }
        }
    }

    private fun markSeekPending(targetMs: Long) {
        seekGeneration++
        pendingSeekGeneration = seekGeneration
        pendingSeekTargetMs = targetMs
        pendingSeekIssuedAt = System.currentTimeMillis()
    }

    private fun scheduleSettlePushStates(mySession: Int) {
        scope.launch {
            delay(150)
            if (mySession == playSessionId) pushState()
            delay(500)
            if (mySession == playSessionId) pushState()
        }
    }

    private fun pushState() {
        val casting = _castManager?.isCasting == true
        val activePlayer: Player = if (casting) _castManager!!.castPlayer!! else player

        val liveMediaItemId = activePlayer.currentMediaItem?.mediaId
        val effectiveCurrentSongId = liveMediaItemId
            ?: queueSongs.getOrNull(currentIndex)?.id

        _state.value = NativeEngineState(
            processingState = when {
                !casting && isResolving && player.playbackState == Player.STATE_IDLE -> "loading"
                activePlayer.playbackState == Player.STATE_IDLE -> "idle"
                activePlayer.playbackState == Player.STATE_BUFFERING -> "buffering"
                activePlayer.playbackState == Player.STATE_READY -> "ready"
                activePlayer.playbackState == Player.STATE_ENDED -> "completed"
                else -> "idle"
            },
            playing = activePlayer.isPlaying,
            positionMs = activePlayer.currentPosition,
            bufferedPositionMs = activePlayer.bufferedPosition,
            durationMs = activePlayer.duration.takeIf { it != C.TIME_UNSET },
            currentIndex = currentIndex,
            speed = activePlayer.playbackParameters.speed,
            queueIds = queueSongs.map { it.id },
            currentSongId = effectiveCurrentSongId,
            liked = currentSongLiked,
            resolveTakingLong = resolveTakingLong,
        )
    }

    private fun emitError(message: String, silent: Boolean = false) {
        AurumDiagnosticLog.logPlaybackError(message, currentSong()?.id)
        onPlaybackError?.invoke(message, silent)
    }

    private fun buildMediaItem(song: NativeSong, url: String): MediaItem {
        val metadataBuilder = androidx.media3.common.MediaMetadata.Builder()
            .setTitle(song.title)
            .setArtist(song.artist)
            .setAlbumTitle(song.album)
        if (song.artworkUrl.isNotEmpty()) {
            metadataBuilder.setArtworkUri(android.net.Uri.parse(song.artworkUrl))
        }
        return MediaItem.Builder()
            .setMediaId(song.id)
            .setUri(url)
            .setMediaMetadata(metadataBuilder.build())
            .build()
    }

    private var mutedSessionCount = 0

    private suspend fun hardStopAndMute(sessionId: Int): Boolean {
        cancelAllVolumeFades()
        fadeJob = null
        fun stillCurrent() = sessionId == playSessionId
        if (!stillCurrent()) return false
        player.volume = 0f
        mutedSessionCount++
        focusPreHandledForThisStart = false
        if (!stillCurrent()) return true
        player.pause()
        if (!stillCurrent()) return true
        player.stop()
        if (!stillCurrent()) return true
        player.clearMediaItems()
        liveMediaIds.clear()
        lastHandledMediaId = null
        return true
    }

    private fun restoreVolume(releaseVolumeToOne: Boolean = true) {
        if (mutedSessionCount > 0) mutedSessionCount--
        if (mutedSessionCount == 0 && releaseVolumeToOne) player.volume = 1f
    }

    fun playQueue(songs: List<NativeSong>, startIndex: Int) {
        scope.launch { playQueueInternal(songs, startIndex) }
    }

    private suspend fun playQueueInternal(songs: List<NativeSong>, startIndex: Int) {
        playSessionId++
        val mySession = playSessionId
        isLoadingNewSong = true
        restoredSilently = false
        userPaused = jamHoldStart

        val safeIndex = if (songs.isEmpty()) 0 else startIndex.coerceIn(0, songs.size - 1)
        var effectiveIndex = safeIndex

        queueSongs = songs
        currentIndex = safeIndex
        splicingInProgress = true
        onQueueChanged?.invoke()
        pushState()

        var started = false
        var keepResolvingOnExit = false
        var didMute = false
        try {
            didMute = hardStopAndMute(mySession)
            if (mySession != playSessionId) return

            isResolving = true
            pushState()

            val resolvedSong = songs[safeIndex]
            var url = resolveFast(resolvedSong, mySession)
            if (mySession != playSessionId) return
            if (url == null) {
                url = resolveWithPatience(resolvedSong, mySession)
                if (mySession != playSessionId) return
            }

            if (url == null) {
                keepResolvingOnExit = true
                pushState()
                return
            }

            resolveTakingLong = false
            if (mySession != playSessionId) return
            try {
                setSingleMediaItemInternal(url, resolvedSong)
            } catch (e: Exception) {
                isResolving = false
                failPlayback(resolvedSong, e.message ?: "setMediaItem failed")
                return
            }
            isResolving = false
            if (mySession != playSessionId) return

            reapplySpeed()
            val freshGrab = !hasAudioFocus
            ensureFocusBeforePlay()
            restoreVolume(releaseVolumeToOne = !freshGrab)
            didMute = false
            if (jamHoldStart) player.pause() else player.play()
            started = true
            scheduleSettlePushStates(mySession)
        } catch (e: Exception) {
            emitError("playQueue failed for \"${songs[safeIndex].title}\" — ${e.message}")
        } finally {
            if (!keepResolvingOnExit && mySession == playSessionId) {
                isResolving = false
            }
            if (didMute) restoreVolume()
            if (mySession == playSessionId) {
                isLoadingNewSong = false
                if (!started) splicingInProgress = false
            } else {
                splicingInProgress = false
                isLoadingNewSong = false
            }
            pushState()
        }

        if (started && mySession == playSessionId) {
            resolveQueueInBackground(songs, effectiveIndex, mySession)
        }
    }

    fun playSong(song: NativeSong) {
        scope.launch { playSongInternal(song) }
    }

    private suspend fun playSongInternal(song: NativeSong) {
        playSessionId++
        val mySession = playSessionId
        restoredSilently = false

        queueSongs = listOf(song)
        currentIndex = 0
        splicingInProgress = false
        onQueueChanged?.invoke()
        pushState()

        var keepResolvingOnExit = false
        var didMute = false
        try {
            isLoadingNewSong = true
            didMute = hardStopAndMute(mySession)
            if (mySession != playSessionId) return

            isResolving = true
            pushState()

            var url = try {
                withTimeoutOrNull(hardCapFor(song)) { resolveFast(song, mySession) }
            } catch (e: CancellationException) { throw e }
            if (mySession != playSessionId) return

            if (url == null) {
                delay(700)
                if (mySession != playSessionId) return
                resolver.invalidate(song)
            }

            if (url == null) {
                url = resolveWithPatience(song, mySession)
                if (mySession != playSessionId) return
            }

            if (url == null) {
                keepResolvingOnExit = true
                pushState()
                return
            }

            resolveTakingLong = false
            if (mySession != playSessionId) return
            try {
                setSingleMediaItemInternal(url, song)
            } catch (e: Exception) {
                isResolving = false
                failPlayback(song, e.message ?: "setMediaItem failed")
                return
            }
            isResolving = false
            if (mySession != playSessionId) return

            reapplySpeed()
            val freshGrab = !hasAudioFocus
            ensureFocusBeforePlay()
            restoreVolume(releaseVolumeToOne = !freshGrab)
            didMute = false
            player.play()
            scheduleSettlePushStates(mySession)
        } catch (e: Exception) {
            emitError("playSong failed for \"${song.title}\" — ${e.message}")
        } finally {
            if (!keepResolvingOnExit && mySession == playSessionId) {
                isResolving = false
            }
            if (mySession == playSessionId) {
                if (didMute) restoreVolume()
                isLoadingNewSong = false
                maybeAutoExtendQueue()
            } else {
                if (didMute) restoreVolume()
                isLoadingNewSong = false
            }
            pushState()
        }
    }

    private fun setSingleMediaItemInternal(url: String, song: NativeSong) {
        val item = buildMediaItem(song, url)
        liveMediaIds = mutableListOf(song.id)
        player.setMediaItem(item)
        player.prepare()
    }

    private suspend fun resolveFast(song: NativeSong, sessionId: Int, maxAttempts: Int = 2): String? {
        if (song.isLocal) {
            val path = song.localPath
            if (path.isNullOrEmpty()) return null
            return if (path.startsWith("file://") || path.startsWith("content://")) path
            else "file://$path"
        }

        val perAttemptTimeoutMs = if (song.source == "youtube") 26_000L else 12_000L
        repeat(maxAttempts) { attemptIndex ->
            if (sessionId != playSessionId) return null
            val url = try {
                withTimeoutOrNull(perAttemptTimeoutMs) { resolver.resolve(song) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
            if (sessionId != playSessionId) return null
            if (!url.isNullOrEmpty()) {
                return url
            }
            if (attemptIndex < maxAttempts - 1) delay(500)
        }
        return null
    }

    private suspend fun resolveWithPatience(song: NativeSong, sessionId: Int): String? {
        if (song.isLocal) {
            return resolveFast(song, sessionId, maxAttempts = 1)
        }
        val startedAt = SystemClock.elapsedRealtime()
        var attempt = 0
        while (true) {
            if (sessionId != playSessionId) return null
            if (!hasAnyNetworkConnection()) {
                return null
            }
            val url = try {
                withTimeoutOrNull(hardCapFor(song)) { resolveFast(song, sessionId) }
            } catch (e: CancellationException) {
                throw e
            }
            if (sessionId != playSessionId) return null
            if (!url.isNullOrEmpty()) return url

            if (dataSaverActive && attempt + 1 >= DATA_SAVER_MAX_RESOLVE_ATTEMPTS) {
                resolveTakingLong = true
                pushState()
                return null
            }

            if (!resolveTakingLong &&
                SystemClock.elapsedRealtime() - startedAt >= RESOLVE_WARNING_THRESHOLD_MS
            ) {
                resolveTakingLong = true
                pushState()
            }

            delay(if (dataSaverActive && attempt >= 2) DATA_SAVER_SLOW_RETRY_MS else retryBackoffMs(attempt))
            attempt++
        }
    }

    private suspend fun findFirstPlayableFrom(
        songs: List<NativeSong>, fromIndex: Int, sessionId: Int,
    ): Pair<Int, String>? {
        for (i in fromIndex until songs.size) {
            if (sessionId != playSessionId) return null
            val url = resolveFast(songs[i], sessionId, maxAttempts = 1)
            if (sessionId != playSessionId) return null
            if (url != null) return i to url
        }
        return null
    }

    private fun failPlayback(song: NativeSong, detail: String) {
        queueSongs = emptyList()
        currentIndex = 0
        splicingInProgress = false
        onQueueChanged?.invoke()
        emitError("Resolve failed for \"${song.title}\" — $detail")
        pushState()
    }

    private suspend fun reapplySpeed() {
        val current = player.playbackParameters
        if (current.speed != 1f || current.pitch != 1f) {
            player.setPlaybackSpeed(current.speed)
        }
    }

    private fun handleIdleEvent() {
        val pos = player.currentPosition
        idleWatchdogJob?.cancel()
        idleWatchdogJob = scope.launch {
            if (pos < 500) handleFreshStartIdle() else handleMidStreamIdle(pos)
        }
    }

    private fun startBufferingWatchdog() {
        bufferingWatchdogJob?.cancel()
        val sessionAtStart = playSessionId
        val songAtStart = queueSongs.getOrNull(currentIndex)
        val posAtStart = player.currentPosition
        bufferingWatchdogJob = scope.launch {
            delay(20_000)
            if (sessionAtStart != playSessionId) return@launch
            if (player.playbackState != Player.STATE_BUFFERING) return@launch
            if (!player.playWhenReady) return@launch
            if (isLoadingNewSong) return@launch
            val song = queueSongs.getOrNull(currentIndex) ?: return@launch
            if (songAtStart == null || song.id != songAtStart.id) return@launch
            _log("[watchdog] Stuck buffering 20s+ on \"${song.title}\" — forcing recovery")
            handleMidStreamIdle(posAtStart.coerceAtLeast(player.currentPosition))
        }
    }

    private fun _log(msg: String) {
        if (BuildConfig.DEBUG) android.util.Log.d("AurumAudioEngine", msg)
    }

    private fun hasAnyNetworkConnection(): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return true
            val network = cm.activeNetwork ?: return false
            val caps = cm.getNetworkCapabilities(network) ?: return false
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } catch (_: Exception) {
            true
        }
    }

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    private fun registerReconnectListener() {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: android.net.Network) {
                if (!isResolving) return
                val songToRetry = queueSongs.getOrNull(currentIndex) ?: return
                val sessionNow = playSessionId
                scope.launch {
                    delay(500)
                    if (sessionNow != playSessionId) return@launch
                    if (!isResolving) return@launch
                    if (!hasAnyNetworkConnection()) return@launch
                    val freshUrl = resolveWithPatience(songToRetry, sessionNow)
                    if (sessionNow != playSessionId) return@launch
                    if (freshUrl == null) {
                        return@launch
                    }
                    resolveTakingLong = false
                    if (queueSongs.getOrNull(currentIndex)?.id != songToRetry.id) return@launch
                    try {
                        setSingleMediaItemInternal(freshUrl, songToRetry)
                        isResolving = false
                        if (!userPaused) player.play()
                        pushState()
                    } catch (e: Exception) {
                        isResolving = false
                        failPlayback(songToRetry, e.message ?: "setMediaItem failed after reconnect")
                    }
                }
            }
        }
        try {
            cm.registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (_: Exception) {
        }
    }

    private fun unregisterReconnectListener() {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        val callback = networkCallback
        if (cm != null && callback != null) {
            try { cm.unregisterNetworkCallback(callback) } catch (_: Exception) {  }
        }
        networkCallback = null
    }

    private fun localSongFileOk(rawPath: String?): Boolean {
        if (rawPath.isNullOrEmpty()) return false
        return try {
            if (rawPath.startsWith("content://")) {
                context.contentResolver.openAssetFileDescriptor(
                    android.net.Uri.parse(rawPath), "r"
                )?.use { it.length > 0 } ?: false
            } else {
                val path = rawPath.removePrefix("file://")
                java.io.File(path).let { it.exists() && it.length() > 0 }
            }
        } catch (_: Exception) {
            false
        }
    }

    private suspend fun handleFreshStartIdle() {
        val songAtIdle = queueSongs.getOrNull(currentIndex) ?: return

        if (songAtIdle.isLocal) {
            val sessionAtIdle = playSessionId
            val fileOk = localSongFileOk(songAtIdle.localPath)
            if (fileOk) {
                delay(400)
                if (sessionAtIdle == playSessionId &&
                    queueSongs.getOrNull(currentIndex)?.id == songAtIdle.id &&
                    player.playbackState == Player.STATE_IDLE
                ) {
                    try {
                        player.prepare()
                        if (!userPaused) player.play()
                        pushState()
                    } catch (_: Exception) {  }
                }
                return
            }
            emitError("Downloaded file for \"${songAtIdle.title}\" is missing or unreadable — skipping to next song.", true)
            advancePastDeadSong(songAtIdle, sessionAtIdle)
            return
        }

        val sessionAtIdle = playSessionId
        delay(1200)

        if (sessionAtIdle != playSessionId) return
        if (isLoadingNewSong) return
        val songNow = queueSongs.getOrNull(currentIndex) ?: return
        if (songNow.id != songAtIdle.id) return
        if (player.playbackState != Player.STATE_IDLE) return
        if (player.currentPosition >= 500) return

        resolver.invalidate(songNow)

        isResolving = true
        pushState()
        val freshUrl = resolveWithPatience(songNow, sessionAtIdle)
        if (sessionAtIdle != playSessionId) return

        if (freshUrl == null) {
            pushState()
            return
        }
        resolveTakingLong = false
        isResolving = false

        if (queueSongs.getOrNull(currentIndex)?.id != songAtIdle.id) return
        if (sessionAtIdle != playSessionId) return

        try {
            setSingleMediaItemInternal(freshUrl, songNow)
            delay(800)
            if (player.playbackState == Player.STATE_IDLE) {
                emitError("Playback failed for \"${songNow.title}\" — stream URL returned but could not be opened. Skipping to next song.", true)
                advancePastDeadSong(songNow, sessionAtIdle)
                return
            }
            if (!userPaused) player.play()
            pushState()
        } catch (e: Exception) {
            if (sessionAtIdle == playSessionId) {
                emitError("Playback failed for \"${songNow.title}\" after retry — ${e.message}. Skipping to next song.", true)
                advancePastDeadSong(songNow, sessionAtIdle)
            }
        }
    }

    private suspend fun handleMidStreamIdle(pos: Long) {
        if (queueSongs.isEmpty() || isLoadingNewSong) return
        val song = queueSongs.getOrNull(currentIndex) ?: return

        if (song.isLocal) {
            val sessionNow = playSessionId
            val fileOk = localSongFileOk(song.localPath)
            if (fileOk) {
                delay(400)
                if (sessionNow == playSessionId &&
                    queueSongs.getOrNull(currentIndex)?.id == song.id &&
                    player.playbackState == Player.STATE_IDLE
                ) {
                    try {
                        player.prepare()
                        player.seekTo(pos)
                        if (!userPaused) player.play()
                        pushState()
                    } catch (_: Exception) {  }
                }
                return
            }
            emitError("Downloaded file for \"${song.title}\" could not continue playing — skipping to next song.", true)
            advancePastDeadSong(song, sessionNow)
            return
        }

        val playerIdxAtStart = player.currentMediaItemIndex
        fun stillOnThisSong(): Boolean {
            val liveIdx = player.currentMediaItemIndex
            if (liveIdx != playerIdxAtStart) return false
            return liveMediaIds.getOrNull(liveIdx) == song.id
        }

        resolver.invalidate(song)
        val sessionAtError = playSessionId

        isResolving = true
        pushState()
        val freshUrl = resolveWithPatience(song, sessionAtError)

        if (sessionAtError != playSessionId) return
        if (!stillOnThisSong()) { isResolving = false; return }

        if (freshUrl == null) {
            pushState()
            return
        }
        resolveTakingLong = false

        try {
            val idx = player.currentMediaItemIndex
            if (idx < player.mediaItemCount && stillOnThisSong()) {
                val item = buildMediaItem(song, freshUrl)
                player.replaceMediaItem(idx, item)
                player.seekTo(idx, pos)
                if (!userPaused) player.play()
                isResolving = false
                pushState()
                return
            }
        } catch (e: Exception) {  }

        isResolving = false
        if (sessionAtError != playSessionId) return
        emitError("Stream expired for \"${song.title}\" and could not be recovered. Skipping to next song.", true)
        advancePastDeadSong(song, sessionAtError)
    }

    private suspend fun advancePastDeadSong(deadSong: NativeSong, sessionAtFailure: Int) {
        if (sessionAtFailure != playSessionId) return
        if (queueSongs.isEmpty()) return
        val deadIdx = queueSongs.indexOfFirst { it.id == deadSong.id }
        val startFrom = if (deadIdx >= 0) deadIdx + 1 else currentIndex + 1
        if (startFrom >= queueSongs.size) {
            emitError("Reached end of queue after \"${deadSong.title}\" could not be played.", false)
            return
        }
        val found = findFirstPlayableFrom(queueSongs, startFrom, sessionAtFailure)
        if (sessionAtFailure != playSessionId) return
        if (found == null) {
            emitError("Could not play \"${deadSong.title}\" or any later song in the queue.", false)
            return
        }
        currentIndex = found.first
        onQueueChanged?.invoke()
        if (sessionAtFailure != playSessionId) return
        try {
            setSingleMediaItemInternal(found.second, queueSongs[found.first])
            if (sessionAtFailure != playSessionId) return
            reapplySpeed()
            player.play()
        } catch (e: Exception) {
            emitError("Could not play \"${deadSong.title}\" or the next song — ${e.message}", false)
        }
        pushState()
    }

    private var lastHandledMediaId: String? = null

    private fun handleCurrentIndexChanged(index: Int?) {
        if (index == null) return

        if ((isLoadingNewSong || isResolving) && player.mediaItemCount == 0) {
            return
        }

        if (stopAfterCurrentSong && index != currentIndex) {
            stopAfterCurrentSong = false
            player.pause()
            return
        }

        val incomingMediaId = liveMediaIds.getOrNull(index)
        val previousId = lastHandledMediaId
        val isRealTrackChange =
            incomingMediaId != null && previousId != null && incomingMediaId != previousId
        if (incomingMediaId != null) lastHandledMediaId = incomingMediaId

        if (crossfadeSecs > 0 && isRealTrackChange && !isLoadingNewSong) {
            applyCrossfadeFadeIn()
        }

        val mediaId = liveMediaIds.getOrNull(index)
        if (mediaId != null) {
            val queueIdx = queueSongs.indexOfFirst { it.id == mediaId }
            if (queueIdx != -1 && queueIdx != currentIndex) {
                currentIndex = queueIdx
            }
            maybeAutoExtendQueue()
            ensureNextResolved(playSessionId)
            applyBitrateForCurrentSong()
            pushState()
            return
        }

        if (index != currentIndex && index < queueSongs.size) {
            currentIndex = index
        }
        maybeAutoExtendQueue()
        ensureNextResolved(playSessionId)
        applyBitrateForCurrentSong()
        pushState()
    }

    private fun applyCrossfadeFadeIn() {
        cancelAllVolumeFades()
        val mySession = playSessionId
        val steps = (crossfadeSecs * 10).toInt().coerceIn(1, 120)
        val stepMs = (crossfadeSecs * 1000 / steps).toLong()
        val startVolume = player.volume
        fadeJob = scope.launch {
            for (step in 1..steps) {
                if (mySession != playSessionId) return@launch
                delay(stepMs)
                val progress = step.toFloat() / steps
                player.volume = (startVolume + (1f - startVolume) * progress).coerceIn(0f, 1f)
            }
            player.volume = 1f
        }
    }

    private var autoExtending = false
    var onFetchSimilarSongs: (suspend (NativeSong, List<String>) -> List<NativeSong>)? = null

    private fun maybeAutoExtendQueue() {
        if (autoExtending || splicingInProgress) return
        if (queueSongs.isEmpty() || currentIndex >= queueSongs.size) return
        val remaining = queueSongs.size - 1 - currentIndex
        if (remaining > 1) return
        val current = queueSongs[currentIndex]
        if (current.isLocal) return

        autoExtending = true
        val mySession = playSessionId
        scope.launch {
            try {
                val similar = onFetchSimilarSongs?.invoke(current, queueSongs.map { it.id }) ?: emptyList()
                autoExtending = false
                if (mySession != playSessionId || similar.isEmpty()) return@launch
                for (song in similar.take(10)) {
                    if (mySession != playSessionId) return@launch
                    addToQueueInternal(song, mySession)
                }
            } catch (e: Exception) {
                autoExtending = false
            }
        }
    }

    suspend fun addToQueue(song: NativeSong) = queueMutex.withLock {
        addToQueueInternal(song, playSessionId)
    }

    private suspend fun addToQueueInternal(song: NativeSong, session: Int) {
        queueSongs = queueSongs + song
        val url = resolveFast(song, session, maxAttempts = 1) ?: return
        if (session != playSessionId) return
        val item = buildMediaItem(song, url)
        player.addMediaItem(item)
        liveMediaIds.add(song.id)
        handleCurrentIndexChanged(player.currentMediaItemIndex)
        onQueueChanged?.invoke()
        pushState()
    }

    suspend fun removeFromQueue(index: Int) = queueMutex.withLock {
        if (index !in queueSongs.indices) return@withLock
        queueSongs = queueSongs.filterIndexed { i, _ -> i != index }
        if (index < liveMediaIds.size) {
            player.removeMediaItem(index)
            liveMediaIds.removeAt(index)
        }
        if (currentIndex > index) currentIndex--
        onQueueChanged?.invoke()
        pushState()
    }

    suspend fun moveQueueItem(from: Int, to: Int) = queueMutex.withLock {
        if (from !in queueSongs.indices || to !in queueSongs.indices) return@withLock
        val mutable = queueSongs.toMutableList()
        val song = mutable.removeAt(from)
        mutable.add(to, song)
        queueSongs = mutable
        if (from < liveMediaIds.size) player.moveMediaItem(from, to)
        if (from == currentIndex) {
            currentIndex = to
        } else if (from < currentIndex && to >= currentIndex) {
            currentIndex--
        } else if (from > currentIndex && to <= currentIndex) {
            currentIndex++
        }
        onQueueChanged?.invoke()
        pushState()
    }

    fun clearQueue() {
        queueSongs = emptyList()
        currentIndex = 0
        player.clearMediaItems()
        liveMediaIds.clear()
        onQueueChanged?.invoke()
        pushState()
    }

    private fun ensureNextResolved(sessionId: Int) {
        val nextIdx = currentIndex + 1
        if (nextIdx >= queueSongs.size) return
        val nextSong = queueSongs[nextIdx]
        if (liveMediaIds.contains(nextSong.id)) return
        scope.launch {
            if (sessionId != playSessionId) return@launch
            try {
                val url = resolveFast(nextSong, sessionId, maxAttempts = 1) ?: return@launch
                if (sessionId != playSessionId) return@launch
                queueMutex.withLock {
                    if (sessionId != playSessionId) return@withLock
                    if (liveMediaIds.contains(nextSong.id)) return@withLock
                    player.addMediaItem(buildMediaItem(nextSong, url))
                    liveMediaIds.add(nextSong.id)
                    handleCurrentIndexChanged(player.currentMediaItemIndex)
                }
            } catch (e: Exception) {  }
        }
    }

    private fun resolveQueueInBackground(songs: List<NativeSong>, startIndex: Int, sessionId: Int) {
        scope.launch {
            try {
                for (i in startIndex + 1 until songs.size) {
                    if (sessionId != playSessionId) return@launch
                    if (i - startIndex > priorityForwardWindow) {
                        if (dataSaverActive) return@launch
                        delay(effectivePacedDelayMs)
                        if (sessionId != playSessionId) return@launch
                    }
                    try {
                        val url = resolveFast(songs[i], sessionId, maxAttempts = 1)
                        if (sessionId != playSessionId) return@launch
                        if (url != null && sessionId == playSessionId) {
                            queueMutex.withLock {
                                if (sessionId != playSessionId) return@withLock
                                player.addMediaItem(buildMediaItem(songs[i], url))
                                liveMediaIds.add(songs[i].id)
                                handleCurrentIndexChanged(player.currentMediaItemIndex)
                            }
                        }
                    } catch (e: Exception) {  }
                }

                for (i in startIndex - 1 downTo 0) {
                    if (sessionId != playSessionId) return@launch
                    if (dataSaverActive) return@launch
                    if (startIndex - i > PRIORITY_BACKWARD_WINDOW) {
                        if (dataSaverActive) return@launch
                        delay(effectivePacedDelayMs)
                        if (sessionId != playSessionId) return@launch
                    }
                    try {
                        val url = resolveFast(songs[i], sessionId, maxAttempts = 1)
                        if (sessionId != playSessionId) return@launch
                        if (url != null && sessionId == playSessionId) {
                            queueMutex.withLock {
                                if (sessionId != playSessionId) return@withLock
                                player.addMediaItem(0, buildMediaItem(songs[i], url))
                                liveMediaIds.add(0, songs[i].id)
                                handleCurrentIndexChanged(player.currentMediaItemIndex)
                            }
                        }
                    } catch (e: Exception) {  }
                }
            } finally {
                if (sessionId == playSessionId) {
                    splicingInProgress = false
                    maybeAutoExtendQueue()
                }
            }
        }
    }

    private val isCastActive: Boolean
        get() = activeCastPlayer != null

    fun isCasting(): Boolean = isCastActive

    private val activeCastPlayer: CastPlayer?
        get() {
            val mgr = _castManager ?: return null
            if (!mgr.isCasting) return null
            return mgr.castPlayer
        }

    fun play() {
        userPaused = false
        activeCastPlayer?.let { it.play(); return }
        restoredSilently = false
        player.play()
    }
    fun pause() {
        userPaused = true
        activeCastPlayer?.let { it.pause(); return }
        player.pause()
    }
    fun stop() {
        activeCastPlayer?.let { try { it.stop() } catch (e: Exception) { }; return }
        try { player.stop() } catch (e: Exception) { }
    }
    fun seek(positionMs: Long) {
        activeCastPlayer?.let { it.seekTo(positionMs); return }
        markSeekPending(positionMs)
        player.seekTo(positionMs)
    }

    private var skipGen = 0

    fun skipToNext() {
        val cp = activeCastPlayer
        if (cp != null) {
            if (cp.hasNextMediaItem()) { cp.seekToNext(); cp.play() }
            else if (cp.repeatMode == Player.REPEAT_MODE_ALL && cp.mediaItemCount > 0) { cp.seekTo(0, 0); cp.play() }
            return
        }
        val gen = ++skipGen
        scope.launch {
            skipMutex.withLock {
                if (gen != skipGen) return@withLock
                val liveLen = player.mediaItemCount
                val livePos = player.currentMediaItemIndex
                if (livePos < liveLen - 1) {
                    userPaused = false
                    player.seekToNext(); player.play()
                } else if (player.repeatMode == Player.REPEAT_MODE_ALL && liveLen > 0) {
                    userPaused = false
                    player.seekTo(0, 0); player.play()
                } else if (currentIndex < queueSongs.size - 1) {
                    restartQueueAt(currentIndex + 1)
                }
            }
        }
    }

    fun skipToPrevious() {
        val cp = activeCastPlayer
        if (cp != null) {
            if (cp.currentPosition > 3000) cp.seekTo(0)
            else if (cp.hasPreviousMediaItem()) cp.seekToPrevious()
            return
        }
        val gen = ++skipGen
        scope.launch {
            skipMutex.withLock {
                if (gen != skipGen) return@withLock
                if (player.currentPosition > 3000) {
                    player.seekTo(0)
                } else {
                    val livePos = player.currentMediaItemIndex
                    if (livePos > 0) {
                        userPaused = false
                        player.seekToPrevious()
                        player.play()
                    } else if (currentIndex > 0) {
                        restartQueueAt(currentIndex - 1)
                    }
                }
            }
        }
    }

    suspend fun skipToQueueItemAwaitable(index: Int) {
        val cp = activeCastPlayer
        if (cp != null) {
            queueMutex.withLock {
                if (index < cp.mediaItemCount) {
                    currentIndex = index
                    pushState()
                    cp.seekTo(index, 0)
                    cp.play()
                }
            }
            return
        }
        val gen = ++skipGen
        queueMutex.withLock {
            skipMutex.withLock {
                if (gen != skipGen) return@withLock
                if (index !in queueSongs.indices) return@withLock

                val targetSong = queueSongs[index]
                val livePos = liveMediaIds.indexOf(targetSong.id)
                if (livePos != -1 && livePos < player.mediaItemCount) {
                    currentIndex = index
                    pushState()
                    player.seekTo(livePos, 0)
                    userPaused = false
                    player.play()
                } else {
                    restartQueueAt(index)
                }
            }
        }
    }

    private fun restartQueueAt(index: Int) {
        val snapshot = queueSongs
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            playQueueInternal(snapshot, index)
        }
    }

    fun canSkipNext(): Boolean {
        val cp = activeCastPlayer
        if (cp != null) return cp.hasNextMediaItem() || cp.mediaItemCount > 0 && cp.repeatMode == Player.REPEAT_MODE_ALL
        return currentIndex < queueSongs.size - 1 ||
            (player.repeatMode == Player.REPEAT_MODE_ALL && queueSongs.isNotEmpty())
    }

    fun canSkipPrevious(): Boolean = queueSongs.isNotEmpty()

    fun setRepeatMode(mode: String) {
        val repeatMode = when (mode) {
            "one" -> Player.REPEAT_MODE_ONE
            "all" -> Player.REPEAT_MODE_ALL
            else -> Player.REPEAT_MODE_OFF
        }
        player.repeatMode = repeatMode
        activeCastPlayer?.repeatMode = repeatMode
    }

    fun setShuffleMode(enabled: Boolean) {
        player.shuffleModeEnabled = enabled
        activeCastPlayer?.shuffleModeEnabled = enabled
    }
    fun setSpeed(speed: Float) {
        player.setPlaybackSpeed(speed)
    }
    fun setCurrentSongLiked(liked: Boolean) { currentSongLiked = liked; pushState() }

    fun triggerLikeToggle() {
        val song = currentSong() ?: return
        onLikeToggleRequested?.invoke(song.id)
    }

    fun isCurrentSongLiked(): Boolean = currentSongLiked
    fun setCrossfadeSeconds(secs: Double) { crossfadeSecs = secs }
    fun sleepAfterCurrentSong() { stopAfterCurrentSong = true }

    fun sleepFadeOutAndPause(fadeMs: Long = 8000L) {
        cancelAllVolumeFades()
        val target: Player = activeCastPlayer ?: player
        sleepFadeJob = scope.launch {
            val start = target.volume
            val steps = 40
            val stepDelay = (fadeMs / steps).coerceAtLeast(1L)
            for (i in 1..steps) {
                val t = i / steps.toFloat()
                target.volume = start * (1f - t)
                delay(stepDelay)
            }
            target.volume = 0f
            target.pause()
            target.volume = 1f
        }
    }

    fun currentQueue(): List<NativeSong> = queueSongs
    fun currentSongIndex(): Int = currentIndex
    fun currentSong(): NativeSong? = queueSongs.getOrNull(currentIndex)

    fun currentQueueForCast(): List<Pair<NativeSong, String>> {
        val result = mutableListOf<Pair<NativeSong, String>>()
        for (i in 0 until player.mediaItemCount) {
            val song = queueSongs.getOrNull(i) ?: continue
            val uri = player.getMediaItemAt(i).localConfiguration?.uri?.toString() ?: continue
            result.add(song to uri)
        }
        return result
    }

    fun currentCastStartIndex(): Int {
        var idx = 0
        for (i in 0 until player.mediaItemCount) {
            if (queueSongs.getOrNull(i) == null) continue
            if (player.getMediaItemAt(i).localConfiguration?.uri == null) continue
            if (i == currentIndex) return idx
            idx++
        }
        return 0
    }

    suspend fun currentFullQueueForCast(resolver: StreamResolver): List<Pair<NativeSong, String>> {
        val loadedUrls = mutableMapOf<Int, String>()
        for (i in 0 until player.mediaItemCount) {
            player.getMediaItemAt(i).localConfiguration?.uri?.toString()?.let { loadedUrls[i] = it }
        }
        val result = mutableListOf<Pair<NativeSong, String>>()
        var resolvedStartIndex = 0
        for (i in queueSongs.indices) {
            val song = queueSongs[i]
            val url = loadedUrls[i] ?: try {
                resolver.resolve(song, forceRefresh = false)
            } catch (e: Exception) {
                null
            }
            if (url != null) {
                result.add(song to url)
                if (i < currentIndex) resolvedStartIndex++
            }
        }
        _lastCastStartIndex = resolvedStartIndex
        return result
    }

    private var _lastCastStartIndex = 0

    fun currentCastStartIndexInFullQueue(): Int = _lastCastStartIndex

    fun currentLocalPositionMs(): Long = player.currentPosition

    fun pauseLocalForCastHandoff() { player.pause() }

    private var _outputManager: AurumAudioOutputManager? = null
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    val outputManager: AurumAudioOutputManager
        get() = _outputManager ?: AurumAudioOutputManager(context, audioManager, player).also {
            _outputManager = it
        }

    private var _castManager: AurumCastManager? = null
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    val castManager: AurumCastManager
        get() = _castManager ?: AurumCastManager(context).also {
            _castManager = it
        }

    fun refreshState() = pushState()

    fun release() {
        fadeJob?.cancel()
        idleWatchdogJob?.cancel()
        unregisterReconnectListener()
        scope.cancel()
        effects.dispose()
        abandonAudioFocus()
        _outputManager?.release()
        _castManager?.release()
        player.release()
    }
}
