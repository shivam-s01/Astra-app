// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.content.Context
import androidx.mediarouter.media.MediaRouter
import androidx.media3.cast.CastPlayer
import androidx.media3.cast.SessionAvailabilityListener
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.CastState
import com.google.android.gms.cast.framework.CastStateListener
import com.google.android.gms.cast.framework.SessionManagerListener

@UnstableApi
class AurumCastManager(
    private val context: Context,
) {
    enum class State {
        UNAVAILABLE,
        AVAILABLE,
        CONNECTING,
        CONNECTED,
    }

    var onStateChanged: (() -> Unit)? = null

    var onSessionStarted: (() -> Unit)? = null

    var onSessionEnded: (() -> Unit)? = null

    private val castContext: CastContext? = try {
        CastContext.getSharedInstance(context)
    } catch (e: Exception) {
        null
    }

    val castPlayer: CastPlayer? = castContext?.let { ctx ->
        CastPlayer(ctx).apply {
            setSessionAvailabilityListener(object : SessionAvailabilityListener {
                override fun onCastSessionAvailable() {
                    onSessionStarted?.invoke()
                }
                override fun onCastSessionUnavailable() {
                    onSessionEnded?.invoke()
                }
            })
        }
    }

    private var connectedDeviceName: String? = null

    private val castStateListener = CastStateListener { state ->
        onStateChanged?.invoke()
    }

    private val sessionManagerListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            connectedDeviceName = session.castDevice?.friendlyName
            onStateChanged?.invoke()
        }
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            connectedDeviceName = session.castDevice?.friendlyName
            onStateChanged?.invoke()
        }
        override fun onSessionEnded(session: CastSession, error: Int) {
            connectedDeviceName = null
            onStateChanged?.invoke()
        }
        override fun onSessionStarting(session: CastSession) { onStateChanged?.invoke() }
        override fun onSessionStartFailed(session: CastSession, error: Int) {
            connectedDeviceName = null
            onStateChanged?.invoke()
        }
        override fun onSessionEnding(session: CastSession) {}
        override fun onSessionResuming(session: CastSession, sessionId: String) {}
        override fun onSessionResumeFailed(session: CastSession, error: Int) {
            connectedDeviceName = null
            onStateChanged?.invoke()
        }
        override fun onSessionSuspended(session: CastSession, reason: Int) {
            onStateChanged?.invoke()
        }
    }

    private val discoveryCallback = object : MediaRouter.Callback() {}
    private var discoveryActive = false

    init {
        castContext?.addCastStateListener(castStateListener)
        castContext?.sessionManager?.addSessionManagerListener(
            sessionManagerListener, CastSession::class.java,
        )
    }

    fun startCastStateDiscovery() {
        if (discoveryActive) return
        val selector = castContext?.mergedSelector ?: return
        MediaRouter.getInstance(context).addCallback(
            selector,
            discoveryCallback,
            MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY,
        )
        discoveryActive = true
    }

    fun stopCastStateDiscovery() {
        if (!discoveryActive) return
        MediaRouter.getInstance(context).removeCallback(discoveryCallback)
        discoveryActive = false
    }

    val isCasting: Boolean
        get() = castContext?.sessionManager?.currentCastSession?.isConnected == true

    var onRoutesChanged: ((List<Map<String, Any?>>) -> Unit)? = null

    private val router: MediaRouter? = try {
        MediaRouter.getInstance(context)
    } catch (e: Exception) {
        null
    }

    private val pickerScanCallback = object : MediaRouter.Callback() {
        override fun onRouteAdded(router: MediaRouter, route: MediaRouter.RouteInfo) = emitRoutes()
        override fun onRouteRemoved(router: MediaRouter, route: MediaRouter.RouteInfo) = emitRoutes()
        override fun onRouteChanged(router: MediaRouter, route: MediaRouter.RouteInfo) = emitRoutes()
    }

    private fun emitRoutes() {
        val r = router ?: return
        val selector = castContext?.mergedSelector ?: return
        val routes = r.routes.filter { route ->
            !route.isDefault && route.matchesSelector(selector) && route.isEnabled
        }
        onRoutesChanged?.invoke(routes.map { route ->
            mapOf(
                "id" to route.id,
                "name" to route.name,
                "description" to route.description,
                "selected" to route.isSelected,
            )
        })
    }

    fun startRouteDiscovery() {
        val selector = castContext?.mergedSelector ?: run {
            onRoutesChanged?.invoke(emptyList())
            return
        }
        router?.addCallback(
            selector,
            pickerScanCallback,
            MediaRouter.CALLBACK_FLAG_PERFORM_ACTIVE_SCAN or MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY,
        )
        emitRoutes()
    }

    fun stopRouteDiscovery() {
        router?.removeCallback(pickerScanCallback)
    }

    fun selectRoute(routeId: String): Boolean {
        val r = router ?: return false
        val route = r.routes.firstOrNull { it.id == routeId } ?: return false
        r.selectRoute(route)
        return true
    }

    fun describeState(): Map<String, Any?> {
        val state = when (castContext?.castState) {
            CastState.NO_DEVICES_AVAILABLE, null -> State.UNAVAILABLE
            CastState.NOT_CONNECTED -> State.AVAILABLE
            CastState.CONNECTING -> State.CONNECTING
            CastState.CONNECTED -> State.CONNECTED
            else -> State.UNAVAILABLE
        }
        return mapOf(
            "state" to state.name,
            "deviceName" to connectedDeviceName,
            "supported" to (castContext != null),
        )
    }

    fun endSession(stopCasting: Boolean) {
        castContext?.sessionManager?.endCurrentSession(stopCasting)
    }

    private val relayServer = AurumCastRelayServer()

    private fun currentLanIp(): String? {
        return try {
            val wifiManager = context.applicationContext
                .getSystemService(Context.WIFI_SERVICE) as? android.net.wifi.WifiManager
            val ipInt = wifiManager?.connectionInfo?.ipAddress ?: return null
            if (ipInt == 0) return null
            String.format(
                "%d.%d.%d.%d",
                ipInt and 0xff,
                ipInt shr 8 and 0xff,
                ipInt shr 16 and 0xff,
                ipInt shr 24 and 0xff,
            )
        } catch (e: Exception) {
            null
        }
    }

    fun relayUrlForCast(upstreamUrl: String): String {
        val ip = currentLanIp() ?: return upstreamUrl
        val headers = mapOf(
            "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
        )
        return relayServer.buildRelayUrl(ip, upstreamUrl, headers) ?: upstreamUrl
    }

    fun buildCastMediaItem(
        mediaId: String,
        streamUrl: String,
        title: String,
        artist: String,
        artworkUrl: String?,
        originalUrlForMimeDetection: String = streamUrl,
    ): MediaItem {
        val metadataBuilder = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
        if (!artworkUrl.isNullOrEmpty()) {
            metadataBuilder.setArtworkUri(android.net.Uri.parse(artworkUrl))
        }
        return MediaItem.Builder()
            .setMediaId(mediaId)
            .setUri(streamUrl)
            .setMediaMetadata(metadataBuilder.build())
            .setMimeType(mimeTypeFor(originalUrlForMimeDetection))
            .build()
    }

    private fun mimeTypeFor(url: String): String = when {
        url.contains(".m4a", ignoreCase = true) -> "audio/mp4"
        url.contains(".mp3", ignoreCase = true) -> "audio/mpeg"
        url.contains(".webm", ignoreCase = true) -> "audio/webm"
        else -> "audio/mp4"
    }

    fun release() {
        castContext?.removeCastStateListener(castStateListener)
        castContext?.sessionManager?.removeSessionManagerListener(
            sessionManagerListener, CastSession::class.java,
        )
        router?.removeCallback(pickerScanCallback)
        stopCastStateDiscovery()
        castPlayer?.setSessionAvailabilityListener(null)
        castPlayer?.release()
        relayServer.stop()
        onStateChanged = null
        onSessionStarted = null
        onSessionEnded = null
        onRoutesChanged = null
    }
}
