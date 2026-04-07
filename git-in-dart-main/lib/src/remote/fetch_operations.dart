/// Fetch operation - download objects and refs from remote
library;

import 'dart:io';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import '../core/repository.dart';
import '../remote/remote_manager.dart';
import '../exceptions/git_exceptions.dart';

/// Fetch result
class FetchResult {
  final bool success;
  final List<String> updatedRefs;
  final int objectsReceived;
  final String? error;

  const FetchResult({
    required this.success,
    required this.updatedRefs,
    required this.objectsReceived,
    this.error,
  });
}

/// Fetch operation
class FetchOperation {
  final GitRepository repo;
  final RemoteManager remoteManager;

  FetchOperation(this.repo) : remoteManager = RemoteManager(repo.gitDir);

  /// Fetch from remote
  Future<FetchResult> fetch(
    String remoteName, {
    Credentials? credentials,
    List<String>? refspecs,
  }) async {
    // Get remote
    final remote = await remoteManager.getRemote(remoteName);
    if (remote == null) {
      throw GitException('Remote not found: $remoteName');
    }

    try {
      if (remote.isHttps) {
        return await _fetchHttps(remote, credentials as HttpsCredentials?);
      } else if (remote.isSsh) {
        return await _fetchSsh(remote, credentials as SshCredentials?);
      } else {
        throw GitException('Unsupported remote protocol: ${remote.url}');
      }
    } catch (e) {
      return FetchResult(
        success: false,
        updatedRefs: [],
        objectsReceived: 0,
        error: e.toString(),
      );
    }
  }

  /// Fetch using HTTPS
  Future<FetchResult> _fetchHttps(
    Remote remote,
    HttpsCredentials? credentials,
  ) async {
    final client = HttpClient();

    try {
      // Discover refs using git smart HTTP protocol
      final refsUrl = '${remote.url}/info/refs?service=git-upload-pack';
      final request = await client.getUrl(Uri.parse(refsUrl));

      if (credentials != null) {
        request.headers.set('Authorization', credentials.getAuthHeader());
      }

      final response = await request.close();

      if (response.statusCode != 200) {
        throw GitException('Failed to fetch: HTTP ${response.statusCode}');
      }

      final refs = await _parseRefs(response);

      // Update remote refs
      final updatedRefs = <String>[];
      for (final ref in refs.entries) {
        await _updateRemoteRef(remote.name, ref.key, ref.value);
        updatedRefs.add(ref.key);
      }

      return FetchResult(
        success: true,
        updatedRefs: updatedRefs,
        objectsReceived: 0, // Simplified - would need pack protocol
      );
    } finally {
      client.close();
    }
  }

  /// Fetch using SSH
  Future<FetchResult> _fetchSsh(
    Remote remote,
    SshCredentials? credentials,
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
      // Parse SSH URL (git@github.com:user/repo.git or ssh://git@github.com/user/repo.git)
      final sshUrl = _parseSshUrl(remote.url);

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

      // Execute git-upload-pack to get refs
      final session = await client.execute(
        'git-upload-pack ${sshUrl.path}',
      );

      // Read the response
      final outputBytes = await session.stdout.toList();
      final output = utf8.decode(outputBytes.expand((x) => x).toList());
      final refs = _parseSshRefs(output);

      // Update remote refs
      final updatedRefs = <String>[];
      for (final ref in refs.entries) {
        await _updateRemoteRef(remote.name, ref.key, ref.value);
        updatedRefs.add(ref.key);
      }

      // Close SSH connection
      client.close();
      await client.done;

      return FetchResult(
        success: true,
        updatedRefs: updatedRefs,
        objectsReceived: 0, // Simplified - full pack protocol not implemented
      );
    } catch (e) {
      throw GitException('SSH fetch failed: $e');
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

  /// Parse refs from SSH git-upload-pack output
  Map<String, String> _parseSshRefs(String output) {
    final refs = <String, String>{};
    final lines = output.split('\n');

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // Parse "hash ref" format
      final parts = line.split(' ');
      if (parts.length >= 2) {
        final hash = parts[0].replaceAll(RegExp(r'[^0-9a-f]'), '');
        var ref = parts[1].trim();

        // Remove capabilities
        if (ref.contains('\x00')) {
          ref = ref.substring(0, ref.indexOf('\x00'));
        }

        if (hash.length == 40 && ref.startsWith('refs/')) {
          refs[ref] = hash;
        }
      }
    }

    return refs;
  }

  /// Parse refs from git-upload-pack response
  Future<Map<String, String>> _parseRefs(HttpClientResponse response) async {
    final refs = <String, String>{};
    final content = await response.transform(utf8.decoder).join();
    final lines = content.split('\n');

    for (var line in lines) {
      // Skip packet line headers (e.g., "001e# service=git-upload-pack")
      if (line.startsWith('#') || line.length < 45) continue;

      // Parse "hash ref" format
      final parts = line.split(' ');
      if (parts.length >= 2) {
        final hash = parts[0].replaceAll(RegExp(r'[^0-9a-f]'), '');
        var ref = parts[1].trim();

        // Remove null byte and capabilities
        if (ref.contains('\x00')) {
          ref = ref.substring(0, ref.indexOf('\x00'));
        }

        if (hash.length == 40 && ref.startsWith('refs/')) {
          refs[ref] = hash;
        }
      }
    }

    return refs;
  }

  /// Update remote ref
  Future<void> _updateRemoteRef(
    String remoteName,
    String ref,
    String hash,
  ) async {
    // Convert refs/heads/main to refs/remotes/origin/main
    if (ref.startsWith('refs/heads/')) {
      final branchName = ref.substring(11);
      final remoteRef = 'refs/remotes/$remoteName/$branchName';

      final refPath = '${repo.gitDir}/$remoteRef';
      final refFile = File(refPath);
      await refFile.parent.create(recursive: true);
      await refFile.writeAsString('$hash\n');
    }
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
