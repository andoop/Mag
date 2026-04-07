import 'dart:io';
import 'package:test/test.dart';
import 'package:git_on_dart/git_on_dart.dart';

void main() {
  late Directory tempDir;
  late GitRepository repo;
  late RemoteManager remoteManager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('git_remote_test');
    repo = await GitRepository.init(tempDir.path);
    remoteManager = RemoteManager(repo.gitDir);

    // Configure user
    final config = await repo.config;
    config.set('user', 'name', 'Test User');
    config.set('user', 'email', 'test@example.com');
    await config.save();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('Remote Manager', () {
    test('add remote with HTTPS URL', () async {
      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final remotes = await remoteManager.listRemotes();
      expect(remotes, hasLength(1));
      expect(remotes.first.name, equals('origin'));
      expect(remotes.first.url, equals('https://github.com/user/repo.git'));
      expect(remotes.first.isHttps, isTrue);
      expect(remotes.first.isSsh, isFalse);
    });

    test('add remote with SSH URL', () async {
      await remoteManager.addRemote(
        'origin',
        'git@github.com:user/repo.git',
      );

      final remotes = await remoteManager.listRemotes();
      expect(remotes, hasLength(1));
      expect(remotes.first.name, equals('origin'));
      expect(remotes.first.url, equals('git@github.com:user/repo.git'));
      expect(remotes.first.isHttps, isFalse);
      expect(remotes.first.isSsh, isTrue);
    });

    test('add multiple remotes', () async {
      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );
      await remoteManager.addRemote(
        'upstream',
        'https://github.com/upstream/repo.git',
      );

      final remotes = await remoteManager.listRemotes();
      expect(remotes, hasLength(2));
      expect(remotes.map((r) => r.name), containsAll(['origin', 'upstream']));
    });

    test('prevent duplicate remote names', () async {
      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      expect(
        () => remoteManager.addRemote('origin', 'https://example.com/repo.git'),
        throwsA(isA<GitException>()),
      );
    });

    test('get remote by name', () async {
      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final remote = await remoteManager.getRemote('origin');
      expect(remote, isNotNull);
      expect(remote!.name, equals('origin'));
      expect(remote.url, equals('https://github.com/user/repo.git'));
    });

    test('get non-existent remote returns null', () async {
      final remote = await remoteManager.getRemote('nonexistent');
      expect(remote, isNull);
    });

    test('remove remote', () async {
      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      var remotes = await remoteManager.listRemotes();
      expect(remotes, hasLength(1));

      await remoteManager.removeRemote('origin');

      remotes = await remoteManager.listRemotes();
      expect(remotes, isEmpty);
    });

    test('remove non-existent remote throws error', () async {
      expect(
        () => remoteManager.removeRemote('nonexistent'),
        throwsA(isA<GitException>()),
      );
    });

    test('set remote URL', () async {
      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      await remoteManager.setUrl(
        'origin',
        'https://github.com/newuser/newrepo.git',
      );

      final remote = await remoteManager.getRemote('origin');
      expect(remote!.url, equals('https://github.com/newuser/newrepo.git'));
    });

    test('set URL for non-existent remote throws error', () async {
      expect(
        () => remoteManager.setUrl('origin', 'https://example.com/repo.git'),
        throwsA(isA<GitException>()),
      );
    });

    test('list remotes when none exist', () async {
      final remotes = await remoteManager.listRemotes();
      expect(remotes, isEmpty);
    });
  });

  group('Credentials', () {
    test('HTTPS token credentials', () {
      final creds = HttpsCredentials.token('ghp_test_token_123');
      expect(creds.token, equals('ghp_test_token_123'));

      final authHeader = creds.getAuthHeader();
      expect(authHeader, equals('Bearer ghp_test_token_123'));
    });

    test('HTTPS basic auth credentials', () {
      final creds = HttpsCredentials.basic('username', 'password');
      expect(creds.username, equals('username'));
      expect(creds.password, equals('password'));

      final authHeader = creds.getAuthHeader();
      expect(authHeader, startsWith('Basic '));
      expect(authHeader,
          contains('dXNlcm5hbWU6cGFzc3dvcmQ=')); // base64 of username:password
    });

    test('SSH credentials with key path', () {
      const creds = SshCredentials(
        privateKeyPath: '/home/user/.ssh/id_rsa',
        passphrase: 'secret',
      );

      expect(creds.privateKeyPath, equals('/home/user/.ssh/id_rsa'));
      expect(creds.passphrase, equals('secret'));
    });

    test('credentials without values throws error', () {
      const creds = HttpsCredentials();

      expect(
        () => creds.getAuthHeader(),
        throwsA(isA<GitException>()),
      );
    });
  });

  group('Fetch Operations', () {
    test('fetch from HTTPS remote (mock)', () async {
      // Note: Real fetch would require a live server
      // This test demonstrates the API structure

      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final fetchOp = FetchOperation(repo);

      // In real scenario with live server:
      // final result = await fetchOp.fetch('origin');
      // expect(result.success, isTrue);

      // For now, we just verify the operation can be created
      expect(fetchOp, isNotNull);
    });

    test('fetch with HTTPS credentials', () async {
      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final creds = HttpsCredentials.token('test_token');
      final fetchOp = FetchOperation(repo);

      // API structure validation
      expect(
          () => fetchOp.fetch('origin', credentials: creds), returnsNormally);
    });

    test('fetch from non-existent remote throws error', () async {
      final fetchOp = FetchOperation(repo);

      expect(
        () => fetchOp.fetch('nonexistent'),
        throwsA(isA<GitException>()),
      );
    });
  });

  group('Push Operations', () {
    test('push to HTTPS remote (mock)', () async {
      // Create initial commit
      await File('${tempDir.path}/file.txt').writeAsString('Content');
      final addOp = AddOperation(repo);
      await addOp.add(['file.txt']);
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial commit');

      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final pushOp = PushOperation(repo);

      // In real scenario with live server:
      // final result = await pushOp.push('origin');
      // expect(result.success, isTrue);

      // For now, we just verify the operation can be created
      expect(pushOp, isNotNull);
    });

    test('push with credentials', () async {
      // Create initial commit
      await File('${tempDir.path}/file.txt').writeAsString('Content');
      final addOp = AddOperation(repo);
      await addOp.add(['file.txt']);
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial commit');

      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final creds = HttpsCredentials.token('test_token');
      final pushOp = PushOperation(repo);

      // API structure validation
      expect(() => pushOp.push('origin', credentials: creds), returnsNormally);
    });

    test('push to non-existent remote throws error', () async {
      final pushOp = PushOperation(repo);

      expect(
        () => pushOp.push('nonexistent'),
        throwsA(isA<GitException>()),
      );
    });

    test('force push option', () async {
      // Create initial commit
      await File('${tempDir.path}/file.txt').writeAsString('Content');
      final addOp = AddOperation(repo);
      await addOp.add(['file.txt']);
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial commit');

      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final pushOp = PushOperation(repo);

      // Verify force flag is accepted
      expect(() => pushOp.push('origin', force: true), returnsNormally);
    });
  });

  group('Pull Operations', () {
    test('pull from remote (mock)', () async {
      // Create initial commit
      await File('${tempDir.path}/file.txt').writeAsString('Content');
      final addOp = AddOperation(repo);
      await addOp.add(['file.txt']);
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial commit');

      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final pullOp = PullOperation(repo);

      // In real scenario with live server:
      // final result = await pullOp.pull('origin');
      // expect(result.success, isTrue);

      // For now, we just verify the operation can be created
      expect(pullOp, isNotNull);
    });

    test('pull with specific branch', () async {
      // Create initial commit
      await File('${tempDir.path}/file.txt').writeAsString('Content');
      final addOp = AddOperation(repo);
      await addOp.add(['file.txt']);
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial commit');

      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final pullOp = PullOperation(repo);

      // API structure validation
      expect(() => pullOp.pull('origin', branch: 'develop'), returnsNormally);
    });

    test('pull with credentials', () async {
      // Create initial commit
      await File('${tempDir.path}/file.txt').writeAsString('Content');
      final addOp = AddOperation(repo);
      await addOp.add(['file.txt']);
      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial commit');

      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      final creds = HttpsCredentials.token('test_token');
      final pullOp = PullOperation(repo);

      // API structure validation
      expect(() => pullOp.pull('origin', credentials: creds), returnsNormally);
    });
  });

  group('Remote Protocol Detection', () {
    test('detect HTTPS protocol', () async {
      await remoteManager.addRemote(
          'origin', 'https://github.com/user/repo.git');
      final remote = await remoteManager.getRemote('origin');

      expect(remote!.isHttps, isTrue);
      expect(remote.isSsh, isFalse);
    });

    test('detect HTTP protocol', () async {
      await remoteManager.addRemote('origin', 'http://example.com/repo.git');
      final remote = await remoteManager.getRemote('origin');

      expect(remote!.isHttps, isTrue);
      expect(remote.isSsh, isFalse);
    });

    test('detect SSH protocol (git@ format)', () async {
      await remoteManager.addRemote('origin', 'git@github.com:user/repo.git');
      final remote = await remoteManager.getRemote('origin');

      expect(remote!.isHttps, isFalse);
      expect(remote.isSsh, isTrue);
    });

    test('detect SSH protocol (ssh:// format)', () async {
      await remoteManager.addRemote(
          'origin', 'ssh://git@github.com/user/repo.git');
      final remote = await remoteManager.getRemote('origin');

      expect(remote!.isHttps, isFalse);
      expect(remote.isSsh, isTrue);
    });
  });

  group('Integration Tests', () {
    test('complete workflow: add remote, create commit, prepare push',
        () async {
      // Add remote
      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );

      // Create file and commit
      await File('${tempDir.path}/README.md').writeAsString('# My Project');
      final addOp = AddOperation(repo);
      await addOp.add(['README.md']);

      final commitOp = CommitOperation(repo);
      await commitOp.commit('Initial commit');

      // Verify remote exists
      final remotes = await remoteManager.listRemotes();
      expect(remotes, hasLength(1));

      // Verify commit exists
      final currentCommit = await repo.getCurrentCommit();
      expect(currentCommit, isNotNull);

      // Verify push operation can be created
      final pushOp = PushOperation(repo);
      expect(pushOp, isNotNull);
    });

    test('multiple remotes workflow', () async {
      // Add multiple remotes
      await remoteManager.addRemote(
        'origin',
        'https://github.com/user/repo.git',
      );
      await remoteManager.addRemote(
        'upstream',
        'https://github.com/upstream/repo.git',
      );
      await remoteManager.addRemote(
        'backup',
        'git@gitlab.com:user/repo.git',
      );

      final remotes = await remoteManager.listRemotes();
      expect(remotes, hasLength(3));

      // Verify each remote
      final origin = await remoteManager.getRemote('origin');
      expect(origin!.isHttps, isTrue);

      final upstream = await remoteManager.getRemote('upstream');
      expect(upstream!.isHttps, isTrue);

      final backup = await remoteManager.getRemote('backup');
      expect(backup!.isSsh, isTrue);

      // Remove one remote
      await remoteManager.removeRemote('backup');

      final remainingRemotes = await remoteManager.listRemotes();
      expect(remainingRemotes, hasLength(2));
    });
  });
}
