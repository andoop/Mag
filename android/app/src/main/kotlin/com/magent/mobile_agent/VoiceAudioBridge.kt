package com.magent.mobile_agent

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class VoiceAudioBridge(private val activity: Activity) {
    companion object {
        private const val PERMISSION_REQUEST = 4301
    }

    private var methodResult: MethodChannel.Result? = null
    private var eventSink: EventChannel.EventSink? = null
    private var recorder: AudioRecord? = null
    private var recordThread: Thread? = null
    private val recording = AtomicBoolean(false)

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobile_agent/voice_audio")
            .setMethodCallHandler(::handleMethodCall)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "mobile_agent/voice_audio_stream")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "start" -> {
                val sampleRate = call.argument<Int>("sampleRate") ?: 16000
                start(sampleRate, result)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(): Boolean {
        return ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        methodResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            PERMISSION_REQUEST,
        )
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        methodResult?.success(granted)
        methodResult = null
        return true
    }

    private fun start(sampleRate: Int, result: MethodChannel.Result) {
        if (!hasPermission()) {
            result.error("microphone_denied", "Microphone permission denied", null)
            return
        }
        if (recording.get()) {
            result.success(null)
            return
        }
        val minBuffer = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            result.error("audio_unavailable", "AudioRecord is unavailable", null)
            return
        }
        val chunkSize = (sampleRate * 2 / 5).coerceAtLeast(minBuffer)
        val audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            chunkSize * 2,
        )
        if (audioRecord.state != AudioRecord.STATE_INITIALIZED) {
            audioRecord.release()
            result.error("audio_unavailable", "AudioRecord failed to initialize", null)
            return
        }
        recorder = audioRecord
        recording.set(true)
        audioRecord.startRecording()
        recordThread = Thread {
            val buffer = ByteArray(chunkSize)
            while (recording.get()) {
                val read = audioRecord.read(buffer, 0, buffer.size)
                if (read > 0) {
                    val chunk = buffer.copyOf(read)
                    activity.runOnUiThread {
                        eventSink?.success(chunk)
                    }
                }
            }
        }.also {
            it.name = "mag-voice-audio"
            it.start()
        }
        result.success(null)
    }

    fun stop() {
        recording.set(false)
        recordThread = null
        recorder?.let {
            try {
                it.stop()
            } catch (_: IllegalStateException) {
            }
            it.release()
        }
        recorder = null
    }
}
