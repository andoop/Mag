package com.magent.mobile_agent

import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val PICK_WORKSPACE_REQUEST = 4107
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobile_agent/workspace")
            .setMethodCallHandler(::handleWorkspaceCall)
    }

    private fun handleWorkspaceCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickWorkspace" -> {
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                startActivityForResult(intent, PICK_WORKSPACE_REQUEST)
            }
            "listDirectory" -> {
                val treeUri = call.argument<String>("treeUri") ?: return result.error("missing_tree", "Missing treeUri", null)
                val relativePath = call.argument<String>("relativePath") ?: ""
                val offset = call.argument<Int>("offset") ?: 1
                val limit = call.argument<Int>("limit")
                val target = resolveDocument(treeUri, relativePath)
                if (target == null || !target.isDirectory) {
                    result.error("not_directory", "Target is not a directory", null)
                    return
                }
                val entries =
                    target.listFiles()
                        .map { toEntry(it, childPath(relativePath, it.name ?: "")) }
                        .sortedWith(compareBy<Map<String, Any?>>({ !(it["isDirectory"] as Boolean) }, { (it["path"] as String).lowercase() }))
                val safeOffset = if (offset < 1) 1 else offset
                val start = (safeOffset - 1).coerceAtMost(entries.size)
                val end = if (limit == null || limit <= 0) entries.size else (start + limit).coerceAtMost(entries.size)
                result.success(entries.subList(start, end))
            }
            "getEntry" -> {
                val treeUri = call.argument<String>("treeUri") ?: return result.error("missing_tree", "Missing treeUri", null)
                val relativePath = call.argument<String>("relativePath") ?: ""
                val target = resolveDocument(treeUri, relativePath)
                if (target == null) {
                    result.error("not_found", "Unable to resolve entry", null)
                    return
                }
                result.success(toEntry(target, normalizeRelativePath(relativePath)))
            }
            "searchEntries" -> {
                val treeUri = call.argument<String>("treeUri") ?: return result.error("missing_tree", "Missing treeUri", null)
                val relativePath = call.argument<String>("relativePath") ?: ""
                val pattern = call.argument<String>("pattern") ?: "*"
                val limit = call.argument<Int>("limit") ?: 100
                val filesOnly = call.argument<Boolean>("filesOnly") ?: true
                val ignorePatterns = call.argument<List<String>>("ignorePatterns") ?: emptyList()
                val target = resolveDocument(treeUri, relativePath)
                if (target == null || !target.isDirectory) {
                    result.error("not_directory", "Target is not a directory", null)
                    return
                }
                val rootPath = normalizeRelativePath(relativePath)
                val globRegex = globToRegex(pattern)
                val matches = mutableListOf<Map<String, Any?>>()
                searchEntries(
                    document = target,
                    rootPath = rootPath,
                    currentPath = rootPath,
                    globRegex = globRegex,
                    filesOnly = filesOnly,
                    limit = limit,
                    ignorePatterns = ignorePatterns,
                    output = matches,
                )
                matches.sortByDescending { (it["lastModified"] as Int?) ?: 0 }
                result.success(matches)
            }
            "grepText" -> {
                val treeUri = call.argument<String>("treeUri") ?: return result.error("missing_tree", "Missing treeUri", null)
                val relativePath = call.argument<String>("relativePath") ?: ""
                val pattern = call.argument<String>("pattern") ?: return result.error("missing_pattern", "Missing pattern", null)
                val include = call.argument<String>("include")
                val limit = call.argument<Int>("limit") ?: 100
                val maxLineLength = call.argument<Int>("maxLineLength") ?: 2000
                val ignorePatterns = call.argument<List<String>>("ignorePatterns") ?: emptyList()
                val target = resolveDocument(treeUri, relativePath)
                if (target == null || !target.isDirectory) {
                    result.error("not_directory", "Target is not a directory", null)
                    return
                }
                val regex =
                    try {
                        Regex(pattern)
                    } catch (error: Throwable) {
                        result.error("invalid_pattern", error.message, null)
                        return
                    }
                val includeRegex = include?.takeIf { it.isNotBlank() }?.let { globToRegex(it) }
                val output = mutableListOf<Map<String, Any?>>()
                grepWorkspace(
                    document = target,
                    currentPath = normalizeRelativePath(relativePath),
                    regex = regex,
                    includeRegex = includeRegex,
                    limit = limit,
                    maxLineLength = maxLineLength,
                    ignorePatterns = ignorePatterns,
                    output = output,
                )
                result.success(output)
            }
            "readText" -> {
                val treeUri = call.argument<String>("treeUri") ?: return result.error("missing_tree", "Missing treeUri", null)
                val relativePath = call.argument<String>("relativePath") ?: ""
                val target = resolveDocument(treeUri, relativePath)
                if (target == null || target.isDirectory) {
                    result.error("not_file", "Target is not a file", null)
                    return
                }
                contentResolver.openInputStream(target.uri)?.bufferedReader().use { reader ->
                    result.success(reader?.readText() ?: "")
                }
            }
            "readBytes" -> {
                val treeUri = call.argument<String>("treeUri") ?: return result.error("missing_tree", "Missing treeUri", null)
                val relativePath = call.argument<String>("relativePath") ?: ""
                val target = resolveDocument(treeUri, relativePath)
                if (target == null || target.isDirectory) {
                    result.error("not_file", "Target is not a file", null)
                    return
                }
                contentResolver.openInputStream(target.uri).use { stream ->
                    result.success(stream?.readBytes() ?: ByteArray(0))
                }
            }
            "writeText" -> {
                val treeUri = call.argument<String>("treeUri") ?: return result.error("missing_tree", "Missing treeUri", null)
                val relativePath = call.argument<String>("relativePath") ?: ""
                val content = call.argument<String>("content") ?: ""
                val target = ensureFile(treeUri, relativePath)
                if (target == null) {
                    result.error("write_failed", "Unable to create file", mapOf("path" to relativePath))
                    return
                }
                val stream = contentResolver.openOutputStream(target.uri, "wt")
                if (stream == null) {
                    result.error("write_failed", "Unable to open output stream", mapOf("path" to relativePath))
                    return
                }
                stream.bufferedWriter().use { writer ->
                    writer.write(content)
                }
                result.success(null)
            }
            "deleteEntry" -> {
                val treeUri = call.argument<String>("treeUri") ?: return result.error("missing_tree", "Missing treeUri", null)
                val relativePath = call.argument<String>("relativePath") ?: ""
                val target = resolveDocument(treeUri, relativePath)
                if (target == null) {
                    result.error("missing_entry", "Unable to resolve entry", null)
                    return
                }
                result.success(target.delete())
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_WORKSPACE_REQUEST) return
        val result = pendingResult ?: return
        pendingResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        contentResolver.takePersistableUriPermission(uri, flags)
        val root = DocumentFile.fromTreeUri(this, uri)
        result.success(
            mapOf(
                "treeUri" to uri.toString(),
                "displayName" to (root?.name ?: "Workspace"),
            )
        )
    }

    private fun resolveDocument(treeUri: String, relativePath: String): DocumentFile? {
        var current = DocumentFile.fromTreeUri(this, Uri.parse(treeUri)) ?: return null
        val normalized = relativePath.trim('/').trim()
        if (normalized.isEmpty()) return current
        val segments = normalizePathSegments(relativePath)
        if (segments.isEmpty()) return null
        for (segment in segments) {
            current = current.findFile(segment) ?: return null
        }
        return current
    }

    private fun ensureFile(treeUri: String, relativePath: String): DocumentFile? {
        val segments = normalizePathSegments(relativePath)
        if (segments.isEmpty()) return null
        var current = DocumentFile.fromTreeUri(this, Uri.parse(treeUri)) ?: return null
        for (i in 0 until segments.size - 1) {
            val name = segments[i]
            val existing = current.findFile(name)
            val next = existing ?: current.createDirectory(name) ?: current.findFile(name)
            if (next == null || !next.isDirectory) return null
            current = next
        }
        val fileName = segments.last()
        val existing = current.findFile(fileName)
        if (existing != null) {
            return if (existing.isDirectory) null else existing
        }
        val mimeType = mimeTypeForFileName(fileName)
        return current.createFile(mimeType, fileName) ?: current.findFile(fileName)
    }

    private fun normalizePathSegments(relativePath: String): List<String> {
        val normalized = normalizeRelativePath(relativePath)
        if (normalized.isEmpty()) return emptyList()
        return normalized
            .split("/")
            .map { it.trim() }
            .filter { it.isNotEmpty() && it != "." }
            .takeUnless { segments -> segments.any { it == ".." } }
            ?: emptyList()
    }

    private fun normalizeRelativePath(relativePath: String): String {
        return relativePath.trim('/').trim()
    }

    private fun mimeTypeForFileName(fileName: String): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        if (extension.isEmpty()) return "text/plain"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "text/plain"
    }

    private fun searchEntries(
        document: DocumentFile,
        rootPath: String,
        currentPath: String,
        globRegex: Regex,
        filesOnly: Boolean,
        limit: Int,
        ignorePatterns: List<String>,
        output: MutableList<Map<String, Any?>>,
    ) {
        if (!document.isDirectory || output.size >= limit) return
        val children = document.listFiles().sortedBy { (it.name ?: "").lowercase() }
        for (child in children) {
            if (output.size >= limit) return
            val childPath = childPath(currentPath, child.name ?: "")
            if (shouldIgnore(childPath, child.isDirectory, ignorePatterns)) continue
            val relativeToRoot =
                if (rootPath.isEmpty()) childPath else childPath.removePrefix("$rootPath/").ifEmpty { child.name ?: "" }
            if ((!filesOnly || !child.isDirectory) && globRegex.matches(relativeToRoot)) {
                output.add(toEntry(child, childPath))
                if (output.size >= limit) return
            }
            if (child.isDirectory) {
                searchEntries(
                    document = child,
                    rootPath = rootPath,
                    currentPath = childPath,
                    globRegex = globRegex,
                    filesOnly = filesOnly,
                    limit = limit,
                    ignorePatterns = ignorePatterns,
                    output = output,
                )
            }
        }
    }

    private fun grepWorkspace(
        document: DocumentFile,
        currentPath: String,
        regex: Regex,
        includeRegex: Regex?,
        limit: Int,
        maxLineLength: Int,
        ignorePatterns: List<String>,
        output: MutableList<Map<String, Any?>>,
    ) {
        if (!document.isDirectory || output.size >= limit) return
        val children = document.listFiles().sortedBy { (it.name ?: "").lowercase() }
        for (child in children) {
            if (output.size >= limit) return
            val childPath = childPath(currentPath, child.name ?: "")
            if (shouldIgnore(childPath, child.isDirectory, ignorePatterns)) continue
            if (child.isDirectory) {
                grepWorkspace(
                    document = child,
                    currentPath = childPath,
                    regex = regex,
                    includeRegex = includeRegex,
                    limit = limit,
                    maxLineLength = maxLineLength,
                    ignorePatterns = ignorePatterns,
                    output = output,
                )
                continue
            }
            if (includeRegex != null && !includeRegex.matches(childPath)) continue
            if (looksBinary(child)) continue
            contentResolver.openInputStream(child.uri)?.bufferedReader()?.useLines { lines ->
                var lineNumber = 0
                for (rawLine in lines) {
                    if (output.size >= limit) return
                    lineNumber += 1
                    if (!regex.containsMatchIn(rawLine)) continue
                    val text =
                        if (rawLine.length > maxLineLength) {
                            rawLine.substring(0, maxLineLength) + "..."
                        } else {
                            rawLine
                        }
                    output.add(
                        mapOf(
                            "path" to childPath,
                            "line" to lineNumber,
                            "text" to text,
                        ),
                    )
                }
            }
        }
    }

    private fun childPath(parent: String, name: String): String {
        return if (parent.isEmpty()) name else "$parent/$name"
    }

    private fun toEntry(document: DocumentFile, path: String): Map<String, Any?> {
        return mapOf(
            "path" to path,
            "name" to (document.name ?: path.substringAfterLast('/')),
            "isDirectory" to document.isDirectory,
            "lastModified" to document.lastModified().toInt(),
            "size" to document.length().toInt(),
            "mimeType" to document.type,
        )
    }

    private fun shouldIgnore(path: String, isDirectory: Boolean, ignorePatterns: List<String>): Boolean {
        val normalized = path.trim('/')
        for (pattern in ignorePatterns) {
            val candidate = pattern.trim()
            if (candidate.isEmpty()) continue
            val regex = globToRegex(candidate)
            if (regex.matches(normalized) || regex.matches("$normalized/")) return true
            if (candidate.endsWith("/")) {
                val prefix = candidate.removeSuffix("/").trim('/')
                if (normalized == prefix || normalized.startsWith("$prefix/")) return true
            }
            if (isDirectory && regex.matches("$normalized/")) return true
        }
        return false
    }

    private fun globToRegex(pattern: String): Regex {
        val normalized = pattern.trim().ifEmpty { "*" }
        val builder = StringBuilder("^")
        var index = 0
        while (index < normalized.length) {
            val char = normalized[index]
            when (char) {
                '*' -> {
                    val next = normalized.getOrNull(index + 1)
                    if (next == '*') {
                        builder.append(".*")
                        index += 2
                    } else {
                        builder.append("[^/]*")
                        index += 1
                    }
                }
                '?' -> {
                    builder.append(".")
                    index += 1
                }
                '{' -> {
                    val end = normalized.indexOf('}', startIndex = index)
                    if (end > index) {
                        val body = normalized.substring(index + 1, end)
                        val parts = body.split(",").joinToString("|") { Regex.escape(it) }
                        builder.append("($parts)")
                        index = end + 1
                    } else {
                        builder.append(Regex.escape(char.toString()))
                        index += 1
                    }
                }
                else -> {
                    builder.append(Regex.escape(char.toString()))
                    index += 1
                }
            }
        }
        builder.append("$")
        return Regex(builder.toString())
    }

    private fun looksBinary(document: DocumentFile): Boolean {
        val mime = document.type ?: ""
        if (mime.startsWith("text/")) return false
        if (mime.startsWith("image/")) return true
        if (mime == "application/pdf") return true
        val name = document.name?.lowercase() ?: return false
        val textExtensions =
            listOf(
                ".dart",
                ".kt",
                ".java",
                ".md",
                ".txt",
                ".yaml",
                ".yml",
                ".json",
                ".xml",
                ".gradle",
                ".properties",
                ".js",
                ".ts",
                ".tsx",
                ".jsx",
                ".html",
                ".css",
                ".scss",
                ".sh",
            )
        return textExtensions.none { name.endsWith(it) }
    }
}
