import 'dart:io';
import 'package:git_on_dart/git_on_dart.dart';

Future<void> main() async {
  print('=== Git on Dart Example ===\n');

  // Create a temporary directory for demo
  final tempDir = await Directory.systemTemp.createTemp('git_demo');
  final repoPath = tempDir.path;

  try {
    // Initialize a new repository
    print('Initializing repository at $repoPath...');
    final repo = await GitRepository.init(repoPath);
    print('✓ Repository initialized\n');

    // Configure user
    final config = await repo.config;
    config.set('user', 'name', 'Demo User');
    config.set('user', 'email', 'demo@example.com');
    await config.save();

    // Create some files
    print('Creating files...');
    await File('$repoPath/README.md')
        .writeAsString('# My Project\n\nThis is a demo project.');
    await File('$repoPath/hello.txt').writeAsString('Hello, World!');
    await Directory('$repoPath/src').create();
    await File('$repoPath/src/main.dart')
        .writeAsString('void main() => print("Hello!");');
    print('✓ Files created\n');

    // Add files to staging area
    print('Adding files to staging area...');
    final addOp = AddOperation(repo);
    await addOp.addAll();
    print('✓ Files staged\n');

    // Check status
    print('Repository status:');
    final statusOp = StatusOperation(repo);
    final status = await statusOp.status();
    print(status);
    print('');

    // Create initial commit
    print('Creating initial commit...');
    final commitOp = CommitOperation(repo);
    final commit1 = await commitOp.commit('Initial commit');
    print('✓ Commit created: ${commit1.hash.substring(0, 7)}\n');

    // Create a new branch
    print('Creating feature branch...');
    await repo.createBranch('feature');
    print('✓ Branch created\n');

    // Switch to feature branch
    print('Checking out feature branch...');
    final checkoutOp = CheckoutOperation(repo);
    await checkoutOp.checkoutBranch('feature');
    print('✓ Switched to feature branch\n');

    // Make changes
    print('Making changes...');
    await File('$repoPath/hello.txt').writeAsString('Hello, Dart!');
    await File('$repoPath/feature.txt').writeAsString('New feature file');
    print('✓ Changes made\n');

    // Add and commit changes
    print('Committing changes...');
    await addOp.addAll();
    final commit2 = await commitOp.commit('Add feature');
    print('✓ Commit created: ${commit2.hash.substring(0, 7)}\n');

    // Switch back to main
    print('Switching back to main...');
    await checkoutOp.checkoutBranch('main');
    print('✓ Switched to main\n');

    // Show commit log
    print('Commit history:');
    final logOp = LogOperation(repo);
    final commits =
        await logOp.getHistory(options: const LogOptions(maxCount: 5));
    for (final commit in commits) {
      print('  ${commit.hash.substring(0, 7)} - ${commit.shortMessage}');
      print('  Author: ${commit.author.name} <${commit.author.email}>');
      print('  Date: ${commit.author.timestamp}\n');
    }

    // Merge feature branch
    print('Merging feature branch...');
    final mergeOp = MergeOperation(repo);
    final mergeResult = await mergeOp.merge('feature');

    if (mergeResult.success) {
      print('✓ Merge successful\n');
    } else {
      print('✗ Merge has conflicts:');
      for (final conflict in mergeResult.conflicts) {
        print('  - $conflict');
      }
      print('');
    }

    // Show final status
    print('Final repository status:');
    final finalStatus = await statusOp.status();
    print(finalStatus);

    // List all branches
    print('Branches:');
    final branches = await repo.listBranches();
    final currentBranch = await repo.getCurrentBranch();
    for (final branch in branches) {
      final marker = branch == currentBranch ? '* ' : '  ';
      print('$marker$branch');
    }
    print('');

    print('✓ Demo completed successfully!');
  } catch (e, stackTrace) {
    print('✗ Error: $e');
    print('Stack trace: $stackTrace');
  } finally {
    // Cleanup
    await tempDir.delete(recursive: true);
    print('\n✓ Cleaned up temporary directory');
  }
}
