/// Checkout operation - switch branches and restore files
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/repository.dart';
import '../models/tree.dart';
import '../core/index.dart';
import '../exceptions/git_exceptions.dart';
import 'status_operations.dart';

/// Checkout branches and restore working tree
class CheckoutOperation {
  final GitRepository repo;

  CheckoutOperation(this.repo);

  /// Checkout a branch
  Future<void> checkoutBranch(String branch) async {
    // Check if branch exists
    if (!await repo.refs.branchExists(branch)) {
      throw ReferenceNotFoundException('refs/heads/$branch');
    }

    final currentBranch = await repo.getCurrentBranch();
    if (currentBranch == branch) {
      return;
    }

    // Get branch commit
    final commitHash = await repo.refs.readBranch(branch);
    await _ensureCheckoutSafe(commitHash);

    // Update working tree
    await _updateWorkingTree(commitHash);

    // Update HEAD to point to branch
    await repo.refs.updateHead(branch, symbolic: true);

    // Update index
    await _updateIndexFromCommit(commitHash);
  }

  /// Checkout a specific commit (detached HEAD)
  Future<void> checkoutCommit(String commitHash) async {
    if (!await repo.objects.hasObject(commitHash)) {
      throw ReferenceNotFoundException(commitHash);
    }

    final currentCommit = await repo.getCurrentCommit();
    final currentBranch = await repo.getCurrentBranch();
    if (currentBranch == null && currentCommit == commitHash) {
      return;
    }

    await _ensureCheckoutSafe(commitHash);

    // Update working tree
    await _updateWorkingTree(commitHash);

    // Update HEAD to point directly to commit
    await repo.refs.updateHead(commitHash, symbolic: false);

    // Update index
    await _updateIndexFromCommit(commitHash);
  }

  /// Restore a file from HEAD
  Future<void> restoreFile(String path) async {
    final headHash = await repo.refs.resolveHead();
    final commit = await repo.readCommit(headHash);
    final tree = await repo.readTree(commit.tree);

    // Find file in tree
    final fileHash = await _findFileInTree(tree, path);
    if (fileHash == null) {
      throw GitException('File not found in HEAD: $path');
    }

    // Read blob
    final blob = await repo.readBlob(fileHash);

    // Write to working tree
    final absPath = repo.getWorkPath(path);
    final file = File(absPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(blob.content);
  }

  /// Update working tree to match commit
  Future<void> _updateWorkingTree(String commitHash) async {
    final targetPaths = await _readCommitTreePaths(commitHash);
    final currentCommit = await repo.getCurrentCommit();
    final currentPaths = currentCommit == null
        ? <String, String>{}
        : await _readCommitTreePaths(currentCommit);

    await _removePathsNotInTarget(
      currentPaths.keys.toSet(),
      targetPaths.keys.toSet(),
    );

    final commit = await repo.readCommit(commitHash);
    final tree = await repo.readTree(commit.tree);

    // Checkout tree
    await _checkoutTree(tree, '');
  }

  /// Checkout a tree recursively
  Future<void> _checkoutTree(GitTree tree, String prefix) async {
    for (final entry in tree.entries) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      final absPath = repo.getWorkPath(path);

      if (entry.isDirectory) {
        // Create directory and checkout subtree
        await Directory(absPath).create(recursive: true);
        final subtree = await repo.readTree(entry.hash);
        await _checkoutTree(subtree, path);
      } else {
        // Checkout file
        final blob = await repo.readBlob(entry.hash);
        final file = File(absPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(blob.content);

        // Set executable permission if needed
        if (entry.mode == GitFileMode.executableFile) {
          // Note: Setting file permissions on mobile may not work
          try {
            await Process.run('chmod', ['+x', absPath]);
          } catch (_) {
            // Ignore on platforms that don't support chmod
          }
        }
      }
    }
  }

  /// Update index to match commit
  Future<void> _updateIndexFromCommit(String commitHash) async {
    final commit = await repo.readCommit(commitHash);
    final tree = await repo.readTree(commit.tree);

    final entries = <IndexEntry>[];
    await _collectIndexEntries(tree, '', entries);

    await repo.index.write(entries);
  }

  /// Collect index entries from tree
  Future<void> _collectIndexEntries(
    GitTree tree,
    String prefix,
    List<IndexEntry> entries,
  ) async {
    for (final entry in tree.entries) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';

      if (entry.isDirectory) {
        final subtree = await repo.readTree(entry.hash);
        await _collectIndexEntries(subtree, path, entries);
      } else {
        // Get file stat
        final absPath = repo.getWorkPath(path);
        final file = File(absPath);
        if (await file.exists()) {
          final stat = await file.stat();
          final indexEntry = await IndexEntry.fromFile(path, entry.hash, stat);
          entries.add(indexEntry);
        }
      }
    }
  }

  /// Find a file in tree by path
  Future<String?> _findFileInTree(GitTree tree, String path) async {
    final parts = path.split('/');
    var currentTree = tree;

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final entry = currentTree.findEntry(part);

      if (entry == null) {
        return null;
      }

      if (i == parts.length - 1) {
        // Last part - should be a file
        return entry.isFile ? entry.hash : null;
      } else {
        // Intermediate part - should be a directory
        if (!entry.isDirectory) {
          return null;
        }
        currentTree = await repo.readTree(entry.hash);
      }
    }

    return null;
  }

  /// Create a new branch and checkout
  Future<void> checkoutNewBranch(String branch) async {
    // Check if branch already exists
    if (await repo.refs.branchExists(branch)) {
      throw GitException('Branch already exists: $branch');
    }

    try {
      final currentCommit = await repo.refs.resolveHead();
      await repo.refs.writeBranch(branch, currentCommit);
    } on ReferenceNotFoundException {
      // Allow switching unborn repositories to a new branch before the first
      // commit. The branch ref will be created by the first commit.
    }

    // Checkout the new branch
    await repo.refs.updateHead(branch, symbolic: true);
  }

  Future<void> _ensureCheckoutSafe(String targetCommitHash) async {
    final status = await StatusOperation(repo).status();
    if (status.staged.isNotEmpty || status.unstaged.isNotEmpty) {
      throw const GitException(
        'Cannot checkout with uncommitted changes in the working tree',
      );
    }

    if (status.untracked.isEmpty) {
      return;
    }

    final targetPaths = (await _readCommitTreePaths(targetCommitHash)).keys.toSet();
    for (final entry in status.untracked) {
      if (_hasPathConflict(entry.path, targetPaths)) {
        throw GitException(
          'Cannot checkout because untracked file would be overwritten: ${entry.path}',
        );
      }
    }
  }

  Future<Map<String, String>> _readCommitTreePaths(String commitHash) async {
    final commit = await repo.readCommit(commitHash);
    final tree = await repo.readTree(commit.tree);
    final paths = <String, String>{};
    await _collectTreePaths(tree, '', paths);
    return paths;
  }

  Future<void> _collectTreePaths(
    GitTree tree,
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

  Future<void> _removePathsNotInTarget(
    Set<String> currentPaths,
    Set<String> targetPaths,
  ) async {
    final toDelete = currentPaths.difference(targetPaths).toList()
      ..sort((a, b) => b.compareTo(a));
    for (final path in toDelete) {
      final file = File(repo.getWorkPath(path));
      if (await file.exists()) {
        await file.delete();
        await _cleanupEmptyParentDirectories(file.parent);
      }
    }
  }

  Future<void> _cleanupEmptyParentDirectories(Directory dir) async {
    final normalizedWorkDir = p.normalize(repo.workDir);
    var current = dir;
    while (p.normalize(current.path) != normalizedWorkDir) {
      if (!await current.exists()) {
        current = current.parent;
        continue;
      }
      final children = await current.list().toList();
      if (children.isNotEmpty) {
        break;
      }
      await current.delete();
      current = current.parent;
    }
  }

  bool _hasPathConflict(String path, Set<String> targetPaths) {
    for (final targetPath in targetPaths) {
      if (targetPath == path ||
          targetPath.startsWith('$path/') ||
          path.startsWith('$targetPath/')) {
        return true;
      }
    }
    return false;
  }
}
