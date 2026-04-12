package com.magent.mobile_agent

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object {
        private const val PICK_WORKSPACE_REQUEST = 4107
        private const val MAX_COPY_DEPTH = 32
        private const val MAX_COPY_FILES = 5000
    }

    private class CopyStats(
        var files: Int = 0,
    )

    private var pendingResult: MethodChannel.Result? = null
    private val workspaceExecutor: ExecutorService by lazy {
        Executors.newFixedThreadPool(2)
    }
    private val gitNetworkBridge: GitNetworkBridge by lazy {
        GitNetworkBridge(this, workspaceExecutor)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobile_agent/workspace")
            .setMethodCallHandler(::handleWorkspaceCall)
        gitNetworkBridge.attach(flutterEngine)
    }

    override fun onDestroy() {
        workspaceExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun handleWorkspaceCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickWorkspace" -> {
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                startActivityForResult(intent, PICK_WORKSPACE_REQUEST)
            }
            "listDirectory" -> runWorkspaceCall(result) { handleListDirectory(call) }
            "getEntry" -> runWorkspaceCall(result) { handleGetEntry(call) }
            "searchEntries" -> runWorkspaceCall(result) { handleSearchEntries(call) }
            "grepText" -> runWorkspaceCall(result) { handleGrepText(call) }
            "readText" -> runWorkspaceCall(result) { handleReadText(call) }
            "readBytes" -> runWorkspaceCall(result) { handleReadBytes(call) }
            "writeText" -> runWorkspaceCall(result) { handleWriteText(call) }
            "writeBytes" -> runWorkspaceCall(result) { handleWriteBytes(call) }
            "deleteEntry" -> runWorkspaceCall(result) { handleDeleteEntry(call) }
            "renameEntry" -> runWorkspaceCall(result) { handleRenameEntry(call) }
            "moveEntry" -> runWorkspaceCall(result) { handleMoveEntry(call) }
            "copyEntry" -> runWorkspaceCall(result) { handleCopyEntry(call) }
            "resolveFilesystemPath" -> runWorkspaceCall(result) { handleResolveFilesystemPath(call) }
            else -> result.notImplemented()
        }
    }

    private fun runWorkspaceCall(
        result: MethodChannel.Result,
        action: () -> Any?,
    ) {
        workspaceExecutor.execute {
            try {
                val value = action()
                runOnUiThread {
                    result.success(value)
                }
            } catch (error: WorkspaceMethodException) {
                runOnUiThread {
                    result.error(error.code, error.message, error.details)
                }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error("workspace_error", error.message, null)
                }
            }
        }
    }

    private fun handleListDirectory(call: MethodCall): List<Map<String, Any?>> {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val offset = call.argument<Int>("offset") ?: 1
        val limit = call.argument<Int>("limit")
        val target = resolveDocument(treeUri, relativePath)
        if (target == null || !target.isDirectory) {
            throw WorkspaceMethodException("not_directory", "Target is not a directory")
        }
        val entries =
            target.listFiles()
                .map { toEntry(it, childPath(relativePath, it.name ?: "")) }
                .sortedWith(compareBy<Map<String, Any?>>({ !(it["isDirectory"] as Boolean) }, { (it["path"] as String).lowercase() }))
        val safeOffset = if (offset < 1) 1 else offset
        val start = (safeOffset - 1).coerceAtMost(entries.size)
        val end = if (limit == null || limit <= 0) entries.size else (start + limit).coerceAtMost(entries.size)
        return entries.subList(start, end)
    }

    private fun handleGetEntry(call: MethodCall): Map<String, Any?> {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val target = resolveDocument(treeUri, relativePath)
            ?: throw WorkspaceMethodException("not_found", "Unable to resolve entry")
        return toEntry(target, normalizeRelativePath(relativePath))
    }

    private fun handleSearchEntries(call: MethodCall): List<Map<String, Any?>> {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val pattern = call.argument<String>("pattern") ?: "*"
        val limit = call.argument<Int>("limit") ?: 100
        val filesOnly = call.argument<Boolean>("filesOnly") ?: true
        val ignorePatterns = call.argument<List<String>>("ignorePatterns") ?: emptyList()
        val target = resolveDocument(treeUri, relativePath)
        if (target == null || !target.isDirectory) {
            throw WorkspaceMethodException("not_directory", "Target is not a directory")
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
        return matches
    }

    private fun handleGrepText(call: MethodCall): List<Map<String, Any?>> {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val pattern =
            call.argument<String>("pattern")
                ?: throw WorkspaceMethodException("missing_pattern", "Missing pattern")
        val include = call.argument<String>("include")
        val limit = call.argument<Int>("limit") ?: 100
        val maxLineLength = call.argument<Int>("maxLineLength") ?: 2000
        val ignorePatterns = call.argument<List<String>>("ignorePatterns") ?: emptyList()
        val target = resolveDocument(treeUri, relativePath)
        if (target == null || !target.isDirectory) {
            throw WorkspaceMethodException("not_directory", "Target is not a directory")
        }
        val regex =
            try {
                Regex(pattern)
            } catch (error: Throwable) {
                throw WorkspaceMethodException("invalid_pattern", error.message ?: "Invalid pattern")
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
        return output
    }

    private fun handleReadText(call: MethodCall): String {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val target = resolveDocument(treeUri, relativePath)
        if (target == null || target.isDirectory) {
            throw WorkspaceMethodException("not_file", "Target is not a file")
        }
        contentResolver.openInputStream(target.uri)?.bufferedReader().use { reader ->
            return reader?.readText() ?: ""
        }
    }

    private fun handleReadBytes(call: MethodCall): ByteArray {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val target = resolveDocument(treeUri, relativePath)
        if (target == null || target.isDirectory) {
            throw WorkspaceMethodException("not_file", "Target is not a file")
        }
        contentResolver.openInputStream(target.uri).use { stream ->
            return stream?.readBytes() ?: ByteArray(0)
        }
    }

    private fun handleWriteText(call: MethodCall): Any? {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val content = call.argument<String>("content") ?: ""
        val target = ensureFile(treeUri, relativePath)
        if (target == null) {
            throw WorkspaceMethodException("write_failed", "Unable to create file", mapOf("path" to relativePath))
        }
        val stream = contentResolver.openOutputStream(target.uri, "wt")
        if (stream == null) {
            throw WorkspaceMethodException("write_failed", "Unable to open output stream", mapOf("path" to relativePath))
        }
        stream.bufferedWriter().use { writer ->
            writer.write(content)
        }
        return null
    }

    private fun handleWriteBytes(call: MethodCall): Any? {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
        val target = ensureFile(treeUri, relativePath)
        if (target == null) {
            throw WorkspaceMethodException("write_failed", "Unable to create file", mapOf("path" to relativePath))
        }
        val stream = contentResolver.openOutputStream(target.uri, "w")
        if (stream == null) {
            throw WorkspaceMethodException("write_failed", "Unable to open output stream", mapOf("path" to relativePath))
        }
        stream.use { output ->
            output.write(bytes)
            output.flush()
        }
        return null
    }

    private fun handleDeleteEntry(call: MethodCall): Boolean {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val target = resolveDocument(treeUri, relativePath)
            ?: throw WorkspaceMethodException("missing_entry", "Unable to resolve entry")
        return deleteRecursive(target)
    }

    private fun handleRenameEntry(call: MethodCall): Map<String, Any?> {
        val treeUri = requireTreeUri(call)
        val relativePath = call.argument<String>("relativePath") ?: ""
        val newName =
            call.argument<String>("newName")?.trim()
                ?: throw WorkspaceMethodException("missing_name", "Missing newName")
        if (newName.isEmpty() || newName.contains('/') || newName.contains('\\')) {
            throw WorkspaceMethodException("invalid_name", "newName must be a single path segment")
        }
        val source =
            resolveDocument(treeUri, relativePath)
                ?: throw WorkspaceMethodException("not_found", "Unable to resolve entry")
        val parentPath = parentRelativePath(relativePath)
        val newPath = if (parentPath.isEmpty()) newName else "$parentPath/$newName"
        val normalizedNew = normalizeRelativePath(newPath)
        if (normalizeRelativePath(relativePath) == normalizedNew) {
            return toEntry(source, normalizedNew)
        }
        if (resolveDocument(treeUri, newPath) != null) {
            throw WorkspaceMethodException("exists", "Destination already exists")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            if (!source.renameTo(newName)) {
                throw WorkspaceMethodException("rename_failed", "Rename failed")
            }
        } else {
            if (source.isDirectory) {
                throw WorkspaceMethodException("rename_unsupported", "Renaming directories requires API 21+")
            }
            copyFileTo(source, treeUri, normalizedNew)
            if (!source.delete()) {
                throw WorkspaceMethodException("rename_failed", "Could not remove source after copy")
            }
        }
        val resolved =
            resolveDocument(treeUri, newPath)
                ?: throw WorkspaceMethodException("not_found", "Unable to resolve renamed entry")
        return toEntry(resolved, normalizedNew)
    }

    private fun handleMoveEntry(call: MethodCall): Map<String, Any?> {
        val treeUri = requireTreeUri(call)
        val fromPath = call.argument<String>("fromPath") ?: ""
        val toPath = call.argument<String>("toPath") ?: ""
        val normalizedFrom = normalizeRelativePath(fromPath)
        val normalizedTo = normalizeRelativePath(toPath)
        if (normalizedFrom.isEmpty() || normalizedTo.isEmpty()) {
            throw WorkspaceMethodException("invalid_path", "Paths must not be empty")
        }
        if (normalizedFrom == normalizedTo) {
            val doc =
                resolveDocument(treeUri, fromPath)
                    ?: throw WorkspaceMethodException("not_found", "Source not found")
            return toEntry(doc, normalizedFrom)
        }
        if (normalizedTo.startsWith("$normalizedFrom/")) {
            throw WorkspaceMethodException("invalid_move", "Cannot move a path into itself")
        }
        val source =
            resolveDocument(treeUri, fromPath)
                ?: throw WorkspaceMethodException("not_found", "Source not found")
        if (resolveDocument(treeUri, toPath) != null) {
            throw WorkspaceMethodException("exists", "Destination already exists")
        }
        val destParentPath = parentRelativePath(toPath)
        val destName = fileNameSegment(toPath)
        val targetParent =
            resolveDocument(treeUri, destParentPath)
                ?: throw WorkspaceMethodException("not_found", "Target parent not found")
        val sourceParent =
            resolveDocument(treeUri, parentRelativePath(fromPath))
                ?: throw WorkspaceMethodException("not_found", "Source parent not found")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val newUri =
                DocumentsContract.moveDocument(
                    contentResolver,
                    source.uri,
                    sourceParent.uri,
                    targetParent.uri,
                ) ?: throw WorkspaceMethodException("move_failed", "moveDocument failed")
            var finalDoc = DocumentFile.fromSingleUri(this, newUri)
            if (finalDoc != null && finalDoc.name != destName) {
                if (!finalDoc.renameTo(destName)) {
                    throw WorkspaceMethodException("rename_failed", "Rename after move failed")
                }
            }
        } else {
            val stats = CopyStats()
            copyRecursive(source, treeUri, normalizedTo, depth = 0, stats)
            if (!deleteRecursive(source)) {
                throw WorkspaceMethodException("move_failed", "Could not remove source after copy")
            }
        }
        val resolved =
            resolveDocument(treeUri, toPath)
                ?: throw WorkspaceMethodException("not_found", "Unable to resolve moved entry")
        return toEntry(resolved, normalizedTo)
    }

    private fun handleCopyEntry(call: MethodCall): Map<String, Any?> {
        val treeUri = requireTreeUri(call)
        val fromPath = call.argument<String>("fromPath") ?: ""
        val toPath = call.argument<String>("toPath") ?: ""
        val normalizedFrom = normalizeRelativePath(fromPath)
        val normalizedTo = normalizeRelativePath(toPath)
        if (normalizedFrom.isEmpty() || normalizedTo.isEmpty()) {
            throw WorkspaceMethodException("invalid_path", "Paths must not be empty")
        }
        if (normalizedFrom == normalizedTo) {
            val doc =
                resolveDocument(treeUri, fromPath)
                    ?: throw WorkspaceMethodException("not_found", "Source not found")
            return toEntry(doc, normalizedFrom)
        }
        if (normalizedTo.startsWith("$normalizedFrom/")) {
            throw WorkspaceMethodException("invalid_copy", "Cannot copy a path into itself")
        }
        val source =
            resolveDocument(treeUri, fromPath)
                ?: throw WorkspaceMethodException("not_found", "Source not found")
        if (resolveDocument(treeUri, toPath) != null) {
            throw WorkspaceMethodException("exists", "Destination already exists")
        }
        val stats = CopyStats()
        copyRecursive(source, treeUri, normalizedTo, depth = 0, stats)
        val resolved =
            resolveDocument(treeUri, toPath)
                ?: throw WorkspaceMethodException("not_found", "Unable to resolve copy result")
        return toEntry(resolved, normalizedTo)
    }

    private fun copyRecursive(
        source: DocumentFile,
        treeUri: String,
        destRelativePath: String,
        depth: Int,
        stats: CopyStats,
    ) {
        if (depth > MAX_COPY_DEPTH) {
            throw WorkspaceMethodException("copy_too_deep", "Maximum directory depth exceeded")
        }
        if (source.isDirectory) {
            val created =
                createDirectoryPath(treeUri, destRelativePath)
                    ?: throw WorkspaceMethodException("copy_failed", "Could not create destination directory")
            if (!created.isDirectory) {
                throw WorkspaceMethodException("copy_failed", "Destination path is not a directory")
            }
            for (child in source.listFiles()) {
                val name = child.name ?: continue
                val childDest =
                    if (destRelativePath.isEmpty()) name else "$destRelativePath/$name"
                copyRecursive(child, treeUri, childDest, depth + 1, stats)
            }
        } else {
            stats.files += 1
            if (stats.files > MAX_COPY_FILES) {
                throw WorkspaceMethodException("copy_too_large", "Too many files to copy")
            }
            copyFileTo(source, treeUri, destRelativePath)
        }
    }

    private fun createDirectoryPath(
        treeUri: String,
        relativePath: String,
    ): DocumentFile? {
        val segments = normalizePathSegments(relativePath)
        if (segments.isEmpty()) {
            return DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
        }
        var current = DocumentFile.fromTreeUri(this, Uri.parse(treeUri)) ?: return null
        for (segment in segments) {
            val existing = current.findFile(segment)
            val next =
                if (existing != null) {
                    if (!existing.isDirectory) return null
                    existing
                } else {
                    current.createDirectory(segment) ?: return null
                }
            current = next
        }
        return current
    }

    private fun copyFileTo(
        source: DocumentFile,
        treeUri: String,
        destRelativePath: String,
    ) {
        val dest =
            ensureFile(treeUri, destRelativePath)
                ?: throw WorkspaceMethodException("copy_failed", "Unable to create destination file")
        contentResolver.openInputStream(source.uri).use { input ->
            if (input == null) {
                throw WorkspaceMethodException("copy_failed", "Unable to read source")
            }
            contentResolver.openOutputStream(dest.uri, "wt").use { output ->
                if (output == null) {
                    throw WorkspaceMethodException("copy_failed", "Unable to write destination")
                }
                input.copyTo(output)
            }
        }
    }

    private fun deleteRecursive(doc: DocumentFile): Boolean {
        if (doc.isDirectory) {
            for (child in doc.listFiles()) {
                if (!deleteRecursive(child)) {
                    return false
                }
            }
        }
        return doc.delete()
    }

    private fun parentRelativePath(relativePath: String): String {
        val normalized = normalizeRelativePath(relativePath)
        if (!normalized.contains('/')) {
            return ""
        }
        return normalized.substringBeforeLast('/')
    }

    private fun fileNameSegment(relativePath: String): String {
        val normalized = normalizeRelativePath(relativePath)
        return if (normalized.contains('/')) {
            normalized.substringAfterLast('/')
        } else {
            normalized
        }
    }

    private fun requireTreeUri(call: MethodCall): String {
        return call.argument<String>("treeUri")
            ?: throw WorkspaceMethodException("missing_tree", "Missing treeUri")
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

    private fun handleResolveFilesystemPath(call: MethodCall): String? {
        val treeUri =
            call.argument<String>("treeUri")
                ?: throw WorkspaceMethodException("missing_tree", "Missing treeUri")
        return resolveTreeUriToFilesystemPath(treeUri)
    }

    private fun resolveTreeUriToFilesystemPath(treeUri: String): String? {
        if (treeUri.startsWith("/")) {
            return treeUri
        }
        val uri = Uri.parse(treeUri)
        if (uri.scheme == "file") {
            return uri.path
        }
        if (uri.authority != "com.android.externalstorage.documents") {
            return null
        }

        val treeId =
            try {
                DocumentsContract.getTreeDocumentId(uri)
            } catch (_: Throwable) {
                null
            } ?: return null

        if (treeId.startsWith("raw:")) {
            return treeId.removePrefix("raw:")
        }

        val separator = treeId.indexOf(':')
        if (separator <= 0) {
            return null
        }

        val volume = treeId.substring(0, separator)
        val docPath = treeId.substring(separator + 1).trim('/')
        val basePath =
            when (volume.lowercase()) {
                "primary" -> "/storage/emulated/0"
                else -> "/storage/$volume"
            }

        val resolvedPath = if (docPath.isEmpty()) basePath else "$basePath/$docPath"
        if (isProtectedAndroidPath(resolvedPath)) {
            return null
        }
        return resolvedPath
    }

    private fun isProtectedAndroidPath(path: String): Boolean {
        val normalized = path.replace('\\', '/')
        return normalized == "/storage/emulated/0/Android" ||
            normalized.startsWith("/storage/emulated/0/Android/") ||
            Regex("^/storage/[^/]+/Android(?:/.*)?$").matches(normalized)
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

private class WorkspaceMethodException(
    val code: String,
    override val message: String,
    val details: Any? = null,
) : RuntimeException(message)
