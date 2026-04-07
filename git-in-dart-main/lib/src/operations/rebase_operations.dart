/// Rebase operation - replay commits on top of another branch
library;

import 'dart:io';
import '../core/repository.dart';
import '../core/index.dart';
import '../models/commit.dart';
import '../operations/log_operations.dart';
import '../operations/commit_operations.dart';
import '../operations/checkout_operations.dart';
import '../exceptions/git_exceptions.dart';

/// Rebase result
class RebaseResult {
  final bool success;
  final List<String> conflicts;
  final String? newHead;

  const RebaseResult({
    required this.success,
    required this.conflicts,
    this.newHead,
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Rebase operation
class RebaseOperation {
  final GitRepository repo;

  RebaseOperation(this.repo);

  /// Rebase current branch onto target branch
  Future<RebaseResult> rebase(String targetBranch) async {
    // Get current branch
    final currentBranch = await repo.getCurrentBranch();
    if (currentBranch == null) {
      throw const GitException('Cannot rebase in detached HEAD state');
    }

    // Get current and target commits
    final currentHash = await repo.refs.resolveHead();
    final targetHash = await repo.refs.readBranch(targetBranch);

    // Find common ancestor
    final logOp = LogOperation(repo);
    final baseHash = await logOp.findCommonAncestor(currentHash, targetHash);

    if (baseHash == null) {
      throw const GitException('No common ancestor found');
    }

    // Get commits to replay (from base to current)
    final commitsToReplay =
        await logOp.getCommitsBetween(baseHash, currentHash);

    if (commitsToReplay.isEmpty) {
      // Already up-to-date
      return const RebaseResult(success: true, conflicts: []);
    }

    // Checkout target branch commit (detached)
    final checkoutOp = CheckoutOperation(repo);
    await checkoutOp.checkoutCommit(targetHash);

    // Replay commits
    var newHead = targetHash;
    final conflicts = <String>[];

    for (final commit in commitsToReplay.reversed) {
      try {
        newHead = await _cherryPickCommit(commit, newHead);
      } catch (e) {
        conflicts.add(commit.hash);
        // In a real implementation, we'd save state and allow continue/abort
        break;
      }
    }

    if (conflicts.isNotEmpty) {
      return RebaseResult(success: false, conflicts: conflicts);
    }

    // Update branch to new head
    await repo.refs.writeBranch(currentBranch, newHead);
    await repo.refs.updateHead(currentBranch, symbolic: true);

    return RebaseResult(success: true, conflicts: [], newHead: newHead);
  }

  /// Cherry-pick a commit
  Future<String> _cherryPickCommit(GitCommit commit, String parentHash) async {
    // Read commit tree
    final commitTree = await repo.readTree(commit.tree);

    // Get parent tree
    final parentCommit = await repo.readCommit(parentHash);
    final parentTree = await repo.readTree(parentCommit.tree);

    // Compare trees and apply changes
    // This is a simplified version - a real implementation would handle conflicts
    final changes = await _compareTreesget(parentTree, commitTree);

    // Apply changes to working tree
    for (final change in changes) {
      await _applyChange(change);
    }

    // Create new commit with same message but new parent
    final commitOp = CommitOperation(repo);
    final newCommit = await commitOp.commit(
      commit.message,
      author: commit.author,
    );

    return newCommit.hash;
  }

  /// Compare two trees and get changes
  Future<List<TreeChange>> _compareTreesget(
    dynamic parentTree,
    dynamic commitTree,
  ) async {
    final changes = <TreeChange>[];

    // Get all paths from both trees
    final parentPaths = <String, String>{};
    final commitPaths = <String, String>{};

    await _collectTreePaths(parentTree, '', parentPaths);
    await _collectTreePaths(commitTree, '', commitPaths);

    // Find changes
    final allPaths = <String>{...parentPaths.keys, ...commitPaths.keys};

    for (final path in allPaths) {
      final parentHash = parentPaths[path];
      final commitHash = commitPaths[path];

      if (parentHash == null && commitHash != null) {
        // File added
        changes.add(TreeChange(
          path: path,
          type: ChangeType.added,
          newHash: commitHash,
        ));
      } else if (parentHash != null && commitHash == null) {
        // File deleted
        changes.add(TreeChange(
          path: path,
          type: ChangeType.deleted,
          oldHash: parentHash,
        ));
      } else if (parentHash != commitHash) {
        // File modified
        changes.add(TreeChange(
          path: path,
          type: ChangeType.modified,
          oldHash: parentHash,
          newHash: commitHash,
        ));
      }
    }

    return changes;
  }

  /// Apply a tree change to working tree
  Future<void> _applyChange(TreeChange change) async {
    final absPath = repo.getWorkPath(change.path);
    final file = File(absPath);

    switch (change.type) {
      case ChangeType.added:
      case ChangeType.modified:
        final blob = await repo.readBlob(change.newHash!);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(blob.content);

        // Update index
        final stat = await file.stat();
        final entry = await IndexEntry.fromFile(
          change.path,
          change.newHash!,
          stat,
        ) as dynamic;
        await repo.index.addEntry(entry);
        break;

      case ChangeType.deleted:
        if (await file.exists()) {
          await file.delete();
        }
        await repo.index.removeEntry(change.path);
        break;
    }
  }

  /// Collect all file paths from a tree
  Future<void> _collectTreePaths(
    dynamic tree,
    String prefix,
    Map<String, String> paths,
  ) async {
    for (final entry in tree.entries) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';

      if (entry.isDirectory) {
        final subtree = await repo.readTree(entry.hash);
        await _collectTreePaths(subtree, path, paths);
      } else {
        paths[path] = entry.hash;
      }
    }
  }

  /// Interactive rebase (simplified)
  Future<RebaseResult> rebaseInteractive(
    String targetBranch,
    List<RebaseCommand> commands,
  ) async {
    // This would allow picking, squashing, editing commits
    // Simplified implementation here
    throw UnimplementedError('Interactive rebase not yet implemented');
  }

  /// Abort rebase
  Future<void> abortRebase() async {
    // In a real implementation, this would restore saved state
    throw UnimplementedError('Rebase abort not yet implemented');
  }

  /// Continue rebase after resolving conflicts
  Future<RebaseResult> continueRebase() async {
    // In a real implementation, this would continue from saved state
    throw UnimplementedError('Rebase continue not yet implemented');
  }
}

/// Tree change type
enum ChangeType { added, deleted, modified }

/// Represents a change in a tree
class TreeChange {
  final String path;
  final ChangeType type;
  final String? oldHash;
  final String? newHash;

  const TreeChange({
    required this.path,
    required this.type,
    this.oldHash,
    this.newHash,
  });
}

/// Rebase command for interactive rebase
class RebaseCommand {
  final String action; // pick, squash, edit, drop
  final String commitHash;

  const RebaseCommand({
    required this.action,
    required this.commitHash,
  });
}
