// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileInputStream

object AurumSilentInstaller {
    private const val TAG = "AurumSilentInstaller"
    private const val ACTION_INSTALL_RESULT = "com.aurum.music.INSTALL_RESULT"

    private var pendingCallback: ((success: Boolean, message: String) -> Unit)? = null
    private var receiver: BroadcastReceiver? = null

    fun install(context: Context, apkPath: String, onResult: (Boolean, String) -> Unit) {
        val appContext = context.applicationContext
        pendingCallback = onResult

        try {
            val packageInstaller = appContext.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL
            ).apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                }
                setAppPackageName(appContext.packageName)
            }

            val sessionId = packageInstaller.createSession(params)
            val session = packageInstaller.openSession(sessionId)

            val apkFile = File(apkPath)
            if (!apkFile.exists() || apkFile.length() < 1024 * 1024) {
                session.abandon()
                onResult(false, "Downloaded update file is missing or incomplete")
                pendingCallback = null
                return
            }

            session.openWrite("aurum_update", 0, apkFile.length()).use { out ->
                FileInputStream(apkFile).use { input ->
                    input.copyTo(out)
                }
                session.fsync(out)
            }

            registerResultReceiver(appContext)

            val intent = Intent(ACTION_INSTALL_RESULT).apply {
                setPackage(appContext.packageName)
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getBroadcast(
                appContext, sessionId, intent, flags
            )

            session.commit(pendingIntent.intentSender)
            session.close()
        } catch (e: Exception) {
            Log.e(TAG, "Silent install failed, falling back", e)
            pendingCallback = null
            try {
                installViaLegacyIntent(appContext, apkPath)
                onResult(true, "Opened system installer")
            } catch (fallbackError: Exception) {
                onResult(false, fallbackError.message ?: "Install failed")
            }
        }
    }

    private fun registerResultReceiver(context: Context) {
        receiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }

        val newReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val status = intent.getIntExtra(
                    PackageInstaller.EXTRA_STATUS,
                    PackageInstaller.STATUS_FAILURE
                )
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "Unknown result"

                when (status) {
                    PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                        val confirmIntent = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                        confirmIntent?.let {
                            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            try {
                                context.startActivity(it)
                            } catch (e: Exception) {
                                pendingCallback?.invoke(false, "Could not show install prompt: ${e.message}")
                                pendingCallback = null
                                cleanup(context)
                            }
                        }
                    }
                    PackageInstaller.STATUS_SUCCESS -> {
                        pendingCallback?.invoke(true, "Updated successfully")
                        pendingCallback = null
                        cleanup(context)
                    }
                    else -> {
                        pendingCallback?.invoke(false, message)
                        pendingCallback = null
                        cleanup(context)
                    }
                }
            }
        }

        val filter = IntentFilter(ACTION_INSTALL_RESULT)
        androidx.core.content.ContextCompat.registerReceiver(
            context, newReceiver, filter,
            androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiver = newReceiver
    }

    private fun cleanup(context: Context) {
        receiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        receiver = null
    }

    private fun installViaLegacyIntent(context: Context, apkPath: String) {
        val file = File(apkPath)
        val uri = androidx.core.content.FileProvider.getUriForFile(
            context, "${context.packageName}.fileprovider", file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}
