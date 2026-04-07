/// Clone operation - create a local copy of a remote repository
library;

import 'dart:io';
import '../core/repository.dart';
import '../remote/remote_manager.dart';
import '../remote/fetch_operations.dart';
import '../operations/checkout_operations.dart';
import '../exceptions/git_exceptions.dart';

/// Clone result
class CloneResult {
  final bool success;
  final GitRepository? repository;
  final String? defaultBranch;
  final int objectsReceived;
  final String? error;

  const CloneResult({
    required this.success,
    this.repository,
    this.defaultBranch,
    this.objectsReceived = 0,
    this.error,
  });
}

/// Clone operation
class CloneOperation {
  /// Clone a repository from a remote URL
  ///
  /// Creates a new repository at [path] and clones from [url].
  /// Optionally specify [branch] to checkout (defaults to remote's HEAD).
  /// Provide [credentials] for authentication if needed.
  /// Set [bare] to true to create a bare repository (no working directory).
  /// Use [remoteName] to set the remote name (defaults to 'origin').
  ///
  /// Example:
  /// ```dart
  /// final cloneOp = CloneOperation();
  /// final result = await cloneOp.clone(
  ///   url: 'https://github.com/user/repo.git',
  ///   path: '/path/to/destination',
  ///   credentials: HttpsCredentials.token('your_token'),
  /// );
  ///
  /// if (result.success) {
  ///   print('Cloned to ${result.repository!.workingDir}');
  ///   print('Default branch: ${result.defaultBranch}');
  /// }
  /// ```
  Future<CloneResult> clone({
    required String url,
    required String path,
    Credentials? credentials,
    String? branch,
    bool bare = false,
    String remoteName = 'origin',
    ProgressCallback? onProgress,
  }) async {
    try {
      // Validate path doesn't already exist
      final targetDir = Directory(path);
      if (await targetDir.exists()) {
        final isEmpty = (await targetDir.list().isEmpty);
        if (!isEmpty) {
          return CloneResult(
            success: false,
            error: 'Target directory already exists and is not empty: $path',
          );
        }
      }

      // Report progress
      onProgress?.call(CloneProgress.initializing, 0.1);

      // Initialize repository
      final repo = await GitRepository.init(path, bare: bare);

      try {
        // Add remote
        onProgress?.call(CloneProgress.addingRemote, 0.2);
        final remoteManager = RemoteManager(repo.gitDir);
        await remoteManager.addRemote(remoteName, url);

        // Fetch from remote
        onProgress?.call(CloneProgress.fetching, 0.3);
        final fetchOp = FetchOperation(repo);
        final fetchResult = await fetchOp.fetch(
          remoteName,
          credentials: credentials,
        );

        if (!fetchResult.success) {
          return CloneResult(
            success: false,
            error: 'Fetch failed: ${fetchResult.error}',
          );
        }

        // Determine default branch
        onProgress?.call(CloneProgress.determiningBranch, 0.7);
        final defaultBranch = branch ??
            await _getDefaultBranch(
              repo,
              remoteName,
              fetchResult.updatedRefs,
            );

        if (defaultBranch == null) {
          return CloneResult(
            success: false,
            error: 'Could not determine default branch',
          );
        }

        // Don't checkout if bare repository
        if (!bare) {
          // Checkout default branch
          onProgress?.call(CloneProgress.checkingOut, 0.8);
          await _checkoutRemoteBranch(repo, remoteName, defaultBranch);
        }

        // Set up tracking branch
        onProgress?.call(CloneProgress.configuringTracking, 0.9);
        await _setupTrackingBranch(repo, defaultBranch, remoteName);

        onProgress?.call(CloneProgress.complete, 1.0);

        return CloneResult(
          success: true,
          repository: repo,
          defaultBranch: defaultBranch,
          objectsReceived: fetchResult.objectsReceived,
        );
      } catch (e) {
        // Clean up on error
        await _cleanupFailedClone(path);
        rethrow;
      }
    } catch (e) {
      return CloneResult(
        success: false,
        error: 'Clone failed: $e',
      );
    }
  }

  /// Get the default branch from remote refs
  Future<String?> _getDefaultBranch(
    GitRepository repo,
    String remoteName,
    List<String> updatedRefs,
  ) async {
    // Try to read symbolic ref from remote HEAD
    final remoteHeadPath = '${repo.gitDir}/refs/remotes/$remoteName/HEAD';
    final remoteHeadFile = File(remoteHeadPath);

    if (await remoteHeadFile.exists()) {
      final content = await remoteHeadFile.readAsString();
      // Format: ref: refs/remotes/origin/main
      if (content.startsWith('ref: ')) {
        final refPath = content.substring(5).trim();
        final parts = refPath.split('/');
        if (parts.length >= 2) {
          return parts.last; // Extract branch name
        }
      }
    }

    // Fallback: look for common branch names
    final commonBranches = ['main', 'master', 'develop', 'trunk'];
    for (final branchName in commonBranches) {
      final refPath = '${repo.gitDir}/refs/remotes/$remoteName/$branchName';
      if (await File(refPath).exists()) {
        return branchName;
      }
    }

    // Last resort: use first available branch
    if (updatedRefs.isNotEmpty) {
      for (final ref in updatedRefs) {
        if (ref.startsWith('refs/heads/')) {
          return ref.substring(11); // Remove 'refs/heads/'
        }
      }
    }

    return null;
  }

  /// Checkout a remote branch as a local branch
  Future<void> _checkoutRemoteBranch(
    GitRepository repo,
    String remoteName,
    String branchName,
  ) async {
    // Get the commit hash from remote branch
    final remoteRefPath = '${repo.gitDir}/refs/remotes/$remoteName/$branchName';
    final remoteRefFile = File(remoteRefPath);

    if (!await remoteRefFile.exists()) {
      throw GitException('Remote branch not found: $remoteName/$branchName');
    }

    final commitHash = (await remoteRefFile.readAsString()).trim();

    // Create local branch pointing to same commit
    final localRefPath = '${repo.gitDir}/refs/heads/$branchName';
    final localRefFile = File(localRefPath);
    await localRefFile.parent.create(recursive: true);
    await localRefFile.writeAsString('$commitHash\n');

    // Update HEAD to point to the new branch
    final headFile = File('${repo.gitDir}/HEAD');
    await headFile.writeAsString('ref: refs/heads/$branchName\n');

    // Checkout the branch
    final checkoutOp = CheckoutOperation(repo);
    await checkoutOp.checkoutBranch(branchName);
  }

  /// Setup tracking branch configuration
  Future<void> _setupTrackingBranch(
    GitRepository repo,
    String branchName,
    String remoteName,
  ) async {
    final config = await repo.config;

    // Set up branch tracking using section format: branch "branchName"
    final branchSection = 'branch "$branchName"';
    config.set(branchSection, 'remote', remoteName);
    config.set(branchSection, 'merge', 'refs/heads/$branchName');

    await config.save();
  }

  /// Clean up directory if clone fails
  Future<void> _cleanupFailedClone(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}

/// Progress callback for clone operation
typedef ProgressCallback = void Function(CloneProgress stage, double progress);

/// Clone progress stages
enum CloneProgress {
  initializing,
  addingRemote,
  fetching,
  determiningBranch,
  checkingOut,
  configuringTracking,
  complete,
}

extension CloneProgressExtension on CloneProgress {
  String get description {
    switch (this) {
      case CloneProgress.initializing:
        return 'Initializing repository';
      case CloneProgress.addingRemote:
        return 'Adding remote';
      case CloneProgress.fetching:
        return 'Fetching objects';
      case CloneProgress.determiningBranch:
        return 'Determining default branch';
      case CloneProgress.checkingOut:
        return 'Checking out files';
      case CloneProgress.configuringTracking:
        return 'Configuring tracking branch';
      case CloneProgress.complete:
        return 'Clone complete';
    }
  }
}
