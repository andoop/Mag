package com.magent.mobile_agent

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
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
