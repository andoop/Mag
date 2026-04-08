library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/config.dart';
import '../exceptions/git_exceptions.dart';

class GitRemote {
  const GitRemote({
    required this.name,
    required this.url,
    this.fetchSpec,
  });

  final String name;
  final String url;
  final String? fetchSpec;

  bool get isLocal =>
      url.startsWith('/') || url.startsWith('file://') || url.startsWith('./') || url.startsWith('../');
  bool get isSsh => url.startsWith('ssh://') || RegExp(r'^[^@/\s]+@[^:/\s]+:.+$').hasMatch(url);
  bool get isHttps => url.startsWith('https://') || url.startsWith('http://');

  String resolveLocalPath(String currentWorkDir) {
    if (url.startsWith('file://')) {
      return Uri.parse(url).toFilePath();
    }
    if (url.startsWith('/')) {
      return url;
    }
    return p.normalize(p.join(currentWorkDir, url));
  }
}

class TrackingBranch {
  const TrackingBranch({
    required this.remote,
    required this.mergeRef,
  });

  final String remote;
  final String mergeRef;

  String get branchName =>
      mergeRef.startsWith('refs/heads/') ? mergeRef.substring(11) : mergeRef;
}

class RemoteManager {
  const RemoteManager(this.gitDir);

  final String gitDir;

  String get configPath => '$gitDir/config';

  Future<void> addRemote(String name, String url) async {
    _validateRemoteName(name);
    final existing = await getRemote(name);
    if (existing != null) {
      throw GitException('Remote already exists: $name');
    }
    final config = await GitConfig.load(configPath);
    final section = 'remote "$name"';
    config.set(section, 'url', url);
    config.set(section, 'fetch', '+refs/heads/*:refs/remotes/$name/*');
    await config.save();
  }

  Future<GitRemote?> getRemote(String name) async {
    final remotes = await listRemotes();
    for (final remote in remotes) {
      if (remote.name == name) {
        return remote;
      }
    }
    return null;
  }

  Future<List<GitRemote>> listRemotes() async {
    final file = File(configPath);
    if (!await file.exists()) {
      return const [];
    }

    final remotes = <GitRemote>[];
    final lines = await file.readAsLines();
    String? currentName;
    String? currentUrl;
    String? currentFetchSpec;

    void flush() {
      if (currentName != null && currentUrl != null) {
        remotes.add(
          GitRemote(
            name: currentName,
            url: currentUrl,
            fetchSpec: currentFetchSpec,
          ),
        );
      }
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      final sectionMatch =
          RegExp(r'^\[remote "(.+)"\]$').firstMatch(line);
      if (sectionMatch != null) {
        flush();
        currentName = sectionMatch.group(1);
        currentUrl = null;
        currentFetchSpec = null;
        continue;
      }
      if (line.startsWith('[')) {
        flush();
        currentName = null;
        currentUrl = null;
        currentFetchSpec = null;
        continue;
      }
      if (currentName == null) {
        continue;
      }
      if (line.startsWith('url = ')) {
        currentUrl = line.substring(6).trim();
      } else if (line.startsWith('fetch = ')) {
        currentFetchSpec = line.substring(8).trim();
      }
    }

    flush();
    return remotes;
  }

  Future<void> setTrackingBranch({
    required String branch,
    required String remote,
    required String mergeRef,
  }) async {
    final config = await GitConfig.load(configPath);
    final section = 'branch "$branch"';
    config.set(section, 'remote', remote);
    config.set(section, 'merge', mergeRef);
    await config.save();
  }

  Future<TrackingBranch?> getTrackingBranch(String branch) async {
    final config = await GitConfig.load(configPath);
    final section = 'branch "$branch"';
    final remote = config.get(section, 'remote')?.toString();
    final merge = config.get(section, 'merge')?.toString();
    if (remote == null || merge == null || remote.isEmpty || merge.isEmpty) {
      return null;
    }
    return TrackingBranch(remote: remote, mergeRef: merge);
  }

  void _validateRemoteName(String name) {
    if (name.trim().isEmpty || name.contains(' ')) {
      throw GitException('Invalid remote name: $name');
    }
  }
}
