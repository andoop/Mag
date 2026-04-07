/// Merge operation - 3-way merge with conflict detection
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../core/repository.dart';
import '../models/commit.dart';
import '../models/git_author.dart';
import '../models/tree.dart';
import '../core/index.dart';
import '../operations/log_operations.dart';
import '../exceptions/git_exceptions.dart';
import 'status_operations.dart';

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
    final status = await StatusOperation(repo).status();
    if (!status.isClean) {
      throw const GitException(
        'Cannot merge with uncommitted changes in the working tree',
      );
    }

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
  Future<void> _fastForwardMerge(String targetHash, String currentBranch) async {
    final commit = await repo.readCommit(targetHash);
    final tree = await repo.readTree(commit.tree);
    await _replaceWorkingTree(tree);

    final entries = <IndexEntry>[];
    await _collectIndexEntriesFromTree(tree, '', entries);
    await repo.index.write(entries);
    await repo.refs.writeBranch(currentBranch, targetHash);
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
    final indexMap = <String, IndexEntry>{};
    for (final entry in await repo.index.read()) {
      indexMap[entry.path] = entry;
    }

    for (final path in allPaths) {
      final baseHash = basePaths[path];
      final ourHash = ourPaths[path];
      final theirHash = theirPaths[path];

      final result = await _mergeFile(
        path,
        baseHash,
        ourHash,
        theirHash,
        theirBranch,
      );

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
        final content = Uint8List.fromList(utf8.encode(result.content!));
        final hash = await repo.objects.writeBlob(content);
        final stat = await file.stat();
        final entry = await IndexEntry.fromFile(path, hash, stat);
        indexMap[path] = entry;
      } else {
        final absPath = repo.getWorkPath(path);
        final file = File(absPath);
        if (await file.exists()) {
          await file.delete();
        }
        indexMap.remove(path);
      }
    }

    if (conflicts.isNotEmpty) {
      await repo.index.write(indexMap.values.toList());
      return MergeResult(success: false, conflicts: conflicts);
    }

    // Create merge commit
    await repo.index.write(indexMap.values.toList());
    final author = await _getDefaultAuthor();
    final treeHash = await _writeTreeFromIndex(indexMap.values.toList());
    final mergeCommit = GitCommit(
      hash: '',
      tree: treeHash,
      parents: [ourHash, theirHash],
      author: author,
      committer: author,
      message: 'Merge branch \'$theirBranch\'',
    );
    final commitHash = await repo.objects.writeObject(mergeCommit);
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
    String theirBranch,
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
      return await _createConflict(path, ourHash, theirHash, theirBranch);
    }

    // Case 3: File deleted in one branch
    if (ourHash == null) {
      // Deleted in our branch
      if (theirHash == baseHash) {
        // Unchanged in their branch - use deletion
        return FileMergeResult(path: path, content: null, hasConflict: false);
      }
      // Modified in their branch - conflict
      return await _createConflict(path, null, theirHash, theirBranch);
    }

    if (theirHash == null) {
      // Deleted in their branch
      if (ourHash == baseHash) {
        // Unchanged in our branch - use deletion
        return FileMergeResult(path: path, content: null, hasConflict: false);
      }
      // Modified in our branch - conflict
      return await _createConflict(path, ourHash, null, theirBranch);
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
    return await _createConflict(path, ourHash, theirHash, theirBranch);
  }

  /// Create conflict marker content
  Future<FileMergeResult> _createConflict(
    String path,
    String? ourHash,
    String? theirHash,
    String theirBranch,
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
    buffer.writeln('>>>>>>> $theirBranch');

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
    await _replaceWorkingTree(tree);
  }

  Future<void> _replaceWorkingTree(GitTree tree) async {
    final dir = Directory(repo.workDir);
    await for (final entity in dir.list()) {
      final name = entity.path.split('/').last;
      if (name == '.git') {
        continue;
      }
      if (entity is File) {
        await entity.delete();
      } else if (entity is Directory) {
        await entity.delete(recursive: true);
      }
    }

    await _checkoutTree(tree, '');
  }

  Future<void> _checkoutTree(GitTree tree, String prefix) async {
    for (final entry in tree.entries) {
      final path = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      final absPath = repo.getWorkPath(path);
      if (entry.isDirectory) {
        await Directory(absPath).create(recursive: true);
        final subtree = await repo.readTree(entry.hash);
        await _checkoutTree(subtree, path);
      } else {
        final blob = await repo.readBlob(entry.hash);
        final file = File(absPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(blob.content);
      }
    }
  }

  Future<GitAuthor> _getDefaultAuthor() async {
    final config = await repo.config;
    final name = config.get('user', 'name', defaultValue: 'Unknown');
    final email =
        config.get('user', 'email', defaultValue: 'unknown@example.com');
    return GitAuthor(
      name: name as String,
      email: email as String,
    );
  }

  Future<String> _writeTreeFromIndex(List<IndexEntry> entries) async {
    final root = <String, dynamic>{};
    for (final entry in entries) {
      final parts = entry.path.split('/');
      var current = root;
      for (var i = 0; i < parts.length - 1; i++) {
        final part = parts[i];
        current[part] ??= <String, dynamic>{};
        current = current[part] as Map<String, dynamic>;
      }
      current[parts.last] = entry;
    }
    return _writeTree(root);
  }

  Future<String> _writeTree(Map<String, dynamic> tree) async {
    final treeEntries = <TreeEntry>[];
    for (final name in tree.keys) {
      final value = tree[name];
      if (value is Map<String, dynamic>) {
        final subtreeHash = await _writeTree(value);
        treeEntries.add(
          TreeEntry(
            mode: GitFileMode.directory,
            name: name,
            hash: subtreeHash,
          ),
        );
      } else {
        final entry = value as IndexEntry;
        treeEntries.add(
          TreeEntry(
            mode: entry.mode == GitFileMode.executableFile.value
                ? GitFileMode.executableFile
                : GitFileMode.regularFile,
            name: name,
            hash: entry.hash,
          ),
        );
      }
    }

    final gitTree = GitTree.create(hash: '', entries: treeEntries);
    return repo.objects.writeObject(gitTree);
  }
}
