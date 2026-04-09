library;

import 'exceptions/git_exceptions.dart';
import 'git_settings_store.dart';
import 'models/commit.dart';
import 'models/git_author.dart';
import 'network_git_bridge.dart';

enum FileStatus {
  untracked,
  added,
  modified,
  deleted,
  renamed,
  copied,
  unmerged,
}

class StatusEntry {
  const StatusEntry({
    required this.path,
    required this.status,
    this.oldPath,
  });

  final String path;
  final FileStatus status;
  final String? oldPath;

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
        return 'R  ${oldPath ?? path} -> $path';
      case FileStatus.copied:
        return 'C  ${oldPath ?? path} -> $path';
      case FileStatus.unmerged:
        return 'UU $path';
    }
  }
}

class RepositoryStatus {
  const RepositoryStatus({
    required this.staged,
    required this.unstaged,
    required this.untracked,
    this.currentBranch,
    this.currentCommit,
  });

  final List<StatusEntry> staged;
  final List<StatusEntry> unstaged;
  final List<StatusEntry> untracked;
  final String? currentBranch;
  final String? currentCommit;

  bool get isClean => staged.isEmpty && unstaged.isEmpty && untracked.isEmpty;

  @override
  String toString() {
    final buffer = StringBuffer();
    if (currentBranch != null) {
      buffer.writeln('On branch $currentBranch');
    } else if (currentCommit != null) {
      final shortCommit = currentCommit!.length > 8
          ? currentCommit!.substring(0, 8)
          : currentCommit;
      buffer.writeln('HEAD detached at $shortCommit');
    } else {
      buffer.writeln('No commits yet');
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

class CloneResult {
  const CloneResult({
    required this.success,
    this.defaultBranch,
    required this.objectsReceived,
    this.error,
  });

  final bool success;
  final String? defaultBranch;
  final int objectsReceived;
  final String? error;
}

class FetchResult {
  const FetchResult({
    required this.success,
    required this.updatedRefs,
    required this.objectsReceived,
    this.error,
  });

  final bool success;
  final List<String> updatedRefs;
  final int objectsReceived;
  final String? error;
}

class MergeResult {
  const MergeResult({
    required this.success,
    required this.conflicts,
    this.mergeCommit,
  });

  final bool success;
  final List<String> conflicts;
  final String? mergeCommit;

  bool get hasConflicts => conflicts.isNotEmpty;
}

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

class PullResult {
  const PullResult({
    required this.success,
    required this.fetchResult,
    this.mergeResult,
    this.rebaseResult,
    this.error,
  });

  final bool success;
  final FetchResult fetchResult;
  final MergeResult? mergeResult;
  final RebaseResult? rebaseResult;
  final String? error;
}

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

class GitService {
  GitService._(this.workDir);

  static const GitNetworkBridge _bridge = GitNetworkBridge();

  final String workDir;

  static Future<GitService> open(String workspacePath) async {
    final result = await _bridge.discoverRepository(path: workspacePath);
    _throwIfBridgeFailed(result, fallback: 'Not a git repository');
    final workDir = result['workDir'] as String?;
    if (workDir == null || workDir.isEmpty) {
      throw const GitException('Not a git repository');
    }
    return GitService._(workDir);
  }

  static Future<GitService> init(String path) async {
    final result = await _bridge.initRepository(path: path);
    _throwIfBridgeFailed(result, fallback: 'Init failed.');
    return GitService._((result['workDir'] as String?) ?? path);
  }

  static Future<CloneResult> clone({
    required String url,
    required String path,
    String remoteName = 'origin',
    String? branch,
    ResolvedGitAuth? auth,
  }) async {
    try {
      final result = await _bridge.clone(
        url: url,
        path: path,
        remoteName: remoteName,
        branch: branch,
        auth: auth,
      );
      return CloneResult(
        success: (result['success'] as bool?) ?? true,
        defaultBranch: result['defaultBranch'] as String?,
        objectsReceived: _asInt(result['objectsReceived']) ?? 0,
        error: result['error'] as String?,
      );
    } catch (error) {
      return CloneResult(
        success: false,
        objectsReceived: 0,
        error: error.toString(),
      );
    }
  }

  static Future<bool> isRepo(String path) async {
    try {
      final result = await _bridge.discoverRepository(path: path);
      return (result['success'] as bool?) != false &&
          ((result['workDir'] as String?)?.isNotEmpty ?? false);
    } catch (_) {
      return false;
    }
  }

  Future<RepositoryStatus> status() async {
    final result = await _bridge.status(workDir: workDir);
    _throwIfBridgeFailed(result, fallback: 'Status failed.');
    return RepositoryStatus(
      staged: _statusEntries(result['staged']),
      unstaged: _statusEntries(result['unstaged']),
      untracked: _statusEntries(result['untracked']),
      currentBranch: result['branch'] as String?,
      currentCommit: result['head'] as String?,
    );
  }

  Future<bool> isClean() async => (await status()).isClean;

  Future<void> add(List<String> paths) async {
    final result = await _bridge.add(workDir: workDir, paths: paths);
    _throwIfBridgeFailed(result, fallback: 'Add failed.');
  }

  Future<void> addAll() async {
    final result = await _bridge.addAll(workDir: workDir);
    _throwIfBridgeFailed(result, fallback: 'Add failed.');
  }

  Future<void> unstage(String path) async {
    final result = await _bridge.unstage(workDir: workDir, path: path);
    _throwIfBridgeFailed(result, fallback: 'Unstage failed.');
  }

  Future<GitCommit> commit(
    String message, {
    String? authorName,
    String? authorEmail,
  }) async {
    final result = await _bridge.commit(
      workDir: workDir,
      message: message,
      authorName: authorName,
      authorEmail: authorEmail,
    );
    _throwIfBridgeFailed(result, fallback: 'Commit failed.');
    return _commitFromMap(
      result,
      fallbackMessage: message,
      fallbackAuthorName: authorName,
      fallbackAuthorEmail: authorEmail,
    );
  }

  Future<GitCommit> amendCommit(
    String message, {
    String? authorName,
    String? authorEmail,
  }) async {
    final result = await _bridge.amendCommit(
      workDir: workDir,
      message: message,
      authorName: authorName,
      authorEmail: authorEmail,
    );
    _throwIfBridgeFailed(result, fallback: 'Commit amend failed.');
    return _commitFromMap(
      result,
      fallbackMessage: message,
      fallbackAuthorName: authorName,
      fallbackAuthorEmail: authorEmail,
    );
  }

  Future<List<GitCommit>> log({
    int? maxCount,
    bool firstParentOnly = false,
    String? since,
    String? until,
  }) async {
    final result = await _bridge.log(
      workDir: workDir,
      maxCount: maxCount ?? 20,
      firstParentOnly: firstParentOnly,
      since: since,
      until: until,
    );
    _throwIfBridgeFailed(result, fallback: 'Log failed.');
    final commits = result['commits'] as List? ?? const [];
    return commits
        .map((item) => _commitFromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<GitCommit> showCommit(String ref) async {
    final result = await _bridge.showCommit(workDir: workDir, ref: ref);
    _throwIfBridgeFailed(result, fallback: 'Show failed.');
    final commit = result['commit'];
    if (commit is! Map) {
      throw const GitException('Commit not found.');
    }
    return _commitFromMap(Map<String, dynamic>.from(commit));
  }

  Future<String?> currentBranch() async {
    final result = await _bridge.currentBranch(workDir: workDir);
    _throwIfBridgeFailed(result, fallback: 'Branch lookup failed.');
    return result['branch'] as String?;
  }

  Future<List<String>> listBranches() async {
    final result = await _bridge.listBranches(workDir: workDir);
    _throwIfBridgeFailed(result, fallback: 'List branches failed.');
    return ((result['branches'] as List?) ?? const [])
        .map((item) => item.toString())
        .toList();
  }

  Future<void> createBranch(String name, {String? startPoint}) async {
    final result = await _bridge.createBranch(
      workDir: workDir,
      name: name,
      startPoint: startPoint,
    );
    _throwIfBridgeFailed(result, fallback: 'Create branch failed.');
  }

  Future<void> deleteBranch(String name, {bool force = false}) async {
    final result = await _bridge.deleteBranch(
      workDir: workDir,
      name: name,
      force: force,
    );
    _throwIfBridgeFailed(result, fallback: 'Delete branch failed.');
  }

  Future<void> checkout(String target) async {
    final result = await _bridge.checkout(workDir: workDir, target: target);
    _throwIfBridgeFailed(result, fallback: 'Checkout failed.');
  }

  Future<void> checkoutNewBranch(String name) async {
    final result =
        await _bridge.checkoutNewBranch(workDir: workDir, name: name);
    _throwIfBridgeFailed(result, fallback: 'Checkout failed.');
  }

  Future<void> restoreFile(String path) async {
    final result = await _bridge.restoreFile(workDir: workDir, path: path);
    _throwIfBridgeFailed(result, fallback: 'Restore failed.');
  }

  Future<MergeResult> merge(String branch) async {
    final result = await _bridge.merge(workDir: workDir, branch: branch);
    final conflicts = ((result['conflicts'] as List?) ?? const [])
        .map((item) => item.toString())
        .toList();
    final success = (result['success'] as bool?) ?? true;
    if (!success && conflicts.isEmpty) {
      throw GitException(result['error'] as String? ?? 'Merge failed.');
    }
    return MergeResult(
      success: success,
      conflicts: conflicts,
      mergeCommit: result['mergeCommit'] as String?,
    );
  }

  Future<MergeResult> mergeRef(String ref, {String? targetLabel}) =>
      merge(ref);

  Future<FetchResult> fetch(
    String remoteName, {
    String? branch,
    ResolvedGitAuth? auth,
  }) async {
    try {
      final result = await _bridge.fetch(
        workDir: workDir,
        remoteName: remoteName,
        branch: branch,
        auth: auth,
      );
      return FetchResult(
        success: (result['success'] as bool?) ?? true,
        updatedRefs: ((result['updatedRefs'] as List?) ?? const [])
            .map((item) => item.toString())
            .toList(),
        objectsReceived: _asInt(result['objectsReceived']) ?? 0,
        error: result['error'] as String?,
      );
    } catch (error) {
      return FetchResult(
        success: false,
        updatedRefs: const [],
        objectsReceived: 0,
        error: error.toString(),
      );
    }
  }

  Future<PullResult> pull(
    String remoteName, {
    String? branch,
    bool rebase = false,
    ResolvedGitAuth? auth,
  }) async {
    try {
      final result = await _bridge.pull(
        workDir: workDir,
        remoteName: remoteName,
        branch: branch,
        rebase: rebase,
        auth: auth,
      );
      final fetchResult = FetchResult(
        success: (result['fetchSuccess'] as bool?) ??
            ((result['success'] as bool?) ?? true),
        updatedRefs: ((result['updatedRefs'] as List?) ?? const [])
            .map((item) => item.toString())
            .toList(),
        objectsReceived: _asInt(result['objectsReceived']) ?? 0,
        error: result['fetchError'] as String?,
      );
      final conflicts = ((result['conflicts'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList();
      return PullResult(
        success: (result['success'] as bool?) ?? true,
        fetchResult: fetchResult,
        mergeResult: rebase
            ? null
            : MergeResult(
                success: (result['success'] as bool?) ?? true,
                conflicts: conflicts,
                mergeCommit: result['mergeCommit'] as String?,
              ),
        rebaseResult: rebase
            ? RebaseResult(
                success: (result['success'] as bool?) ?? true,
                conflicts: conflicts,
                newHead: result['newHead'] as String?,
              )
            : null,
        error: result['error'] as String?,
      );
    } catch (error) {
      return PullResult(
        success: false,
        fetchResult: const FetchResult(
          success: false,
          updatedRefs: [],
          objectsReceived: 0,
        ),
        error: error.toString(),
      );
    }
  }

  Future<PushResult> push(
    String remoteName, {
    String? refspec,
    bool force = false,
    ResolvedGitAuth? auth,
  }) async {
    try {
      final result = await _bridge.push(
        workDir: workDir,
        remoteName: remoteName,
        refspec: refspec,
        force: force,
        auth: auth,
      );
      return PushResult(
        success: (result['success'] as bool?) ?? true,
        pushedRefs: ((result['pushedRefs'] as List?) ?? const [])
            .map((item) => item.toString())
            .toList(),
        error: result['error'] as String?,
      );
    } catch (error) {
      return PushResult(
        success: false,
        pushedRefs: const [],
        error: error.toString(),
      );
    }
  }

  Future<RebaseResult> rebase(String targetRef) async {
    final result =
        await _bridge.rebase(workDir: workDir, targetRef: targetRef);
    final conflicts = ((result['conflicts'] as List?) ?? const [])
        .map((item) => item.toString())
        .toList();
    final success = (result['success'] as bool?) ?? true;
    if (!success && conflicts.isEmpty) {
      throw GitException(result['error'] as String? ?? 'Rebase failed.');
    }
    return RebaseResult(
      success: success,
      conflicts: conflicts,
      newHead: result['newHead'] as String?,
    );
  }

  Future<String> diff({List<String>? paths}) async {
    final result = await _bridge.diff(workDir: workDir, paths: paths);
    _throwIfBridgeFailed(result, fallback: 'Diff failed.');
    return result['diff'] as String? ?? 'No changes.';
  }

  Future<String?> getConfigValue(String section, String key) async {
    final result = await _bridge.getConfigValue(
      workDir: workDir,
      section: section,
      key: key,
    );
    _throwIfBridgeFailed(result, fallback: 'Config lookup failed.');
    return result['value'] as String?;
  }

  Future<void> setConfigValue(String section, String key, String value) async {
    final result = await _bridge.setConfigValue(
      workDir: workDir,
      section: section,
      key: key,
      value: value,
    );
    _throwIfBridgeFailed(result, fallback: 'Config update failed.');
  }

  Future<String?> getRemoteUrl(String remoteName) async {
    final result = await _bridge.getRemoteUrl(
      workDir: workDir,
      remoteName: remoteName,
    );
    _throwIfBridgeFailed(result, fallback: 'Remote lookup failed.');
    return result['url'] as String?;
  }

  static void _throwIfBridgeFailed(
    Map<String, dynamic> result, {
    required String fallback,
  }) {
    if ((result['success'] as bool?) == false) {
      throw GitException(result['error'] as String? ?? fallback);
    }
  }

  static List<StatusEntry> _statusEntries(dynamic raw) {
    final input = raw as List?;
    if (input == null) {
      return const <StatusEntry>[];
    }
    return input.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return StatusEntry(
        path: map['path'] as String? ?? '',
        status: _fileStatusFromString(map['status'] as String? ?? 'modified'),
        oldPath: map['oldPath'] as String?,
      );
    }).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  static FileStatus _fileStatusFromString(String value) {
    switch (value) {
      case 'untracked':
        return FileStatus.untracked;
      case 'added':
        return FileStatus.added;
      case 'deleted':
        return FileStatus.deleted;
      case 'renamed':
        return FileStatus.renamed;
      case 'copied':
        return FileStatus.copied;
      case 'unmerged':
        return FileStatus.unmerged;
      case 'modified':
      default:
        return FileStatus.modified;
    }
  }

  static GitCommit _commitFromMap(
    Map<String, dynamic> map, {
    String? fallbackMessage,
    String? fallbackAuthorName,
    String? fallbackAuthorEmail,
  }) {
    return GitCommit(
      hash: map['hash'] as String? ?? '',
      tree: map['tree'] as String? ?? '',
      parents: ((map['parents'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      author: GitAuthor(
        name: map['authorName'] as String? ?? (fallbackAuthorName ?? 'Unknown'),
        email: map['authorEmail'] as String? ??
            (fallbackAuthorEmail ?? 'unknown@example.com'),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          _asInt(map['authorTimestampMs']) ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        timezone: map['authorTimezone'] as String?,
      ),
      committer: GitAuthor(
        name:
            map['committerName'] as String? ?? (fallbackAuthorName ?? 'Unknown'),
        email: map['committerEmail'] as String? ??
            (fallbackAuthorEmail ?? 'unknown@example.com'),
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          _asInt(map['committerTimestampMs']) ??
              DateTime.now().millisecondsSinceEpoch,
        ),
        timezone: map['committerTimezone'] as String?,
      ),
      message: map['message'] as String? ?? fallbackMessage ?? '',
    );
  }

  static int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
