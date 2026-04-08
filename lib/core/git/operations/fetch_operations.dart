library;

import 'dart:io';

import '../core/repository.dart';
import '../exceptions/git_exceptions.dart';
import '../models/commit.dart';
import '../models/tree.dart';
import '../models/blob.dart';
import '../remote/remote_manager.dart';

class FetchResult {
  const FetchResult({
    required this.success,
    required this.updatedRefs,
    required this.objectsReceived,
    this.error,
  });

  final bool success;
  final List<String> updatedRefs;
  final int objectsReceived;
  final String? error;
}

class FetchOperation {
  FetchOperation(this.repo) : remoteManager = RemoteManager(repo.gitDir);

  final GitRepository repo;
  final RemoteManager remoteManager;

  Future<FetchResult> fetch(
    String remoteName, {
    String? branch,
  }) async {
    final remote = await remoteManager.getRemote(remoteName);
    if (remote == null) {
      throw GitException('Remote not found: $remoteName');
    }
    if (!remote.isLocal) {
      throw const GitException(
        'Only local path and file:// remotes are supported for fetch right now',
      );
    }

    try {
      final remotePath = remote.resolveLocalPath(repo.workDir);
      final remoteRepo = await GitRepository.open(remotePath);
      final updatedRefs = <String>[];
      final copiedObjects = <String>{};

      final branches = branch == null
          ? await remoteRepo.listBranches()
          : <String>[branch];
      for (final branchName in branches) {
        final commitHash = await remoteRepo.refs.readBranch(branchName);
        await _copyReachableObjects(
          remoteRepo: remoteRepo,
          hash: commitHash,
          copiedObjects: copiedObjects,
        );
        await _writeRef(
          'refs/remotes/$remoteName/$branchName',
          commitHash,
        );
        updatedRefs.add('refs/remotes/$remoteName/$branchName');
      }

      final tags = await remoteRepo.refs.listTags();
      for (final tag in tags) {
        final hash = await remoteRepo.refs.readTag(tag);
        await _copyReachableObjects(
          remoteRepo: remoteRepo,
          hash: hash,
          copiedObjects: copiedObjects,
        );
        await _writeRef('refs/tags/$tag', hash);
      }

      final defaultBranch = await remoteRepo.getCurrentBranch();
      if (defaultBranch != null) {
        final headFile = File('${repo.gitDir}/refs/remotes/$remoteName/HEAD');
        await headFile.parent.create(recursive: true);
        await headFile
            .writeAsString('ref: refs/remotes/$remoteName/$defaultBranch\n');
      }

      return FetchResult(
        success: true,
        updatedRefs: updatedRefs,
        objectsReceived: copiedObjects.length,
      );
    } catch (error) {
      return FetchResult(
        success: false,
        updatedRefs: const [],
        objectsReceived: 0,
        error: error.toString(),
      );
    }
  }

  Future<void> _writeRef(String refPath, String hash) async {
    final file = File('${repo.gitDir}/$refPath');
    await file.parent.create(recursive: true);
    await file.writeAsString('$hash\n');
  }

  Future<void> _copyReachableObjects({
    required GitRepository remoteRepo,
    required String hash,
    required Set<String> copiedObjects,
  }) async {
    if (copiedObjects.contains(hash) || await repo.objects.hasObject(hash)) {
      return;
    }

    final raw = await remoteRepo.objects.readObjectRaw(hash);
    await repo.objects.writeRawObject(raw);
    copiedObjects.add(hash);

    final object = await remoteRepo.objects.readObject(hash);
    if (object is GitCommit) {
      await _copyReachableObjects(
        remoteRepo: remoteRepo,
        hash: object.tree,
        copiedObjects: copiedObjects,
      );
      for (final parent in object.parents) {
        await _copyReachableObjects(
          remoteRepo: remoteRepo,
          hash: parent,
          copiedObjects: copiedObjects,
        );
      }
      return;
    }

    if (object is GitTree) {
      for (final entry in object.entries) {
        await _copyReachableObjects(
          remoteRepo: remoteRepo,
          hash: entry.hash,
          copiedObjects: copiedObjects,
        );
      }
      return;
    }

    if (object is GitBlob) {
      return;
    }
  }
}
