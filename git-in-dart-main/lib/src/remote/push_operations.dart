/// Push operation - upload objects and refs to remote
library;

import 'dart:io';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import '../core/repository.dart';
import '../remote/remote_manager.dart';
import '../exceptions/git_exceptions.dart';

/// Push result
class PushResult {
  final bool success;
  final List<String> pushedRefs;
  final String? error;

  const PushResult({
    required this.success,
    required this.pushedRefs,
    this.error,
  });
}

/// Push operation
class PushOperation {
  final GitRepository repo;
  final RemoteManager remoteManager;

  PushOperation(this.repo) : remoteManager = RemoteManager(repo.gitDir);

  /// Push to remote
  Future<PushResult> push(
    String remoteName, {
    Credentials? credentials,
    String? refspec,
    bool force = false,
  }) async {
    // Get remote
    final remote = await remoteManager.getRemote(remoteName);
    if (remote == null) {
      throw GitException('Remote not found: $remoteName');
    }

    // Default refspec: push current branch
    final currentBranch = await repo.getCurrentBranch();
    final pushRefspec =
        refspec ?? 'refs/heads/$currentBranch:refs/heads/$currentBranch';

    try {
      if (remote.isHttps) {
        return await _pushHttps(
          remote,
          pushRefspec,
          credentials as HttpsCredentials?,
          force,
        );
      } else if (remote.isSsh) {
        return await _pushSsh(
          remote,
          pushRefspec,
          credentials as SshCredentials?,
          force,
        );
      } else {
        throw GitException('Unsupported remote protocol: ${remote.url}');
      }
    } catch (e) {
      return PushResult(
        success: false,
        pushedRefs: [],
        error: e.toString(),
      );
    }
  }

  /// Push using HTTPS
  Future<PushResult> _pushHttps(
    Remote remote,
    String refspec,
    HttpsCredentials? credentials,
    bool force,
  ) async {
    final client = HttpClient();

    try {
      // Get current commit
      final commitHash = await repo.refs.resolveHead();

      // Build push request
      final pushUrl = '${remote.url}/git-receive-pack';
      final request = await client.postUrl(Uri.parse(pushUrl));

      if (credentials != null) {
        request.headers.set('Authorization', credentials.getAuthHeader());
      }
      request.headers
          .set('Content-Type', 'application/x-git-receive-pack-request');

      // Build pack protocol push
      // Simplified - real implementation would need pack file generation
      final pushData = _buildPushData(refspec, commitHash, force);
      request.write(pushData);

      final response = await request.close();

      if (response.statusCode != 200) {
        throw GitException('Failed to push: HTTP ${response.statusCode}');
      }

      return PushResult(
        success: true,
        pushedRefs: [refspec],
      );
    } finally {
      client.close();
    }
  }

  /// Push using SSH
  Future<PushResult> _pushSsh(
    Remote remote,
    String refspec,
    SshCredentials? credentials,
    bool force,
  ) async {
    if (credentials == null) {
      throw const GitException('SSH credentials required for SSH remote');
    }

    // Verify private key exists
    if (!await credentials.hasPrivateKey()) {
      throw GitException(
          'SSH private key not found: ${credentials.privateKeyPath}');
    }

    try {
      // Parse SSH URL
      final sshUrl = _parseSshUrl(remote.url);

      // Get current commit hash
      final commitHash = await repo.refs.resolveHead();

      // Read SSH private key
      final privateKeyFile = File(credentials.privateKeyPath);
      final privateKey = await privateKeyFile.readAsString();

      // Create SSH socket
      final socket = await SSHSocket.connect(
        sshUrl.host,
        sshUrl.port,
        timeout: const Duration(seconds: 30),
      );

      // Create SSH client
      final client = SSHClient(
        socket,
        username: sshUrl.username,
        identities: [
          ...SSHKeyPair.fromPem(privateKey, credentials.passphrase),
        ],
      );

      // Parse refspec
      final parts = refspec.split(':');
      final remoteRef = parts.length > 1 ? parts[1] : parts[0];

      // Build push command data
      final pushCommand = _buildSshPushCommand(
        commitHash,
        remoteRef,
        force,
      );

      // Execute git-receive-pack
      final session = await client.execute(
        'git-receive-pack ${sshUrl.path}',
      );

      // Send push data
      session.stdin.add(utf8.encode(pushCommand));
      await session.stdin.close();

      // Read response
      final errorBytes = await session.stderr.toList();
      final errorOutput = utf8.decode(errorBytes.expand((x) => x).toList());

      // Close SSH connection
      client.close();
      await client.done;

      // Check for errors
      if (errorOutput.isNotEmpty && errorOutput.contains('error')) {
        throw GitException('Push failed: $errorOutput');
      }

      return PushResult(
        success: true,
        pushedRefs: [refspec],
      );
    } catch (e) {
      throw GitException('SSH push failed: $e');
    }
  }

  /// Parse SSH URL to extract components
  _SshUrlComponents _parseSshUrl(String url) {
    // Handle git@github.com:user/repo.git format
    if (url.contains('@') && !url.startsWith('ssh://')) {
      final parts = url.split('@');
      final userPart = parts[0].replaceFirst('git://', '');
      final remaining = parts[1];

      final colonIndex = remaining.indexOf(':');
      final host = remaining.substring(0, colonIndex);
      final path = remaining.substring(colonIndex + 1);

      return _SshUrlComponents(
        username: userPart.isEmpty ? 'git' : userPart,
        host: host,
        port: 22,
        path: path.startsWith('/') ? path : '/$path',
      );
    }

    // Handle ssh://user@host/path format
    final uri = Uri.parse(url);
    return _SshUrlComponents(
      username: uri.userInfo.isEmpty ? 'git' : uri.userInfo,
      host: uri.host,
      port: uri.port == 0 ? 22 : uri.port,
      path: uri.path,
    );
  }

  /// Build SSH push command
  String _buildSshPushCommand(String hash, String ref, bool force) {
    // Simplified push command - real implementation would need full pack protocol
    final forcePrefix = force ? '+' : '';
    return '$forcePrefix$hash $ref\n';
  }

  /// Build push data (simplified)
  String _buildPushData(String refspec, String hash, bool force) {
    // This is a simplified version - real implementation needs pack protocol
    final parts = refspec.split(':');
    final remoteRef = parts.length > 1 ? parts[1] : parts[0];

    return '$hash $remoteRef\n';
  }
}

/// SSH URL components
class _SshUrlComponents {
  final String username;
  final String host;
  final int port;
  final String path;

  const _SshUrlComponents({
    required this.username,
    required this.host,
    required this.port,
    required this.path,
  });
}
