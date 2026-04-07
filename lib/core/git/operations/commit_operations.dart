/// Commit operation - create commits from staged changes
library;

import '../core/repository.dart';
import '../models/git_author.dart';
import '../models/commit.dart';
import '../models/tree.dart';
import '../exceptions/git_exceptions.dart';

/// Create commits from staged changes
class CommitOperation {
  final GitRepository repo;

  CommitOperation(this.repo);

  /// Create a commit from the current index
  Future<GitCommit> commit(String message, {GitAuthor? author}) async {
    // Get author info
    final commitAuthor = author ?? await _getDefaultAuthor();
    final committer = commitAuthor; // Same as author for now

    // Read index
    final entries = await repo.index.read();
    if (entries.isEmpty) {
      throw const GitException('No changes staged for commit');
    }

    // Build tree from index
    final treeHash = await _writeTreeFromIndex(entries);

    // Get parent commit (if exists)
    final parents = <String>[];
    try {
      final headHash = await repo.refs.resolveHead();
      parents.add(headHash);
    } catch (_) {
      // No parent (initial commit)
    }

    if (parents.isNotEmpty) {
      final parentCommit = await repo.readCommit(parents.first);
      if (parentCommit.tree == treeHash) {
        throw const GitException('No changes staged for commit');
      }
    }

    // Create commit object
    final commit = GitCommit(
      hash: '', // Will be computed when writing
      tree: treeHash,
      parents: parents,
      author: commitAuthor,
      committer: committer,
      message: message,
    );

    // Write commit object
    final commitHash = await repo.objects.writeObject(commit);

    // Create commit with correct hash
    final finalCommit = GitCommit(
      hash: commitHash,
      tree: treeHash,
      parents: parents,
      author: commitAuthor,
      committer: committer,
      message: message,
    );

    // Update HEAD
    final currentBranch = await repo.getCurrentBranch();
    if (currentBranch != null) {
      await repo.refs.writeBranch(currentBranch, commitHash);
    } else {
      // Detached HEAD
      await repo.refs.updateHead(commitHash, symbolic: false);
    }

    return finalCommit;
  }

  /// Build and write tree from index entries
  Future<String> _writeTreeFromIndex(List<dynamic> entries) async {
    // Group entries by directory
    final root = <String, dynamic>{};

    for (final entry in entries) {
      final parts = entry.path.split('/');
      var current = root;

      for (var i = 0; i < parts.length - 1; i++) {
        final part = parts[i];
        current[part] ??= <String, dynamic>{};
        current = current[part] as Map<String, dynamic>;
      }

      // Add file entry
      final fileName = parts.last;
      current[fileName] = entry;
    }

    // Write tree recursively
    return await _writeTree(root);
  }

  /// Write tree object recursively
  Future<String> _writeTree(Map<String, dynamic> tree) async {
    final treeEntries = <TreeEntry>[];

    for (final name in tree.keys) {
      final value = tree[name];

      if (value is Map<String, dynamic>) {
        // Subdirectory - write as tree
        final subtreeHash = await _writeTree(value);
        treeEntries.add(TreeEntry(
          mode: GitFileMode.directory,
          name: name,
          hash: subtreeHash,
        ));
      } else {
        // File - add as blob
        final entry = value as dynamic;
        treeEntries.add(TreeEntry(
          mode: _modeFromIndex(entry.mode),
          name: name,
          hash: entry.hash,
        ));
      }
    }

    // Create and write tree
    final gitTree = GitTree.create(
      hash: '', // Will be computed
      entries: treeEntries,
    );

    final treeHash = await repo.objects.writeObject(gitTree);

    return treeHash;
  }

  /// Get default author from config
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

  /// Amend the last commit
  Future<GitCommit> amend(String message, {GitAuthor? author}) async {
    // Get current commit
    final headHash = await repo.refs.resolveHead();
    final oldCommit = await repo.readCommit(headHash);

    // Use current index
    final entries = await repo.index.read();
    final treeHash = await _writeTreeFromIndex(entries);

    // Create new commit with same parent as old commit
    final commitAuthor = author ?? oldCommit.author;
    final commit = GitCommit(
      hash: '', // Will be computed
      tree: treeHash,
      parents: oldCommit.parents, // Use old commit's parents
      author: commitAuthor,
      committer: GitAuthor(name: commitAuthor.name, email: commitAuthor.email),
      message: message,
    );

    final commitHash = await repo.objects.writeObject(commit);

    final finalCommit = GitCommit(
      hash: commitHash,
      tree: treeHash,
      parents: oldCommit.parents,
      author: commitAuthor,
      committer: GitAuthor(name: commitAuthor.name, email: commitAuthor.email),
      message: message,
    );

    // Update HEAD
    final currentBranch = await repo.getCurrentBranch();
    if (currentBranch != null) {
      await repo.refs.writeBranch(currentBranch, commitHash);
    } else {
      await repo.refs.updateHead(commitHash, symbolic: false);
    }

    return finalCommit;
  }

  GitFileMode _modeFromIndex(int mode) {
    if (mode == GitFileMode.executableFile.value) {
      return GitFileMode.executableFile;
    }
    return GitFileMode.regularFile;
  }
}
