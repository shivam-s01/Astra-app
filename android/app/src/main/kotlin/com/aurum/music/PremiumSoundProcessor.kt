// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.min

@UnstableApi
class PremiumSoundProcessor : BaseAudioProcessor() {
    companion object {
        private const val BLOCK_FRAMES = 2048
        private const val INV_32768 = 1f / 32768f
        private const val LOG_TAG = "PREMIUM_DSP"

        private const val FADE_MS = 150.0
    }

    private val core = AurumDspCore(smoothMs = FADE_MS)
    private val block = FloatArray(BLOCK_FRAMES * 2)
    private var tailPending = false
    private var rng = 0x2545F491

    @Volatile private var wantedEnabled = false
    @Volatile private var wantedIntensity = 1f
    @Volatile private var wantedKbps = 0

    private var loggedFirstBuffer = false

    fun setParams(enabled: Boolean, intensity: Float, sourceKbps: Int) {
        val changed = enabled != wantedEnabled
        wantedEnabled = enabled
        wantedIntensity = intensity
        wantedKbps = sourceKbps
        core.setParams(PremiumVoicing.paramsFor(enabled, intensity, sourceKbps))
        if (changed) {
            diag("setParams enabled=$enabled intensity=${"%.2f".format(intensity)} kbps=$sourceKbps")
            loggedFirstBuffer = false
        }
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val encodingOk = inputAudioFormat.encoding == C.ENCODING_PCM_16BIT ||
            inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        val channelsOk = inputAudioFormat.channelCount in 1..2
        val rateOk = inputAudioFormat.sampleRate in 8000..384000
        if (!encodingOk || !channelsOk || !rateOk) {
            diag(
                "NOT processing this stream: encoding=${inputAudioFormat.encoding} " +
                    "channels=${inputAudioFormat.channelCount} rate=${inputAudioFormat.sampleRate}",
            )
            return AudioProcessor.AudioFormat.NOT_SET
        }
        core.configure(inputAudioFormat.sampleRate, inputAudioFormat.channelCount)
        loggedFirstBuffer = false
        diag(
            "configured rate=${inputAudioFormat.sampleRate} channels=${inputAudioFormat.channelCount} " +
                "encoding=${if (inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT) "float" else "pcm16"} " +
                "premiumWanted=$wantedEnabled",
        )
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        if (!inputBuffer.hasRemaining()) return
        val fmt = inputAudioFormat
        val ch = fmt.channelCount
        val isFloat = fmt.encoding == C.ENCODING_PCM_FLOAT
        val bytesPerFrame = fmt.bytesPerFrame
        val totalFrames = inputBuffer.remaining() / bytesPerFrame

        val out = replaceOutputBuffer(totalFrames * bytesPerFrame)
        val savedOrder = inputBuffer.order()
        inputBuffer.order(ByteOrder.nativeOrder())
        var left = totalFrames
        while (left > 0) {
            val n = min(left, BLOCK_FRAMES)
            val samples = n * ch
            if (isFloat) {
                for (i in 0 until samples) block[i] = inputBuffer.getFloat()
            } else {
                for (i in 0 until samples) block[i] = inputBuffer.getShort() * INV_32768
            }
            val written = core.process(block, n)
            if (written > 0) writeSamples(out, written * ch, isFloat, core.lastCallActive)
            left -= n
        }
        inputBuffer.order(savedOrder)
        inputBuffer.position(inputBuffer.limit())
        out.flip()

        if (wantedEnabled && !loggedFirstBuffer && core.lastCallActive) {
            loggedFirstBuffer = true
            diag("DSP is shaping the audio (first processed buffer after enable)")
        }
    }

    override fun onQueueEndOfStream() {
        tailPending = core.pendingFrames > 0
    }

    override fun getOutput(): ByteBuffer {
        if (tailPending && !hasPendingOutput()) {
            tailPending = false
            emitTail()
        }
        return super.getOutput()
    }

    override fun isEnded(): Boolean = super.isEnded() && !tailPending

    override fun onFlush() {
        tailPending = false
        core.reset()
    }

    override fun onReset() {
        tailPending = false
        core.reset()
    }

    private fun emitTail() {
        val fmt = inputAudioFormat
        val ch = fmt.channelCount
        val pending = core.pendingFrames
        if (pending <= 0) return
        val data = FloatArray(pending * ch)
        val written = core.process(data, pending, flushing = true)
        if (written <= 0) return
        val out = replaceOutputBuffer(written * fmt.bytesPerFrame)
        System.arraycopy(data, 0, block, 0, min(data.size, block.size))
        writeSamples(out, written * ch, fmt.encoding == C.ENCODING_PCM_FLOAT, core.lastCallActive)
        out.flip()
    }

    private fun writeSamples(out: ByteBuffer, count: Int, isFloat: Boolean, dither: Boolean) {
        if (isFloat) {
            for (i in 0 until count) out.putFloat(block[i].coerceIn(-1f, 1f))
        } else {
            for (i in 0 until count) {
                var v = block[i] * 32768f
                if (dither) v += nextRand() - nextRand()
                val r = Math.round(v)
                out.putShort((if (r > 32767) 32767 else if (r < -32768) -32768 else r).toShort())
            }
        }
    }

    private fun nextRand(): Float {
        var x = rng
        x = x xor (x shl 13)
        x = x xor (x ushr 17)
        x = x xor (x shl 5)
        rng = x
        return (x ushr 8) * (1f / 16777216f)
    }

    private fun diag(message: String) {
        try {
            AurumDiagnosticLog.logEvent(LOG_TAG, message)
        } catch (_: Throwable) {
        }
    }
}
