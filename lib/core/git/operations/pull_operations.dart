library;

import 'dart:io';

import '../core/repository.dart';
import '../exceptions/git_exceptions.dart';
import '../remote/remote_manager.dart';
import 'fetch_operations.dart';
import 'merge_operations.dart';
import 'rebase_operations.dart';

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

class PullOperation {
  PullOperation(this.repo) : remoteManager = RemoteManager(repo.gitDir);

  final GitRepository repo;
  final RemoteManager remoteManager;

  Future<PullResult> pull(
    String remoteName, {
    String? branch,
    bool rebase = false,
  }) async {
    try {
      final fetchResult = await FetchOperation(repo).fetch(
        remoteName,
        branch: branch,
      );
      if (!fetchResult.success) {
        return PullResult(
          success: false,
          fetchResult: fetchResult,
          error: fetchResult.error,
        );
      }

      final currentBranch = await repo.getCurrentBranch();
      if (currentBranch == null) {
        throw const GitException('Cannot pull in detached HEAD state');
      }

      final tracking = await remoteManager.getTrackingBranch(currentBranch);
      final remoteBranch = branch ?? tracking?.branchName ?? currentBranch;
      final targetRef = 'refs/remotes/$remoteName/$remoteBranch';
      final targetFile = File('${repo.gitDir}/$targetRef');
      if (!await targetFile.exists()) {
        throw GitException('Remote branch not found: $remoteName/$remoteBranch');
      }

      if (rebase) {
        final result = await RebaseOperation(repo).rebase(targetRef);
        return PullResult(
          success: result.success,
          fetchResult: fetchResult,
          rebaseResult: result,
          error: result.success ? null : 'Rebase conflicts: ${result.conflicts.join(', ')}',
        );
      }

      final result = await MergeOperation(repo).mergeRef(
        targetRef,
        targetLabel: '$remoteName/$remoteBranch',
      );
      return PullResult(
        success: result.success && !result.hasConflicts,
        fetchResult: fetchResult,
        mergeResult: result,
        error: result.hasConflicts ? 'Merge conflicts: ${result.conflicts.join(', ')}' : null,
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
}
