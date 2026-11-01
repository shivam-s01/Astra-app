// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue

object AurumDiagnosticLog {
    private const val TAG = "AurumDiagnosticLog"
    private const val FILE_NAME = "aurum_diagnostic.log"
    private const val MAX_BYTES = 2L * 1024 * 1024
    private const val TRIM_TO_BYTES = 1L * 1024 * 1024

    private const val HEARTBEAT_INTERVAL_MS = 5_000L
    private const val ANR_THRESHOLD_MS = 5_000L

    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    private val writerExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "AurumDiagnosticLogWriter").apply { isDaemon = true }
    }

    @Volatile private var logFile: File? = null
    @Volatile private var initialized = false

    private var anrWatchdogThread: Thread? = null
    @Volatile private var anrWatchdogRunning = false

    fun init(context: Context) {
        if (initialized) return
        initialized = true
        try {
            logFile = File(context.applicationContext.filesDir, FILE_NAME)
            writeLine("SYSTEM", "=== AurumDiagnosticLog initialized ===")
            installCrashHandler()
            startAnrWatchdog()
        } catch (e: Exception) {
            Log.e(TAG, "init failed: $e")
        }
    }

    fun logCrash(thread: Thread, throwable: Throwable) {
        try {
            val sb = StringBuilder()
            sb.append("=== CRASH on thread '${thread.name}' ===\n")
            sb.append(Log.getStackTraceString(throwable))
            writeLineSync("CRASH", sb.toString())
        } catch (_: Exception) {
        }
    }

    fun logAnr(stuckForMs: Long, stackTrace: String) {
        writeLine("ANR", "Main thread unresponsive for ${stuckForMs}ms\n$stackTrace")
    }

    fun logOffload(offloaded: Boolean, encoding: Int, sampleRate: Int, songId: String?) {
        writeLine(
            "OFFLOAD",
            "offloaded=$offloaded encoding=$encoding sampleRate=$sampleRate songId=${songId ?: "?"}",
        )
    }

    fun logPlaybackError(message: String, songId: String?) {
        writeLine("PLAYBACK_ERROR", "song=${songId ?: "?"} — $message")
    }

    fun logNetworkError(context: String, message: String) {
        writeLine("NETWORK_ERROR", "$context — $message")
    }

    fun logEvent(tag: String, message: String) {
        writeLine(tag, message)
    }

    fun getLogFile(context: Context): File {
        return logFile ?: File(context.applicationContext.filesDir, FILE_NAME).also { logFile = it }
    }

    fun clear(context: Context) {
        writerExecutor.execute {
            try {
                getLogFile(context).writeText("")
            } catch (e: Exception) {
                Log.e(TAG, "clear failed: $e")
            }
        }
    }

    private fun formatLine(tag: String, message: String): String {
        val ts = dateFormat.format(Date())
        return "[$ts] [$tag] $message\n"
    }

    private fun writeLine(tag: String, message: String) {
        val line = formatLine(tag, message)
        val file = logFile ?: return
        writerExecutor.execute {
            try {
                appendAndRotate(file, line)
            } catch (e: Exception) {
                Log.e(TAG, "write failed: $e")
            }
        }
    }

    private fun writeLineSync(tag: String, message: String) {
        val line = formatLine(tag, message)
        val file = logFile ?: return
        try {
            appendAndRotate(file, line)
        } catch (_: Exception) {
        }
    }

    private fun appendAndRotate(file: File, line: String) {
        file.appendText(line)
        if (file.length() > MAX_BYTES) {
            val bytes = file.readBytes()
            val start = (bytes.size - TRIM_TO_BYTES).coerceAtLeast(0).toInt()
            file.writeBytes(bytes.copyOfRange(start, bytes.size))
        }
    }

    private fun installCrashHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            logCrash(thread, throwable)
            previous?.uncaughtException(thread, throwable)
                ?: run {
                    Log.e(TAG, "Uncaught exception, no previous handler", throwable)
                    Runtime.getRuntime().exit(10)
                }
        }
    }

    private fun startAnrWatchdog() {
        if (anrWatchdogRunning) return
        anrWatchdogRunning = true
        val mainHandler = Handler(Looper.getMainLooper())

        anrWatchdogThread = Thread({
            while (anrWatchdogRunning) {
                val token = Object()
                val responded = LinkedBlockingQueue<Boolean>(1)
                val postedAt = SystemClock.elapsedRealtime()

                mainHandler.post {
                    responded.offer(true)
                }

                val gotResponse = responded.poll(ANR_THRESHOLD_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
                if (gotResponse == null) {
                    val stuckForMs = SystemClock.elapsedRealtime() - postedAt
                    val mainThreadStack = Looper.getMainLooper().thread.stackTrace
                        .joinToString("\n") { "    at $it" }
                    logAnr(stuckForMs, mainThreadStack)
                }

                try {
                    Thread.sleep(HEARTBEAT_INTERVAL_MS)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }, "AurumAnrWatchdog").apply {
            isDaemon = true
            start()
        }
    }

    fun stopAnrWatchdog() {
        anrWatchdogRunning = false
        anrWatchdogThread?.interrupt()
        anrWatchdogThread = null
    }
}
