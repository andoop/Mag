/// Example demonstrating SSH authentication for push and pull operations
library;

import 'package:git_on_dart/git_on_dart.dart';

Future<void> main() async {
  // Initialize or open a repository
  final repo = await GitRepository.open('/path/to/your/repo');

  // Configure SSH credentials
  final sshCreds = SshCredentials(
    privateKeyPath: '~/.ssh/id_rsa',
    passphrase: null, // Set if your key is encrypted
  );

  // Verify SSH key exists
  if (!await sshCreds.hasPrivateKey()) {
    print('Error: SSH private key not found!');
    return;
  }

  print('Using SSH key at: ${sshCreds.privateKeyPath}');

  // Add remote with SSH URL (if not already added)
  final remoteManager = RemoteManager(repo.gitDir);
  try {
    await remoteManager.addRemote(
      'origin',
      'git@github.com:username/repo.git',
    );
    print('✓ Added remote origin');
  } catch (e) {
    print('Remote already exists or error: $e');
  }

  // Fetch from remote using SSH
  print('\nFetching from remote...');
  final fetchOp = FetchOperation(repo);
  final fetchResult = await fetchOp.fetch(
    'origin',
    credentials: sshCreds,
  );

  if (fetchResult.success) {
    print('✓ Fetch successful!');
    print('  Updated refs: ${fetchResult.updatedRefs.length}');
    for (final ref in fetchResult.updatedRefs) {
      print('    - $ref');
    }
  } else {
    print('✗ Fetch failed: ${fetchResult.error}');
  }

  // Make some changes and commit
  print('\nMaking changes...');
  final addOp = AddOperation(repo);
  await addOp.addAll();

  final commitOp = CommitOperation(repo);
  final author = GitAuthor(
    name: 'Your Name',
    email: 'your.email@example.com',
  );
  await commitOp.commit('Test commit via SSH', author: author);
  print('✓ Created commit');

  // Push using SSH
  print('\nPushing to remote...');
  final pushOp = PushOperation(repo);
  final pushResult = await pushOp.push(
    'origin',
    credentials: sshCreds,
    refspec: 'main:main',
  );

  if (pushResult.success) {
    print('✓ Push successful!');
    print('  Pushed refs: ${pushResult.pushedRefs}');
  } else {
    print('✗ Push failed: ${pushResult.error}');
  }

  // Pull from remote using SSH
  print('\nPulling from remote...');
  final pullOp = PullOperation(repo);
  final pullResult = await pullOp.pull(
    'origin',
    credentials: sshCreds,
    branch: 'main',
  );

  if (pullResult.success) {
    print('✓ Pull successful!');
    if (pullResult.mergeResult?.hasConflicts == true) {
      print('⚠ Conflicts detected in:');
      for (final conflict in pullResult.mergeResult!.conflicts) {
        print('    - $conflict');
      }
    }
  } else {
    print('✗ Pull failed: ${pullResult.error}');
  }

  print('\n✓ SSH operations example completed!');
}
