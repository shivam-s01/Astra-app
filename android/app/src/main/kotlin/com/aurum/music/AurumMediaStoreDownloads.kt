// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

object AurumMediaStoreDownloads {
    private const val RELATIVE_DIR = "Music/Astra"

    fun saveToPublicMusic(
        context: Context,
        sourceFile: File,
        displayName: String,
        mimeType: String = "audio/mpeg",
        artworkBytes: ByteArray? = null,
    ): String? {
        return try {
            if (artworkBytes != null && artworkBytes.isNotEmpty()) {
                Id3ArtworkWriter.embedCoverArt(sourceFile, artworkBytes)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveViaMediaStore(context, sourceFile, displayName, mimeType)
            } else {
                saveViaLegacyPublicDir(sourceFile, displayName)
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun saveViaMediaStore(
        context: Context,
        sourceFile: File,
        displayName: String,
        mimeType: String,
    ): String? {
        val resolver = context.contentResolver
        val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
            put(MediaStore.Audio.Media.RELATIVE_PATH, RELATIVE_DIR)
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }

        val itemUri = resolver.insert(collection, values) ?: return null

        try {
            resolver.openOutputStream(itemUri)?.use { out ->
                sourceFile.inputStream().use { input -> input.copyTo(out) }
            } ?: run {
                resolver.delete(itemUri, null, null)
                return null
            }
        } catch (e: Exception) {
            try { resolver.delete(itemUri, null, null) } catch (_: Exception) {}
            return null
        }

        try {
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            resolver.update(itemUri, values, null, null)
        } catch (e: Exception) {
            try { resolver.delete(itemUri, null, null) } catch (_: Exception) {}
            return null
        }

        try { sourceFile.delete() } catch (_: Exception) {}

        return itemUri.toString()
    }

    private fun saveViaLegacyPublicDir(sourceFile: File, displayName: String): String? {
        val musicDir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
            "Astra",
        )
        if (!musicDir.exists()) musicDir.mkdirs()
        val safeName = File(displayName).name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        if (safeName.isBlank() || safeName == "." || safeName == "..") return null
        val destFile = File(musicDir, safeName)
        try {
            sourceFile.copyTo(destFile, overwrite = true)
        } catch (e: Exception) {
            try { if (destFile.exists()) destFile.delete() } catch (_: Exception) {}
            return null
        }
        try { sourceFile.delete() } catch (_: Exception) {}
        return destFile.absolutePath
    }

    fun delete(context: Context, pathOrUri: String): Boolean {
        return try {
            if (pathOrUri.startsWith("content://")) {
                val uri = Uri.parse(pathOrUri)
                val rows = context.contentResolver.delete(uri, null, null)
                rows > 0
            } else {
                val f = File(pathOrUri)
                if (!f.exists()) true
                else f.delete()
            }
        } catch (e: Exception) {
            false
        }
    }

    fun exists(context: Context, pathOrUri: String): Boolean {
        return try {
            if (pathOrUri.startsWith("content://")) {
                val uri = Uri.parse(pathOrUri)
                context.contentResolver.openInputStream(uri)?.use { true } ?: false
            } else {
                File(pathOrUri).exists()
            }
        } catch (e: Exception) {
            false
        }
    }
}
