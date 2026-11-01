// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

object PremiumVoicing {
    private const val BASS_SHELF_DB = 2.4f
    private const val WIDEN = 0.32f
    private const val MAKEUP_DB = 1.5f
    private const val REVERB = 0.30f

    private val BAND_DB = floatArrayOf(0.8f, -1.2f, -0.4f, -1.6f, -3.2f)

    private val LOWBR_DB = floatArrayOf(0.0f, 0.0f, 0.2f, -0.4f, -1.2f)
    private const val KBPS_FULL = 96
    private const val KBPS_NONE = 192

    fun lowBitrateScale(kbps: Int): Float = when {
        kbps <= 0 || kbps >= KBPS_NONE -> 0f
        kbps <= KBPS_FULL -> 1f
        else -> 1f - (kbps - KBPS_FULL).toFloat() / (KBPS_NONE - KBPS_FULL).toFloat()
    }

    fun paramsFor(enabled: Boolean, intensity: Float, kbps: Int): AurumDspCore.Params {
        if (!enabled) return AurumDspCore.Params()
        val i = if (intensity.isFinite()) intensity.coerceIn(0f, 1f) else 1f
        val lowBr = lowBitrateScale(kbps)
        val bands = FloatArray(AurumDspCore.BANDS) { b ->
            BAND_DB[b] * i + LOWBR_DB[b] * lowBr
        }
        return AurumDspCore.Params(
            bandDb = bands,
            bassShelfDb = BASS_SHELF_DB * i,
            widen = WIDEN * i,
            makeupDb = MAKEUP_DB * i,
            reverb = REVERB * i,
        )
    }
}
