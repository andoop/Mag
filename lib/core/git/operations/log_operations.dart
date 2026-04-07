/// Log operation - traverse commit history
library;

import '../core/repository.dart';
import '../models/commit.dart';
import '../exceptions/git_exceptions.dart';

/// Options for log operation
class LogOptions {
  final int? maxCount;
  final bool firstParentOnly;
  final String? since;
  final String? until;

  const LogOptions({
    this.maxCount,
    this.firstParentOnly = false,
    this.since,
    this.until,
  });
}

/// Traverse commit history
class LogOperation {
  final GitRepository repo;

  LogOperation(this.repo);

  /// Get commit history starting from HEAD
  Stream<GitCommit> log({LogOptions? options}) async* {
    final opts = options ?? const LogOptions();

    try {
      final headHash = await repo.refs.resolveHead();
      yield* _walkCommits(headHash, opts);
    } catch (e) {
      if (e is! ReferenceNotFoundException) {
        rethrow;
      }
      // No commits yet
    }
  }

  /// Get commit history starting from a specific ref
  Stream<GitCommit> logFrom(String ref, {LogOptions? options}) async* {
    final opts = options ?? const LogOptions();
    final commitHash = await repo.resolveCommitish(ref);
    yield* _walkCommits(commitHash, opts);
  }

  /// Walk commit graph
  Stream<GitCommit> _walkCommits(String startHash, LogOptions options) async* {
    final visited = <String>{};
    final queue = [startHash];
    var count = 0;
    final since = _parseDate(options.since);
    final until = _parseDate(options.until);

    while (queue.isNotEmpty) {
      final hash = queue.removeAt(0);

      // Skip if already visited
      if (visited.contains(hash)) {
        continue;
      }
      visited.add(hash);

      // Read commit
      final commit = await repo.readCommit(hash);

      final timestamp = commit.author.timestamp;
      final isAfterSince = since == null || !timestamp.isBefore(since);
      final isBeforeUntil = until == null || !timestamp.isAfter(until);
      if (isAfterSince && isBeforeUntil) {
        if (options.maxCount != null && count >= options.maxCount!) {
          break;
        }
        yield commit;
        count++;
      }

      // Add parents to queue
      if (options.firstParentOnly && commit.parents.isNotEmpty) {
        queue.add(commit.parents.first);
      } else {
        queue.addAll(commit.parents);
      }
    }
  }

  /// Get commit history as list (for convenience)
  Future<List<GitCommit>> getHistory({LogOptions? options}) async {
    final commits = <GitCommit>[];
    await for (final commit in log(options: options)) {
      commits.add(commit);
    }
    return commits;
  }

  /// Get commit history from a ref
  Future<List<GitCommit>> getHistoryFrom(
    String ref, {
    LogOptions? options,
  }) async {
    final commits = <GitCommit>[];
    await for (final commit in logFrom(ref, options: options)) {
      commits.add(commit);
    }
    return commits;
  }

  /// Find common ancestor of two commits
  Future<String?> findCommonAncestor(String hash1, String hash2) async {
    // Get all ancestors of hash1
    final ancestors1 = <String>{};
    await for (final commit in _walkCommits(hash1, const LogOptions())) {
      ancestors1.add(commit.hash);
    }

    // Find first ancestor of hash2 that's in ancestors1
    await for (final commit in _walkCommits(hash2, const LogOptions())) {
      if (ancestors1.contains(commit.hash)) {
        return commit.hash;
      }
    }

    return null;
  }

  /// Get commits between two refs
  Future<List<GitCommit>> getCommitsBetween(
    String from,
    String to,
  ) async {
    final fromHash = await repo.resolveCommitish(from);
    final toHash = await repo.resolveCommitish(to);

    // Get all commits from 'from'
    final fromCommits = <String>{};
    await for (final commit in _walkCommits(fromHash, const LogOptions())) {
      fromCommits.add(commit.hash);
    }

    // Get commits from 'to' that are not in 'from'
    final commits = <GitCommit>[];
    await for (final commit in _walkCommits(toHash, const LogOptions())) {
      if (!fromCommits.contains(commit.hash)) {
        commits.add(commit);
      } else {
        break; // Reached common ancestor
      }
    }

    return commits;
  }

  /// Get single commit by hash or ref
  Future<GitCommit> getCommit(String ref) async {
    final hash = await repo.resolveCommitish(ref);
    return await repo.readCommit(hash);
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }
}
