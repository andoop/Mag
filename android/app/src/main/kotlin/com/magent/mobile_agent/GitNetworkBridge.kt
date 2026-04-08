package com.magent.mobile_agent

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.charset.StandardCharsets
import java.security.PublicKey
import java.net.InetSocketAddress
import java.util.concurrent.ExecutorService
import org.apache.sshd.common.NamedResource
import org.apache.sshd.common.util.security.SecurityUtils
import org.eclipse.jgit.api.CloneCommand
import org.eclipse.jgit.api.FetchCommand
import org.eclipse.jgit.api.Git
import org.eclipse.jgit.api.PullCommand
import org.eclipse.jgit.api.PushCommand
import org.eclipse.jgit.transport.CredentialsProvider
import org.eclipse.jgit.api.TransportCommand
import org.eclipse.jgit.transport.sshd.ServerKeyDatabase
import org.eclipse.jgit.transport.sshd.SshdSessionFactory
import org.eclipse.jgit.transport.sshd.SshdSessionFactoryBuilder
import org.eclipse.jgit.transport.PushResult
import org.eclipse.jgit.transport.RefSpec
import org.eclipse.jgit.transport.SshTransport
import org.eclipse.jgit.transport.UsernamePasswordCredentialsProvider
import org.eclipse.jgit.util.FS

class GitNetworkBridge(
    private val activity: FlutterActivity,
    private val executor: ExecutorService,
) {
    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mobile_agent/git_network")
            .setMethodCallHandler(::handleMethodCall)
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cloneRepository" -> runGitCall(result) { handleCloneRepository(call) }
            "fetchRepository" -> runGitCall(result) { handleFetchRepository(call) }
            "pullRepository" -> runGitCall(result) { handlePullRepository(call) }
            "pushRepository" -> runGitCall(result) { handlePushRepository(call) }
            else -> result.notImplemented()
        }
    }

    private fun runGitCall(
        result: MethodChannel.Result,
        action: () -> Map<String, Any?>,
    ) {
        executor.execute {
            try {
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
}

private data class GitAuth(
    val type: String,
    val username: String,
    val secret: String?,
    val privateKeyPem: String?,
)
