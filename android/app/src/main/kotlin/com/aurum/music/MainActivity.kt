// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.content.ComponentName
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.util.Log
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val CHANNEL = "com.aurum.music/media_store"
        private const val TAG = "AurumMainActivity"
        private val ALBUM_ART_URI = Uri.parse("content://media/external/audio/albumart")
        private const val MIN_SIZE_BYTES = 500_000L
    }

    private var methodChannel: MethodChannel? = null

    private var voiceChannel: MethodChannel? = null
    private var pendingVoiceQuery: String? = null

    private var audioEngineChannelHandler: AurumEngineChannelHandler? = null

    private var relatedChannelHandler: AurumRelatedChannelHandler? = null

    private var batteryChannelHandler: AurumBatteryChannelHandler? = null

    private var mediaSessionServiceConnection: ServiceConnection? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen()

        super.onCreate(savedInstanceState)
        AurumDiagnosticLog.init(this)
        val enabled = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getBoolean("flutter.high_refresh_rate", false)
        applyHighRefreshRate(enabled)
        captureVoiceIntent(intent, push = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureVoiceIntent(intent, push = true)
    }

    private fun captureVoiceIntent(intent: Intent?, push: Boolean) {
        if (intent?.action != "android.media.action.MEDIA_PLAY_FROM_SEARCH") return
        val q = (intent.getStringExtra(VoiceBridge.EXTRA_PAYLOAD)
            ?: VoiceBridge.payload(intent.getStringExtra(android.app.SearchManager.QUERY), intent.extras)).trim()
        if (q.isEmpty() || q.length > 1000) return
        pendingVoiceQuery = q
        if (push) {
            voiceChannel?.invokeMethod("voicePlay", q, object : MethodChannel.Result {
                override fun success(result: Any?) { pendingVoiceQuery = null }
                override fun error(code: String, msg: String?, details: Any?) {}
                override fun notImplemented() {}
            })
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        audioEngineChannelHandler = AurumEngineChannelHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        bindMediaSessionService()

        relatedChannelHandler = AurumRelatedChannelHandler(flutterEngine.dartExecutor.binaryMessenger)

        batteryChannelHandler = AurumBatteryChannelHandler(this, flutterEngine.dartExecutor.binaryMessenger)

        voiceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.aurum.music/voice").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "getPending") {
                    val q = pendingVoiceQuery ?: VoiceBridge.take()
                    pendingVoiceQuery = null
                    VoiceBridge.pending = null
                    result.success(q)
                } else result.notImplemented()
            }
        }

        VoiceBridge.sink = { q ->
            voiceChannel?.invokeMethod("voicePlay", q, object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(code: String, msg: String?, details: Any?) {}
                override fun notImplemented() { VoiceBridge.pending = q }
            })
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { methodChannel = it }
        methodChannel!!
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSongs" -> {
                        try {
                            result.success(getSongs())
                        } catch (e: Exception) {
                            Log.e(TAG, "getSongs error", e)
                            result.error("GET_SONGS_ERROR", e.message, null)
                        }
                    }
                    "getSdkInt" -> {
                        result.success(Build.VERSION.SDK_INT)
                    }
                    "getDiagnosticLogPath" -> {
                        try {
                            val file = AurumDiagnosticLog.getLogFile(this)
                            result.success(if (file.exists()) file.absolutePath else null)
                        } catch (e: Exception) {
                            Log.e(TAG, "getDiagnosticLogPath error", e)
                            result.error("DIAG_LOG_ERROR", e.message, null)
                        }
                    }
                    "clearDiagnosticLog" -> {
                        AurumDiagnosticLog.clear(this)
                        result.success(null)
                    }
                    "logNetworkError" -> {
                        val ctx = call.argument<String>("context") ?: "unknown"
                        val msg = call.argument<String>("message") ?: ""
                        AurumDiagnosticLog.logNetworkError(ctx, msg)
                        result.success(null)
                    }
                    "openAutostartSettings" -> {
                        result.success(openAutostartSettings())
                    }

                "installApk" -> {
                    try {
                        val apkPath = call.argument<String>("path") ?: run { result.error("NO_PATH", "No path", null); return@setMethodCallHandler }
                        AurumSilentInstaller.install(this, apkPath) { success, message ->
                            runOnUiThread {
                                methodChannel?.invokeMethod(
                                    "onInstallResult",
                                    mapOf("success" to success, "message" to message)
                                )
                            }
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }
                "getAlbumArt" -> {
                        try {
                            val uri = call.argument<String>("uri")
                            if (uri.isNullOrEmpty()) {
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            result.success(getAlbumArtBytes(uri))
                        } catch (e: Exception) {
                            Log.w(TAG, "getAlbumArt error", e)
                            result.success(null)
                        }
                    }
                "setStopOnTaskRemoved" -> {
                        try {
                            val value = call.argument<Boolean>("value") ?: false
                            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                                .edit()
                                .putBoolean("flutter.stop_on_swipe", value)
                                .apply()
                            result.success(null)
                        } catch (e: Exception) {
                            Log.w(TAG, "setStopOnTaskRemoved error", e)
                            result.success(null)
                        }
                    }
                    "setHighRefreshRate" -> {
                        try {
                            val enabled = call.argument<Boolean>("enabled") ?: true
                            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                                .edit()
                                .putBoolean("flutter.high_refresh_rate", enabled)
                                .apply()
                            applyHighRefreshRate(enabled)
                            result.success(null)
                        } catch (e: Exception) {
                            Log.w(TAG, "setHighRefreshRate error", e)
                            result.success(null)
                        }
                    }
                    "vibrateHaptic" -> {
                        try {
                            val amplitude = call.argument<Int>("amplitude") ?: 128
                            val durationMs = call.argument<Int>("durationMs") ?: 12
                            vibrateWithAmplitude(amplitude, durationMs.toLong())
                            result.success(null)
                        } catch (e: Exception) {
                            Log.w(TAG, "vibrateHaptic error", e)
                            result.success(null)
                        }
                    }

                    "checkOverlayPermission" -> {
                        result.success(hasOverlayPermission())
                    }
                    "requestOverlayPermission" -> {
                        try {
                            requestOverlayPermission()
                            result.success(null)
                        } catch (e: Exception) {
                            Log.w(TAG, "requestOverlayPermission error", e)
                            result.error("OVERLAY_PERMISSION_ERROR", e.message, null)
                        }
                    }
                    "startIslandOverlay" -> {
                        try {
                            if (!hasOverlayPermission()) {
                                result.error("NO_OVERLAY_PERMISSION", "SYSTEM_ALERT_WINDOW not granted", null)
                                return@setMethodCallHandler
                            }
                            if (!appInForeground) {
                                startService(Intent(this, AurumIslandService::class.java))
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            Log.w(TAG, "startIslandOverlay error", e)
                            result.error("ISLAND_START_ERROR", e.message, null)
                        }
                    }
                    "stopIslandOverlay" -> {
                        try {
                            stopService(Intent(this, AurumIslandService::class.java))
                            result.success(null)
                        } catch (e: Exception) {
                            Log.w(TAG, "stopIslandOverlay error", e)
                            result.success(null)
                        }
                    }
                    "updateIslandCustomization" -> {
                        try {
                            if (AurumIslandService.isRunning) {
                                AurumIslandService.refreshCustomizationNow()
                            }
                            result.success(null)
                        } catch (e: Exception) {
                            Log.w(TAG, "updateIslandCustomization error", e)
                            result.success(null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun applyHighRefreshRate(enabled: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return

        if (!enabled) {
            window.attributes = window.attributes.apply { preferredDisplayModeId = 0 }
            return
        }
        try {
            val modes = display.supportedModes
            val currentMode = display.mode
            val best = modes
                .filter { it.physicalWidth == currentMode.physicalWidth &&
                          it.physicalHeight == currentMode.physicalHeight }
                .maxByOrNull { it.refreshRate }
            if (best != null) {
                window.attributes = window.attributes.apply { preferredDisplayModeId = best.modeId }
            }
        } catch (e: Exception) {
            Log.w(TAG, "applyHighRefreshRate error", e)
        }
    }

    private var cachedVibrator: Vibrator? = null
    private fun getVibrator(): Vibrator? {
        cachedVibrator?.let { return it }
        val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val mgr = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            mgr?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
        cachedVibrator = v
        return v
    }

    private fun vibrateWithAmplitude(amplitude: Int, durationMs: Long) {
        val vibrator = getVibrator() ?: return
        if (!vibrator.hasVibrator()) return
        val clamped = amplitude.coerceIn(1, 255)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(durationMs, clamped))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(durationMs)
        }
    }

    private fun getSongs(): List<Map<String, Any?>> {
        val songs = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.SIZE,
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.SIZE} >= $MIN_SIZE_BYTES"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} ASC"

        val cursor: Cursor? = contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection, selection, null, sortOrder
        )

        cursor?.use {
            val idCol       = it.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol    = it.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol   = it.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol    = it.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol  = it.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val durationCol = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val dataCol     = it.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)

            while (it.moveToNext()) {
                val id      = it.getLong(idCol)
                val albumId = it.getLong(albumIdCol)
                val artUri  = ContentUris.withAppendedId(ALBUM_ART_URI, albumId).toString()
                val contentUri = ContentUris.withAppendedId(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, id
                ).toString()

                songs.add(mapOf(
                    "id"         to "local_$id",
                    "title"      to it.getString(titleCol),
                    "artist"     to (it.getString(artistCol) ?: "Unknown"),
                    "album"      to (it.getString(albumCol) ?: ""),
                    "artworkUrl" to artUri,
                    "localPath"  to it.getString(dataCol),
                    "contentUri" to contentUri,
                    "duration"   to (it.getLong(durationCol) / 1000).toInt(),
                ))
            }
        }
        Log.d(TAG, "Scanned ${songs.size} songs")
        return songs
    }

    private fun getAlbumArtBytes(uriString: String): ByteArray? {
        return try {
            val uri = Uri.parse(uriString)
            val bitmap: Bitmap? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    contentResolver.loadThumbnail(uri, android.util.Size(500, 500), null)
                } catch (e: Exception) {
                    Log.w(TAG, "loadThumbnail failed, falling back: ${e.message}")
                    openStreamAsBitmap(uri)
                }
            } else {
                openStreamAsBitmap(uri)
            }
            bitmap?.let { bmp ->
                ByteArrayOutputStream().use { out ->
                    bmp.compress(Bitmap.CompressFormat.JPEG, 85, out)
                    out.toByteArray()
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "getAlbumArtBytes failed for $uriString: ${e.message}")
            null
        }
    }

    private fun openAutostartSettings(): Boolean {
        val intents = listOf(
            Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")),
            Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.startupapp.StartupAppListActivity")),
            Intent().setComponent(ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")),
            Intent().setComponent(ComponentName("com.coloros.oppoguardelf", "com.coloros.powermanager.fuelgaue.PowerConsumptionActivity")),
            Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")),
            Intent().setComponent(ComponentName("com.letv.android.letvsafe", "com.letv.android.letvsafe.AutobootManageActivity")),
            Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")),
            Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")),
            Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")),
            Intent().setComponent(ComponentName("com.asus.mobilemanager", "com.asus.mobilemanager.autostart.AutoStartActivity"))
        )
        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (packageManager.resolveActivity(intent, 0) != null) {
                    startActivity(intent)
                    return true
                }
            } catch (_: Exception) {  }
        }
        return try {
            val fallback = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallback)
            true
        } catch (e: Exception) {
            Log.e(TAG, "openAutostartSettings fallback failed", e)
            false
        }
    }

    private fun bindMediaSessionService() {
        if (mediaSessionServiceConnection != null) return
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            }
            override fun onServiceDisconnected(name: ComponentName?) {
                mediaSessionServiceConnection = null
            }
        }
        val intent = Intent(this, AurumMediaSessionService::class.java)
        startService(intent)
        bindService(intent, connection, Context.BIND_AUTO_CREATE)
        mediaSessionServiceConnection = connection
    }

    private fun hasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.provider.Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val intent = Intent(
            android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName"),
        ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        startActivity(intent)
    }

    private fun openStreamAsBitmap(uri: Uri): Bitmap? {
        val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
        return contentResolver.openInputStream(uri)?.use { stream ->
            BitmapFactory.decodeStream(stream, null, opts)
        }
    }

    private var screenUnlockReceiver: android.content.BroadcastReceiver? = null
    private var appInForeground = false

    override fun onStart() {
        super.onStart()
        appInForeground = true
        val receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action == Intent.ACTION_USER_PRESENT) {
                    AutoSleepGuard.recordActivity(ctx.applicationContext)
                }
            }
        }
        registerReceiver(receiver, android.content.IntentFilter(Intent.ACTION_USER_PRESENT))
        screenUnlockReceiver = receiver

        if (AurumIslandService.isRunning) {
            stopService(Intent(this, AurumIslandService::class.java))
        }
    }

    override fun onStop() {
        appInForeground = false
        screenUnlockReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        screenUnlockReceiver = null

        try {
            val islandEnabled = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.island_enabled", false)
            val hasSong = AurumMediaSessionService.sharedEngine?.player?.let {
                it.mediaItemCount > 0
            } ?: false
            if (islandEnabled && hasSong && hasOverlayPermission() && !AurumIslandService.isRunning) {
                startService(Intent(this, AurumIslandService::class.java))
            }
        } catch (e: Exception) {
            Log.w(TAG, "Island overlay restore on stop failed: ${e.message}")
        }

        super.onStop()
    }

    override fun onDestroy() {
        val stillPlaying = AurumMediaSessionService.sharedEngine?.player?.let {
            it.isPlaying
        } ?: false
        if (!stillPlaying) {
            try { stopService(Intent(this, AurumIslandService::class.java)) } catch (_: Exception) {}
        }
        mediaSessionServiceConnection?.let {
            try { unbindService(it) } catch (_: Exception) {}
        }
        mediaSessionServiceConnection = null
        VoiceBridge.sink = null
        audioEngineChannelHandler?.release()
        audioEngineChannelHandler = null
        batteryChannelHandler?.release()
        batteryChannelHandler = null
        super.onDestroy()
    }
}
