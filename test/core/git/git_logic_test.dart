import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/git/git_service.dart';
import 'package:mobile_agent/core/git/network_git_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mobile_agent/git_network');
    late Directory tempDir;
  late _FakeNativeGitBackend backend;

    setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mag_git_native_');
    backend = _FakeNativeGitBackend();
    GitNetworkBridge.debugOverrideIsSupported = true;
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, backend.handle);
    });

    tearDown(() async {
    GitNetworkBridge.debugOverrideIsSupported = null;
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

  group('git service native bridge', () {
    test('clone -> status is clean and current branch is preserved', () async {
      final sourcePath = '${tempDir.path}/source';
      final clonePath = '${tempDir.path}/clone';
      final source = await GitService.init(sourcePath);
      await source.add(['README.md']);
      await source.commit('initial');

      final cloned = await GitService.clone(url: sourcePath, path: clonePath);
      final cloneService = await GitService.open(clonePath);
      final status = await cloneService.status();

      expect(cloned.success, isTrue);
      expect(cloned.defaultBranch, 'main');
      expect(status.isClean, isTrue);
      expect(status.currentBranch, 'main');
    });

    test('add -> status -> commit -> status -> show/log works', () async {
      final repoPath = '${tempDir.path}/repo';
      final service = await GitService.init(repoPath);

      backend.repo(repoPath).untracked.add('note.txt');
      await service.add(['note.txt']);
      final staged = await service.status();
      final commit = await service.commit(
        'initial commit',
        authorName: 'Tester',
        authorEmail: 'tester@example.com',
      );
      final clean = await service.status();
      final shown = await service.showCommit(commit.hash);
      final history = await service.log(maxCount: 5);

      expect(staged.staged.single.path, 'note.txt');
      expect(staged.staged.single.status, FileStatus.added);
      expect(clean.isClean, isTrue);
      expect(shown.shortMessage, 'initial commit');
      expect(shown.author.name, 'Tester');
      expect(history.first.hash, commit.hash);
    });

    test('branch create/list/checkout/delete flows stay stable', () async {
      final repoPath = '${tempDir.path}/repo';
      final service = await GitService.init(repoPath);
      backend.repo(repoPath).untracked.add('tracked.txt');
      await service.add(['tracked.txt']);
      await service.commit('base');

      await service.createBranch('feature');
      expect(await service.listBranches(), containsAll(['main', 'feature']));

      await service.checkout('feature');
      expect(await service.currentBranch(), 'feature');

      await service.checkout('main');
      await service.deleteBranch('feature', force: true);
      expect(await service.listBranches(), isNot(contains('feature')));
    });

    test('fetch, pull, and push route through native bridge', () async {
      final sourcePath = '${tempDir.path}/source';
      final clonePath = '${tempDir.path}/clone';
      final source = await GitService.init(sourcePath);
      await source.setConfigValue('remote.origin', 'url', sourcePath);
      backend.repo(sourcePath).untracked.add('base.txt');
      await source.add(['base.txt']);
      final initial = await source.commit('initial');

      await GitService.clone(url: sourcePath, path: clonePath);
      final cloned = await GitService.open(clonePath);

      backend.repo(sourcePath).untracked.add('remote.txt');
      await source.add(['remote.txt']);
      final remoteHead = await source.commit('remote update');

      final fetched = await cloned.fetch('origin');
      final pulled = await cloned.pull('origin');

      expect(pulled.success, isTrue);
      expect(backend.repo(clonePath).head, remoteHead.hash);

      backend.repo(clonePath).untracked.add('local.txt');
      await cloned.add(['local.txt']);
      final localHead = await cloned.commit('local update');
      final pushed = await cloned.push(
        'origin',
        refspec: 'refs/heads/main:refs/heads/sync',
      );

      expect(initial.hash, isNot(remoteHead.hash));
      expect(fetched.success, isTrue);
      expect(fetched.updatedRefs, contains('refs/remotes/origin/main'));
      expect(pushed.success, isTrue);
      expect(backend.repo(sourcePath).branches['sync'], localHead.hash);
    });

    test('merge conflict and rebase success are surfaced', () async {
      final repoPath = '${tempDir.path}/repo';
      final service = await GitService.init(repoPath);
      backend.repo(repoPath).untracked.add('tracked.txt');
      await service.add(['tracked.txt']);
      await service.commit('base');
      await service.createBranch('feature');

      backend.repo(repoPath).nextMergeConflicts = ['tracked.txt'];
      final merge = await service.merge('feature');

      backend.repo(repoPath).untracked.add('local.txt');
      await service.add(['local.txt']);
      final local = await service.commit('local change');
      backend.repo(repoPath).branches['main'] = backend.nextHash();
      backend.repo(repoPath).commits[backend.repo(repoPath).branches['main']!] =
          _FakeCommit(
        hash: backend.repo(repoPath).branches['main']!,
        parents: [local.hash],
        message: 'main ahead',
      );
      final rebase = await service.rebase('main');

      expect(merge.hasConflicts, isTrue);
      expect(merge.conflicts, ['tracked.txt']);
      expect(rebase.success, isTrue);
      expect(rebase.newHead, isNotNull);
    });

    test('diff, config, and remote URL use the native bridge', () async {
      final repoPath = '${tempDir.path}/repo';
      final service = await GitService.init(repoPath);
      final repo = backend.repo(repoPath);
      repo.untracked.add('draft.txt');
      repo.unstagedModified.add('tracked.txt');
      repo.remotes['origin'] = '${tempDir.path}/remote';

      final diff = await service.diff();
      await service.setConfigValue('user', 'name', 'Magent');
      final name = await service.getConfigValue('user', 'name');
      final remoteUrl = await service.getRemoteUrl('origin');

      expect(diff, contains('Untracked files'));
      expect(diff, contains('draft.txt'));
      expect(name, 'Magent');
      expect(remoteUrl, '${tempDir.path}/remote');
    });
  });
}

class _FakeNativeGitBackend {
  final Map<String, _FakeRepo> _repos = {};
  int _hashSeed = 1;

  _FakeRepo repo(String path) => _repos[path]!;

  String nextHash() => (_hashSeed++).toRadixString(16).padLeft(40, '0');

  Future<dynamic> handle(MethodCall call) async {
    final args = Map<String, dynamic>.from(call.arguments as Map? ?? const {});
    switch (call.method) {
      case 'discoverRepository':
        return _discover(args['path'] as String? ?? '');
      case 'initRepository':
        return _init(args['path'] as String? ?? '');
      case 'cloneRepository':
        return _clone(args);
      case 'statusRepository':
        return _status(args['workDir'] as String? ?? '');
      case 'addRepositoryPaths':
        return _add(args);
      case 'addAllRepositoryPaths':
        return _addAll(args['workDir'] as String? ?? '');
      case 'unstageRepositoryPath':
        return _unstage(
          args['workDir'] as String? ?? '',
          args['path'] as String? ?? '',
        );
      case 'commitRepository':
        return _commit(args, amend: false);
      case 'amendCommitRepository':
        return _commit(args, amend: true);
      case 'logRepository':
        return _log(args);
      case 'showRepositoryCommit':
        return _show(args);
      case 'diffRepository':
        return _diff(args['workDir'] as String? ?? '');
      case 'currentRepositoryBranch':
        return _branchInfo(args['workDir'] as String? ?? '');
      case 'listRepositoryBranches':
        return _listBranches(args['workDir'] as String? ?? '');
      case 'createRepositoryBranch':
        return _createBranch(args);
      case 'deleteRepositoryBranch':
        return _deleteBranch(args);
      case 'checkoutRepositoryTarget':
        return _checkout(args);
      case 'checkoutRepositoryNewBranch':
        return _checkoutNewBranch(args);
      case 'restoreRepositoryFile':
        return _restore(args);
      case 'mergeRepositoryBranch':
        return _merge(args);
      case 'fetchRepository':
        return _fetch(args);
      case 'pullRepository':
        return _pull(args);
      case 'pushRepository':
        return _push(args);
      case 'rebaseRepositoryTarget':
        return _rebase(args);
      case 'getRepositoryConfigValue':
        return _getConfig(args);
      case 'setRepositoryConfigValue':
        return _setConfig(args);
      case 'getRepositoryRemoteUrl':
        return _getRemoteUrl(args);
      default:
        throw MissingPluginException('Unhandled ${call.method}');
    }
  }

  Map<String, dynamic> _discover(String path) {
    for (final repo in _repos.values) {
      if (path == repo.workDir || path.startsWith('${repo.workDir}/')) {
        return {'success': true, 'workDir': repo.workDir};
      }
    }
    return {'success': false, 'error': 'Not a git repository'};
  }

  Map<String, dynamic> _init(String path) {
    _repos[path] = _FakeRepo(workDir: path);
    return {'success': true, 'workDir': path};
  }

  Map<String, dynamic> _clone(Map<String, dynamic> args) {
    final sourcePath = args['url'] as String? ?? '';
    final targetPath = args['path'] as String? ?? '';
    final source = _repos[sourcePath];
    if (source == null) {
      return {'success': false, 'error': 'Source not found'};
    }
    final clone = source.copyTo(targetPath);
    clone.remotes['origin'] = sourcePath;
    if (source.head != null) {
      clone.remoteBranches['refs/remotes/origin/main'] = source.head!;
    }
    _repos[targetPath] = clone;
    return {
      'success': true,
      'defaultBranch': clone.currentBranch,
      'objectsReceived': 0,
    };
  }

  Map<String, dynamic> _status(String workDir) {
    final repo = _requireRepo(workDir);
    return {
      'success': true,
      'branch': repo.currentBranch,
      'head': repo.head,
      'clean': repo.isClean,
      'staged': repo.stagedEntries,
      'unstaged': repo.unstagedEntries,
      'untracked': repo.untrackedEntries,
    };
  }

  Map<String, dynamic> _add(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final paths = (args['paths'] as List? ?? const [])
        .map((item) => item.toString())
        .toList();
    for (final path in paths) {
      if (repo.untracked.remove(path)) {
        repo.stagedAdded.add(path);
      } else if (repo.unstagedModified.remove(path)) {
        repo.stagedModified.add(path);
      } else if (repo.unstagedDeleted.remove(path)) {
        repo.stagedDeleted.add(path);
      } else {
        repo.stagedAdded.add(path);
      }
    }
    return {'success': true};
  }

  Map<String, dynamic> _addAll(String workDir) {
    final repo = _requireRepo(workDir);
    repo.stagedAdded.addAll(repo.untracked);
    repo.untracked.clear();
    repo.stagedModified.addAll(repo.unstagedModified);
    repo.unstagedModified.clear();
    repo.stagedDeleted.addAll(repo.unstagedDeleted);
    repo.unstagedDeleted.clear();
    return {'success': true};
  }

  Map<String, dynamic> _unstage(String workDir, String path) {
    final repo = _requireRepo(workDir);
    repo.stagedAdded.remove(path);
    repo.stagedModified.remove(path);
    repo.stagedDeleted.remove(path);
    return {'success': true};
  }

  Map<String, dynamic> _commit(Map<String, dynamic> args, {required bool amend}) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    if (repo.stagedAdded.isEmpty &&
        repo.stagedModified.isEmpty &&
        repo.stagedDeleted.isEmpty &&
        !amend) {
      return {'success': false, 'error': 'No changes staged for commit'};
    }
    final parent = amend
        ? repo.commits[repo.head!]?.parents ?? const <String>[]
        : (repo.head == null ? const <String>[] : <String>[repo.head!]);
    final hash = nextHash();
    final authorName = args['authorName'] as String? ?? 'Unknown';
    final authorEmail = args['authorEmail'] as String? ?? 'unknown@example.com';
    repo.commits[hash] = _FakeCommit(
      hash: hash,
      parents: parent,
      message: args['message'] as String? ?? '',
      authorName: authorName,
      authorEmail: authorEmail,
    );
    repo.head = hash;
    repo.branches[repo.currentBranch] = hash;
    repo.stagedAdded.clear();
    repo.stagedModified.clear();
    repo.stagedDeleted.clear();
    repo.unstagedModified.clear();
    repo.unstagedDeleted.clear();
    repo.untracked.clear();
    return repo.commits[hash]!.toMap(success: true);
  }

  Map<String, dynamic> _log(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final maxCount = (args['maxCount'] as int?) ?? 20;
    final commits = <Map<String, dynamic>>[];
    var current = repo.head;
    while (current != null && commits.length < maxCount) {
      final commit = repo.commits[current];
      if (commit == null) {
        break;
      }
      commits.add(commit.toMap());
      current = commit.parents.isEmpty ? null : commit.parents.first;
    }
    return {'success': true, 'commits': commits};
  }

  Map<String, dynamic> _show(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final ref = args['ref'] as String? ?? 'HEAD';
    final hash = ref == 'HEAD' ? repo.head : ref;
    final commit = hash == null ? null : repo.commits[hash];
    if (commit == null) {
      return {'success': false, 'error': 'Commit not found'};
    }
    return {'success': true, 'commit': commit.toMap()};
  }

  Map<String, dynamic> _diff(String workDir) {
    final repo = _requireRepo(workDir);
    final sections = <String>[];
    if (repo.stagedEntries.isNotEmpty) {
      sections.add(
        'Staged changes:\n${repo.stagedEntries.map((e) => "--- ${e['status']}: ${e['path']}").join('\n')}',
      );
    }
    if (repo.unstagedEntries.isNotEmpty) {
      sections.add(
        'Unstaged changes:\n${repo.unstagedEntries.map((e) => "--- ${e['status']}: ${e['path']}").join('\n')}',
      );
    }
    if (repo.untrackedEntries.isNotEmpty) {
      sections.add(
        'Untracked files:\n${repo.untrackedEntries.map((e) => "+++ ${e['path']}").join('\n')}',
      );
    }
    return {
      'success': true,
      'diff': sections.isEmpty ? 'No changes.' : sections.join('\n\n'),
    };
  }

  Map<String, dynamic> _branchInfo(String workDir) {
    final repo = _requireRepo(workDir);
    return {
      'success': true,
      'branch': repo.currentBranch,
      'head': repo.head,
    };
  }

  Map<String, dynamic> _listBranches(String workDir) {
    final repo = _requireRepo(workDir);
    return {
      'success': true,
      'branches': repo.branches.keys.toList()..sort(),
      'current': repo.currentBranch,
    };
  }

  Map<String, dynamic> _createBranch(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final name = args['name'] as String? ?? '';
    repo.branches[name] = repo.branches[repo.currentBranch];
    return {'success': true};
  }

  Map<String, dynamic> _deleteBranch(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final name = args['name'] as String? ?? '';
    repo.branches.remove(name);
    return {'success': true};
  }

  Map<String, dynamic> _checkout(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final target = args['target'] as String? ?? '';
    if (repo.branches.containsKey(target)) {
      repo.currentBranch = target;
      repo.head = repo.branches[target];
      return {'success': true};
    }
    if (repo.commits.containsKey(target)) {
      repo.head = target;
      return {'success': true};
    }
    return {'success': false, 'error': 'Unknown ref: $target'};
  }

  Map<String, dynamic> _checkoutNewBranch(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final name = args['name'] as String? ?? '';
    repo.branches[name] = repo.head;
    repo.currentBranch = name;
    return {'success': true};
  }

  Map<String, dynamic> _restore(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final path = args['path'] as String? ?? '';
    repo.stagedAdded.remove(path);
    repo.stagedModified.remove(path);
    repo.stagedDeleted.remove(path);
    repo.unstagedModified.remove(path);
    repo.unstagedDeleted.remove(path);
    return {'success': true};
  }

  Map<String, dynamic> _merge(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final conflicts = repo.nextMergeConflicts;
    repo.nextMergeConflicts = const [];
    if (conflicts.isNotEmpty) {
      return {
        'success': false,
        'conflicts': conflicts,
        'mergeCommit': null,
        'error': 'Merge failed',
      };
    }
    final target = args['branch'] as String? ?? '';
    final targetHead = repo.branches[target] ?? repo.remoteBranches[target];
    if (targetHead != null) {
      repo.head = targetHead;
      repo.branches[repo.currentBranch] = targetHead;
    }
    return {
      'success': true,
      'conflicts': const [],
      'mergeCommit': repo.head,
    };
  }

  Map<String, dynamic> _fetch(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final remoteName = (args['remoteName'] as String? ?? 'origin').trim();
    final remotePath = repo.remotes[remoteName];
    final remoteRepo =
        remotePath == null ? null : _repos[remotePath];
    if (remoteRepo == null) {
      return {'success': false, 'error': 'Remote not found: $remoteName'};
    }
    final branch = (args['branch'] as String?)?.trim();
    final branches = branch == null || branch.isEmpty
        ? remoteRepo.branches.keys
        : [branch];
    final updatedRefs = <String>[];
    for (final name in branches) {
      final head = remoteRepo.branches[name];
      if (head == null) {
        continue;
      }
      final ref = 'refs/remotes/$remoteName/$name';
      repo.remoteBranches[ref] = head;
      updatedRefs.add(ref);
    }
    return {
      'success': true,
      'updatedRefs': updatedRefs,
      'objectsReceived': 0,
    };
  }

  Map<String, dynamic> _pull(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final remoteName = (args['remoteName'] as String? ?? 'origin').trim();
    final fetchResult = _fetch(args);
    if (fetchResult['success'] == false) {
      return {
        'success': false,
        'fetchSuccess': false,
        'updatedRefs': const [],
        'objectsReceived': 0,
        'error': fetchResult['error'],
      };
    }
    final branch = (args['branch'] as String?)?.trim();
    final branchName = branch == null || branch.isEmpty ? repo.currentBranch : branch;
    final remoteRef = 'refs/remotes/$remoteName/$branchName';
    final remoteHead = repo.remoteBranches[remoteRef];
    if (remoteHead == null) {
      return {'success': false, 'error': 'Remote branch not found'};
    }
    final useRebase = args['rebase'] == true;
    if (!useRebase || repo.head == null || repo.head == remoteHead) {
      repo.head = remoteHead;
      repo.branches[repo.currentBranch] = remoteHead;
      return {
        'success': true,
        'fetchSuccess': true,
        'updatedRefs': fetchResult['updatedRefs'],
        'objectsReceived': 0,
        'mergeCommit': remoteHead,
      };
    }
    final current = repo.commits[repo.head!];
    final rebasedHash = nextHash();
    repo.commits[rebasedHash] = _FakeCommit(
      hash: rebasedHash,
      parents: [remoteHead],
      message: current?.message ?? 'rebased commit',
      authorName: current?.authorName ?? 'Unknown',
      authorEmail: current?.authorEmail ?? 'unknown@example.com',
    );
    repo.head = rebasedHash;
    repo.branches[repo.currentBranch] = rebasedHash;
    return {
      'success': true,
      'fetchSuccess': true,
      'updatedRefs': fetchResult['updatedRefs'],
      'objectsReceived': 0,
      'newHead': rebasedHash,
      'conflicts': const [],
    };
  }

  Map<String, dynamic> _push(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final remoteName = (args['remoteName'] as String? ?? 'origin').trim();
    final remotePath = repo.remotes[remoteName];
    final remoteRepo =
        remotePath == null ? null : _repos[remotePath];
    if (remoteRepo == null) {
      return {'success': false, 'error': 'Remote not found: $remoteName'};
    }
    final refspec =
        args['refspec'] as String? ?? 'refs/heads/${repo.currentBranch}:refs/heads/${repo.currentBranch}';
    final parts = refspec.split(':');
    final target = parts.last.split('/').last;
    final sourceHead = repo.head;
    if (sourceHead == null) {
      return {'success': false, 'error': 'Nothing to push'};
    }
    remoteRepo.branches[target] = sourceHead;
    remoteRepo.commits[sourceHead] = repo.commits[sourceHead]!;
    return {
      'success': true,
      'pushedRefs': [refspec],
    };
  }

  Map<String, dynamic> _rebase(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final conflicts = repo.nextRebaseConflicts;
    repo.nextRebaseConflicts = const [];
    if (conflicts.isNotEmpty) {
      return {
        'success': false,
        'conflicts': conflicts,
        'newHead': repo.head,
        'error': 'Rebase failed',
      };
    }
    final target = args['targetRef'] as String? ?? '';
    final targetHead = repo.branches[target] ?? repo.remoteBranches[target];
    if (targetHead == null || repo.head == null) {
      return {'success': true, 'conflicts': const [], 'newHead': repo.head};
    }
    final current = repo.commits[repo.head!];
    final rebasedHash = nextHash();
    repo.commits[rebasedHash] = _FakeCommit(
      hash: rebasedHash,
      parents: [targetHead],
      message: current?.message ?? 'rebased commit',
      authorName: current?.authorName ?? 'Unknown',
      authorEmail: current?.authorEmail ?? 'unknown@example.com',
    );
    repo.head = rebasedHash;
    repo.branches[repo.currentBranch] = rebasedHash;
    return {
      'success': true,
      'conflicts': const [],
      'newHead': rebasedHash,
    };
  }

  Map<String, dynamic> _getConfig(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final section = args['section'] as String? ?? '';
    final key = args['key'] as String? ?? '';
    return {
      'success': true,
      'value': repo.config['$section.$key'],
    };
  }

  Map<String, dynamic> _setConfig(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final section = args['section'] as String? ?? '';
    final key = args['key'] as String? ?? '';
    repo.config['$section.$key'] = args['value'] as String? ?? '';
    return {'success': true};
  }

  Map<String, dynamic> _getRemoteUrl(Map<String, dynamic> args) {
    final repo = _requireRepo(args['workDir'] as String? ?? '');
    final remoteName = (args['remoteName'] as String? ?? 'origin').trim();
    return {
      'success': true,
      'url': repo.remotes[remoteName],
    };
  }

  _FakeRepo _requireRepo(String workDir) {
    final repo = _repos[workDir];
    if (repo == null) {
      throw PlatformException(code: 'git_network_error', message: 'Unknown repo');
    }
    return repo;
  }
}

class _FakeRepo {
  _FakeRepo({required this.workDir});

  final String workDir;
  String currentBranch = 'main';
  String? head;
  final Map<String, String?> branches = {'main': null};
  final Map<String, _FakeCommit> commits = {};
  final Map<String, String> remotes = {};
  final Map<String, String> remoteBranches = {};
  final Map<String, String> config = {};
  final Set<String> untracked = <String>{};
  final Set<String> unstagedModified = <String>{};
  final Set<String> unstagedDeleted = <String>{};
  final Set<String> stagedAdded = <String>{};
  final Set<String> stagedModified = <String>{};
  final Set<String> stagedDeleted = <String>{};
  List<String> nextMergeConflicts = const [];
  List<String> nextRebaseConflicts = const [];

  bool get isClean =>
      untracked.isEmpty &&
      unstagedModified.isEmpty &&
      unstagedDeleted.isEmpty &&
      stagedAdded.isEmpty &&
      stagedModified.isEmpty &&
      stagedDeleted.isEmpty;

  List<Map<String, String>> get stagedEntries => [
        ...(stagedAdded.toList()..sort())
            .map((path) => {'path': path, 'status': 'added'}),
        ...(stagedModified.toList()..sort())
            .map((path) => {'path': path, 'status': 'modified'}),
        ...(stagedDeleted.toList()..sort())
            .map((path) => {'path': path, 'status': 'deleted'}),
      ];

  List<Map<String, String>> get unstagedEntries => [
        ...(unstagedModified.toList()..sort())
            .map((path) => {'path': path, 'status': 'modified'}),
        ...(unstagedDeleted.toList()..sort())
            .map((path) => {'path': path, 'status': 'deleted'}),
      ];

  List<Map<String, String>> get untrackedEntries =>
      (untracked.toList()..sort())
          .map((path) => {'path': path, 'status': 'untracked'})
          .toList();

  _FakeRepo copyTo(String targetPath) {
    final next = _FakeRepo(workDir: targetPath)
      ..currentBranch = currentBranch
      ..head = head
      ..branches.addAll(branches)
      ..commits.addAll(commits.map((key, value) => MapEntry(key, value.copy())))
      ..config.addAll(config)
      ..remotes.addAll(remotes)
      ..remoteBranches.addAll(remoteBranches);
    return next;
  }
}

class _FakeCommit {
  _FakeCommit({
    required this.hash,
    required this.parents,
    required this.message,
    this.authorName = 'Unknown',
    this.authorEmail = 'unknown@example.com',
  });

  final String hash;
  final List<String> parents;
  final String message;
  final String authorName;
  final String authorEmail;

  _FakeCommit copy() => _FakeCommit(
        hash: hash,
        parents: List<String>.from(parents),
        message: message,
        authorName: authorName,
        authorEmail: authorEmail,
      );

  Map<String, dynamic> toMap({bool? success}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      if (success != null) 'success': success,
      'hash': hash,
      'tree': hash.padRight(40, '0').substring(0, 40),
      'parents': parents,
      'message': message,
      'authorName': authorName,
      'authorEmail': authorEmail,
      'authorTimestampMs': now,
      'authorTimezone': '+0000',
      'committerName': authorName,
      'committerEmail': authorEmail,
      'committerTimestampMs': now,
      'committerTimezone': '+0000',
    };
  }
}
