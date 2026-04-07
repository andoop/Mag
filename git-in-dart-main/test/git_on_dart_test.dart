import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:git_on_dart/git_on_dart.dart';

void main() {
  late Directory tempDir;
  late GitRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('git_test');
    repo = await GitRepository.init(tempDir.path);

    // Configure user
    final config = await repo.config;
    config.set('user', 'name', 'Test User');
    config.set('user', 'email', 'test@example.com');
    await config.save();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('Repository', () {
    test('initialize repository', () async {
      expect(await Directory('${tempDir.path}/.git').exists(), isTrue);
      expect(await File('${tempDir.path}/.git/HEAD').exists(), isTrue);
      expect(await File('${tempDir.path}/.git/config').exists(), isTrue);
    });

    test('get current branch', () async {
      // Create initial commit first
      await File('${tempDir.path}/init.txt').writeAsString('Init');
      final addOp = AddOperation(repo);
      await addOp.add(['init.txt']);
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial commit');

      final branch = await repo.getCurrentBranch();
      expect(branch, equals('main'));
    });

    test('create and list branches', () async {
      // Create initial commit first
      await File('${tempDir.path}/init.txt').writeAsString('Init');
      final addOp = AddOperation(repo);
      await addOp.add(['init.txt']);
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial commit');

      await repo.createBranch('feature');
      final branches = await repo.listBranches();
      expect(branches, contains('main'));
      expect(branches, contains('feature'));
    });
  });

  group('Add and Commit', () {
    test('add and commit files', () async {
      // Create a file
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('Hello, World!');

      // Add to staging
      final addOp = AddOperation(repo);
      await addOp.add(['test.txt']);

      // Commit
      final commitOp = CommitOperation(repo);
      final commit = await commitOp.commit('Test commit');

      expect(commit.hash, hasLength(40));
      expect(commit.message, equals('Test commit'));
      expect(commit.parents, isEmpty); // Initial commit
    });

    test('commit with multiple files', () async {
      // Create files
      await File('${tempDir.path}/file1.txt').writeAsString('File 1');
      await File('${tempDir.path}/file2.txt').writeAsString('File 2');
      await Directory('${tempDir.path}/src').create();
      await File('${tempDir.path}/src/main.dart')
          .writeAsString('void main() {}');

      // Add all and commit
      final addOp = AddOperation(repo);
      await addOp.addAll();

      final commitOp = CommitOperation(repo);
      final commit = await commitOp.commit('Add multiple files');

      expect(commit.hash, hasLength(40));

      // Verify tree structure
      final tree = await repo.readTree(commit.tree);
      expect(tree.entries.length, equals(3)); // file1, file2, src
    });
  });

  group('Status', () {
    test('detect untracked files', () async {
      await File('${tempDir.path}/new.txt').writeAsString('New file');

      final statusOp = StatusOperation(repo);
      final status = await statusOp.status();

      expect(status.untracked, hasLength(1));
      expect(status.untracked.first.path, equals('new.txt'));
    });

    test('detect staged files', () async {
      await File('${tempDir.path}/staged.txt').writeAsString('Staged file');

      final addOp = AddOperation(repo);
      await addOp.add(['staged.txt']);

      final statusOp = StatusOperation(repo);
      final status = await statusOp.status();

      expect(status.staged, hasLength(1));
      expect(status.staged.first.path, equals('staged.txt'));
    });
  });

  group('Checkout', () {
    test('checkout branch', () async {
      // Create initial commit
      await File('${tempDir.path}/file.txt').writeAsString('Content');
      final addOp = AddOperation(repo);
      await addOp.addAll();
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial');

      // Create and checkout new branch
      await repo.createBranch('feature');
      final checkoutOp = CheckoutOperation(repo);
      await checkoutOp.checkoutBranch('feature');

      final currentBranch = await repo.getCurrentBranch();
      expect(currentBranch, equals('feature'));
    });
  });

  group('Log', () {
    test('get commit history', () async {
      // Create multiple commits
      final addOp = AddOperation(repo);
      final commitOp = CommitOperation(repo);

      await File('${tempDir.path}/file1.txt').writeAsString('File 1');
      await addOp.addAll();
      await commitOp.commit('Commit 1');

      await File('${tempDir.path}/file2.txt').writeAsString('File 2');
      await addOp.addAll();
      await commitOp.commit('Commit 2');

      await File('${tempDir.path}/file3.txt').writeAsString('File 3');
      await addOp.addAll();
      await commitOp.commit('Commit 3');

      // Get history
      final logOp = LogOperation(repo);
      final commits = await logOp.getHistory();

      expect(commits, hasLength(3));
      expect(commits[0].shortMessage, equals('Commit 3'));
      expect(commits[1].shortMessage, equals('Commit 2'));
      expect(commits[2].shortMessage, equals('Commit 1'));
    });
  });

  group('Merge', () {
    test('fast-forward merge', () async {
      // Create initial commit on main
      await File('${tempDir.path}/main.txt').writeAsString('Main');
      final addOp = AddOperation(repo);
      await addOp.addAll();
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial');

      // Create feature branch and add commit
      await repo.createBranch('feature');
      final checkoutOp = CheckoutOperation(repo);
      await checkoutOp.checkoutBranch('feature');

      await File('${tempDir.path}/feature.txt').writeAsString('Feature');
      await addOp.addAll();
      await commitOp.commit('Add feature');

      // Switch back and merge
      await checkoutOp.checkoutBranch('main');
      final mergeOp = MergeOperation(repo);
      final result = await mergeOp.merge('feature');

      expect(result.success, isTrue);
      expect(result.conflicts, isEmpty);
    });
  });

  group('Object Database', () {
    test('write and read blob', () async {
      const content = 'Hello, World!';
      final contentBytes = Uint8List.fromList(content.codeUnits);
      final hash = await repo.objects.writeBlob(contentBytes);

      expect(hash, hasLength(40));

      final blob = await repo.readBlob(hash);
      expect(blob.contentAsString, equals(content));
    });

    test('SHA-1 hash is deterministic', () async {
      const content = 'Test content';
      final contentBytes = Uint8List.fromList(content.codeUnits);
      final hash1 = await repo.objects.writeBlob(contentBytes);
      final hash2 = await repo.objects.writeBlob(contentBytes);

      expect(hash1, equals(hash2));
    });
  });
}
