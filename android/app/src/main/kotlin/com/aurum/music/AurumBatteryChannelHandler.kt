// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

class AurumBatteryChannelHandler(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "com.aurum.music/battery"
    }

    private val eventChannel = EventChannel(messenger, CHANNEL)
    private var receiver: BroadcastReceiver? = null

    init {
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val br = object : BroadcastReceiver() {
                    override fun onReceive(ctx: Context, intent: Intent) {
                        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                        if (level < 0 || scale <= 0) return
                        val percent = (level * 100) / scale
                        try {
                            events?.success(percent)
                        } catch (_: Exception) {
                        }
                    }
                }
                context.registerReceiver(br, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                receiver = br
            }

            override fun onCancel(arguments: Any?) {
                receiver?.let {
                    try { context.unregisterReceiver(it) } catch (_: Exception) {}
                }
                receiver = null
            }
        })
    }

    fun release() {
        receiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        receiver = null
    }
}
