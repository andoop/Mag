library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/repository.dart';
import '../exceptions/git_exceptions.dart';
import '../remote/remote_manager.dart';
import 'checkout_operations.dart';
import 'fetch_operations.dart';

class CloneResult {
  const CloneResult({
    required this.success,
    this.repository,
    this.defaultBranch,
    this.objectsReceived = 0,
    this.error,
  });

  final bool success;
  final GitRepository? repository;
  final String? defaultBranch;
  final int objectsReceived;
  final String? error;
}

class CloneOperation {
  Future<CloneResult> clone({
    required String url,
    required String path,
    String remoteName = 'origin',
    String? branch,
  }) async {
    try {
      final targetDir = Directory(path);
      if (await targetDir.exists()) {
        final isEmpty = await targetDir.list().isEmpty;
        if (!isEmpty) {
          throw GitException(
            'Target directory already exists and is not empty: $path',
          );
        }
      }

      final sourcePath = _resolveSourcePath(url);
      final sourceRepo = await GitRepository.open(sourcePath);
      final repo = await GitRepository.init(path);
      final remoteManager = RemoteManager(repo.gitDir);
      await remoteManager.addRemote(remoteName, url);

      final fetchResult = await FetchOperation(repo).fetch(
        remoteName,
        branch: branch,
      );
      if (!fetchResult.success) {
        throw GitException(fetchResult.error ?? 'Clone fetch failed');
      }

      final defaultBranch =
          branch ?? await sourceRepo.getCurrentBranch() ?? await _firstBranch(sourceRepo);
      if (defaultBranch != null) {
        final remoteRefFile =
            File('${repo.gitDir}/refs/remotes/$remoteName/$defaultBranch');
        if (await remoteRefFile.exists()) {
          final commitHash = (await remoteRefFile.readAsString()).trim();
          await CheckoutOperation(repo).checkoutCommit(commitHash);
          await repo.refs.writeBranch(defaultBranch, commitHash);
          await repo.refs.updateHead(defaultBranch, symbolic: true);
          await remoteManager.setTrackingBranch(
            branch: defaultBranch,
            remote: remoteName,
            mergeRef: 'refs/heads/$defaultBranch',
          );
        }
      }

      return CloneResult(
        success: true,
        repository: repo,
        defaultBranch: defaultBranch,
        objectsReceived: fetchResult.objectsReceived,
      );
    } catch (error) {
      await _cleanupFailedClone(path);
      return CloneResult(
        success: false,
        error: error.toString(),
      );
    }
  }

  String _resolveSourcePath(String url) {
    if (url.startsWith('file://')) {
      return Uri.parse(url).toFilePath();
    }
    if (url.startsWith('/')) {
      return url;
    }
    return p.normalize(File(url).absolute.path);
  }

  Future<String?> _firstBranch(GitRepository repo) async {
    final branches = await repo.listBranches();
    if (branches.isEmpty) {
      return null;
    }
    return branches.first;
  }

  Future<void> _cleanupFailedClone(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
