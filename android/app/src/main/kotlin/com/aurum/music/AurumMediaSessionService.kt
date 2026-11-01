// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

private const val VOICE_NOOP_ID = "aurum_voice_noop"
private val VOICE_NOOP_ITEM: MediaItem = MediaItem.Builder().setMediaId(VOICE_NOOP_ID).build()

class AurumMediaSessionService : MediaSessionService() {
    companion object {
        private const val LIKE_ACTION = "com.aurum.music.ACTION_TOGGLE_LIKE"
        private const val NOTIFICATION_CHANNEL_ID = "aurum_playback"
        private const val NOTIFICATION_ID = 1001

        var sharedEngine: AurumAudioEngine? = null

        var instance: AurumMediaSessionService? = null
    }

    private var mediaSession: MediaSession? = null
    private var notificationProvider: androidx.media3.session.DefaultMediaNotificationProvider? = null
    private val likeCommand = SessionCommand(LIKE_ACTION, Bundle.EMPTY)

    override fun onCreate() {
        super.onCreate()
        instance = this

        notificationProvider = androidx.media3.session.DefaultMediaNotificationProvider
            .Builder(this)
            .setChannelId(NOTIFICATION_CHANNEL_ID)
            .setChannelName(androidx.media3.session.R.string.default_notification_channel_name)
            .build()
        setMediaNotificationProvider(notificationProvider!!)
        createNotificationChannelIfNeeded()

        val engine = sharedEngine ?: run {
            stopSelf()
            return
        }

        val likeButton = CommandButton.Builder()
            .setDisplayName(if (engine.isCurrentSongLiked()) "Unlike" else "Like")
            .setSessionCommand(likeCommand)
            .setIconResId(
                if (engine.isCurrentSongLiked()) R.drawable.ic_like_filled
                else R.drawable.ic_like_outline
            )
            .build()

        val sessionActivityIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.let { intent ->
                PendingIntent.getActivity(
                    this, 0, intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            }

        val callback = object : MediaSession.Callback {
            override fun onConnect(
                session: MediaSession,
                controller: MediaSession.ControllerInfo,
            ): MediaSession.ConnectionResult {
                val result = MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                    .setAvailableSessionCommands(
                        MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS
                            .buildUpon()
                            .add(likeCommand)
                            .build()
                    )
                    .build()
                return result
            }

            override fun onPlaybackResumption(
                mediaSession: MediaSession,
                controller: MediaSession.ControllerInfo,
            ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
                return Futures.immediateFailedFuture(UnsupportedOperationException(
                    "Playback resumption disabled — Aurum always starts playback via Dart's playSong/playQueue"
                ))
            }

            override fun onSetMediaItems(
                mediaSession: MediaSession,
                controller: MediaSession.ControllerInfo,
                mediaItems: MutableList<MediaItem>,
                startIndex: Int,
                startPositionMs: Long,
            ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
                if (mediaItems.isNotEmpty() && mediaItems.all { it.localConfiguration == null }) {
                    val q = mediaItems.firstNotNullOfOrNull { it.requestMetadata.searchQuery }
                    val extras = mediaItems.firstNotNullOfOrNull { it.requestMetadata.extras }
                    val payload = VoiceBridge.payload(q, extras)
                    if (payload.isNotBlank()) {
                        VoiceBridge.dispatch(applicationContext, payload)
                    } else if (mediaSession.player.mediaItemCount == 0) {
                        VoiceBridge.dispatch(applicationContext, "liked songs")
                    }
                    return Futures.immediateFuture(
                        MediaSession.MediaItemsWithStartPosition(
                            listOf(VOICE_NOOP_ITEM), 0, 0L
                        )
                    )
                }
                return super.onSetMediaItems(mediaSession, controller, mediaItems, startIndex, startPositionMs)
            }

            override fun onPostConnect(session: MediaSession, controller: MediaSession.ControllerInfo) {
                super.onPostConnect(session, controller)
                session.setCustomLayout(ImmutableList.of(likeButton))
            }

            override fun onCustomCommand(
                session: MediaSession,
                controller: MediaSession.ControllerInfo,
                customCommand: SessionCommand,
                args: Bundle,
            ): ListenableFuture<SessionResult> {
                if (customCommand.customAction == LIKE_ACTION) {
                    engine.triggerLikeToggle()
                }
                return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
            }
        }

        val sessionPlayer = object : androidx.media3.common.ForwardingPlayer(engine.player) {
            override fun getAvailableCommands(): Player.Commands {
                val b = super.getAvailableCommands().buildUpon()
                if (engine.canSkipNext()) {
                    b.add(Player.COMMAND_SEEK_TO_NEXT)
                    b.add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                }
                if (engine.canSkipPrevious()) {
                    b.add(Player.COMMAND_SEEK_TO_PREVIOUS)
                    b.add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                }
                return b.build()
            }
            private fun isVoiceNoop(items: List<MediaItem>) =
                items.size == 1 && items[0].mediaId == VOICE_NOOP_ID
            override fun setMediaItems(mediaItems: MutableList<MediaItem>) {
                if (!isVoiceNoop(mediaItems)) super.setMediaItems(mediaItems)
            }
            override fun setMediaItems(mediaItems: MutableList<MediaItem>, resetPosition: Boolean) {
                if (!isVoiceNoop(mediaItems)) super.setMediaItems(mediaItems, resetPosition)
            }
            override fun setMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long) {
                if (!isVoiceNoop(mediaItems)) super.setMediaItems(mediaItems, startIndex, startPositionMs)
            }
            override fun isCommandAvailable(command: Int): Boolean =
                getAvailableCommands().contains(command)
            override fun hasNextMediaItem(): Boolean =
                super.hasNextMediaItem() || engine.canSkipNext()
            override fun hasPreviousMediaItem(): Boolean =
                super.hasPreviousMediaItem() || engine.canSkipPrevious()
            override fun play() {
                if (VoiceBridge.voiceJustRequested()) return
                super.play()
            }
            override fun setPlayWhenReady(playWhenReady: Boolean) {
                if (playWhenReady && VoiceBridge.voiceJustRequested()) return
                super.setPlayWhenReady(playWhenReady)
            }
            override fun seekToNext() { engine.skipToNext() }
            override fun seekToNextMediaItem() { engine.skipToNext() }
            override fun seekToPrevious() { engine.skipToPrevious() }
            override fun seekToPreviousMediaItem() { engine.skipToPrevious() }
        }

        val sessionBuilder = MediaSession.Builder(this, sessionPlayer)
            .setCallback(callback)
        if (sessionActivityIntent != null) {
            sessionBuilder.setSessionActivity(sessionActivityIntent)
        }
        mediaSession = sessionBuilder.build()

        val placeholderNotification = androidx.core.app.NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle("Aurum")
            .setContentText("Loading…")
            .setSmallIcon(R.drawable.ic_like_outline)
            .setOngoing(true)
            .setVisibility(androidx.core.app.NotificationCompat.VISIBILITY_PUBLIC)
            .setStyle(
                androidx.media3.session.MediaStyleNotificationHelper
                    .MediaStyle(mediaSession!!)
            )
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                placeholderNotification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, placeholderNotification)
        }

        addSession(mediaSession!!)

        engine.player.addListener(object : Player.Listener {
            override fun onMediaMetadataChanged(mediaMetadata: androidx.media3.common.MediaMetadata) {
                refreshLikeButton(engine)
                AurumWidgetProvider.refreshAll(this@AurumMediaSessionService)
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                AurumWidgetProvider.refreshAll(this@AurumMediaSessionService)
                AutoSleepGuard.onPlaybackStateChanged(this@AurumMediaSessionService, isPlaying)
            }

            override fun onPositionDiscontinuity(
                oldPosition: Player.PositionInfo,
                newPosition: Player.PositionInfo,
                reason: Int,
            ) {
                if (reason == Player.DISCONTINUITY_REASON_SEEK) {
                    AutoSleepGuard.recordActivity(this@AurumMediaSessionService)
                }
            }
        })

        AurumWidgetProvider.refreshAll(this)
    }

    private fun createNotificationChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Playback",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        manager.createNotificationChannel(channel)
    }

    private fun refreshLikeButton(engine: AurumAudioEngine) {
        val session = mediaSession ?: return
        val liked = engine.isCurrentSongLiked()
        val button = CommandButton.Builder()
            .setDisplayName(if (liked) "Unlike" else "Like")
            .setSessionCommand(likeCommand)
            .setIconResId(
                if (liked) R.drawable.ic_like_filled else R.drawable.ic_like_outline
            )
            .build()
        session.setCustomLayout(ImmutableList.of(button))
    }

    fun onLikedStateChanged() {
        sharedEngine?.let { refreshLikeButton(it) }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = mediaSession?.player
        val isActivelyPlaying = player != null && player.playWhenReady && player.mediaItemCount > 0
        if (!isActivelyPlaying) {
            try {
                AurumWidgetProvider.refreshAll(this)
            } catch (e: Exception) {
                Log.e("AurumMediaSessionService", "Widget refresh on task removed failed: ${e.message}", e)
            }
            stopSelf()
        } else if (readStopOnSwipePref()) {
            player?.stop()
            try {
                AurumWidgetProvider.clearArtworkCache()
                AurumWidgetProvider.refreshAll(this)
            } catch (e: Exception) {
                Log.e("AurumMediaSessionService", "Widget refresh on swipe-stop failed: ${e.message}", e)
            }
            stopSelf()
        }
        super.onTaskRemoved(rootIntent)
    }

    private fun readStopOnSwipePref(): Boolean {
        return try {
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.stop_on_swipe", false)
        } catch (e: Exception) {
            false
        }
    }

    override fun onDestroy() {
        mediaSession?.run {
            removeSession(this)
            player.release()
            release()
            mediaSession = null
        }
        AurumMediaSessionService.sharedEngine?.release()
        instance = null
        if (AurumMediaSessionService.sharedEngine != null) {
            AurumMediaSessionService.sharedEngine = null
        }
        try {
            AurumWidgetProvider.clearArtworkCache()
            AurumWidgetProvider.refreshAll(this)
        } catch (e: Exception) {
            Log.e("AurumMediaSessionService", "Widget cache clear on destroy failed: ${e.message}", e)
        }
        super.onDestroy()
    }
}
