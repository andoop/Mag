/// Merge operation - 3-way merge with conflict detection
library;

import 'dart:io';
import '../core/repository.dart';
import '../models/commit.dart';
import '../models/tree.dart';
import '../core/index.dart';
import '../operations/log_operations.dart';
import '../operations/commit_operations.dart';
import '../exceptions/git_exceptions.dart';

/// Merge result
class MergeResult {
  final bool success;
  final List<String> conflicts;
  final String? mergeCommit;

  const MergeResult({
    required this.success,
    required this.conflicts,
    this.mergeCommit,
  });

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// File merge result
class FileMergeResult {
  final String path;
  final String? content;
  final bool hasConflict;

  const FileMergeResult({
    required this.path,
    this.content,
    required this.hasConflict,
  });
}

/// Three-way merge operation
class MergeOperation {
  final GitRepository repo;

  MergeOperation(this.repo);

  /// Merge a branch into current branch
  Future<MergeResult> merge(String branch) async {
    // Get current branch and commit
    final currentBranch = await repo.getCurrentBranch();
    if (currentBranch == null) {
      throw const GitException('Cannot merge in detached HEAD state');
    }

    final ourCommitHash = await repo.refs.resolveHead();
    final theirCommitHash = await repo.refs.readBranch(branch);

    // Check if already up-to-date
    if (ourCommitHash == theirCommitHash) {
      return const MergeResult(success: true, conflicts: []);
    }

    // Find common ancestor (merge base)
    final logOp = LogOperation(repo);
    final baseHash = await logOp.findCommonAncestor(
      ourCommitHash,
      theirCommitHash,
    );

    if (baseHash == null) {
      throw const GitException('No common ancestor found');
    }

    // Check for fast-forward
    if (baseHash == ourCommitHash) {
      // Fast-forward merge
      await _fastForwardMerge(theirCommitHash, currentBranch);
      return MergeResult(
        success: true,
        conflicts: [],
        mergeCommit: theirCommitHash,
      );
    }

    // Perform 3-way merge
    final mergeResult = await _threeWayMerge(
      baseHash,
      ourCommitHash,
      theirCommitHash,
      branch,
    );

    return mergeResult;
  }

  /// Fast-forward merge
  Future<void> _fastForwardMerge(String targetHash, String branch) async {
    await repo.refs.writeBranch(branch, targetHash);

    // Update working tree and index
    final commit = await repo.readCommit(targetHash);
    final tree = await repo.readTree(commit.tree);

    // Update index from tree
    final entries = <IndexEntry>[];
    await _collectIndexEntriesFromTree(tree, '', entries);
    await repo.index.write(entries);
  }

  /// Perform 3-way merge
  Future<MergeResult> _threeWayMerge(
    String baseHash,
    String ourHash,
    String theirHash,
    String theirBranch,
  ) async {
    // Read commits and trees
    final baseCommit = await repo.readCommit(baseHash);
    final ourCommit = await repo.readCommit(ourHash);
    final theirCommit = await repo.readCommit(theirHash);

    final baseTree = await repo.readTree(baseCommit.tree);
    final ourTree = await repo.readTree(ourCommit.tree);
    final theirTree = await repo.readTree(theirCommit.tree);

    // Get all file paths from all three trees
    final basePaths = <String, String>{};
    final ourPaths = <String, String>{};
    final theirPaths = <String, String>{};

    await _collectTreePaths(baseTree, '', basePaths);
    await _collectTreePaths(ourTree, '', ourPaths);
    await _collectTreePaths(theirTree, '', theirPaths);

    // Merge files
    final allPaths = <String>{
      ...basePaths.keys,
      ...ourPaths.keys,
      ...theirPaths.keys,
    };

    final conflicts = <String>[];
    final indexEntries = <IndexEntry>[];

    for (final path in allPaths) {
      final baseHash = basePaths[path];
      final ourHash = ourPaths[path];
      final theirHash = theirPaths[path];

      final result = await _mergeFile(path, baseHash, ourHash, theirHash);

      if (result.hasConflict) {
        conflicts.add(path);

        // Write conflict to working tree
        final absPath = repo.getWorkPath(path);
        final file = File(absPath);
        await file.parent.create(recursive: true);
        await file.writeAsString(result.content ?? '');
      } else if (result.content != null) {
        // Write merged content
        final absPath = repo.getWorkPath(path);
        final file = File(absPath);
        await file.parent.create(recursive: true);
        await file.writeAsString(result.content!);

        // Add to index
        final content = result.content!.codeUnits;
        final hash = await repo.objects.writeBlob(content as dynamic);
        final stat = await file.stat();
        final entry = await IndexEntry.fromFile(path, hash, stat);
        indexEntries.add(entry);
      }
    }

    if (conflicts.isNotEmpty) {
      // Write index with conflict markers
      await repo.index.write(indexEntries);
      return MergeResult(success: false, conflicts: conflicts);
    }

    // Create merge commit
    await repo.index.write(indexEntries);
    final commitOp = CommitOperation(repo);
    final mergeCommit = await commitOp.commit(
      'Merge branch \'$theirBranch\'',
    );

    // Update commit to have both parents
    final finalCommit = GitCommit(
      hash: mergeCommit.hash,
      tree: mergeCommit.tree,
      parents: [ourHash, theirHash],
      author: mergeCommit.author,
      committer: mergeCommit.committer,
      message: mergeCommit.message,
    );

    final commitHash = await repo.objects.writeObject(finalCommit);
    final currentBranch = await repo.getCurrentBranch();
    if (currentBranch != null) {
      await repo.refs.writeBranch(currentBranch, commitHash);
    }

    return MergeResult(
      success: true,
      conflicts: [],
      mergeCommit: commitHash,
    );
  }

  /// Merge a single file using 3-way merge
  Future<FileMergeResult> _mergeFile(
    String path,
    String? baseHash,
    String? ourHash,
    String? theirHash,
  ) async {
    // Case 1: File unchanged in both branches
    if (ourHash == theirHash) {
      if (ourHash != null) {
        final blob = await repo.readBlob(ourHash);
        return FileMergeResult(
          path: path,
          content: blob.contentAsString,
          hasConflict: false,
        );
      }
      return FileMergeResult(path: path, content: null, hasConflict: false);
    }

    // Case 2: File added in one branch only
    if (baseHash == null) {
      if (ourHash == null) {
        // Added in their branch
        final blob = await repo.readBlob(theirHash!);
        return FileMergeResult(
          path: path,
          content: blob.contentAsString,
          hasConflict: false,
        );
      }
      if (theirHash == null) {
        // Added in our branch
        final blob = await repo.readBlob(ourHash);
        return FileMergeResult(
          path: path,
          content: blob.contentAsString,
          hasConflict: false,
        );
      }
      // Added in both branches with different content - conflict
      return await _createConflict(path, ourHash, theirHash);
    }

    // Case 3: File deleted in one branch
    if (ourHash == null) {
      // Deleted in our branch
      if (theirHash == baseHash) {
        // Unchanged in their branch - use deletion
        return FileMergeResult(path: path, content: null, hasConflict: false);
      }
      // Modified in their branch - conflict
      return await _createConflict(path, null, theirHash);
    }

    if (theirHash == null) {
      // Deleted in their branch
      if (ourHash == baseHash) {
        // Unchanged in our branch - use deletion
        return FileMergeResult(path: path, content: null, hasConflict: false);
      }
      // Modified in our branch - conflict
      return await _createConflict(path, ourHash, null);
    }

    // Case 4: File modified in one branch only
    if (ourHash == baseHash) {
      // Unchanged in our branch, use their version
      final blob = await repo.readBlob(theirHash);
      return FileMergeResult(
        path: path,
        content: blob.contentAsString,
        hasConflict: false,
      );
    }

    if (theirHash == baseHash) {
      // Unchanged in their branch, use our version
      final blob = await repo.readBlob(ourHash);
      return FileMergeResult(
        path: path,
        content: blob.contentAsString,
        hasConflict: false,
      );
    }

    // Case 5: File modified in both branches - conflict
    return await _createConflict(path, ourHash, theirHash);
  }

  /// Create conflict marker content
  Future<FileMergeResult> _createConflict(
    String path,
    String? ourHash,
    String? theirHash,
  ) async {
    final buffer = StringBuffer();

    buffer.writeln('<<<<<<< HEAD');
    if (ourHash != null) {
      final blob = await repo.readBlob(ourHash);
      buffer.write(blob.contentAsString);
    }
    buffer.writeln('=======');
    if (theirHash != null) {
      final blob = await repo.readBlob(theirHash);
      buffer.write(blob.contentAsString);
    }
    buffer.writeln('>>>>>>> branch');

    return FileMergeResult(
      path: path,
      content: buffer.toString(),
      hasConflict: true,
    );
  }

  /// Collect all file paths from a tree
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

  /// Collect index entries from tree
  Future<void> _collectIndexEntriesFromTree(
    GitTree tree,
    String prefix,
    List<IndexEntry> entries,
  ) async {
    for (final entry in tree.entries) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';

      if (entry.isDirectory) {
        final subtree = await repo.readTree(entry.hash);
        await _collectIndexEntriesFromTree(subtree, path, entries);
      } else {
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

  /// Abort merge
  Future<void> abortMerge() async {
    // Reset to HEAD
    final headHash = await repo.refs.resolveHead();
    final commit = await repo.readCommit(headHash);
    final tree = await repo.readTree(commit.tree);

    // Update index
    final entries = <IndexEntry>[];
    await _collectIndexEntriesFromTree(tree, '', entries);
    await repo.index.write(entries);
  }
}
