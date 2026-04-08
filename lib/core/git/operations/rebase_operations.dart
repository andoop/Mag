library;

import 'dart:io';

import '../core/index.dart';
import '../core/repository.dart';
import '../exceptions/git_exceptions.dart';
import '../models/commit.dart';
import '../models/tree.dart';
import 'checkout_operations.dart';
import 'commit_operations.dart';
import 'log_operations.dart';
import 'status_operations.dart';

class RebaseResult {
  const RebaseResult({
    required this.success,
    required this.conflicts,
    this.newHead,
  });

  final bool success;
  final List<String> conflicts;
  final String? newHead;

  bool get hasConflicts => conflicts.isNotEmpty;
}

class RebaseOperation {
  RebaseOperation(this.repo);

  final GitRepository repo;

  Future<RebaseResult> rebase(String targetRef) async {
    final status = await StatusOperation(repo).status();
    if (!status.isClean) {
      throw const GitException(
        'Cannot rebase with uncommitted changes in the working tree',
      );
    }

    final currentBranch = await repo.getCurrentBranch();
    if (currentBranch == null) {
      throw const GitException('Cannot rebase in detached HEAD state');
    }

    final currentHash = await repo.refs.resolveHead();
    final targetHash = await repo.resolveCommitish(targetRef);
    if (currentHash == targetHash) {
      return RebaseResult(success: true, conflicts: const [], newHead: currentHash);
    }

    final logOp = LogOperation(repo);
    final baseHash = await logOp.findCommonAncestor(currentHash, targetHash);
    if (baseHash == null) {
      throw const GitException('No common ancestor found');
    }

    if (baseHash == currentHash) {
      await CheckoutOperation(repo).checkoutCommit(targetHash);
      await repo.refs.writeBranch(currentBranch, targetHash);
      await repo.refs.updateHead(currentBranch, symbolic: true);
      return RebaseResult(success: true, conflicts: const [], newHead: targetHash);
    }

    if (baseHash == targetHash) {
      return RebaseResult(success: true, conflicts: const [], newHead: currentHash);
    }

    final commitsToReplay = await logOp.getCommitsBetween(baseHash, currentHash);
    if (commitsToReplay.isEmpty) {
      return RebaseResult(success: true, conflicts: const [], newHead: currentHash);
    }

    await CheckoutOperation(repo).checkoutCommit(targetHash);
    await repo.refs.writeBranch(currentBranch, targetHash);
    await repo.refs.updateHead(currentBranch, symbolic: true);

    var newHead = targetHash;
    for (final commit in commitsToReplay.reversed) {
      final replay = await _replayCommit(commit);
      if (replay.isNotEmpty) {
        return RebaseResult(success: false, conflicts: replay, newHead: newHead);
      }
      newHead = await repo.refs.resolveHead();
    }

    return RebaseResult(success: true, conflicts: const [], newHead: newHead);
  }

  Future<List<String>> _replayCommit(GitCommit commit) async {
    if (commit.parents.length > 1) {
      throw GitException(
        'Rebase does not support replaying merge commits yet: ${commit.hash}',
      );
    }

    final parentTree = commit.parents.isEmpty
        ? <String, String>{}
        : await _treePathsForCommit(commit.parents.first);
    final commitTree = await _treePathsForCommit(commit.hash);
    final currentHead = await repo.refs.resolveHead();
    final currentTree = await _treePathsForCommit(currentHead);
    final indexEntries = {for (final entry in await repo.index.read()) entry.path: entry};

    final conflicts = <String>[];
    final allPaths = <String>{...parentTree.keys, ...commitTree.keys};
    for (final path in allPaths) {
      final oldHash = parentTree[path];
      final newHash = commitTree[path];
      if (oldHash == newHash) {
        continue;
      }
      final currentHash = currentTree[path];
      final conflict = await _applyPathChange(
        path: path,
        oldHash: oldHash,
        newHash: newHash,
        currentHash: currentHash,
        indexEntries: indexEntries,
        conflictLabel: commit.hash.substring(0, 8),
      );
      if (conflict) {
        conflicts.add(path);
      }
    }

    await repo.index.write(indexEntries.values.toList());
    if (conflicts.isNotEmpty) {
      return conflicts;
    }

    final committed = await CommitOperation(repo).commit(
      commit.message,
      author: commit.author,
    );
    await repo.refs.writeBranch((await repo.getCurrentBranch())!, committed.hash);
    return const [];
  }

  Future<bool> _applyPathChange({
    required String path,
    required String? oldHash,
    required String? newHash,
    required String? currentHash,
    required Map<String, IndexEntry> indexEntries,
    required String conflictLabel,
  }) async {
    if (oldHash == null) {
      if (currentHash == null) {
        await _writeBlobToWorkingTree(path, newHash!, indexEntries);
        return false;
      }
      if (currentHash == newHash) {
        return false;
      }
      await _writeConflict(path, currentHash, newHash, conflictLabel);
      return true;
    }

    if (newHash == null) {
      if (currentHash == oldHash) {
        await _deleteFromWorkingTree(path, indexEntries);
        return false;
      }
      if (currentHash == null) {
        return false;
      }
      await _writeConflict(path, currentHash, null, conflictLabel);
      return true;
    }

    if (currentHash == oldHash) {
      await _writeBlobToWorkingTree(path, newHash, indexEntries);
      return false;
    }
    if (currentHash == newHash) {
      return false;
    }
    await _writeConflict(path, currentHash, newHash, conflictLabel);
    return true;
  }

  Future<void> _writeBlobToWorkingTree(
    String path,
    String hash,
    Map<String, IndexEntry> indexEntries,
  ) async {
    final blob = await repo.readBlob(hash);
    final file = File(repo.getWorkPath(path));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(blob.content);
    final stat = await file.stat();
    indexEntries[path] = await IndexEntry.fromFile(path, hash, stat);
  }

  Future<void> _deleteFromWorkingTree(
    String path,
    Map<String, IndexEntry> indexEntries,
  ) async {
    final file = File(repo.getWorkPath(path));
    if (await file.exists()) {
      await file.delete();
    }
    indexEntries.remove(path);
  }

  Future<void> _writeConflict(
    String path,
    String? currentHash,
    String? incomingHash,
    String conflictLabel,
  ) async {
    final currentContent = currentHash == null
        ? ''
        : (await repo.readBlob(currentHash)).contentAsString;
    final incomingContent = incomingHash == null
        ? ''
        : (await repo.readBlob(incomingHash)).contentAsString;
    final file = File(repo.getWorkPath(path));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '<<<<<<< HEAD\n'
      '$currentContent\n'
      '=======\n'
      '$incomingContent\n'
      '>>>>>>> $conflictLabel\n',
    );
  }

  Future<Map<String, String>> _treePathsForCommit(String commitHash) async {
    final commit = await repo.readCommit(commitHash);
    final tree = await repo.readTree(commit.tree);
    final out = <String, String>{};
    await _collectTreePaths(tree, '', out);
    return out;
  }

  Future<void> _collectTreePaths(
    GitTree tree,
    String prefix,
    Map<String, String> out,
  ) async {
    for (final entry in tree.entries) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isDirectory) {
        final subtree = await repo.readTree(entry.hash);
        await _collectTreePaths(subtree, path, out);
      } else {
        out[path] = entry.hash;
      }
    }
  }
}
