package com.magent.mobile_agent

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.PublicKey
import java.net.InetSocketAddress
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.concurrent.ExecutorService
import org.apache.sshd.common.NamedResource
import org.apache.sshd.common.util.security.SecurityUtils
import org.eclipse.jgit.api.CloneCommand
import org.eclipse.jgit.api.CommitCommand
import org.eclipse.jgit.api.FetchCommand
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.api.PullCommand
import org.eclipse.jgit.api.PushCommand
import org.eclipse.jgit.diff.DiffEntry
import org.eclipse.jgit.diff.DiffFormatter
import org.eclipse.jgit.diff.RawTextComparator
import org.eclipse.jgit.lib.Constants
import org.eclipse.jgit.lib.ObjectId
import org.eclipse.jgit.lib.PersonIdent
import org.eclipse.jgit.lib.Repository
import org.eclipse.jgit.revwalk.RevCommit
import org.eclipse.jgit.revwalk.RevWalk
import org.eclipse.jgit.transport.CredentialsProvider
import org.eclipse.jgit.api.TransportCommand
import org.eclipse.jgit.transport.sshd.ServerKeyDatabase
import org.eclipse.jgit.transport.sshd.SshdSessionFactory
import org.eclipse.jgit.transport.sshd.SshdSessionFactoryBuilder
import org.eclipse.jgit.transport.PushResult
import org.eclipse.jgit.transport.RefSpec
import org.eclipse.jgit.transport.SshTransport
import org.eclipse.jgit.transport.UsernamePasswordCredentialsProvider

class GitNetworkBridge(
    private val activity: FlutterActivity,
    private val executor: ExecutorService,
) {
    @Volatile
    private var jGitEnvironmentInitialized = false

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobile_agent/git_network")
            .setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "discoverRepository" -> runGitCall(result) { handleDiscoverRepository(call) }
            "initRepository" -> runGitCall(result) { handleInitRepository(call) }
            "cloneRepository" -> runGitCall(result) { handleCloneRepository(call) }
            "statusRepository" -> runGitCall(result) { handleStatusRepository(call) }
            "addRepositoryPaths" -> runGitCall(result) { handleAddRepositoryPaths(call) }
            "addAllRepositoryPaths" -> runGitCall(result) { handleAddAllRepositoryPaths(call) }
            "unstageRepositoryPath" -> runGitCall(result) { handleUnstageRepositoryPath(call) }
            "commitRepository" -> runGitCall(result) { handleCommitRepository(call, amend = false) }
            "amendCommitRepository" -> runGitCall(result) { handleCommitRepository(call, amend = true) }
            "logRepository" -> runGitCall(result) { handleLogRepository(call) }
            "showRepositoryCommit" -> runGitCall(result) { handleShowRepositoryCommit(call) }
            "diffRepository" -> runGitCall(result) { handleDiffRepository(call) }
            "currentRepositoryBranch" -> runGitCall(result) { handleCurrentRepositoryBranch(call) }
            "listRepositoryBranches" -> runGitCall(result) { handleListRepositoryBranches(call) }
            "createRepositoryBranch" -> runGitCall(result) { handleCreateRepositoryBranch(call) }
            "deleteRepositoryBranch" -> runGitCall(result) { handleDeleteRepositoryBranch(call) }
            "checkoutRepositoryTarget" -> runGitCall(result) { handleCheckoutRepositoryTarget(call) }
            "checkoutRepositoryNewBranch" -> runGitCall(result) { handleCheckoutRepositoryNewBranch(call) }
            "restoreRepositoryFile" -> runGitCall(result) { handleRestoreRepositoryFile(call) }
            "mergeRepositoryBranch" -> runGitCall(result) { handleMergeRepositoryBranch(call) }
            "fetchRepository" -> runGitCall(result) { handleFetchRepository(call) }
            "pullRepository" -> runGitCall(result) { handlePullRepository(call) }
            "pushRepository" -> runGitCall(result) { handlePushRepository(call) }
            "rebaseRepositoryTarget" -> runGitCall(result) { handleRebaseRepositoryTarget(call) }
            "getRepositoryConfigValue" -> runGitCall(result) { handleGetRepositoryConfigValue(call) }
            "setRepositoryConfigValue" -> runGitCall(result) { handleSetRepositoryConfigValue(call) }
            "getRepositoryRemoteUrl" -> runGitCall(result) { handleGetRepositoryRemoteUrl(call) }
            else -> result.notImplemented()
        }
    }

    private fun runGitCall(
        result: MethodChannel.Result,
        action: () -> Map<String, Any?>,
    ) {
        executor.execute {
            try {
                ensureJGitEnvironment()
                val value = action()
                activity.runOnUiThread {
                    result.success(value)
                }
            } catch (error: Throwable) {
                activity.runOnUiThread {
                    result.error("git_network_error", describeError(error), null)
                }
            }
        }
    }

    private fun ensureJGitEnvironment() {
        if (jGitEnvironmentInitialized) {
            return
        }
        synchronized(this) {
            if (jGitEnvironmentInitialized) {
                return
            }
            val homeDir = File(activity.filesDir, "jgit-home").apply { mkdirs() }
            File(homeDir, ".ssh").apply { mkdirs() }
            System.setProperty("user.home", homeDir.absolutePath)
            System.setProperty("java.io.tmpdir", activity.cacheDir.absolutePath)
            jGitEnvironmentInitialized = true
        }
    }

    private fun handleDiscoverRepository(call: MethodCall): Map<String, Any?> {
        val path = requireString(call, "path")
        val builder = org.eclipse.jgit.storage.file.FileRepositoryBuilder()
            .findGitDir(File(path))
        val gitDir = builder.gitDir
            ?: return mapOf(
                "success" to false,
                "error" to "Not a git repository",
            )
        builder.build().use { repository ->
            return mapOf(
                "success" to true,
                "workDir" to (repository.workTree?.absolutePath ?: gitDir.parentFile?.absolutePath ?: path),
            )
        }
    }

    private fun handleInitRepository(call: MethodCall): Map<String, Any?> {
        val path = requireString(call, "path")
        Git.init().setDirectory(File(path)).call().use { _ ->
            return mapOf(
                "success" to true,
                "workDir" to path,
            )
        }
    }

    private fun handleCloneRepository(call: MethodCall): Map<String, Any?> {
        val url = requireString(call, "url")
        val path = requireString(call, "path")
        val remoteName = call.argument<String>("remoteName")?.trim().orEmpty().ifEmpty { "origin" }
        val branch = call.argument<String>("branch")?.trim().orEmpty().ifEmpty { null }
        val auth = parseAuth(call.argument<Map<String, Any?>>("auth"))
        val targetDir = File(path)
        if (targetDir.exists() && targetDir.list()?.isNotEmpty() == true) {
            throw IllegalArgumentException("Target directory already exists and is not empty: $path")
        }

        var git: Git? = null
        try {
            val command = Git.cloneRepository()
                .setURI(normalizeRemoteUrl(url, auth))
                .setDirectory(targetDir)
                .setRemote(remoteName)
                .setCloneAllBranches(branch == null)
            if (branch != null) {
                command.setBranch("refs/heads/$branch")
            }
            configureTransport(command, auth)
            git = command.call()
            val defaultBranch = git.repository.branch
            return mapOf(
                "success" to true,
                "defaultBranch" to defaultBranch,
                "objectsReceived" to 0,
            )
        } catch (error: Throwable) {
            cleanupDirectory(targetDir)
            return mapOf(
                "success" to false,
                "error" to describeError(error),
            )
        } finally {
            git?.close()
        }
    }

    private fun handleStatusRepository(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        Git.open(File(workDir)).use { git ->
            val status = git.status().call()
            val repository = git.repository
            val branch = currentBranch(repository)
            return mapOf(
                "success" to true,
                "branch" to branch,
                "head" to repository.resolve(Constants.HEAD)?.name,
                "clean" to status.isClean,
                "staged" to buildStatusEntries(
                    added = status.added,
                    changed = status.changed,
                    removed = status.removed,
                ),
                "unstaged" to buildStatusEntries(
                    modified = status.modified,
                    missing = status.missing,
                    conflicting = status.conflicting,
                ),
                "untracked" to status.untracked.sorted().map { path ->
                    mapOf(
                        "path" to path,
                        "status" to "untracked",
                    )
                },
            )
        }
    }

    private fun handleAddRepositoryPaths(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val rawPaths = call.argument<List<*>>("paths") ?: emptyList<Any?>()
        val paths = rawPaths.mapNotNull { it?.toString()?.trim() }.filter { it.isNotEmpty() }
        if (paths.isEmpty()) {
            throw IllegalArgumentException("Missing required parameter: paths")
        }
        Git.open(File(workDir)).use { git ->
            val command = git.add()
            paths.forEach { command.addFilepattern(it) }
            command.call()
            return mapOf("success" to true)
        }
    }

    private fun handleAddAllRepositoryPaths(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        Git.open(File(workDir)).use { git ->
            git.add()
                .addFilepattern(".")
                .setUpdate(false)
                .call()
            return mapOf("success" to true)
        }
    }

    private fun handleUnstageRepositoryPath(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val path = requireString(call, "path")
        Git.open(File(workDir)).use { git ->
            git.reset().addPath(path).call()
            return mapOf("success" to true)
        }
    }

    private fun handleFetchRepository(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val remoteName = call.argument<String>("remoteName")?.trim().orEmpty().ifEmpty { "origin" }
        val branch = call.argument<String>("branch")?.trim().orEmpty().ifEmpty { null }
        val auth = parseAuth(call.argument<Map<String, Any?>>("auth"))
        Git.open(File(workDir)).use { git ->
            val command = git.fetch().setRemote(remoteName).setRemoveDeletedRefs(false)
            if (branch != null) {
                command.setRefSpecs(
                    RefSpec("+refs/heads/$branch:refs/remotes/$remoteName/$branch"),
                )
            }
            configureTransport(command, auth)
            val result = command.call()
            val updatedRefs = result.trackingRefUpdates
                .mapNotNull { it.localName ?: it.remoteName }
            return mapOf(
                "success" to true,
                "updatedRefs" to updatedRefs,
                "objectsReceived" to 0,
            )
        }
    }

    private fun handleCommitRepository(
        call: MethodCall,
        amend: Boolean,
    ): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val message = requireString(call, "message")
        val authorName = call.argument<String>("authorName")?.trim().orEmpty().ifEmpty { null }
        val authorEmail = call.argument<String>("authorEmail")?.trim().orEmpty().ifEmpty { null }
        Git.open(File(workDir)).use { git ->
            val command = git.commit()
                .setMessage(message)
                .setAmend(amend)
            configureCommitIdentity(command, authorName, authorEmail)
            val commit = command.call()
            val author = commit.authorIdent
            val committer = commit.committerIdent
            return mapOf(
                "success" to true,
                "hash" to commit.name,
                "tree" to commit.tree.name,
                "parents" to commit.parents.map { it.name },
                "message" to commit.fullMessage,
                "authorName" to author.name,
                "authorEmail" to author.emailAddress,
                "authorTimestampMs" to author.`when`.time,
                "authorTimezone" to formatTimezoneOffset(author.timeZoneOffset),
                "committerName" to committer.name,
                "committerEmail" to committer.emailAddress,
                "committerTimestampMs" to committer.`when`.time,
                "committerTimezone" to formatTimezoneOffset(committer.timeZoneOffset),
            )
        }
    }

    private fun handleLogRepository(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val maxCount = call.argument<Int>("maxCount") ?: 20
        val firstParentOnly = call.argument<Boolean>("firstParentOnly") == true
        val since = parseDateFilter(call.argument<String>("since"))
        val until = parseDateFilter(call.argument<String>("until"))
        Git.open(File(workDir)).use { git ->
            val commits = if (firstParentOnly) {
                loadFirstParentHistory(git.repository, maxCount, since, until)
            } else {
                git.log()
                    .setMaxCount(maxCount.coerceAtLeast(1))
                    .call()
                    .mapNotNull { commit ->
                        val timestampMs = commit.commitTime.toLong() * 1000L
                        if ((since == null || timestampMs >= since) &&
                            (until == null || timestampMs <= until)
                        ) {
                            commitPayload(commit)
                        } else {
                            null
                        }
                    }
                    .toList()
            }
            return mapOf(
                "success" to true,
                "commits" to commits,
            )
        }
    }

    private fun handleShowRepositoryCommit(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val ref = requireString(call, "ref")
        Git.open(File(workDir)).use { git ->
            val objectId = git.repository.resolve(ref)
                ?: throw IllegalArgumentException("Unknown ref: $ref")
            RevWalk(git.repository).use { revWalk ->
                val commit = revWalk.parseCommit(objectId)
                return mapOf(
                    "success" to true,
                    "commit" to commitPayload(commit),
                )
            }
        }
    }

    private fun handleDiffRepository(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val rawPaths = call.argument<List<*>>("paths") ?: emptyList<Any?>()
        val paths = rawPaths.mapNotNull { it?.toString()?.trim() }.filter { it.isNotEmpty() }.toSet()
        Git.open(File(workDir)).use { git ->
            val out = ByteArrayOutputStream()
            DiffFormatter(out).use { formatter ->
                formatter.setRepository(git.repository)
                formatter.setDetectRenames(true)
                formatter.setDiffComparator(RawTextComparator.DEFAULT)

                val staged = git.diff().setCached(true).call().filter { matchesDiffPaths(it, paths) }
                if (staged.isNotEmpty()) {
                    out.write("Staged changes:\n".toByteArray(StandardCharsets.UTF_8))
                    staged.forEach { formatter.format(it) }
                    out.write("\n".toByteArray(StandardCharsets.UTF_8))
                }

                val unstaged = git.diff().call().filter { matchesDiffPaths(it, paths) }
                if (unstaged.isNotEmpty()) {
                    out.write("Unstaged changes:\n".toByteArray(StandardCharsets.UTF_8))
                    unstaged.forEach { formatter.format(it) }
                    out.write("\n".toByteArray(StandardCharsets.UTF_8))
                }
            }
            val status = git.status().call()
            val untracked = status.untracked.sorted().filter { paths.isEmpty() || paths.contains(it) }
            if (untracked.isNotEmpty()) {
                out.write("Untracked files:\n".toByteArray(StandardCharsets.UTF_8))
                untracked.forEach { path ->
                    out.write("+++ $path\n".toByteArray(StandardCharsets.UTF_8))
                }
            }
            val diffText = out.toString(StandardCharsets.UTF_8.name()).trim().ifEmpty { "No changes." }
            return mapOf(
                "success" to true,
                "diff" to diffText,
            )
        }
    }

    private fun handleCurrentRepositoryBranch(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        Git.open(File(workDir)).use { git ->
            return mapOf(
                "success" to true,
                "branch" to currentBranch(git.repository),
                "head" to git.repository.resolve(Constants.HEAD)?.name,
            )
        }
    }

    private fun handleListRepositoryBranches(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        Git.open(File(workDir)).use { git ->
            val branches = git.branchList().call()
                .map { Repository.shortenRefName(it.name) }
                .sorted()
            return mapOf(
                "success" to true,
                "branches" to branches,
                "current" to currentBranch(git.repository),
            )
        }
    }

    private fun handleCreateRepositoryBranch(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val name = requireString(call, "name")
        val startPoint = call.argument<String>("startPoint")?.trim().orEmpty().ifEmpty { null }
        Git.open(File(workDir)).use { git ->
            val command = git.branchCreate().setName(name)
            if (startPoint != null) {
                command.setStartPoint(startPoint)
            }
            command.call()
            return mapOf("success" to true)
        }
    }

    private fun handleDeleteRepositoryBranch(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val name = requireString(call, "name")
        val force = call.argument<Boolean>("force") == true
        Git.open(File(workDir)).use { git ->
            git.branchDelete()
                .setBranchNames(name)
                .setForce(force)
                .call()
            return mapOf("success" to true)
        }
    }

    private fun handleCheckoutRepositoryTarget(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val target = requireString(call, "target")
        Git.open(File(workDir)).use { git ->
            git.checkout()
                .setName(target)
                .call()
            return mapOf("success" to true)
        }
    }

    private fun handleCheckoutRepositoryNewBranch(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val name = requireString(call, "name")
        Git.open(File(workDir)).use { git ->
            git.checkout()
                .setCreateBranch(true)
                .setName(name)
                .call()
            return mapOf("success" to true)
        }
    }

    private fun handleRestoreRepositoryFile(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val path = requireString(call, "path")
        Git.open(File(workDir)).use { git ->
            git.checkout()
                .addPath(path)
                .call()
            return mapOf("success" to true)
        }
    }

    private fun handleMergeRepositoryBranch(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val branch = requireString(call, "branch")
        Git.open(File(workDir)).use { git ->
            val ref = git.repository.findRef(branch)
                ?: git.repository.findRef("refs/heads/$branch")
                ?: git.repository.findRef("refs/remotes/$branch")
                ?: throw IllegalArgumentException("Unknown ref: $branch")
            val result = git.merge().include(ref).call()
            val conflicts = result.conflicts?.keys?.sorted() ?: emptyList()
            val mergeStatus = result.mergeStatus.name
            return mapOf(
                "success" to (mergeStatus !in setOf("FAILED", "CONFLICTING", "NOT_SUPPORTED") && conflicts.isEmpty()),
                "conflicts" to conflicts,
                "mergeCommit" to result.newHead?.name,
                "status" to mergeStatus,
                "error" to if (mergeStatus in setOf("FAILED", "CONFLICTING", "NOT_SUPPORTED")) "Merge failed: $mergeStatus" else null,
            )
        }
    }

    private fun handlePullRepository(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val remoteName = call.argument<String>("remoteName")?.trim().orEmpty().ifEmpty { "origin" }
        val branch = call.argument<String>("branch")?.trim().orEmpty().ifEmpty { null }
        val rebase = call.argument<Boolean>("rebase") == true
        val auth = parseAuth(call.argument<Map<String, Any?>>("auth"))
        Git.open(File(workDir)).use { git ->
            val command = git.pull().setRemote(remoteName)
            if (branch != null) {
                command.setRemoteBranchName(branch)
            }
            command.setRebase(rebase)
            configureTransport(command, auth)
            val result = command.call()
            val fetchUpdates = result.fetchResult?.trackingRefUpdates
                ?.mapNotNull { it.localName ?: it.remoteName }
                ?: emptyList()
            val success = result.isSuccessful
            return mapOf(
                "success" to success,
                "fetchSuccess" to (result.fetchResult != null),
                "updatedRefs" to fetchUpdates,
                "objectsReceived" to 0,
                "error" to if (success) null else buildPullError(result),
            )
        }
    }

    private fun handlePushRepository(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val remoteName = call.argument<String>("remoteName")?.trim().orEmpty().ifEmpty { "origin" }
        val refspec = call.argument<String>("refspec")?.trim().orEmpty().ifEmpty { null }
        val force = call.argument<Boolean>("force") == true
        val auth = parseAuth(call.argument<Map<String, Any?>>("auth"))
        Git.open(File(workDir)).use { git ->
            val branch = git.repository.branch
            val effectiveRefspec = refspec ?: "refs/heads/$branch:refs/heads/$branch"
            val command = git.push()
                .setRemote(remoteName)
                .setRefSpecs(RefSpec(effectiveRefspec))
                .setForce(force)
            configureTransport(command, auth)
            val results = command.call().toList()
            val error = extractPushError(results)
            return mapOf(
                "success" to (error == null),
                "pushedRefs" to listOf(effectiveRefspec),
                "error" to error,
            )
        }
    }

    private fun handleRebaseRepositoryTarget(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val targetRef = requireString(call, "targetRef")
        Git.open(File(workDir)).use { git ->
            val result = git.rebase()
                .setUpstream(targetRef)
                .call()
            val conflicts = git.status().call().conflicting.toList().sorted()
            val rebaseStatus = result.status.name
            return mapOf(
                "success" to (rebaseStatus !in setOf("STOPPED", "FAILED", "CONFLICTS", "UNCOMMITTED_CHANGES") && conflicts.isEmpty()),
                "conflicts" to conflicts,
                "newHead" to git.repository.resolve(Constants.HEAD)?.name,
                "status" to rebaseStatus,
                "error" to if (rebaseStatus in setOf("STOPPED", "FAILED", "CONFLICTS", "UNCOMMITTED_CHANGES")) "Rebase failed: $rebaseStatus" else null,
            )
        }
    }

    private fun handleGetRepositoryConfigValue(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val section = requireString(call, "section")
        val key = requireString(call, "key")
        Git.open(File(workDir)).use { git ->
            return mapOf(
                "success" to true,
                "value" to git.repository.config.getString(section, null, key),
            )
        }
    }

    private fun handleSetRepositoryConfigValue(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val section = requireString(call, "section")
        val key = requireString(call, "key")
        val value = requireString(call, "value")
        Git.open(File(workDir)).use { git ->
            git.repository.config.setString(section, null, key, value)
            git.repository.config.save()
            return mapOf("success" to true)
        }
    }

    private fun handleGetRepositoryRemoteUrl(call: MethodCall): Map<String, Any?> {
        val workDir = requireString(call, "workDir")
        val remoteName = call.argument<String>("remoteName")?.trim().orEmpty().ifEmpty { "origin" }
        Git.open(File(workDir)).use { git ->
            return mapOf(
                "success" to true,
                "url" to git.repository.config.getString("remote", remoteName, "url"),
            )
        }
    }

    private fun buildPullError(result: org.eclipse.jgit.api.PullResult): String {
        val mergeStatus = result.mergeResult?.mergeStatus?.toString()
        if (!mergeStatus.isNullOrBlank()) {
            return "Pull failed: $mergeStatus"
        }
        val rebaseStatus = result.rebaseResult?.status?.toString()
        if (!rebaseStatus.isNullOrBlank()) {
            return "Pull failed: $rebaseStatus"
        }
        return "Pull failed"
    }

    private fun extractPushError(results: List<PushResult>): String? {
        for (result in results) {
            val message = result.messages?.trim().orEmpty()
            if (message.isNotEmpty()) {
                return message
            }
            for (update in result.remoteUpdates) {
                val status = update.status
                if (status != org.eclipse.jgit.transport.RemoteRefUpdate.Status.OK &&
                    status != org.eclipse.jgit.transport.RemoteRefUpdate.Status.UP_TO_DATE
                ) {
                    return "Push failed: ${update.remoteName} ($status)"
                }
            }
        }
        return null
    }

    private fun buildStatusEntries(
        added: Set<String> = emptySet(),
        changed: Set<String> = emptySet(),
        removed: Set<String> = emptySet(),
        modified: Set<String> = emptySet(),
        missing: Set<String> = emptySet(),
        conflicting: Set<String> = emptySet(),
    ): List<Map<String, Any?>> {
        val entries = mutableListOf<Map<String, Any?>>()
        added.sorted().forEach { path ->
            entries += mapOf("path" to path, "status" to "added")
        }
        changed.sorted().forEach { path ->
            entries += mapOf("path" to path, "status" to "modified")
        }
        removed.sorted().forEach { path ->
            entries += mapOf("path" to path, "status" to "deleted")
        }
        modified.sorted().forEach { path ->
            entries += mapOf("path" to path, "status" to "modified")
        }
        missing.sorted().forEach { path ->
            entries += mapOf("path" to path, "status" to "deleted")
        }
        conflicting.sorted().forEach { path ->
            entries += mapOf("path" to path, "status" to "unmerged")
        }
        return entries
    }

    private fun currentBranch(repository: Repository): String? {
        val fullBranch = repository.fullBranch ?: return null
        return if (ObjectId.isId(fullBranch)) {
            null
        } else {
            Repository.shortenRefName(fullBranch)
        }
    }

    private fun commitPayload(commit: RevCommit): Map<String, Any?> {
        val author = commit.authorIdent
        val committer = commit.committerIdent
        return mapOf(
            "hash" to commit.name,
            "tree" to commit.tree.name,
            "parents" to commit.parents.map { it.name },
            "message" to commit.fullMessage,
            "authorName" to author.name,
            "authorEmail" to author.emailAddress,
            "authorTimestampMs" to author.`when`.time,
            "authorTimezone" to formatTimezoneOffset(author.timeZoneOffset),
            "committerName" to committer.name,
            "committerEmail" to committer.emailAddress,
            "committerTimestampMs" to committer.`when`.time,
            "committerTimezone" to formatTimezoneOffset(committer.timeZoneOffset),
        )
    }

    private fun loadFirstParentHistory(
        repository: Repository,
        maxCount: Int,
        since: Long?,
        until: Long?,
    ): List<Map<String, Any?>> {
        val head = repository.resolve(Constants.HEAD) ?: return emptyList()
        RevWalk(repository).use { revWalk ->
            var current = revWalk.parseCommit(head)
            val commits = mutableListOf<Map<String, Any?>>()
            while (current != null && commits.size < maxCount.coerceAtLeast(1)) {
                val timestampMs = current.commitTime.toLong() * 1000L
                if ((since == null || timestampMs >= since) &&
                    (until == null || timestampMs <= until)
                ) {
                    commits += commitPayload(current)
                }
                current = if (current.parentCount > 0) {
                    revWalk.parseCommit(current.getParent(0))
                } else {
                    null
                }
            }
            return commits
        }
    }

    private fun parseDateFilter(value: String?): Long? {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty()) {
            return null
        }
        return try {
            Instant.parse(trimmed).toEpochMilli()
        } catch (_: Throwable) {
            try {
                LocalDate.parse(trimmed).atStartOfDay().toInstant(ZoneOffset.UTC).toEpochMilli()
            } catch (_: Throwable) {
                null
            }
        }
    }

    private fun matchesDiffPaths(entry: DiffEntry, paths: Set<String>): Boolean {
        if (paths.isEmpty()) {
            return true
        }
        return paths.contains(entry.newPath) || paths.contains(entry.oldPath)
    }

    private fun configureTransport(
        command: TransportCommand<*, *>,
        auth: GitAuth?,
    ) {
        if (auth == null) {
            return
        }
        if (auth.type == "https-basic") {
            command.setCredentialsProvider(
                UsernamePasswordCredentialsProvider(
                    auth.username,
                    auth.secret.orEmpty(),
                ),
            )
            return
        }
        if (auth.type == "ssh" && !auth.privateKeyPem.isNullOrBlank()) {
            val sessionFactory = createSshSessionFactory(auth)
            command.setTransportConfigCallback { transport ->
                if (transport is SshTransport) {
                    transport.sshSessionFactory = sessionFactory
                }
            }
        }
    }

    private fun configureCommitIdentity(
        command: CommitCommand,
        authorName: String?,
        authorEmail: String?,
    ) {
        if (authorName.isNullOrBlank() || authorEmail.isNullOrBlank()) {
            return
        }
        val identity = PersonIdent(authorName, authorEmail)
        command.setAuthor(identity)
        command.setCommitter(identity)
    }

    private fun createSshSessionFactory(auth: GitAuth): SshdSessionFactory {
        val sshHome = File(activity.cacheDir, "git-ssh-home").apply { mkdirs() }
        val sshDir = File(sshHome, ".ssh").apply { mkdirs() }
        return SshdSessionFactoryBuilder()
            .setHomeDirectory(sshHome)
            .setSshDirectory(sshDir)
            .setPreferredAuthentications("publickey")
            .setConfigFile { null }
            .setDefaultIdentities { emptyList() }
            .setDefaultKnownHostsFiles { emptyList() }
            .setDefaultKeysProvider { loadSshKeyPairs(auth) }
            .setServerKeyDatabase { _, _ ->
                object : ServerKeyDatabase {
                    override fun lookup(
                        connectAddress: String,
                        remoteAddress: InetSocketAddress,
                        config: ServerKeyDatabase.Configuration,
                    ): List<PublicKey> = emptyList()

                    override fun accept(
                        connectAddress: String,
                        remoteAddress: InetSocketAddress,
                        serverKey: PublicKey,
                        config: ServerKeyDatabase.Configuration,
                        provider: CredentialsProvider?,
                    ): Boolean = true
                }
            }
            .build(null)
    }

    private fun loadSshKeyPairs(auth: GitAuth): Iterable<java.security.KeyPair> {
        val privateKeyPem = auth.privateKeyPem?.trim()
        if (privateKeyPem.isNullOrEmpty()) {
            throw IllegalArgumentException("SSH private key is missing")
        }
        ByteArrayInputStream(privateKeyPem.toByteArray(StandardCharsets.UTF_8)).use { input ->
            return SecurityUtils.loadKeyPairIdentities(
                null,
                object : NamedResource {
                    override fun getName(): String = "mag-key"
                },
                input,
                null,
            )
        }
    }

    private fun normalizeRemoteUrl(url: String, auth: GitAuth?): String {
        if (auth == null || auth.type != "ssh" || auth.username.isBlank()) {
            return url
        }
        if (url.startsWith("ssh://")) {
            val uri = java.net.URI(url)
            if (!uri.userInfo.isNullOrBlank()) {
                return url
            }
            val authority = buildString {
                append(auth.username)
                append("@")
                append(uri.host)
                if (uri.port != -1) {
                    append(":")
                    append(uri.port)
                }
            }
            return java.net.URI(
                uri.scheme,
                authority,
                uri.path,
                uri.query,
                uri.fragment,
            ).toString()
        }
        return if (url.contains("@")) url else "${auth.username}@$url"
    }

    private fun parseAuth(raw: Map<String, Any?>?): GitAuth? {
        if (raw == null) {
            return null
        }
        return GitAuth(
            type = raw["type"]?.toString().orEmpty(),
            username = raw["username"]?.toString().orEmpty(),
            secret = raw["secret"]?.toString(),
            privateKeyPem = raw["privateKeyPem"]?.toString(),
        )
    }

    private fun requireString(call: MethodCall, key: String): String {
        val value = call.argument<String>(key)?.trim()
        if (value.isNullOrEmpty()) {
            throw IllegalArgumentException("Missing required parameter: $key")
        }
        return value
    }

    private fun cleanupDirectory(dir: File) {
        try {
            if (dir.exists()) {
                dir.deleteRecursively()
            }
        } catch (_: Throwable) {
        }
    }

    private fun describeError(error: Throwable): String {
        val parts = linkedSetOf<String>()
        var current: Throwable? = error
        while (current != null) {
            val message = current.message?.trim().orEmpty()
            if (message.isNotEmpty()) {
                parts.add(message)
            } else {
                parts.add(current.javaClass.simpleName)
            }
            current = current.cause
        }
        if (parts.isEmpty()) {
            return error.toString()
        }
        val message = parts.joinToString(" | ")
        if (message.contains("Auth fail", ignoreCase = true)) {
            return "$message | SSH authentication failed. Check that the remote username is correct and the generated Ed25519 public key has been added to the git server."
        }
        return message
    }

    private fun formatTimezoneOffset(offsetMinutes: Int): String {
        val sign = if (offsetMinutes < 0) "-" else "+"
        val absolute = kotlin.math.abs(offsetMinutes)
        val hours = absolute / 60
        val minutes = absolute % 60
        return "%s%02d%02d".format(sign, hours, minutes)
    }
}

private data class GitAuth(
    val type: String,
    val username: String,
    val secret: String?,
    val privateKeyPem: String?,
)
