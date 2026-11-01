// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.util.LruCache
import java.net.URL

object ArtworkBytesCache {
    private val cache = object : LruCache<String, ByteArray>(6 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ByteArray): Int = value.size
    }

    fun fetch(urlString: String, connectTimeoutMs: Int, readTimeoutMs: Int): ByteArray? {
        cache.get(urlString)?.let { return it }
        val bytes = URL(urlString).openConnection().apply {
            connectTimeout = connectTimeoutMs
            readTimeout = readTimeoutMs
        }.getInputStream().use { it.readBytes() }
        if (bytes.isNotEmpty() && bytes.size < 2 * 1024 * 1024) cache.put(urlString, bytes)
        return bytes
    }
}
