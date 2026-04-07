/// High-level git service wrapping pure-Dart repository operations.
///
/// Provides a single entry point for both AI tool calls and programmatic use.
/// All paths are workspace-relative; the service resolves them against the
/// repository working directory.
library;

import 'dart:io';

import 'core/repository.dart';
import 'models/commit.dart';
import 'models/git_author.dart';
import 'models/tree.dart';
import 'operations/add_operations.dart';
import 'operations/commit_operations.dart';
import 'operations/status_operations.dart';
import 'operations/log_operations.dart';
import 'operations/checkout_operations.dart';
import 'operations/merge_operations.dart';

class GitService {
  GitService._(this._repo);

  final GitRepository _repo;

  GitRepository get repository => _repo;
  String get workDir => _repo.workDir;

  // ---------------------------------------------------------------------------
  // Factory / lifecycle
  // ---------------------------------------------------------------------------

  /// Open the git repository that contains [workspacePath].
  /// Walks parent directories looking for `.git/`.
  static Future<GitService> open(String workspacePath) async {
    final repo = await GitRepository.open(workspacePath);
    return GitService._(repo);
  }

  /// Initialise a brand-new repository at [path].
  static Future<GitService> init(String path) async {
    final repo = await GitRepository.init(path);
    return GitService._(repo);
  }

  /// Returns `true` if [path] is inside a git repository.
  static Future<bool> isRepo(String path) => GitRepository.isRepository(path);

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  Future<RepositoryStatus> status() => StatusOperation(_repo).status();

  Future<bool> isClean() => StatusOperation(_repo).isClean();

  // ---------------------------------------------------------------------------
  // Add / stage
  // ---------------------------------------------------------------------------

  /// Stage specific files.  [paths] are workspace-relative.
  Future<void> add(List<String> paths) => AddOperation(_repo).add(paths);

  /// Stage all modified & untracked files.
  Future<void> addAll() => AddOperation(_repo).addAll();

  /// Unstage a file (remove from index).
  Future<void> unstage(String path) => AddOperation(_repo).remove(path);

  // ---------------------------------------------------------------------------
  // Commit
  // ---------------------------------------------------------------------------

  Future<GitCommit> commit(
    String message, {
    String? authorName,
    String? authorEmail,
  }) {
    final author = (authorName != null && authorEmail != null)
        ? GitAuthor(name: authorName, email: authorEmail)
        : null;
    return CommitOperation(_repo).commit(message, author: author);
  }

  Future<GitCommit> amendCommit(
    String message, {
    String? authorName,
    String? authorEmail,
  }) {
    final author = (authorName != null && authorEmail != null)
        ? GitAuthor(name: authorName, email: authorEmail)
        : null;
    return CommitOperation(_repo).amend(message, author: author);
  }

  // ---------------------------------------------------------------------------
  // Log
  // ---------------------------------------------------------------------------

  Future<List<GitCommit>> log({
    int? maxCount,
    bool firstParentOnly = false,
    String? since,
    String? until,
  }) =>
      LogOperation(_repo).getHistory(
        options: LogOptions(
          maxCount: maxCount ?? 20,
          firstParentOnly: firstParentOnly,
          since: since,
          until: until,
        ),
      );

  Future<GitCommit> showCommit(String ref) =>
      LogOperation(_repo).getCommit(ref);

  // ---------------------------------------------------------------------------
  // Branch
  // ---------------------------------------------------------------------------

  Future<String?> currentBranch() => _repo.getCurrentBranch();

  Future<List<String>> listBranches() => _repo.listBranches();

  Future<void> createBranch(String name, {String? startPoint}) =>
      _repo.createBranch(name, startPoint: startPoint);

  Future<void> deleteBranch(String name, {bool force = false}) =>
      _repo.deleteBranch(name, force: force);

  // ---------------------------------------------------------------------------
  // Checkout
  // ---------------------------------------------------------------------------

  Future<void> checkout(String target) async {
    final op = CheckoutOperation(_repo);
    if (await _repo.refs.branchExists(target)) {
      await op.checkoutBranch(target);
      return;
    }

    final commitHash = await _repo.resolveCommitish(target);
    await op.checkoutCommit(commitHash);
  }

  Future<void> checkoutNewBranch(String name) =>
      CheckoutOperation(_repo).checkoutNewBranch(name);

  Future<void> restoreFile(String path) =>
      CheckoutOperation(_repo).restoreFile(path);

  // ---------------------------------------------------------------------------
  // Merge
  // ---------------------------------------------------------------------------

  Future<MergeResult> merge(String branch) =>
      MergeOperation(_repo).merge(branch);

  // ---------------------------------------------------------------------------
  // Diff  (working tree vs HEAD)
  // ---------------------------------------------------------------------------

  /// Returns a human-readable diff between the working tree and HEAD.
  /// Only handles text files; binary files are reported but not diffed.
  Future<String> diff({List<String>? paths}) async {
    final st = await status();
    final filter = paths?.toSet();
    final stagedEntries = _filterEntries(st.staged, filter);
    final unstagedEntries = _filterEntries(st.unstaged, filter);
    final untrackedEntries = _filterEntries(st.untracked, filter);
    if (stagedEntries.isEmpty &&
        unstagedEntries.isEmpty &&
        untrackedEntries.isEmpty) {
      return 'No changes.';
    }

    final headCommitHash = await _repo.getCurrentCommit();
    Map<String, String>? headTree;
    if (headCommitHash != null) {
      headTree = {};
      final commit = await _repo.readCommit(headCommitHash);
      final tree = await _repo.readTree(commit.tree);
      await _collectPaths(tree, '', headTree);
    }

    final indexEntries = await _repo.index.read();
    final indexMap = <String, String>{};
    for (final entry in indexEntries) {
      indexMap[entry.path] = entry.hash;
    }

    final buf = StringBuffer();
    await _appendDiffGroup(
      buf: buf,
      title: 'Staged changes',
      entries: stagedEntries,
      oldBlobHashes: headTree,
      newBlobHashes: indexMap,
      allowWorkingTreeReads: false,
    );
    await _appendDiffGroup(
      buf: buf,
      title: 'Unstaged changes',
      entries: unstagedEntries,
      oldBlobHashes: indexMap,
      newBlobHashes: null,
      allowWorkingTreeReads: true,
    );
    await _appendDiffGroup(
      buf: buf,
      title: 'Untracked files',
      entries: untrackedEntries,
      oldBlobHashes: const {},
      newBlobHashes: null,
      allowWorkingTreeReads: true,
    );
    final result = buf.toString().trimRight();
    return result.isEmpty ? 'No changes.' : result;
  }

  Future<void> _appendDiffGroup({
    required StringBuffer buf,
    required String title,
    required List<StatusEntry> entries,
    required Map<String, String>? oldBlobHashes,
    required Map<String, String>? newBlobHashes,
    required bool allowWorkingTreeReads,
  }) async {
    if (entries.isEmpty) {
      return;
    }

    buf.writeln('$title:');
    for (final entry in entries) {
      buf.writeln('--- ${entry.status.name}: ${entry.path}');
      try {
        final oldContent = await _readBlobContent(
          path: entry.path,
          hashes: oldBlobHashes,
        );
        final newContent = await _readNewSideContent(
          path: entry.path,
          hashes: newBlobHashes,
          allowWorkingTreeReads: allowWorkingTreeReads,
        );

        if (entry.status == FileStatus.added ||
            entry.status == FileStatus.untracked) {
          _writeAddedContent(newContent, buf);
        } else if (entry.status == FileStatus.deleted) {
          _writeDeletedContent(oldContent, buf);
        } else {
          _simpleDiff(oldContent ?? '', newContent ?? '', buf);
        }
      } catch (_) {
        buf.writeln('  (binary or unreadable)');
      }
      buf.writeln();
    }
  }

  // ---------------------------------------------------------------------------
  // Config helpers
  // ---------------------------------------------------------------------------

  Future<String?> getConfigValue(String section, String key) async {
    final cfg = await _repo.config;
    final v = cfg.get(section, key);
    return v?.toString();
  }

  Future<void> setConfigValue(
      String section, String key, String value) async {
    final cfg = await _repo.config;
    cfg.set(section, key, value);
    await cfg.save();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _collectPaths(
      GitTree tree, String prefix, Map<String, String> out) async {
    for (final entry in tree.entries) {
      final p = prefix.isEmpty ? entry.name : '$prefix/${entry.name}';
      if (entry.isDirectory) {
        final sub = await _repo.readTree(entry.hash);
        await _collectPaths(sub, p, out);
      } else {
        out[p] = entry.hash;
      }
    }
  }

  List<StatusEntry> _filterEntries(List<StatusEntry> entries, Set<String>? filter) {
    final sorted = List<StatusEntry>.from(entries)
      ..sort((a, b) => a.path.compareTo(b.path));
    if (filter == null || filter.isEmpty) {
      return sorted;
    }
    return sorted.where((entry) => filter.contains(entry.path)).toList();
  }

  Future<String?> _readBlobContent({
    required String path,
    required Map<String, String>? hashes,
  }) async {
    final hash = hashes?[path];
    if (hash == null || hash.isEmpty) {
      return null;
    }
    final blob = await _repo.readBlob(hash);
    return blob.contentAsString;
  }

  Future<String?> _readNewSideContent({
    required String path,
    required Map<String, String>? hashes,
    required bool allowWorkingTreeReads,
  }) async {
    final hash = hashes?[path];
    if (hash != null) {
      final blob = await _repo.readBlob(hash);
      return blob.contentAsString;
    }
    if (!allowWorkingTreeReads) {
      return null;
    }
    final file = File(_repo.getWorkPath(path));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  void _writeAddedContent(String? content, StringBuffer buf) {
    for (final line in (content ?? '').split('\n')) {
      buf.writeln('+$line');
    }
  }

  void _writeDeletedContent(String? content, StringBuffer buf) {
    for (final line in (content ?? '').split('\n')) {
      buf.writeln('-$line');
    }
  }

  /// Minimal line-level diff (no Myers — just enough for AI context).
  void _simpleDiff(String old, String cur, StringBuffer buf) {
    final oldLines = old.split('\n');
    final curLines = cur.split('\n');
    final maxLen = oldLines.length > curLines.length
        ? oldLines.length
        : curLines.length;
    for (var i = 0; i < maxLen; i++) {
      final o = i < oldLines.length ? oldLines[i] : null;
      final c = i < curLines.length ? curLines[i] : null;
      if (o == c) {
        buf.writeln(' ${o ?? ''}');
      } else {
        if (o != null) buf.writeln('-$o');
        if (c != null) buf.writeln('+$c');
      }
    }
  }
}
