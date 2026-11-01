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
import android.database.ContentObserver
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer

@UnstableApi
class AurumAudioOutputManager(
    private val context: Context,
    private val audioManager: AudioManager,
    private val player: ExoPlayer,
) {
    var onDevicesChanged: (() -> Unit)? = null
    var onVolumeChanged: (() -> Unit)? = null

    private var forcedSpeaker = false
    private var selectedDeviceId: Int? = null

    private var lastKnownVolume: Int = -1

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            notifyDevicesChangedSoon()
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var callbackReady = false

    private fun notifyDevicesChangedSoon() {
        onDevicesChanged?.invoke()
        mainHandler.postDelayed({ onDevicesChanged?.invoke() }, 250)
        mainHandler.postDelayed({ onDevicesChanged?.invoke() }, 800)
    }

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) {
            if (callbackReady && added.any { isRelevantOutput(it.type) && it.type != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }) {
                clearOverride()
            }
            notifyDevicesChangedSoon()
        }

        override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) {
            val id = selectedDeviceId
            if (id != null && removed.any { it.id == id }) clearOverride()
            notifyDevicesChangedSoon()
        }
    }

    private fun clearOverride() {
        forcedSpeaker = false
        selectedDeviceId = null
        try { player.setPreferredAudioDevice(null) } catch (e: Exception) {}
    }

    private val volumeObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            if (current != lastKnownVolume) {
                lastKnownVolume = current
                onVolumeChanged?.invoke()
            }
        }
    }

    init {
        val filter = IntentFilter().apply {
            addAction(AudioManager.ACTION_HEADSET_PLUG)
            addAction(android.bluetooth.BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(android.bluetooth.BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction("android.bluetooth.a2dp.profile.action.CONNECTION_STATE_CHANGED")
            addAction("android.bluetooth.a2dp.profile.action.ACTIVE_DEVICE_CHANGED")
            addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
        audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
        mainHandler.post { callbackReady = true }
        lastKnownVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        context.contentResolver.registerContentObserver(
            Settings.System.CONTENT_URI, true, volumeObserver)
    }

    fun currentVolume(): Pair<Int, Int> {
        val current = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        return current to max
    }

    fun supportsExplicitRouting(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

    fun describeDevices(): List<Map<String, Any?>> {
        val infos = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val currentId = currentDeviceId()
        val relevant = infos.filter { isRelevantOutput(it.type) }

        val byNameAndKind = LinkedHashMap<String, AudioDeviceInfo>()
        for (info in relevant) {
            val dedupeKey = "${deviceLabel(info)}|${deviceTypeName(info.type)}"
            val existing = byNameAndKind[dedupeKey]
            if (existing == null) {
                byNameAndKind[dedupeKey] = info
            } else if (existing.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO &&
                info.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) {
                byNameAndKind[dedupeKey] = info
            }
        }

        return byNameAndKind.values.map { info ->
            val groupKey = "${deviceLabel(info)}|${deviceTypeName(info.type)}"
            val isSelected = info.id == currentId || relevant.any {
                it.id == currentId &&
                    "${deviceLabel(it)}|${deviceTypeName(it.type)}" == groupKey
            }
            mapOf(
                "id" to info.id,
                "name" to deviceLabel(info),
                "kind" to deviceTypeName(info.type),
                "type" to deviceTypeName(info.type),
                "selected" to isSelected,
            )
        }
    }

    fun selectDevice(deviceId: Int): Boolean {
        if (!supportsExplicitRouting()) return false
        val target = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.id == deviceId } ?: return false

        forcedSpeaker = false
        return try {
            player.setPreferredAudioDevice(target)
            selectedDeviceId = target.id
            notifyDevicesChangedSoon()
            true
        } catch (e: Exception) {
            false
        }
    }

    fun setForceSpeaker(force: Boolean) {
        forcedSpeaker = force
        if (!supportsExplicitRouting()) return
        if (!force) {
            player.setPreferredAudioDevice(null)
            selectedDeviceId = null
            notifyDevicesChangedSoon()
            return
        }
        val speaker = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
        player.setPreferredAudioDevice(speaker)
        selectedDeviceId = speaker?.id
        notifyDevicesChangedSoon()
    }

    fun release() {
        try {
            context.unregisterReceiver(receiver)
        } catch (e: Exception) {
        }
        try {
            audioManager.unregisterAudioDeviceCallback(deviceCallback)
        } catch (e: Exception) {
        }
        mainHandler.removeCallbacksAndMessages(null)
        try {
            context.contentResolver.unregisterContentObserver(volumeObserver)
        } catch (e: Exception) {
        }
        onDevicesChanged = null
        onVolumeChanged = null
    }

    private fun currentDeviceId(): Int? {
        selectedDeviceId?.let { return it }
        return inferredActiveDeviceId()
    }

    private fun inferredActiveDeviceId(): Int? {
        val infos = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val priority = listOf(
            AudioDeviceInfo.TYPE_HEARING_AID,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        )
        for (type in priority) {
            infos.firstOrNull { it.type == type }?.let { return it.id }
        }
        return infos.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }?.id
    }

    private fun isRelevantOutput(type: Int): Boolean = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_HEARING_AID -> true
        else -> false
    }

    private fun deviceTypeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE -> "usb"
        AudioDeviceInfo.TYPE_HEARING_AID -> "hearing_aid"
        else -> "unknown"
    }

    private fun deviceLabel(info: AudioDeviceInfo): String {
        val productName = info.productName?.toString()
        if (!productName.isNullOrBlank() && info.type != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
            return productName
        }
        return when (info.type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Phone speaker"
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired headphones"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth device"
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB audio"
            AudioDeviceInfo.TYPE_HEARING_AID -> "Hearing aid"
            else -> "Unknown device"
        }
    }
}
