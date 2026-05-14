package com.magent.mobile_agent

import android.Manifest
import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.Camera
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.ViewGroup
import android.view.Window
import android.webkit.MimeTypeMap
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class DeviceFilesCapabilityProvider(
    private val activity: Activity,
    private val requestCode: Int,
) {
    private var pendingResult: MethodChannel.Result? = null

    fun invoke(input: Map<*, *>, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "Another file picker is already active.", null)
            return
        }
        pendingResult = result
        val accept = input["accept"] as? String ?: ""
        val multiple = input["multiple"] as? Boolean ?: false
        val mimeTypes = parseAccept(accept)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (mimeTypes.size == 1) mimeTypes.first() else "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
            if (mimeTypes.size > 1) {
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            }
        }
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (error: Throwable) {
            pendingResult = null
            result.error("picker_unavailable", error.message, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != this.requestCode) return false
        val result = pendingResult ?: return true
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any?>>())
            return true
        }
        try {
            val uris = mutableListOf<Uri>()
            data.data?.let { uris.add(it) }
            val clipData = data.clipData
            if (clipData != null) {
                for (index in 0 until clipData.itemCount) {
                    clipData.getItemAt(index).uri?.let { uris.add(it) }
                }
            }
            val files = uris.distinct().map { copyUriToCache(it) }
            result.success(files)
        } catch (error: Throwable) {
            result.error("copy_failed", error.message, null)
        }
        return true
    }

    private fun copyUriToCache(uri: Uri): Map<String, Any?> {
        val name = displayName(uri) ?: "file-${System.currentTimeMillis()}"
        val mimeType = activity.contentResolver.getType(uri)
            ?: mimeTypeForName(name)
            ?: "application/octet-stream"
        val dir = File(activity.cacheDir, "html-capabilities/files").apply { mkdirs() }
        val target = File(dir, "${System.currentTimeMillis()}-${sanitizeName(name)}")
        activity.contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Unable to open selected file." }
            target.outputStream().use { output -> input.copyTo(output) }
        }
        return filePayload(target, name, mimeType)
    }

    private fun displayName(uri: Uri): String? {
        val cursor: Cursor? = activity.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )
        cursor.use {
            if (it != null && it.moveToFirst()) {
                return it.getString(0)
            }
        }
        return uri.lastPathSegment
    }

    private fun parseAccept(accept: String): List<String> {
        val values = accept
            .split(",")
            .map { it.trim().lowercase(Locale.US) }
            .filter { it.isNotEmpty() }
            .mapNotNull { value ->
                when {
                    value.contains("/") -> value
                    value.startsWith(".") -> MimeTypeMap.getSingleton()
                        .getMimeTypeFromExtension(value.drop(1))
                    else -> null
                }
            }
            .distinct()
        return values.ifEmpty { listOf("*/*") }
    }
}

class DeviceMediaCapabilityProvider(
    private val activity: Activity,
    private val requestCode: Int,
    private val cameraPermissionRequestCode: Int,
) {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPhoto: File? = null

    fun invoke(_input: Map<*, *>, result: MethodChannel.Result) {
        _input.containsKey("quality")
        if (pendingResult != null) {
            result.error("busy", "Another camera capture is already active.", null)
            return
        }
        pendingResult = result
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.CAMERA),
                cameraPermissionRequestCode,
            )
            return
        }
        launchCamera()
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != cameraPermissionRequestCode) return false
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            launchCamera()
        } else {
            val result = pendingResult
            pendingResult = null
            result?.error("permission_denied", "Camera permission denied.", null)
        }
        return true
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, _data: Intent?): Boolean {
        _data?.extras
        if (requestCode != this.requestCode) return false
        val result = pendingResult ?: return true
        pendingResult = null
        val photo = pendingPhoto
        pendingPhoto = null
        if (resultCode != Activity.RESULT_OK || photo == null || !photo.exists()) {
            photo?.delete()
            result.success(null)
            return true
        }
        result.success(filePayload(photo, photo.name, "image/jpeg"))
        return true
    }

    private fun launchCamera() {
        val result = pendingResult ?: return
        val dir = File(activity.cacheDir, "html-capabilities/camera").apply { mkdirs() }
        val photo = File(dir, "photo-${System.currentTimeMillis()}.jpg")
        pendingPhoto = photo
        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            photo,
        )
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        if (intent.resolveActivity(activity.packageManager) == null) {
            pendingResult = null
            pendingPhoto = null
            result.error("camera_unavailable", "No camera app is available.", null)
            return
        }
        activity.startActivityForResult(intent, requestCode)
    }
}

class DeviceAudioCapabilityProvider(
    private val activity: Activity,
    private val audioPermissionRequestCode: Int,
) {
    private var pendingResult: MethodChannel.Result? = null
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var dialog: Dialog? = null
    private var durationText: TextView? = null
    private var statusText: TextView? = null
    private var pauseButton: TextView? = null
    private var startedAtMs: Long = 0
    private var accumulatedMs: Long = 0
    private var isPaused = false
    private val timerHandler = Handler(Looper.getMainLooper())
    private val timerTick = object : Runnable {
        override fun run() {
            val runningMs = if (isPaused) 0 else System.currentTimeMillis() - startedAtMs
            durationText?.text = formatDuration(accumulatedMs + runningMs)
            timerHandler.postDelayed(this, 500)
        }
    }

    fun invoke(_input: Map<*, *>, result: MethodChannel.Result) {
        _input.containsKey("maxDurationMs")
        if (pendingResult != null) {
            result.error("busy", "Another audio recording is already active.", null)
            return
        }
        pendingResult = result
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                audioPermissionRequestCode,
            )
            return
        }
        startRecording()
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != audioPermissionRequestCode) return false
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startRecording()
        } else {
            val result = pendingResult
            pendingResult = null
            result?.error("permission_denied", "Microphone permission denied.", null)
        }
        return true
    }

    private fun startRecording() {
        val result = pendingResult ?: return
        try {
            val dir = File(activity.cacheDir, "html-capabilities/audio").apply { mkdirs() }
            val file = File(dir, "recording-${System.currentTimeMillis()}.m4a")
            recordingFile = file
            recorder = MediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128_000)
                setAudioSamplingRate(44_100)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }
            startedAtMs = System.currentTimeMillis()
            accumulatedMs = 0
            isPaused = false
            showRecordingDialog()
            timerHandler.post(timerTick)
        } catch (error: Throwable) {
            cleanupRecording(deleteFile = true)
            pendingResult = null
            result.error("recording_failed", error.message, null)
        }
    }

    private fun showRecordingDialog() {
        val zh = isChinese()
        val root = FrameLayout(activity).apply {
            background = GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.rgb(249, 250, 251), Color.rgb(243, 244, 246)),
            )
            setPadding(dp(20), statusBarHeight() + dp(16), dp(20), navigationBarHeight() + dp(16))
        }
        val card = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(22), dp(22), dp(22), dp(18))
            background = roundedDrawable(Color.WHITE, dp(22).toFloat())
            elevation = dp(6).toFloat()
        }
        val badge = TextView(activity).apply {
            text = if (zh) "●  正在录音" else "●  Recording"
            setTextColor(Color.rgb(37, 99, 235))
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        statusText = badge
        val timer = TextView(activity).apply {
            text = "00:00"
            setTextColor(Color.rgb(17, 24, 39))
            textSize = 48f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, dp(14))
        }
        durationText = timer
        val buttons = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val cancel = mediaButton(if (zh) "取消" else "Cancel", filled = false).apply {
            setOnClickListener { cancelRecording() }
        }
        val pause = mediaButton(if (zh) "暂停" else "Pause", filled = false).apply {
            isEnabled = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
            alpha = if (isEnabled) 1f else 0.45f
            setOnClickListener { togglePauseRecording() }
        }
        pauseButton = pause
        val done = mediaButton(if (zh) "完成" else "Done", filled = true).apply {
            setOnClickListener { finishRecording() }
        }
        buttons.addView(cancel)
        buttons.addView(pause)
        buttons.addView(done)
        card.addView(badge)
        card.addView(timer)
        card.addView(buttons)
        root.addView(
            card,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )
        dialog = Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar).apply {
            requestWindowFeature(Window.FEATURE_NO_TITLE)
            setContentView(root)
            setOnCancelListener { cancelRecording() }
            window?.setBackgroundDrawableResource(android.R.color.transparent)
            show()
            window?.setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }
    }

    private fun togglePauseRecording() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val recorder = recorder ?: return
        val zh = isChinese()
        try {
            if (isPaused) {
                recorder.resume()
                startedAtMs = System.currentTimeMillis()
                isPaused = false
                statusText?.text = if (zh) "●  正在录音" else "●  Recording"
                pauseButton?.text = if (zh) "暂停" else "Pause"
            } else {
                recorder.pause()
                accumulatedMs += System.currentTimeMillis() - startedAtMs
                isPaused = true
                statusText?.text = if (zh) "Ⅱ  已暂停" else "Ⅱ  Paused"
                pauseButton?.text = if (zh) "继续" else "Resume"
            }
        } catch (_: Throwable) {
        }
    }

    private fun mediaButton(label: String, filled: Boolean): TextView {
        return TextView(activity).apply {
            text = label
            textSize = 15f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(if (filled) Color.WHITE else Color.rgb(55, 65, 81))
            background = roundedDrawable(
                if (filled) Color.rgb(17, 24, 39) else Color.rgb(243, 244, 246),
                dp(999).toFloat(),
            )
            val params = LinearLayout.LayoutParams(0, dp(48), 1f)
            params.setMargins(dp(4), 0, dp(4), 0)
            layoutParams = params
        }
    }

    private fun finishRecording() {
        val result = pendingResult ?: return
        val file = recordingFile
        cleanupRecording(deleteFile = false)
        pendingResult = null
        if (file == null || !file.exists() || file.length() == 0L) {
            file?.delete()
            result.error("recording_failed", "Recorded audio file is empty.", null)
            return
        }
        result.success(filePayload(file, file.name, "audio/m4a"))
    }

    private fun cancelRecording() {
        val result = pendingResult ?: return
        cleanupRecording(deleteFile = true)
        pendingResult = null
        result.success(null)
    }

    private fun cleanupRecording(deleteFile: Boolean) {
        timerHandler.removeCallbacks(timerTick)
        durationText = null
        statusText = null
        pauseButton = null
        accumulatedMs = 0
        isPaused = false
        try {
            recorder?.stop()
        } catch (_: Throwable) {
        }
        try {
            recorder?.release()
        } catch (_: Throwable) {
        }
        recorder = null
        dialog?.setOnCancelListener(null)
        dialog?.dismiss()
        dialog = null
        if (deleteFile) {
            recordingFile?.delete()
        }
        recordingFile = null
    }
}

class DeviceVideoCapabilityProvider(
    private val activity: Activity,
    private val permissionRequestCode: Int,
) {
    private var pendingResult: MethodChannel.Result? = null
    private var dialog: Dialog? = null
    private var surfaceView: SurfaceView? = null
    private var camera: Camera? = null
    private var cameraId = 0
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var isRecording = false
    private var durationText: TextView? = null
    private var statusText: TextView? = null
    private var pauseButton: TextView? = null
    private var recordButton: TextView? = null
    private var startedAtMs: Long = 0
    private var accumulatedMs: Long = 0
    private var isPaused = false
    private val timerHandler = Handler(Looper.getMainLooper())
    private val timerTick = object : Runnable {
        override fun run() {
            val runningMs = if (isPaused) 0 else System.currentTimeMillis() - startedAtMs
            durationText?.text = formatDuration(accumulatedMs + runningMs)
            timerHandler.postDelayed(this, 500)
        }
    }

    fun invoke(_input: Map<*, *>, result: MethodChannel.Result) {
        _input.containsKey("maxDurationMs")
        if (pendingResult != null) {
            result.error("busy", "Another video recording is already active.", null)
            return
        }
        pendingResult = result
        val missing = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            missing.add(Manifest.permission.CAMERA)
        }
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            missing.add(Manifest.permission.RECORD_AUDIO)
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(activity, missing.toTypedArray(), permissionRequestCode)
            return
        }
        showRecorder()
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != permissionRequestCode) return false
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            showRecorder()
        } else {
            val result = pendingResult
            pendingResult = null
            result?.error("permission_denied", "Camera or microphone permission denied.", null)
        }
        return true
    }

    private fun showRecorder() {
        if (Camera.getNumberOfCameras() <= 0) {
            val result = pendingResult
            pendingResult = null
            result?.error("camera_unavailable", "No camera is available.", null)
            return
        }

        val root = FrameLayout(activity).apply {
            setBackgroundColor(Color.BLACK)
            setPadding(0, statusBarHeight(), 0, navigationBarHeight())
        }
        val preview = SurfaceView(activity)
        surfaceView = preview
        root.addView(
            preview,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        val topBar = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(20), dp(14), dp(20), dp(12))
            background = roundedDrawable(0xCC111827.toInt(), dp(24).toFloat())
        }
        val title = TextView(activity).apply {
            text = if (isChinese()) "准备录制" else "Ready to record"
            setTextColor(Color.WHITE)
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        statusText = title
        val timer = TextView(activity).apply {
            text = "00:00"
            setTextColor(0xFFE5E7EB.toInt())
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(0, dp(4), 0, 0)
        }
        durationText = timer
        topBar.addView(title)
        topBar.addView(timer)
        val topParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.CENTER_HORIZONTAL,
        )
        topParams.setMargins(0, dp(10), 0, 0)
        root.addView(topBar, topParams)

        val cancelButton = TextView(activity).apply {
            text = if (isChinese()) "取消" else "Cancel"
            textSize = 14f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = roundedDrawable(0x66111827, dp(999).toFloat())
            setOnClickListener { cancelRecording() }
        }
        val cancelParams = FrameLayout.LayoutParams(dp(74), dp(40), Gravity.TOP or Gravity.START)
        cancelParams.setMargins(dp(16), dp(10), 0, 0)
        root.addView(cancelButton, cancelParams)

        cameraId = backCameraId()
        val switchButton = videoCircleButton("↻", enabled = Camera.getNumberOfCameras() > 1).apply {
            alpha = if (isEnabled) 1f else 0.42f
            setOnClickListener { switchCamera() }
        }
        val pauseButton = videoCircleButton(if (isChinese()) "Ⅱ" else "Ⅱ", enabled = false).apply {
            alpha = 0.42f
            setOnClickListener { togglePauseRecording() }
        }
        val recordButton = videoShutterButton(recording = false).apply {
            setOnClickListener {
                if (isRecording) {
                    finishRecording()
                } else {
                    startRecording(this)
                }
            }
        }
        this.pauseButton = pauseButton
        this.recordButton = recordButton
        val bottomControls = FrameLayout(activity)
        bottomControls.addView(
            switchButton,
            FrameLayout.LayoutParams(dp(54), dp(54), Gravity.START or Gravity.CENTER_VERTICAL),
        )
        bottomControls.addView(
            recordButton,
            FrameLayout.LayoutParams(dp(74), dp(74), Gravity.CENTER),
        )
        bottomControls.addView(
            pauseButton,
            FrameLayout.LayoutParams(dp(54), dp(54), Gravity.END or Gravity.CENTER_VERTICAL),
        )
        val recordParams = FrameLayout.LayoutParams(
            dp(220),
            dp(82),
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
        )
        recordParams.setMargins(0, 0, 0, dp(18))
        root.addView(bottomControls, recordParams)

        dialog = Dialog(activity, android.R.style.Theme_Material_NoActionBar).apply {
            requestWindowFeature(Window.FEATURE_NO_TITLE)
            setContentView(root)
            setOnCancelListener { cancelRecording() }
            show()
            window?.setBackgroundDrawableResource(android.R.color.black)
            window?.setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
        }

        preview.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                openCamera(holder)
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                releaseCamera()
            }
        })
    }

    private fun videoShutterButton(recording: Boolean): TextView {
        return TextView(activity).apply {
            text = if (recording) "■" else "●"
            textSize = if (recording) 25f else 34f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(if (recording) Color.WHITE else Color.rgb(37, 99, 235))
            background = if (recording) {
                roundedDrawable(Color.rgb(17, 24, 39), dp(999).toFloat())
            } else {
                roundedDrawable(Color.WHITE, dp(999).toFloat())
            }
        }
    }

    private fun videoCircleButton(label: String, enabled: Boolean): TextView {
        return TextView(activity).apply {
            text = label
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            isEnabled = enabled
            setTextColor(Color.WHITE)
            background = roundedDrawable(0x88111827.toInt(), dp(999).toFloat())
        }
    }

    private fun openCamera(holder: SurfaceHolder) {
        try {
            val opened = Camera.open(cameraId)
            opened.setDisplayOrientation(90)
            opened.setPreviewDisplay(holder)
            opened.startPreview()
            camera = opened
        } catch (error: Throwable) {
            val result = pendingResult
            cleanupVideo(deleteFile = true)
            pendingResult = null
            result?.error("camera_unavailable", error.message, null)
        }
    }

    private fun switchCamera() {
        if (isRecording || Camera.getNumberOfCameras() <= 1) return
        val holder = surfaceView?.holder ?: return
        releaseCamera()
        cameraId = nextCameraId(cameraId)
        openCamera(holder)
    }

    private fun backCameraId(): Int {
        val info = Camera.CameraInfo()
        for (index in 0 until Camera.getNumberOfCameras()) {
            Camera.getCameraInfo(index, info)
            if (info.facing == Camera.CameraInfo.CAMERA_FACING_BACK) return index
        }
        return 0
    }

    private fun nextCameraId(current: Int): Int {
        val count = Camera.getNumberOfCameras()
        return if (count <= 1) current else (current + 1) % count
    }

    private fun startRecording(button: TextView) {
        val result = pendingResult ?: return
        val activeCamera = camera ?: run {
            result.error("camera_unavailable", "Camera preview is not ready.", null)
            return
        }
        val surface = surfaceView?.holder?.surface ?: run {
            result.error("camera_unavailable", "Camera preview surface is not ready.", null)
            return
        }
        try {
            val dir = File(activity.cacheDir, "html-capabilities/video").apply { mkdirs() }
            val file = File(dir, "video-${System.currentTimeMillis()}.mp4")
            val size = chooseVideoSize(activeCamera)
            recordingFile = file
            activeCamera.unlock()
            recorder = MediaRecorder().apply {
                setCamera(activeCamera)
                setAudioSource(MediaRecorder.AudioSource.CAMCORDER)
                setVideoSource(MediaRecorder.VideoSource.CAMERA)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setVideoFrameRate(30)
                setVideoSize(size.first, size.second)
                setVideoEncodingBitRate(4_000_000)
                setOrientationHint(90)
                setPreviewDisplay(surface)
                setOutputFile(file.absolutePath)
                prepare()
                start()
            }
            isRecording = true
            startedAtMs = System.currentTimeMillis()
            accumulatedMs = 0
            isPaused = false
            timerHandler.post(timerTick)
            button.text = "■"
            button.textSize = 25f
            button.setTextColor(Color.WHITE)
            button.background = roundedDrawable(Color.rgb(17, 24, 39), dp(999).toFloat())
            pauseButton?.isEnabled = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
            pauseButton?.alpha = if (pauseButton?.isEnabled == true) 1f else 0.42f
            statusText?.text = if (isChinese()) "●  正在录制" else "●  Recording"
        } catch (error: Throwable) {
            cleanupVideo(deleteFile = true)
            pendingResult = null
            result.error("recording_failed", error.message, null)
        }
    }

    private fun togglePauseRecording() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val recorder = recorder ?: return
        val zh = isChinese()
        try {
            if (isPaused) {
                recorder.resume()
                startedAtMs = System.currentTimeMillis()
                isPaused = false
                statusText?.text = if (zh) "●  正在录制" else "●  Recording"
                pauseButton?.text = if (zh) "暂停" else "Pause"
            } else {
                recorder.pause()
                accumulatedMs += System.currentTimeMillis() - startedAtMs
                isPaused = true
                statusText?.text = if (zh) "Ⅱ  已暂停" else "Ⅱ  Paused"
                pauseButton?.text = if (zh) "继续" else "Resume"
            }
        } catch (_: Throwable) {
        }
    }

    private fun chooseVideoSize(activeCamera: Camera): Pair<Int, Int> {
        val sizes = activeCamera.parameters.supportedVideoSizes
            ?: activeCamera.parameters.supportedPreviewSizes
        val preferred = sizes
            .filter { it.width <= 1280 && it.height <= 720 }
            .maxByOrNull { it.width * it.height }
        val fallback = sizes.maxByOrNull { it.width * it.height }
        val size = preferred ?: fallback
        return if (size == null) 640 to 480 else size.width to size.height
    }

    private fun finishRecording() {
        val result = pendingResult ?: return
        val file = recordingFile
        cleanupVideo(deleteFile = false)
        pendingResult = null
        if (file == null || !file.exists() || file.length() == 0L) {
            file?.delete()
            result.error("recording_failed", "Recorded video file is empty.", null)
            return
        }
        result.success(filePayload(file, file.name, "video/mp4"))
    }

    private fun cancelRecording() {
        val result = pendingResult ?: return
        cleanupVideo(deleteFile = true)
        pendingResult = null
        result.success(null)
    }

    private fun cleanupVideo(deleteFile: Boolean) {
        timerHandler.removeCallbacks(timerTick)
        durationText = null
        statusText = null
        pauseButton = null
        recordButton = null
        accumulatedMs = 0
        isPaused = false
        if (isRecording) {
            try {
                recorder?.stop()
            } catch (_: Throwable) {
            }
        }
        try {
            recorder?.release()
        } catch (_: Throwable) {
        }
        recorder = null
        isRecording = false
        releaseCamera()
        dialog?.setOnCancelListener(null)
        dialog?.dismiss()
        dialog = null
        surfaceView = null
        if (deleteFile) {
            recordingFile?.delete()
        }
        recordingFile = null
    }

    private fun releaseCamera() {
        try {
            camera?.stopPreview()
        } catch (_: Throwable) {
        }
        try {
            camera?.release()
        } catch (_: Throwable) {
        }
        camera = null
    }
}

private fun filePayload(file: File, name: String, mimeType: String): Map<String, Any?> {
    return mapOf(
        "path" to file.absolutePath,
        "name" to name,
        "mimeType" to mimeType,
        "size" to file.length(),
    )
}

private fun sanitizeName(name: String): String {
    return name.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { "file" }
}

private fun mimeTypeForName(name: String): String? {
    val extension = name.substringAfterLast('.', "").lowercase(Locale.US)
    if (extension.isEmpty()) return null
    return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
}

private fun isChinese(): Boolean {
    return Locale.getDefault().language.lowercase(Locale.US).startsWith("zh")
}

private fun dp(value: Int): Int {
    return (value * android.content.res.Resources.getSystem().displayMetrics.density).toInt()
}

private fun statusBarHeight(): Int {
    return systemDimension("status_bar_height")
}

private fun navigationBarHeight(): Int {
    return systemDimension("navigation_bar_height")
}

private fun systemDimension(name: String): Int {
    val resources = android.content.res.Resources.getSystem()
    val id = resources.getIdentifier(name, "dimen", "android")
    return if (id > 0) resources.getDimensionPixelSize(id) else 0
}

private fun roundedDrawable(color: Int, radius: Float): GradientDrawable {
    return GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius
    }
}

private fun formatDuration(elapsedMs: Long): String {
    val totalSeconds = (elapsedMs / 1000).coerceAtLeast(0)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%02d:%02d".format(Locale.US, minutes, seconds)
}
