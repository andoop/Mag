/// Example demonstrating repository cloning with different authentication methods
library;

import 'dart:io';
import 'package:git_on_dart/git_on_dart.dart';

Future<void> main() async {
  print('=== Git Clone Examples ===\n');

  // Example 1: Clone public repository (HTTPS, no auth)
  await clonePublicRepo();

  // Example 2: Clone private repository with token (HTTPS)
  // await clonePrivateRepoWithToken();

  // Example 3: Clone with SSH
  // await cloneWithSSH();

  // Example 4: Clone with progress tracking
  // await cloneWithProgress();

  // Example 5: Clone bare repository
  // await cloneBareRepo();
}

/// Example 1: Clone a public repository via HTTPS
Future<void> clonePublicRepo() async {
  print('--- Example 1: Clone Public Repository ---');

  final cloneOp = CloneOperation();

  try {
    final result = await cloneOp.clone(
      url: 'https://github.com/git/git.git',
      path: '/tmp/git-clone-test',
    );

    if (result.success) {
      print('✓ Clone successful!');
      print('  Repository: ${result.repository!.workDir}');
      print('  Default branch: ${result.defaultBranch}');
      print('  Objects received: ${result.objectsReceived}');

      // Verify clone by checking status
      final statusOp = StatusOperation(result.repository!);
      final status = await statusOp.status();
      print('  Current branch: ${status.currentBranch}');
      print('  Working tree clean: ${status.isClean}');
    } else {
      print('✗ Clone failed: ${result.error}');
    }
  } catch (e) {
    print('✗ Error: $e');
  }

  print('');
}

/// Example 2: Clone a private repository with personal access token
Future<void> clonePrivateRepoWithToken() async {
  print('--- Example 2: Clone Private Repository (Token) ---');

  final cloneOp = CloneOperation();

  // Replace with your actual token and repository
  final credentials = HttpsCredentials.token('ghp_your_github_token_here');

  try {
    final result = await cloneOp.clone(
      url: 'https://github.com/username/private-repo.git',
      path: '/tmp/private-clone-test',
      credentials: credentials,
    );

    if (result.success) {
      print('✓ Clone successful!');
      print('  Repository: ${result.repository!.workDir}');
      print('  Default branch: ${result.defaultBranch}');

      // List files in working directory
      final dir = Directory(result.repository!.workDir);
      print('  Files:');
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.contains('.git')) {
          print('    - ${entity.path.split('/').last}');
        }
      }
    } else {
      print('✗ Clone failed: ${result.error}');
    }
  } catch (e) {
    print('✗ Error: $e');
  }

  print('');
}

/// Example 3: Clone with SSH authentication
Future<void> cloneWithSSH() async {
  print('--- Example 3: Clone with SSH ---');

  final cloneOp = CloneOperation();

  final sshCreds = SshCredentials(
    privateKeyPath: '~/.ssh/id_ed25519',
    passphrase: null, // Set if your key has a passphrase
  );

  // Verify SSH key exists
  if (!await sshCreds.hasPrivateKey()) {
    print('✗ SSH key not found at ${sshCreds.privateKeyPath}');
    return;
  }

  try {
    final result = await cloneOp.clone(
      url: 'git@github.com:username/repo.git',
      path: '/tmp/ssh-clone-test',
      credentials: sshCreds,
    );

    if (result.success) {
      print('✓ Clone successful!');
      print('  Repository: ${result.repository!.workDir}');
      print('  Default branch: ${result.defaultBranch}');

      // Check remote configuration
      final remoteManager = RemoteManager(result.repository!.gitDir);
      final remotes = await remoteManager.listRemotes();
      print('  Remotes:');
      for (final remote in remotes) {
        print('    - ${remote.name}: ${remote.url}');
      }
    } else {
      print('✗ Clone failed: ${result.error}');
    }
  } catch (e) {
    print('✗ Error: $e');
  }

  print('');
}

/// Example 4: Clone with progress tracking
Future<void> cloneWithProgress() async {
  print('--- Example 4: Clone with Progress Tracking ---');

  final cloneOp = CloneOperation();

  try {
    final result = await cloneOp.clone(
      url: 'https://github.com/flutter/flutter.git',
      path: '/tmp/progress-clone-test',
      onProgress: (stage, progress) {
        final percentage = (progress * 100).toStringAsFixed(0);
        final stageName = stage.toString().split('.').last;
        print('[$percentage%] $stageName');
      },
    );

    if (result.success) {
      print('\n✓ Clone complete!');
      print('  Repository: ${result.repository!.workDir}');
      print('  Default branch: ${result.defaultBranch}');
    } else {
      print('\n✗ Clone failed: ${result.error}');
    }
  } catch (e) {
    print('\n✗ Error: $e');
  }

  print('');
}

/// Example 5: Clone as bare repository (no working directory)
Future<void> cloneBareRepo() async {
  print('--- Example 5: Clone Bare Repository ---');

  final cloneOp = CloneOperation();

  try {
    final result = await cloneOp.clone(
      url: 'https://github.com/dart-lang/sdk.git',
      path: '/tmp/bare-clone-test.git',
      bare: true,
    );

    if (result.success) {
      print('✓ Bare clone successful!');
      print('  Repository: ${result.repository!.gitDir}');
      print('  Default branch: ${result.defaultBranch}');
      print('  (No working directory - bare repository)');

      // List branches
      final branches = await result.repository!.listBranches();
      print('  Branches:');
      for (final branch in branches.take(5)) {
        print('    - $branch');
      }
      if (branches.length > 5) {
        print('    ... and ${branches.length - 5} more');
      }
    } else {
      print('✗ Clone failed: ${result.error}');
    }
  } catch (e) {
    print('✗ Error: $e');
  }

  print('');
}

/// Example 6: Clone specific branch
Future<void> cloneSpecificBranch() async {
  print('--- Example 6: Clone Specific Branch ---');

  final cloneOp = CloneOperation();

  try {
    final result = await cloneOp.clone(
      url: 'https://github.com/username/repo.git',
      path: '/tmp/branch-clone-test',
      branch: 'develop', // Clone and checkout specific branch
    );

    if (result.success) {
      print('✓ Clone successful!');
      print('  Repository: ${result.repository!.workDir}');
      print('  Checked out branch: ${result.defaultBranch}');

      // Verify we're on the correct branch
      final currentBranch = await result.repository!.getCurrentBranch();
      print('  Current branch: $currentBranch');
    } else {
      print('✗ Clone failed: ${result.error}');
    }
  } catch (e) {
    print('✗ Error: $e');
  }

  print('');
}

/// Example 7: Clone with custom remote name
Future<void> cloneWithCustomRemote() async {
  print('--- Example 7: Clone with Custom Remote Name ---');

  final cloneOp = CloneOperation();

  try {
    final result = await cloneOp.clone(
      url: 'https://github.com/username/repo.git',
      path: '/tmp/custom-remote-test',
      remoteName: 'upstream', // Use 'upstream' instead of 'origin'
    );

    if (result.success) {
      print('✓ Clone successful!');
      print('  Repository: ${result.repository!.workDir}');

      // Check remote name
      final remoteManager = RemoteManager(result.repository!.gitDir);
      final remotes = await remoteManager.listRemotes();
      print('  Remotes:');
      for (final remote in remotes) {
        print('    - ${remote.name}: ${remote.url}');
      }
    } else {
      print('✗ Clone failed: ${result.error}');
    }
  } catch (e) {
    print('✗ Error: $e');
  }

  print('');
}

/// Clean up test directories
Future<void> cleanupTestDirs() async {
  final testDirs = [
    '/tmp/git-clone-test',
    '/tmp/private-clone-test',
    '/tmp/ssh-clone-test',
    '/tmp/progress-clone-test',
    '/tmp/bare-clone-test.git',
    '/tmp/branch-clone-test',
    '/tmp/custom-remote-test',
  ];

  for (final path in testDirs) {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        print('Cleaned up: $path');
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}
