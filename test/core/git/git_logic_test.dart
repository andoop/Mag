import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/core/git/core/refs.dart';
import 'package:mobile_agent/core/git/core/repository.dart';
import 'package:mobile_agent/core/git/exceptions/git_exceptions.dart';
import 'package:mobile_agent/core/git/git_service.dart';
import 'package:mobile_agent/core/git/models/git_author.dart';
import 'package:mobile_agent/core/git/operations/add_operations.dart';
import 'package:mobile_agent/core/git/operations/commit_operations.dart';
import 'package:mobile_agent/core/git/operations/log_operations.dart';
import 'package:mobile_agent/core/git/operations/status_operations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('git logic', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mag_git_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('packed refs are visible to branch operations', () async {
      final gitDir = Directory('${tempDir.path}/.git');
      await Directory('${gitDir.path}/refs/heads').create(recursive: true);
      await Directory('${gitDir.path}/refs/tags').create(recursive: true);

      const hash = '1234567890123456789012345678901234567890';
      await File('${gitDir.path}/HEAD').writeAsString('ref: refs/heads/main\n');
      await File('${gitDir.path}/packed-refs').writeAsString(
        '# pack-refs with: peeled fully-peeled sorted\n'
        '$hash refs/heads/main\n',
      );

      final refs = RefManager(gitDir.path);

      expect(await refs.getCurrentBranch(), 'main');
      expect(await refs.branchExists('main'), isTrue);
      expect(await refs.readBranch('main'), hash);
      expect(await refs.resolveHead(), hash);
      expect(await refs.listBranches(), contains('main'));
    });

    test('status does not persist blob objects for untracked files', () async {
      final repo = await GitRepository.init(tempDir.path);
      await File('${tempDir.path}/note.txt').writeAsString('hello world');

      final before = await repo.objects.listObjects();
      final status = await StatusOperation(repo).status();
      final after = await repo.objects.listObjects();

      expect(status.untracked.map((entry) => entry.path), contains('note.txt'));
      expect(after, before);
    });

    test('addAll stages deletions by removing missing index entries', () async {
      final repo = await GitRepository.init(tempDir.path);
      final file = File('${tempDir.path}/tracked.txt');
      await file.writeAsString('v1');

      final add = AddOperation(repo);
      final commit = CommitOperation(repo);

      await add.add(['tracked.txt']);
      await commit.commit('initial');
      await file.delete();

      await add.addAll();
      final status = await StatusOperation(repo).status();

      expect(
        status.staged.any(
          (entry) =>
              entry.path == 'tracked.txt' &&
              entry.status == FileStatus.deleted,
        ),
        isTrue,
      );
      expect(
        status.unstaged.any((entry) => entry.path == 'tracked.txt'),
        isFalse,
      );
    });

    test('commit rejects no-op commits when tree matches HEAD', () async {
      final repo = await GitRepository.init(tempDir.path);
      await File('${tempDir.path}/tracked.txt').writeAsString('v1');

      final add = AddOperation(repo);
      final commit = CommitOperation(repo);

      await add.add(['tracked.txt']);
      await commit.commit('initial');

      await expectLater(
        commit.commit('no-op'),
        throwsA(isA<GitException>()),
      );
    });

    test('resolveCommitish accepts unique abbreviated commit hashes', () async {
      final repo = await GitRepository.init(tempDir.path);
      await File('${tempDir.path}/tracked.txt').writeAsString('v1');

      final add = AddOperation(repo);
      final commit = CommitOperation(repo);

      await add.add(['tracked.txt']);
      final created = await commit.commit('initial');
      final shortHash = created.hash.substring(0, 8);

      expect(await repo.resolveCommitish(shortHash), created.hash);
    });

    test('log options filter by date and first parent', () async {
      final repo = await GitRepository.init(tempDir.path);
      final add = AddOperation(repo);
      final commit = CommitOperation(repo);

      final firstAuthor = GitAuthor(
        name: 'Test',
        email: 'test@example.com',
        timestamp: DateTime.parse('2024-01-01T00:00:00Z'),
      );
      await File('${tempDir.path}/tracked.txt').writeAsString('v1');
      await add.add(['tracked.txt']);
      final first = await commit.commit('first', author: firstAuthor);

      final secondAuthor = GitAuthor(
        name: 'Test',
        email: 'test@example.com',
        timestamp: DateTime.parse('2024-02-01T00:00:00Z'),
      );
      await File('${tempDir.path}/tracked.txt').writeAsString('v2');
      await add.add(['tracked.txt']);
      final second = await commit.commit('second', author: secondAuthor);

      final log = LogOperation(repo);
      final commits = await log.getHistory(
        options: const LogOptions(
          firstParentOnly: true,
          since: '2024-01-15T00:00:00Z',
        ),
      );

      expect(commits.map((item) => item.hash), [second.hash]);
      expect(first.hash, isNot(second.hash));
    });

    test('branch delete rejects unmerged branch unless forced', () async {
      final repo = await GitRepository.init(tempDir.path);
      final add = AddOperation(repo);
      final commit = CommitOperation(repo);
      final service = GitService.open(tempDir.path);

      await File('${tempDir.path}/tracked.txt').writeAsString('base');
      await add.add(['tracked.txt']);
      await commit.commit('initial');
      await repo.createBranch('feature');

      await repo.refs.updateHead('feature');
      await File('${tempDir.path}/tracked.txt').writeAsString('feature change');
      await add.add(['tracked.txt']);
      await commit.commit('feature commit');

      await repo.refs.updateHead('main');

      await expectLater(
        () => repo.deleteBranch('feature'),
        throwsA(isA<GitException>()),
      );

      expect(await (await service).listBranches(), contains('feature'));

      await repo.deleteBranch('feature', force: true);
      expect(await (await service).listBranches(), isNot(contains('feature')));
    });

    test('open supports file paths inside repository', () async {
      final repo = await GitRepository.init(tempDir.path);
      final file = File('${tempDir.path}/nested/file.txt');
      await file.parent.create(recursive: true);
      await file.writeAsString('hello');

      final opened = await GitRepository.open(file.path);

      expect(opened.workDir, repo.workDir);
      expect(opened.gitDir, repo.gitDir);
    });

    test('diff separates staged and unstaged content', () async {
      final service = await GitService.init(tempDir.path);
      final file = File('${tempDir.path}/tracked.txt');
      await file.writeAsString('one\n');
      await service.add(['tracked.txt']);
      await service.commit('initial');

      await file.writeAsString('two\n');
      await service.add(['tracked.txt']);
      await file.writeAsString('three\n');

      final diff = await service.diff();

      expect(diff, contains('Staged changes:'));
      expect(diff, contains('Unstaged changes:'));
      expect(diff, contains('+two'));
      expect(diff, contains('+three'));
      expect(diff, isNot(contains('+one')));
    });

    test('checkoutNewBranch works before the first commit', () async {
      final service = await GitService.init(tempDir.path);

      await service.checkoutNewBranch('feature');

      expect(await service.currentBranch(), 'feature');
      expect(await service.repository.getCurrentCommit(), isNull);
      expect(await service.repository.refs.branchExists('feature'), isFalse);
    });

    test('checkout preserves unrelated untracked files', () async {
      final service = await GitService.init(tempDir.path);
      final tracked = File('${tempDir.path}/tracked.txt');
      await tracked.writeAsString('main');
      await service.add(['tracked.txt']);
      await service.commit('initial');
      await service.createBranch('feature');

      await service.checkout('feature');
      await tracked.writeAsString('feature');
      await service.add(['tracked.txt']);
      await service.commit('feature commit');

      await service.checkout('main');
      final scratch = File('${tempDir.path}/scratch.txt');
      await scratch.writeAsString('keep me');

      await service.checkout('feature');

      expect(await scratch.exists(), isTrue);
      expect(await scratch.readAsString(), 'keep me');
      expect(await tracked.readAsString(), 'feature');
    });

    test('checkout blocks conflicting untracked files', () async {
      final service = await GitService.init(tempDir.path);
      final tracked = File('${tempDir.path}/tracked.txt');
      await tracked.writeAsString('main');
      await service.add(['tracked.txt']);
      await service.commit('initial');
      await service.createBranch('feature');

      await service.checkout('feature');
      final branchOnly = File('${tempDir.path}/branch-only.txt');
      await branchOnly.writeAsString('feature file');
      await service.add(['branch-only.txt']);
      await service.commit('feature commit');

      await service.checkout('main');
      await branchOnly.writeAsString('local untracked');

      await expectLater(
        () => service.checkout('feature'),
        throwsA(isA<GitException>()),
      );
    });

    test('merge conflict keeps file tracked and writes branch marker', () async {
      final service = await GitService.init(tempDir.path);
      final tracked = File('${tempDir.path}/tracked.txt');
      await tracked.writeAsString('base\n');
      await service.add(['tracked.txt']);
      await service.commit('initial');
      await service.createBranch('feature');

      await service.checkout('feature');
      await tracked.writeAsString('feature\n');
      await service.add(['tracked.txt']);
      await service.commit('feature commit');

      await service.checkout('main');
      await tracked.writeAsString('main\n');
      await service.add(['tracked.txt']);
      await service.commit('main commit');

      final result = await service.merge('feature');
      final status = await service.status();
      final content = await tracked.readAsString();

      expect(result.hasConflicts, isTrue);
      expect(content, contains('<<<<<<< HEAD'));
      expect(content, contains('>>>>>>> feature'));
      expect(
        status.untracked.any((entry) => entry.path == 'tracked.txt'),
        isFalse,
      );
      expect(
        status.unstaged.any((entry) => entry.path == 'tracked.txt'),
        isTrue,
      );
    });
  });
}
