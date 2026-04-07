/// Remote repository management
library;

import 'dart:io';
import '../exceptions/git_exceptions.dart';

/// Remote repository configuration
class Remote {
  final String name;
  final String url;
  final String? pushUrl;

  const Remote({
    required this.name,
    required this.url,
    this.pushUrl,
  });

  /// Check if this is an HTTPS remote
  bool get isHttps => url.startsWith('https://') || url.startsWith('http://');

  /// Check if this is an SSH remote
  bool get isSsh => url.startsWith('git@') || url.startsWith('ssh://');

  @override
  String toString() => '$name\t$url (fetch)\n$name\t${pushUrl ?? url} (push)';
}

/// Authentication credentials for remote operations
abstract class Credentials {
  const Credentials();
}

/// HTTPS authentication with username/password or token
class HttpsCredentials extends Credentials {
  final String? username;
  final String? password;
  final String? token;

  const HttpsCredentials({
    this.username,
    this.password,
    this.token,
  });

  /// Create from personal access token
  factory HttpsCredentials.token(String token) {
    return HttpsCredentials(token: token);
  }

  /// Create from username and password
  factory HttpsCredentials.basic(String username, String password) {
    return HttpsCredentials(username: username, password: password);
  }

  /// Get authorization header value
  String getAuthHeader() {
    if (token != null) {
      return 'Bearer $token';
    } else if (username != null && password != null) {
      final credentials = '$username:$password';
      final encoded = base64Encode(credentials.codeUnits);
      return 'Basic $encoded';
    }
    throw const GitException('No credentials provided');
  }
}

/// SSH authentication with key pair
class SshCredentials extends Credentials {
  final String privateKeyPath;
  final String? passphrase;
  final String? publicKeyPath;

  const SshCredentials({
    required this.privateKeyPath,
    this.passphrase,
    this.publicKeyPath,
  });

  /// Check if private key file exists
  Future<bool> hasPrivateKey() async {
    return await File(privateKeyPath).exists();
  }
}

/// Remote repository manager
class RemoteManager {
  final String gitDir;

  const RemoteManager(this.gitDir);

  /// Get path to config file
  String get configPath => '$gitDir/config';

  /// Add a remote
  Future<void> addRemote(String name, String url) async {
    // Validate name
    if (name.isEmpty || name.contains(' ')) {
      throw GitException('Invalid remote name: $name');
    }

    // Check if remote already exists
    final remotes = await listRemotes();
    if (remotes.any((r) => r.name == name)) {
      throw GitException('Remote already exists: $name');
    }

    // Add to config
    await _updateConfig((config) {
      config.add('[remote "$name"]');
      config.add('\turl = $url');
      config.add('\tfetch = +refs/heads/*:refs/remotes/$name/*');
    });
  }

  /// Remove a remote
  Future<void> removeRemote(String name) async {
    final remotes = await listRemotes();
    if (!remotes.any((r) => r.name == name)) {
      throw GitException('Remote not found: $name');
    }

    await _updateConfig((config) {
      // Remove remote section
      var inRemoteSection = false;
      final newConfig = <String>[];

      for (var line in config) {
        if (line.trim() == '[remote "$name"]') {
          inRemoteSection = true;
          continue;
        }

        if (inRemoteSection && line.trim().startsWith('[')) {
          inRemoteSection = false;
        }

        if (!inRemoteSection) {
          newConfig.add(line);
        }
      }

      return newConfig;
    });

    // Clean up remote refs
    final remoteRefsDir = Directory('$gitDir/refs/remotes/$name');
    if (await remoteRefsDir.exists()) {
      await remoteRefsDir.delete(recursive: true);
    }
  }

  /// List all remotes
  Future<List<Remote>> listRemotes() async {
    final file = File(configPath);
    if (!await file.exists()) {
      return [];
    }

    final remotes = <Remote>[];
    final content = await file.readAsString();
    final lines = content.split('\n');

    String? currentRemote;
    String? url;
    String? pushUrl;

    for (var line in lines) {
      line = line.trim();

      final remoteMatch = RegExp(r'^\[remote "(.+)"\]$').firstMatch(line);
      if (remoteMatch != null) {
        // Save previous remote
        if (currentRemote != null && url != null) {
          remotes.add(Remote(
            name: currentRemote,
            url: url,
            pushUrl: pushUrl,
          ));
        }

        currentRemote = remoteMatch.group(1);
        url = null;
        pushUrl = null;
        continue;
      }

      if (currentRemote != null) {
        if (line.startsWith('url = ')) {
          url = line.substring(6);
        } else if (line.startsWith('pushurl = ')) {
          pushUrl = line.substring(10);
        }
      }
    }

    // Add last remote
    if (currentRemote != null && url != null) {
      remotes.add(Remote(
        name: currentRemote,
        url: url,
        pushUrl: pushUrl,
      ));
    }

    return remotes;
  }

  /// Get a specific remote by name
  Future<Remote?> getRemote(String name) async {
    final remotes = await listRemotes();
    return remotes.where((r) => r.name == name).firstOrNull;
  }

  /// Set remote URL
  Future<void> setUrl(String name, String url) async {
    final remote = await getRemote(name);
    if (remote == null) {
      throw GitException('Remote not found: $name');
    }

    await _updateConfig((config) {
      var inRemoteSection = false;
      final newConfig = <String>[];

      for (var line in config) {
        if (line.trim() == '[remote "$name"]') {
          inRemoteSection = true;
          newConfig.add(line);
          continue;
        }

        if (inRemoteSection && line.trim().startsWith('[')) {
          inRemoteSection = false;
        }

        if (inRemoteSection && line.trim().startsWith('url = ')) {
          newConfig.add('\turl = $url');
        } else {
          newConfig.add(line);
        }
      }

      return newConfig;
    });
  }

  /// Update config file
  Future<void> _updateConfig(dynamic Function(List<String>) updater) async {
    final file = File(configPath);
    final content = await file.exists() ? await file.readAsString() : '';
    var lines = content.split('\n').toList();

    final result = updater(lines);
    if (result is List<String>) {
      lines = result;
    }

    await file.writeAsString(lines.join('\n'));
  }
}

/// Base64 encoding helper
String base64Encode(List<int> bytes) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final output = StringBuffer();

  for (var i = 0; i < bytes.length; i += 3) {
    final b1 = bytes[i];
    final b2 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    final b3 = i + 2 < bytes.length ? bytes[i + 2] : 0;

    final n = (b1 << 16) | (b2 << 8) | b3;

    output.write(chars[(n >> 18) & 63]);
    output.write(chars[(n >> 12) & 63]);
    output.write(i + 1 < bytes.length ? chars[(n >> 6) & 63] : '=');
    output.write(i + 2 < bytes.length ? chars[n & 63] : '=');
  }

  return output.toString();
}
