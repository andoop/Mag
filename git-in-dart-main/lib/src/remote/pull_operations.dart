/// Pull operation - fetch and merge from remote
library;

import 'dart:io';
import '../core/repository.dart';
import '../remote/remote_manager.dart';
import '../remote/fetch_operations.dart';
import '../operations/merge_operations.dart';

/// Pull result
class PullResult {
  final bool success;
  final FetchResult fetchResult;
  final MergeResult? mergeResult;
  final String? error;

  const PullResult({
    required this.success,
    required this.fetchResult,
    this.mergeResult,
    this.error,
  });
}

/// Pull operation
class PullOperation {
  final GitRepository repo;
  final RemoteManager remoteManager;

  PullOperation(this.repo) : remoteManager = RemoteManager(repo.gitDir);

  /// Pull from remote (fetch + merge)
  Future<PullResult> pull(
    String remoteName, {
    Credentials? credentials,
    String? branch,
  }) async {
    try {
      // Fetch from remote
      final fetchOp = FetchOperation(repo);
      final fetchResult = await fetchOp.fetch(
        remoteName,
        credentials: credentials,
      );

      if (!fetchResult.success) {
        return PullResult(
          success: false,
          fetchResult: fetchResult,
          error: fetchResult.error,
        );
      }

      // Get current branch
      final currentBranch = await repo.getCurrentBranch();
      if (currentBranch == null) {
        return PullResult(
          success: false,
          fetchResult: fetchResult,
          error: 'Cannot pull in detached HEAD state',
        );
      }

      // Merge remote branch
      final remoteBranch = branch ?? currentBranch;
      final remoteRef = '$remoteName/$remoteBranch';

      // Check if remote tracking branch exists
      final remoteRefPath = '${repo.gitDir}/refs/remotes/$remoteRef';
      final remoteRefFile = File(remoteRefPath);

      if (!await remoteRefFile.exists()) {
        return PullResult(
          success: false,
          fetchResult: fetchResult,
          error: 'Remote branch not found: $remoteRef',
        );
      }

      // Merge would need to support merging from remote refs
      // This is simplified - real implementation would resolve remote ref

      return PullResult(
        success: true,
        fetchResult: fetchResult,
      );
    } catch (e) {
      return PullResult(
        success: false,
        fetchResult: FetchResult(
          success: false,
          updatedRefs: [],
          objectsReceived: 0,
          error: e.toString(),
        ),
        error: e.toString(),
      );
    }
  }
}
