/// Checkout operation - switch branches and restore files
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/repository.dart';
import '../models/tree.dart';
import '../core/index.dart';
import '../exceptions/git_exceptions.dart';

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

    // Get branch commit
    final commitHash = await repo.refs.readBranch(branch);

    // Update working tree
    await _updateWorkingTree(commitHash);

    // Update HEAD to point to branch
    await repo.refs.updateHead(branch, symbolic: true);

    // Update index
    await _updateIndexFromCommit(commitHash);
  }

  /// Checkout a specific commit (detached HEAD)
  Future<void> checkoutCommit(String commitHash) async {
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
    final commit = await repo.readCommit(commitHash);
    final tree = await repo.readTree(commit.tree);

    // Clear working tree (except .git)
    await _clearWorkingTree();

    // Checkout tree
    await _checkoutTree(tree, '');
  }

  /// Clear working tree files (but keep .git)
  Future<void> _clearWorkingTree() async {
    final dir = Directory(repo.workDir);

    await for (final entity in dir.list()) {
      final name = p.basename(entity.path);
      if (name != '.git') {
        if (entity is File) {
          await entity.delete();
        } else if (entity is Directory) {
          await entity.delete(recursive: true);
        }
      }
    }
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

    // Get current commit
    final currentCommit = await repo.refs.resolveHead();

    // Create new branch
    await repo.refs.writeBranch(branch, currentCommit);

    // Checkout the new branch
    await repo.refs.updateHead(branch, symbolic: true);
  }
}
