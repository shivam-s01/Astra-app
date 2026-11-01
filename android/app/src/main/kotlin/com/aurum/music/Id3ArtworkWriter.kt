// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import java.io.ByteArrayOutputStream
import java.io.File

object Id3ArtworkWriter {
    private const val TAG_ID = "ID3"
    private const val FRAME_ID_APIC = "APIC"

    fun embedCoverArt(file: File, artworkBytes: ByteArray, mimeType: String = "image/jpeg"): Boolean {
        return try {
            val original = file.readBytes()

            val looksLikeMp3 =
                (original.size >= 3 &&
                    original[0] == 'I'.code.toByte() &&
                    original[1] == 'D'.code.toByte() &&
                    original[2] == '3'.code.toByte()) ||
                (original.size >= 2 &&
                    (original[0].toInt() and 0xFF) == 0xFF &&
                    (original[1].toInt() and 0xE0) == 0xE0)

            if (looksLikeMp3) {
                embedIntoMp3(file, original, artworkBytes, mimeType)
            } else {
                embedIntoMp4Safely(file, original, artworkBytes, mimeType)
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun embedIntoMp3(file: File, original: ByteArray, artworkBytes: ByteArray, mimeType: String): Boolean {
        return try {
            val apicFrame = buildApicFrame(artworkBytes, mimeType)

            val existingTagSize = existingId3v2TagSize(original)
            val output = ByteArrayOutputStream(original.size + apicFrame.size + 64)

            if (existingTagSize > 0) {
                val oldFrames = original.copyOfRange(10, existingTagSize)
                val newFramesSize = oldFrames.size + apicFrame.size

                output.write(TAG_ID.toByteArray(Charsets.ISO_8859_1))
                output.write(byteArrayOf(0x03, 0x00))
                output.write(byteArrayOf(0x00))
                output.write(synchsafe(newFramesSize))
                output.write(oldFrames)
                output.write(apicFrame)
                output.write(original.copyOfRange(existingTagSize, original.size))
            } else {
                output.write(TAG_ID.toByteArray(Charsets.ISO_8859_1))
                output.write(byteArrayOf(0x03, 0x00))
                output.write(byteArrayOf(0x00))
                output.write(synchsafe(apicFrame.size))
                output.write(apicFrame)
                output.write(original)
            }

            file.writeBytes(output.toByteArray())
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun existingId3v2TagSize(bytes: ByteArray): Int {
        if (bytes.size < 10) return 0
        if (bytes[0] != 'I'.code.toByte() || bytes[1] != 'D'.code.toByte() || bytes[2] != '3'.code.toByte()) {
            return 0
        }
        val size = unsynchsafe(bytes, 6)
        return if (size in 1..bytes.size) 10 + size else 0
    }

    private fun synchsafe(size: Int): ByteArray {
        return byteArrayOf(
            ((size ushr 21) and 0x7F).toByte(),
            ((size ushr 14) and 0x7F).toByte(),
            ((size ushr 7) and 0x7F).toByte(),
            (size and 0x7F).toByte(),
        )
    }

    private fun unsynchsafe(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0x7F) shl 21) or
            ((bytes[offset + 1].toInt() and 0x7F) shl 14) or
            ((bytes[offset + 2].toInt() and 0x7F) shl 7) or
            (bytes[offset + 3].toInt() and 0x7F)
    }

    private fun buildApicFrame(artworkBytes: ByteArray, mimeType: String): ByteArray {
        val body = ByteArrayOutputStream(artworkBytes.size + 32)
        body.write(0x00)
        body.write(mimeType.toByteArray(Charsets.ISO_8859_1))
        body.write(0x00)
        body.write(0x03)
        body.write(0x00)
        body.write(artworkBytes)

        val bodyBytes = body.toByteArray()
        val frame = ByteArrayOutputStream(bodyBytes.size + 10)
        frame.write(FRAME_ID_APIC.toByteArray(Charsets.ISO_8859_1))
        frame.write((bodyBytes.size ushr 24) and 0xFF)
        frame.write((bodyBytes.size ushr 16) and 0xFF)
        frame.write((bodyBytes.size ushr 8) and 0xFF)
        frame.write(bodyBytes.size and 0xFF)
        frame.write(byteArrayOf(0x00, 0x00))
        frame.write(bodyBytes)
        return frame.toByteArray()
    }

    private fun embedIntoMp4Safely(file: File, original: ByteArray, artworkBytes: ByteArray, mimeType: String): Boolean {
        return try {
            val boxes = readTopLevelBoxes(original) ?: return false
            val moov = boxes.firstOrNull { it.type == "moov" } ?: return false
            val mdat = boxes.firstOrNull { it.type == "mdat" } ?: return false

            if (moov.offset < mdat.offset) return false

            val moovChildren = readTopLevelBoxes(
                original.copyOfRange(moov.offset + 8, moov.offset + moov.size)
            ) ?: return false
            if (moovChildren.any { it.type == "udta" }) return false

            val typeIndicator = if (mimeType.contains("png", ignoreCase = true)) 14 else 13
            val dataPayload = ByteArrayOutputStream(artworkBytes.size + 8).apply {
                write(byteArrayOf(0x00, 0x00, 0x00, typeIndicator.toByte()))
                write(byteArrayOf(0x00, 0x00, 0x00, 0x00))
                write(artworkBytes)
            }.toByteArray()
            val dataBox = mp4Box("data", dataPayload)
            val covrBox = mp4Box("covr", dataBox)
            val ilstBox = mp4Box("ilst", covrBox)

            val hdlrPayload = ByteArrayOutputStream(32).apply {
                write(byteArrayOf(0x00, 0x00, 0x00, 0x00))
                write(byteArrayOf(0x00, 0x00, 0x00, 0x00))
                write("mdir".toByteArray(Charsets.US_ASCII))
                write(ByteArray(12))
                write(0x00)
            }.toByteArray()
            val hdlrBox = mp4Box("hdlr", hdlrPayload)

            val metaPayload = ByteArrayOutputStream(hdlrBox.size + ilstBox.size + 4).apply {
                write(byteArrayOf(0x00, 0x00, 0x00, 0x00))
                write(hdlrBox)
                write(ilstBox)
            }.toByteArray()
            val metaBox = mp4Box("meta", metaPayload)
            val udtaBox = mp4Box("udta", metaBox)

            val insertAt = moov.offset + moov.size
            val output = ByteArrayOutputStream(original.size + udtaBox.size)
            output.write(original, 0, insertAt)
            output.write(udtaBox)
            output.write(original, insertAt, original.size - insertAt)
            val result = output.toByteArray()

            val newMoovSize = moov.size + udtaBox.size
            result[moov.offset] = ((newMoovSize ushr 24) and 0xFF).toByte()
            result[moov.offset + 1] = ((newMoovSize ushr 16) and 0xFF).toByte()
            result[moov.offset + 2] = ((newMoovSize ushr 8) and 0xFF).toByte()
            result[moov.offset + 3] = (newMoovSize and 0xFF).toByte()

            file.writeBytes(result)
            true
        } catch (e: Exception) {
            false
        }
    }

    private data class Mp4Box(val type: String, val offset: Int, val size: Int)

    private fun readTopLevelBoxes(bytes: ByteArray): List<Mp4Box>? {
        val boxes = mutableListOf<Mp4Box>()
        var pos = 0
        while (pos + 8 <= bytes.size) {
            val size = ((bytes[pos].toInt() and 0xFF) shl 24) or
                ((bytes[pos + 1].toInt() and 0xFF) shl 16) or
                ((bytes[pos + 2].toInt() and 0xFF) shl 8) or
                (bytes[pos + 3].toInt() and 0xFF)
            if (size < 8 || pos + size > bytes.size) return null
            val type = String(bytes, pos + 4, 4, Charsets.US_ASCII)
            boxes.add(Mp4Box(type, pos, size))
            pos += size
        }
        return boxes
    }

    private fun mp4Box(type: String, payload: ByteArray): ByteArray {
        val size = payload.size + 8
        val box = ByteArrayOutputStream(size)
        box.write((size ushr 24) and 0xFF)
        box.write((size ushr 16) and 0xFF)
        box.write((size ushr 8) and 0xFF)
        box.write(size and 0xFF)
        box.write(type.toByteArray(Charsets.US_ASCII))
        box.write(payload)
        return box.toByteArray()
    }
}
