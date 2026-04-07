/// Status operation - show working tree status
library;

import 'dart:io';
import '../core/repository.dart';
import '../models/tree.dart';

/// File status
enum FileStatus {
  untracked,
  added,
  modified,
  deleted,
  renamed,
  copied,
  unmerged,
}

/// Status entry for a file
class StatusEntry {
  final String path;
  final FileStatus status;
  final String? oldPath; // For renames

  const StatusEntry({
    required this.path,
    required this.status,
    this.oldPath,
  });

  @override
  String toString() {
    switch (status) {
      case FileStatus.untracked:
        return '?? $path';
      case FileStatus.added:
        return 'A  $path';
      case FileStatus.modified:
        return ' M $path';
      case FileStatus.deleted:
        return ' D $path';
      case FileStatus.renamed:
        return 'R  $oldPath -> $path';
      default:
        return '   $path';
    }
  }
}

/// Repository status
class RepositoryStatus {
  final List<StatusEntry> staged;
  final List<StatusEntry> unstaged;
  final List<StatusEntry> untracked;
  final String? currentBranch;
  final String? currentCommit;

  const RepositoryStatus({
    required this.staged,
    required this.unstaged,
    required this.untracked,
    this.currentBranch,
    this.currentCommit,
  });

  bool get isClean => staged.isEmpty && unstaged.isEmpty && untracked.isEmpty;

  @override
  String toString() {
    final buffer = StringBuffer();

    if (currentBranch != null) {
      buffer.writeln('On branch $currentBranch');
    } else {
      buffer.writeln('HEAD detached at $currentCommit');
    }

    if (isClean) {
      buffer.writeln('nothing to commit, working tree clean');
      return buffer.toString();
    }

    if (staged.isNotEmpty) {
      buffer.writeln('\nChanges to be committed:');
      for (final entry in staged) {
        buffer.writeln('  $entry');
      }
    }

    if (unstaged.isNotEmpty) {
      buffer.writeln('\nChanges not staged for commit:');
      for (final entry in unstaged) {
        buffer.writeln('  $entry');
      }
    }

    if (untracked.isNotEmpty) {
      buffer.writeln('\nUntracked files:');
      for (final entry in untracked) {
        buffer.writeln('  $entry');
      }
    }

    return buffer.toString();
  }
}

/// Get repository status
class StatusOperation {
  final GitRepository repo;

  StatusOperation(this.repo);

  /// Get full repository status
  Future<RepositoryStatus> status() async {
    final currentBranch = await repo.getCurrentBranch();
    final currentCommit = await repo.getCurrentCommit();

    // Get index entries
    final indexEntries = await repo.index.read();
    final indexPaths = <String, dynamic>{};
    for (final entry in indexEntries) {
      indexPaths[entry.path] = entry;
    }

    // Get HEAD tree entries
    final headPaths = <String, String>{};
    if (currentCommit != null) {
      try {
        final commit = await repo.readCommit(currentCommit);
        final tree = await repo.readTree(commit.tree);
        await _collectTreePaths(tree, '', headPaths);
      } catch (_) {
        // No HEAD tree yet
      }
    }

    // Get working tree files
    final workingPaths = await _getWorkingTreeFiles();

    final staged = <StatusEntry>[];
    final unstaged = <StatusEntry>[];
    final untracked = <StatusEntry>[];

    // Check staged changes (index vs HEAD)
    for (final path in indexPaths.keys) {
      final indexEntry = indexPaths[path];
      final headHash = headPaths[path];

      if (headHash == null) {
        // New file in index
        staged.add(StatusEntry(path: path, status: FileStatus.added));
      } else if (headHash != indexEntry.hash) {
        // Modified in index
        staged.add(StatusEntry(path: path, status: FileStatus.modified));
      }
    }

    // Check for deletions in index
    for (final path in headPaths.keys) {
      if (!indexPaths.containsKey(path)) {
        staged.add(StatusEntry(path: path, status: FileStatus.deleted));
      }
    }

    // Check unstaged changes (working tree vs index)
    for (final path in workingPaths.keys) {
      final workingHash = workingPaths[path];
      final indexEntry = indexPaths[path];

      if (indexEntry == null) {
        // Untracked file
        untracked.add(StatusEntry(path: path, status: FileStatus.untracked));
      } else if (workingHash != indexEntry.hash) {
        // Modified in working tree
        unstaged.add(StatusEntry(path: path, status: FileStatus.modified));
      }
    }

    // Check for deletions in working tree
    for (final path in indexPaths.keys) {
      if (!workingPaths.containsKey(path)) {
        unstaged.add(StatusEntry(path: path, status: FileStatus.deleted));
      }
    }

    return RepositoryStatus(
      staged: staged,
      unstaged: unstaged,
      untracked: untracked,
      currentBranch: currentBranch,
      currentCommit: currentCommit,
    );
  }

  /// Collect all file paths from a tree recursively
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

  /// Get all files in working tree with their hashes
  Future<Map<String, String>> _getWorkingTreeFiles() async {
    final files = <String, String>{};
    final dir = Directory(repo.workDir);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = repo.getRelativePath(entity.path);

        // Skip .git directory
        if (relativePath.startsWith('.git/') || relativePath == '.git') {
          continue;
        }

        // Compute hash for file
        final content = await entity.readAsBytes();
        final hash = await repo.objects.writeBlob(content);
        files[relativePath] = hash;
      }
    }

    return files;
  }

  /// Check if working tree is clean
  Future<bool> isClean() async {
    final status = await this.status();
    return status.isClean;
  }
}
