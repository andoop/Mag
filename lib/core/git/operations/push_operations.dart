library;

import 'dart:io';

import '../core/repository.dart';
import '../exceptions/git_exceptions.dart';
import '../models/blob.dart';
import '../models/commit.dart';
import '../models/tree.dart';
import '../operations/log_operations.dart';
import '../remote/remote_manager.dart';

class PushResult {
  const PushResult({
    required this.success,
    required this.pushedRefs,
    this.error,
  });

  final bool success;
  final List<String> pushedRefs;
  final String? error;
}

class PushOperation {
  PushOperation(this.repo) : remoteManager = RemoteManager(repo.gitDir);

  final GitRepository repo;
  final RemoteManager remoteManager;

  Future<PushResult> push(
    String remoteName, {
    String? refspec,
    bool force = false,
  }) async {
    final remote = await remoteManager.getRemote(remoteName);
    if (remote == null) {
      throw GitException('Remote not found: $remoteName');
    }
    if (!remote.isLocal) {
      throw const GitException(
        'Only local path and file:// remotes are supported for local push',
      );
    }

    try {
      final currentBranch = await repo.getCurrentBranch();
      final effectiveRefspec = refspec ??
          (currentBranch == null
              ? null
              : 'refs/heads/$currentBranch:refs/heads/$currentBranch');
      if (effectiveRefspec == null || effectiveRefspec.trim().isEmpty) {
        throw const GitException(
          'Detached HEAD push requires an explicit refspec',
        );
      }

      final parts = effectiveRefspec.split(':');
      if (parts.length != 2) {
        throw GitException('Unsupported refspec: $effectiveRefspec');
      }
      final sourceRef = parts[0].trim();
      final targetRef = parts[1].trim();
      if (targetRef.isEmpty || !targetRef.startsWith('refs/heads/')) {
        throw GitException('Only branch push is supported right now: $targetRef');
      }

      final sourceHash = await repo.resolveCommitish(sourceRef);
      final remotePath = remote.resolveLocalPath(repo.workDir);
      final remoteRepo = await GitRepository.open(remotePath);
      await _ensurePushAllowed(
        remoteRepo: remoteRepo,
        targetRef: targetRef,
        sourceHash: sourceHash,
        force: force,
      );

      final copiedObjects = <String>{};
      await _copyReachableObjects(
        remoteRepo: remoteRepo,
        hash: sourceHash,
        copiedObjects: copiedObjects,
      );
      await _writeRemoteRef(remoteRepo, targetRef, sourceHash);

      return PushResult(
        success: true,
        pushedRefs: [effectiveRefspec],
      );
    } catch (error) {
      return PushResult(
        success: false,
        pushedRefs: const [],
        error: error.toString(),
      );
    }
  }

  Future<void> _ensurePushAllowed({
    required GitRepository remoteRepo,
    required String targetRef,
    required String sourceHash,
    required bool force,
  }) async {
    final targetBranch = targetRef.substring('refs/heads/'.length);
    final checkedOutBranch = await remoteRepo.getCurrentBranch();
    if (checkedOutBranch == targetBranch) {
      throw GitException(
        'Refusing to update checked-out branch on non-bare remote: $targetBranch',
      );
    }

    String? remoteHash;
    try {
      remoteHash = await remoteRepo.refs.resolveRef(targetRef);
    } catch (_) {
      remoteHash = null;
    }
    if (remoteHash == null || remoteHash.isEmpty || force) {
      return;
    }
    if (remoteHash == sourceHash) {
      return;
    }
    if (!await repo.objects.hasObject(remoteHash)) {
      throw const GitException(
        'Push rejected because the remote contains commits missing locally. Fetch first or use force.',
      );
    }
    final base = await LogOperation(repo).findCommonAncestor(
      sourceHash,
      remoteHash,
    );
    if (base != remoteHash) {
      throw const GitException(
        'Push rejected because it is not a fast-forward. Fetch first or use force.',
      );
    }
  }

  Future<void> _writeRemoteRef(
    GitRepository remoteRepo,
    String refPath,
    String hash,
  ) async {
    final file = File('${remoteRepo.gitDir}/$refPath');
    await file.parent.create(recursive: true);
    await file.writeAsString('$hash\n');
  }

  Future<void> _copyReachableObjects({
    required GitRepository remoteRepo,
    required String hash,
    required Set<String> copiedObjects,
  }) async {
    if (copiedObjects.contains(hash) || await remoteRepo.objects.hasObject(hash)) {
      return;
    }

    final raw = await repo.objects.readObjectRaw(hash);
    await remoteRepo.objects.writeRawObject(raw);
    copiedObjects.add(hash);

    final object = await repo.objects.readObject(hash);
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
