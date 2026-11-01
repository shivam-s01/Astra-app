// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.app.SearchManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import org.json.JSONObject

object VoiceBridge {
    const val EXTRA_PAYLOAD = "aurum_voice_payload"

    @Volatile var pending: String? = null
    @Volatile var sink: ((String) -> Unit)? = null
    @Volatile private var lastVoiceAt: Long = 0L

    fun markVoice() { lastVoiceAt = SystemClock.elapsedRealtime() }

    fun voiceJustRequested(windowMs: Long = 2000L): Boolean {
        val t = lastVoiceAt
        return t != 0L && SystemClock.elapsedRealtime() - t < windowMs
    }

    fun payload(query: String?, extras: Bundle?): String {
        fun str(key: String): String =
            try { extras?.getString(key)?.trim().orEmpty() } catch (_: Exception) { "" }

        val focusRaw = str("android.intent.extra.focus").lowercase()
        val focus = when {
            focusRaw.contains("artist") -> "artist"
            focusRaw.contains("album") -> "album"
            focusRaw.contains("playlist") -> "playlist"
            focusRaw.contains("genre") -> "genre"
            focusRaw.contains("audio") -> "song"
            else -> "any"
        }
        val q = (query?.takeIf { it.isNotBlank() } ?: str(SearchManager.QUERY)).trim()
        val title = str("android.intent.extra.title")
        val artist = str("android.intent.extra.artist")
        val album = str("android.intent.extra.album")
        val genre = str("android.intent.extra.genre")
        val playlist = str("android.intent.extra.playlist")

        if (q.isEmpty() && title.isEmpty() && artist.isEmpty() && album.isEmpty() &&
            genre.isEmpty() && playlist.isEmpty()) return ""

        val o = JSONObject()
        o.put("focus", focus)
        if (q.isNotEmpty()) o.put("q", q)
        if (title.isNotEmpty()) o.put("title", title)
        if (artist.isNotEmpty()) o.put("artist", artist)
        if (album.isNotEmpty()) o.put("album", album)
        if (genre.isNotEmpty()) o.put("genre", genre)
        if (playlist.isNotEmpty()) o.put("playlist", playlist)
        return o.toString()
    }

    fun dispatch(ctx: Context, payload: String) {
        markVoice()
        val s = sink
        if (s != null) {
            Handler(Looper.getMainLooper()).post { s(payload) }
            return
        }
        pending = payload
        try {
            ctx.startActivity(
                Intent(ctx, MainActivity::class.java).apply {
                    action = "android.media.action.MEDIA_PLAY_FROM_SEARCH"
                    putExtra(EXTRA_PAYLOAD, payload)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
            )
        } catch (_: Exception) {}
    }

    fun take(): String? { val q = pending; pending = null; return q }
}
