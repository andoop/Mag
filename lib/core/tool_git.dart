part of 'tool_runtime.dart';

/// AI-facing git tool.  Dispatches on `command` to the appropriate
/// [GitService] method and returns structured output.
Future<ToolExecutionResult> _gitTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final command = (args['command'] as String? ?? '').trim().toLowerCase();
  if (command.isEmpty) {
    return ToolExecutionResult(
      title: 'git',
      output: 'Missing required parameter: command.  '
          'Supported: status, add, restore, reset, commit, log, diff, branch, checkout, '
          'merge, cherry-pick, init, show, clone, fetch, pull, push, rebase, config, remote-url, remote.',
    );
  }

  final workDir = await ctx.bridge.resolveFilesystemPath(
    treeUri: ctx.workspace.treeUri,
  );
  if (workDir == null || workDir.isEmpty) {
    final pathHint = _bestEffortTreeUriPath(ctx.workspace.treeUri);
    final protectedAndroidPath =
        pathHint != null && _isProtectedAndroidPath(pathHint);
    return ToolExecutionResult(
      title: 'git',
      output: protectedAndroidPath
          ? 'This workspace is inside Android protected storage '
              '(`$pathHint`). Pure-Dart git needs direct filesystem access and '
              'cannot operate there. Move the project outside `Android/`, '
              'for example into `Download/` or another normal folder.'
          : 'Cannot resolve workspace to a filesystem path.  '
              'Git operations require direct file access.',
    );
  }

  final progressTitle = command == 'clone' ? 'git clone' : 'git $command';
  final progressMetadata = <String, dynamic>{
    'command': command,
    'phase': 'executing',
  };
  final progressPath = (args['path'] as String?)?.trim();
  final progressTarget = (args['target'] as String?)?.trim();
  if (progressPath != null && progressPath.isNotEmpty) {
    progressMetadata['path'] = progressPath;
  }
  if (progressTarget != null && progressTarget.isNotEmpty) {
    progressMetadata['target'] = progressTarget;
  }
  await ctx.updateToolProgress(
    title: progressTitle,
    displayOutput: 'Running $progressTitle',
    metadata: progressMetadata,
  );

  late final GitService git;
  if (command != 'init' && command != 'clone') {
    try {
      git = await GitService.open(workDir);
    } catch (e) {
      return ToolExecutionResult(
        title: 'git $command',
        output: 'Not a git repository (or any parent): $workDir',
      );
    }
  }

  try {
    switch (command) {
      // ------------------------------------------------------------------
      case 'init':
        final svc = await GitService.init(workDir);
        final identity = await _loadSavedGitIdentity(ctx.database);
        if (identity != null) {
          await svc.setConfigValue('user', 'name', identity.name);
          await svc.setConfigValue('user', 'email', identity.email);
        }
        return ToolExecutionResult(
          title: 'git init',
          output: 'Initialized empty git repository at ${svc.workDir}',
          metadata: {'workDir': svc.workDir},
        );

      case 'clone':
        final url = (args['url'] as String? ?? '').trim();
        if (url.isEmpty) {
          return ToolExecutionResult(
            title: 'git clone',
            output: 'Missing required parameter: url.',
          );
        }
        final relativePath = (args['path'] as String? ?? '').trim();
        final targetPath = relativePath.isEmpty
            ? workDir
            : p.normalize(p.join(workDir, relativePath));
        if (!p.isWithin(workDir, targetPath) && targetPath != workDir) {
          return ToolExecutionResult(
            title: 'git clone',
            output: 'Clone path must stay inside the current workspace.',
          );
        }
        final remoteName = (args['remote'] as String? ?? 'origin').trim();
        final branch = (args['branch'] as String?)?.trim();
        final auth = await _loadSavedGitAuth(ctx.database, url);
        if (_looksLikeSshRemoteUrl(url) && auth == null) {
          return ToolExecutionResult(
            title: 'git clone',
            output: 'No SSH credential matched this remote URL. '
                'Add an SSH binding in Settings, or set a default SSH key first.',
          );
        }
        final result = await GitService.clone(
          url: url,
          path: targetPath,
          remoteName: remoteName.isEmpty ? 'origin' : remoteName,
          branch: branch != null && branch.isNotEmpty ? branch : null,
          auth: auth,
        );
        if (!result.success) {
          return ToolExecutionResult(
            title: 'git clone',
            output: result.error ?? 'Clone failed.',
          );
        }
        return ToolExecutionResult(
          title: 'git clone',
          output: 'Cloned into $targetPath'
              '${result.defaultBranch != null ? ' on ${result.defaultBranch}' : ''}.',
          metadata: {
            'path': targetPath,
            'defaultBranch': result.defaultBranch,
            'objectsReceived': result.objectsReceived,
          },
        );

      // ------------------------------------------------------------------
      case 'status':
        final st = await git.status();
        return ToolExecutionResult(
          title: 'git status',
          output: st.toString(),
          displayOutput: st.isClean
              ? 'Working tree clean'
              : '${st.staged.length} staged, '
                  '${st.unstaged.length} unstaged, '
                  '${st.untracked.length} untracked',
          metadata: {
            'branch': st.currentBranch,
            'clean': st.isClean,
            'staged': st.staged.length,
            'unstaged': st.unstaged.length,
            'untracked': st.untracked.length,
          },
        );

      // ------------------------------------------------------------------
      case 'add':
        final rawPaths = args['paths'];
        final all = args['all'] == true;
        if (all) {
          await git.addAll();
          return ToolExecutionResult(
            title: 'git add .',
            output: 'Staged all changes.',
          );
        }
        if (rawPaths is List && rawPaths.isNotEmpty) {
          final paths = rawPaths.map((e) => e.toString()).toList();
          await git.add(paths);
          return ToolExecutionResult(
            title: 'git add',
            output: 'Staged ${paths.length} path(s): ${paths.join(', ')}',
            metadata: {'paths': paths},
          );
        }
        return ToolExecutionResult(
          title: 'git add',
          output:
              'Provide `paths` (array) or set `all` to true to stage all files.',
        );

      // ------------------------------------------------------------------
      case 'restore':
        final rawPaths = args['paths'];
        if (rawPaths is List && rawPaths.isNotEmpty) {
          final paths = rawPaths
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (paths.isEmpty) {
            return ToolExecutionResult(
              title: 'git restore',
              output: 'Provide `paths` (array) with tracked files to restore.',
            );
          }
          for (final path in paths) {
            await git.restoreFile(path);
          }
          return ToolExecutionResult(
            title: 'git restore',
            output:
                'Restored ${paths.length} path(s) from HEAD: ${paths.join(', ')}',
            metadata: {'paths': paths},
          );
        }
        return ToolExecutionResult(
          title: 'git restore',
          output: 'Provide `paths` (array) with tracked files to restore.',
        );

      // ------------------------------------------------------------------
      case 'reset':
        final rawPaths = args['paths'];
        final mode = (args['mode'] as String? ?? 'mixed').trim().toLowerCase();
        if (!const {'soft', 'mixed', 'hard'}.contains(mode)) {
          return ToolExecutionResult(
            title: 'git reset',
            output: 'Unknown reset mode: $mode. Use soft, mixed, or hard.',
          );
        }
        if (rawPaths is List && rawPaths.isNotEmpty) {
          final paths = rawPaths
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          if (paths.isEmpty) {
            return ToolExecutionResult(
              title: 'git reset',
              output: 'Provide non-empty `paths` or a `target` to reset to.',
            );
          }
          await git.reset(paths: paths, mode: mode);
          return ToolExecutionResult(
            title: 'git reset',
            output:
                'Reset ${paths.length} path(s) from the index: ${paths.join(', ')}',
            metadata: {'paths': paths, 'mode': mode},
          );
        }
        final target = (args['target'] as String? ?? 'HEAD').trim();
        await git.reset(target: target, mode: mode);
        return ToolExecutionResult(
          title: 'git reset',
          output: 'Reset $mode to $target.',
          metadata: {'target': target, 'mode': mode},
        );

      // ------------------------------------------------------------------
      case 'commit':
        final message = (args['message'] as String? ?? '').trim();
        if (message.isEmpty) {
          return ToolExecutionResult(
            title: 'git commit',
            output: 'Missing required parameter: message.',
          );
        }
        final amend = args['amend'] == true;
        var authorName = args['authorName'] as String?;
        var authorEmail = args['authorEmail'] as String?;
        if ((authorName == null || authorName.trim().isEmpty) &&
            (authorEmail == null || authorEmail.trim().isEmpty)) {
          final identity = await _loadSavedGitIdentity(ctx.database);
          if (identity != null) {
            authorName = identity.name;
            authorEmail = identity.email;
          }
        }
        final result = amend
            ? await git.amendCommit(message,
                authorName: authorName, authorEmail: authorEmail)
            : await git.commit(message,
                authorName: authorName, authorEmail: authorEmail);
        final verb = amend ? 'Amended' : 'Created';
        return ToolExecutionResult(
          title: 'git commit',
          output:
              '$verb commit ${result.hash.substring(0, 8)}: ${result.shortMessage}',
          displayOutput: '$verb ${result.hash.substring(0, 8)}',
          metadata: {
            'hash': result.hash,
            'message': result.message,
          },
        );

      // ------------------------------------------------------------------
      case 'log':
        final maxCount =
            (args['maxCount'] as int?) ?? (args['max_count'] as int?) ?? 10;
        final firstParentOnly = args['firstParentOnly'] == true;
        final since = (args['since'] as String?)?.trim();
        final until = (args['until'] as String?)?.trim();
        final commits = await git.log(
          maxCount: maxCount,
          firstParentOnly: firstParentOnly,
          since: since != null && since.isNotEmpty ? since : null,
          until: until != null && until.isNotEmpty ? until : null,
        );
        final lines = commits.map((c) {
          final short = c.hash.substring(0, 8);
          final date = c.author.timestamp.toIso8601String().substring(0, 10);
          return '$short $date ${c.shortMessage}';
        }).join('\n');
        return ToolExecutionResult(
          title: 'git log',
          output: lines.isEmpty ? 'No commits yet.' : lines,
          displayOutput: '${commits.length} commit(s)',
          metadata: {'count': commits.length},
        );

      // ------------------------------------------------------------------
      case 'diff':
        final rawPaths = args['paths'];
        final paths = rawPaths is List
            ? rawPaths.map((e) => e.toString()).toList()
            : null;
        final diffText = await git.diff(paths: paths);
        return ToolExecutionResult(
          title: 'git diff',
          output: diffText,
        );

      // ------------------------------------------------------------------
      case 'branch':
        final action =
            (args['action'] as String? ?? 'list').trim().toLowerCase();
        final name = (args['name'] as String? ?? '').trim();

        if (action == 'list' || action == '') {
          final branches = await git.listBranches();
          final current = await git.currentBranch();
          final lines = branches.map((b) {
            return b == current ? '* $b' : '  $b';
          }).join('\n');
          return ToolExecutionResult(
            title: 'git branch',
            output: lines.isEmpty ? 'No branches yet.' : lines,
            metadata: {'current': current, 'branches': branches},
          );
        }
        if (name.isEmpty) {
          return ToolExecutionResult(
            title: 'git branch',
            output: 'Missing required parameter: name.',
          );
        }
        if (action == 'create') {
          final startPoint = (args['startPoint'] as String?)?.trim();
          await git.createBranch(
            name,
            startPoint:
                startPoint != null && startPoint.isNotEmpty ? startPoint : null,
          );
          return ToolExecutionResult(
            title: 'git branch',
            output: startPoint != null && startPoint.isNotEmpty
                ? 'Created branch $name at $startPoint.'
                : 'Created branch $name.',
          );
        }
        if (action == 'delete') {
          final force = args['force'] == true;
          await git.deleteBranch(name, force: force);
          return ToolExecutionResult(
            title: 'git branch',
            output:
                force ? 'Force deleted branch $name.' : 'Deleted branch $name.',
          );
        }
        return ToolExecutionResult(
          title: 'git branch',
          output: 'Unknown action: $action. Use list, create, or delete.',
        );

      // ------------------------------------------------------------------
      case 'checkout':
        final target = (args['target'] as String? ?? '').trim();
        final newBranch = args['newBranch'] == true;
        if (target.isEmpty) {
          return ToolExecutionResult(
            title: 'git checkout',
            output: 'Missing required parameter: target (branch or commit).',
          );
        }
        if (newBranch) {
          await git.checkoutNewBranch(target);
          return ToolExecutionResult(
            title: 'git checkout -b',
            output: 'Created and switched to new branch $target.',
          );
        }
        await git.checkout(target);
        return ToolExecutionResult(
          title: 'git checkout',
          output: 'Switched to $target.',
        );

      // ------------------------------------------------------------------
      case 'merge':
        final action =
            (args['action'] as String? ?? 'start').trim().toLowerCase();
        if (!const {'start', 'continue', 'abort'}.contains(action)) {
          return ToolExecutionResult(
            title: 'git merge',
            output: 'Unknown action: $action. Use start, continue, or abort.',
          );
        }
        final branch = (args['branch'] as String? ?? '').trim();
        if (action == 'start' && branch.isEmpty) {
          return ToolExecutionResult(
            title: 'git merge',
            output: 'Missing required parameter: branch.',
          );
        }
        final message = (args['message'] as String?)?.trim();
        final mr = await git.merge(
          action == 'start' ? branch : null,
          action: action,
          message: message != null && message.isNotEmpty ? message : null,
        );
        if (mr.hasConflicts) {
          return ToolExecutionResult(
            title: 'git merge',
            output:
                'Merge conflicts in ${mr.conflicts.length} file(s):\n${mr.conflicts.join('\n')}',
            metadata: {
              'action': action,
              'conflicts': mr.conflicts,
              'success': false,
            },
          );
        }
        return ToolExecutionResult(
          title: 'git merge',
          output: action == 'abort'
              ? 'Aborted merge successfully.'
              : action == 'continue'
                  ? 'Continued merge successfully.'
                  : 'Merged $branch successfully.'
                      '${mr.mergeCommit != null ? ' (${mr.mergeCommit!.substring(0, 8)})' : ''}',
          metadata: {
            'action': action,
            if (message != null && message.isNotEmpty) 'message': message,
            'success': true,
            'mergeCommit': mr.mergeCommit,
          },
        );

      case 'fetch':
        final remote = (args['remote'] as String? ?? 'origin').trim();
        final branch = (args['branch'] as String?)?.trim();
        final remoteUrl =
            await git.getRemoteUrl(remote.isEmpty ? 'origin' : remote);
        final auth = remoteUrl == null
            ? null
            : await _loadSavedGitAuth(ctx.database, remoteUrl);
        if (remoteUrl != null &&
            _looksLikeSshRemoteUrl(remoteUrl) &&
            auth == null) {
          return ToolExecutionResult(
            title: 'git fetch',
            output: 'No SSH credential matched this remote URL. '
                'Add an SSH binding in Settings, or set a default SSH key first.',
          );
        }
        final fetched = await git.fetch(
          remote.isEmpty ? 'origin' : remote,
          branch: branch != null && branch.isNotEmpty ? branch : null,
          auth: auth,
        );
        if (!fetched.success) {
          return ToolExecutionResult(
            title: 'git fetch',
            output: fetched.error ?? 'Fetch failed.',
          );
        }
        return ToolExecutionResult(
          title: 'git fetch',
          output: fetched.updatedRefs.isEmpty
              ? 'Fetched successfully, no refs updated.'
              : 'Fetched ${fetched.updatedRefs.length} ref(s).',
          metadata: {
            'updatedRefs': fetched.updatedRefs,
            'objectsReceived': fetched.objectsReceived,
          },
        );

      case 'pull':
        final remote = (args['remote'] as String? ?? 'origin').trim();
        final branch = (args['branch'] as String?)?.trim();
        final useRebase = args['rebase'] == true;
        final remoteUrl =
            await git.getRemoteUrl(remote.isEmpty ? 'origin' : remote);
        final auth = remoteUrl == null
            ? null
            : await _loadSavedGitAuth(ctx.database, remoteUrl);
        if (remoteUrl != null &&
            _looksLikeSshRemoteUrl(remoteUrl) &&
            auth == null) {
          return ToolExecutionResult(
            title: 'git pull',
            output: 'No SSH credential matched this remote URL. '
                'Add an SSH binding in Settings, or set a default SSH key first.',
          );
        }
        final pulled = await git.pull(
          remote.isEmpty ? 'origin' : remote,
          branch: branch != null && branch.isNotEmpty ? branch : null,
          rebase: useRebase,
          auth: auth,
        );
        if (!pulled.success) {
          return ToolExecutionResult(
            title: 'git pull',
            output: pulled.error ?? 'Pull failed.',
            metadata: {
              'updatedRefs': pulled.fetchResult.updatedRefs,
              'objectsReceived': pulled.fetchResult.objectsReceived,
            },
          );
        }
        return ToolExecutionResult(
          title: 'git pull',
          output: useRebase
              ? 'Pulled and rebased successfully.'
              : 'Pulled and merged successfully.',
          metadata: {
            'updatedRefs': pulled.fetchResult.updatedRefs,
            'objectsReceived': pulled.fetchResult.objectsReceived,
            'mergeCommit': pulled.mergeResult?.mergeCommit,
            'newHead': pulled.rebaseResult?.newHead,
          },
        );

      case 'push':
        final remote = (args['remote'] as String? ?? 'origin').trim();
        final refspec = (args['refspec'] as String?)?.trim();
        final force = args['force'] == true;
        final remoteUrl =
            await git.getRemoteUrl(remote.isEmpty ? 'origin' : remote);
        final auth = remoteUrl == null
            ? null
            : await _loadSavedGitAuth(ctx.database, remoteUrl);
        if (remoteUrl != null &&
            _looksLikeSshRemoteUrl(remoteUrl) &&
            auth == null) {
          return ToolExecutionResult(
            title: 'git push',
            output: 'No SSH credential matched this remote URL. '
                'Add an SSH binding in Settings, or set a default SSH key first.',
          );
        }
        final pushed = await git.push(
          remote.isEmpty ? 'origin' : remote,
          refspec: refspec != null && refspec.isNotEmpty ? refspec : null,
          force: force,
          auth: auth,
        );
        if (!pushed.success) {
          return ToolExecutionResult(
            title: 'git push',
            output: pushed.error ?? 'Push failed.',
          );
        }
        return ToolExecutionResult(
          title: 'git push',
          output: pushed.pushedRefs.isEmpty
              ? 'Pushed successfully.'
              : 'Pushed ${pushed.pushedRefs.join(', ')}.',
          metadata: {'pushedRefs': pushed.pushedRefs},
        );

      case 'cherry-pick':
        final action =
            (args['action'] as String? ?? 'start').trim().toLowerCase();
        if (!const {'start', 'continue', 'abort'}.contains(action)) {
          return ToolExecutionResult(
            title: 'git cherry-pick',
            output: 'Unknown action: $action. Use start, continue, or abort.',
          );
        }
        final ref = (args['ref'] as String? ?? '').trim();
        if (action == 'start' && ref.isEmpty) {
          return ToolExecutionResult(
            title: 'git cherry-pick',
            output: 'Missing required parameter: ref.',
          );
        }
        final message = (args['message'] as String?)?.trim();
        final picked = await git.cherryPick(
          action == 'start' ? ref : null,
          action: action,
          message: message != null && message.isNotEmpty ? message : null,
        );
        if (!picked.success) {
          return ToolExecutionResult(
            title: 'git cherry-pick',
            output:
                'Cherry-pick stopped with conflicts in ${picked.conflicts.length} file(s):\n${picked.conflicts.join('\n')}',
            metadata: {
              'action': action,
              'conflicts': picked.conflicts,
              'newHead': picked.newHead,
            },
          );
        }
        return ToolExecutionResult(
          title: 'git cherry-pick',
          output: action == 'abort'
              ? 'Aborted cherry-pick successfully.'
              : action == 'continue'
                  ? 'Continued cherry-pick successfully.'
                  : 'Cherry-picked $ref successfully.',
          metadata: {
            'action': action,
            'ref': ref,
            'newHead': picked.newHead,
          },
        );

      case 'rebase':
        final action =
            (args['action'] as String? ?? 'start').trim().toLowerCase();
        if (!const {'start', 'continue', 'skip', 'abort'}.contains(action)) {
          return ToolExecutionResult(
            title: 'git rebase',
            output:
                'Unknown action: $action. Use start, continue, skip, or abort.',
          );
        }
        final ref = (args['ref'] as String? ?? '').trim();
        if (action == 'start' && ref.isEmpty) {
          return ToolExecutionResult(
            title: 'git rebase',
            output: 'Missing required parameter: ref.',
          );
        }
        final rebased =
            await git.rebase(action == 'start' ? ref : null, action: action);
        if (!rebased.success) {
          return ToolExecutionResult(
            title: 'git rebase',
            output:
                'Rebase stopped with conflicts in ${rebased.conflicts.length} file(s):\n${rebased.conflicts.join('\n')}',
            metadata: {
              'action': action,
              'conflicts': rebased.conflicts,
              'newHead': rebased.newHead,
            },
          );
        }
        return ToolExecutionResult(
          title: 'git rebase',
          output: action == 'abort'
              ? 'Aborted rebase successfully.'
              : action == 'continue'
                  ? 'Continued rebase successfully.'
                  : action == 'skip'
                      ? 'Skipped the current rebase commit successfully.'
                      : 'Rebased successfully onto $ref.',
          metadata: {
            'action': action,
            'ref': ref,
            'newHead': rebased.newHead,
          },
        );

      // ------------------------------------------------------------------
      case 'config':
        final action =
            (args['action'] as String? ?? 'get').trim().toLowerCase();
        final section = (args['section'] as String? ?? '').trim();
        final key = (args['key'] as String? ?? '').trim();
        if (section.isEmpty || key.isEmpty) {
          return ToolExecutionResult(
            title: 'git config',
            output: 'Missing required parameters: section and key.',
          );
        }
        if (action == 'get' || action.isEmpty) {
          final value = await git.getConfigValue(section, key);
          return ToolExecutionResult(
            title: 'git config',
            output: value == null
                ? 'Config is not set: $section.$key'
                : '$section.$key=$value',
            metadata: {
              'action': 'get',
              'section': section,
              'key': key,
              'value': value,
              'found': value != null,
            },
          );
        }
        if (action == 'set') {
          final value = (args['value'] as String? ?? '').trim();
          if (value.isEmpty) {
            return ToolExecutionResult(
              title: 'git config',
              output: 'Missing required parameter: value.',
            );
          }
          await git.setConfigValue(section, key, value);
          return ToolExecutionResult(
            title: 'git config',
            output: 'Updated $section.$key.',
            metadata: {
              'action': 'set',
              'section': section,
              'key': key,
              'value': value,
            },
          );
        }
        return ToolExecutionResult(
          title: 'git config',
          output: 'Unknown action: $action. Use get or set.',
        );

      // ------------------------------------------------------------------
      case 'remote-url':
        final remote = (args['remote'] as String? ?? 'origin').trim();
        final effectiveRemote = remote.isEmpty ? 'origin' : remote;
        final url = await git.getRemoteUrl(effectiveRemote);
        return ToolExecutionResult(
          title: 'git remote-url',
          output: url == null
              ? 'Remote $effectiveRemote has no configured URL.'
              : '$effectiveRemote $url',
          metadata: {'remote': effectiveRemote, 'url': url},
        );

      // ------------------------------------------------------------------
      case 'remote':
        final action =
            (args['action'] as String? ?? 'list').trim().toLowerCase();
        final remote = (args['remote'] as String? ?? 'origin').trim();
        final effectiveRemote = remote.isEmpty ? 'origin' : remote;
        if (action.isEmpty || action == 'list') {
          final remotes = await git.listRemotes();
          final names = remotes.keys.toList()..sort();
          final output = names.isEmpty
              ? 'No remotes configured.'
              : names
                  .map((name) =>
                      remotes[name] == null ? name : '$name ${remotes[name]}')
                  .join('\n');
          return ToolExecutionResult(
            title: 'git remote',
            output: output,
            metadata: {
              'action': 'list',
              'count': names.length,
              'remotes': names
                  .map((name) => {'name': name, 'url': remotes[name]})
                  .toList(),
            },
          );
        }
        if (action == 'get-url') {
          final url = await git.getRemoteUrl(effectiveRemote);
          return ToolExecutionResult(
            title: 'git remote',
            output: url == null
                ? 'Remote $effectiveRemote has no configured URL.'
                : '$effectiveRemote $url',
            metadata: {
              'action': 'get-url',
              'remote': effectiveRemote,
              'url': url,
            },
          );
        }
        if (action == 'add') {
          final url = (args['url'] as String? ?? '').trim();
          if (url.isEmpty) {
            return ToolExecutionResult(
              title: 'git remote',
              output: 'Missing required parameter: url.',
            );
          }
          await git.addRemote(effectiveRemote, url);
          return ToolExecutionResult(
            title: 'git remote',
            output: 'Added remote $effectiveRemote.',
            metadata: {'action': 'add', 'remote': effectiveRemote, 'url': url},
          );
        }
        if (action == 'set-url') {
          final url = (args['url'] as String? ?? '').trim();
          if (url.isEmpty) {
            return ToolExecutionResult(
              title: 'git remote',
              output: 'Missing required parameter: url.',
            );
          }
          await git.setRemoteUrl(effectiveRemote, url);
          return ToolExecutionResult(
            title: 'git remote',
            output: 'Updated remote $effectiveRemote URL.',
            metadata: {
              'action': 'set-url',
              'remote': effectiveRemote,
              'url': url
            },
          );
        }
        if (action == 'remove') {
          await git.removeRemote(effectiveRemote);
          return ToolExecutionResult(
            title: 'git remote',
            output: 'Removed remote $effectiveRemote.',
            metadata: {'action': 'remove', 'remote': effectiveRemote},
          );
        }
        if (action == 'rename') {
          final oldName = (args['oldName'] as String? ?? '').trim();
          final newName = (args['newName'] as String? ?? '').trim();
          if (oldName.isEmpty || newName.isEmpty) {
            return ToolExecutionResult(
              title: 'git remote',
              output: 'Missing required parameters: oldName and newName.',
            );
          }
          await git.renameRemote(oldName, newName);
          return ToolExecutionResult(
            title: 'git remote',
            output: 'Renamed remote $oldName to $newName.',
            metadata: {
              'action': 'rename',
              'oldName': oldName,
              'newName': newName
            },
          );
        }
        return ToolExecutionResult(
          title: 'git remote',
          output:
              'Unknown action: $action. Use list, get-url, add, set-url, remove, or rename.',
        );

      // ------------------------------------------------------------------
      case 'show':
        final ref = (args['ref'] as String? ?? 'HEAD').trim();
        final c = await git.showCommit(ref);
        final buf = StringBuffer()
          ..writeln('commit ${c.hash}')
          ..writeln('Author: ${c.author.name} <${c.author.email}>')
          ..writeln('Date:   ${c.author.timestamp}')
          ..writeln()
          ..writeln('    ${c.message}');
        return ToolExecutionResult(
          title: 'git show',
          output: buf.toString(),
          metadata: {'hash': c.hash},
        );

      // ------------------------------------------------------------------
      default:
        return ToolExecutionResult(
          title: 'git',
          output: 'Unknown git command: $command.  '
              'Supported: status, add, restore, reset, commit, log, diff, branch, '
              'checkout, merge, cherry-pick, init, show, clone, fetch, pull, push, rebase, config, remote-url, remote.',
        );
    }
  } on GitException catch (e) {
    return ToolExecutionResult(
      title: 'git $command',
      output: e.message,
    );
  } on ArgumentError catch (e) {
    return ToolExecutionResult(
      title: 'git $command',
      output: e.message?.toString() ?? e.toString(),
    );
  } catch (e) {
    if (e is FileSystemException && _isProtectedAndroidPath(workDir)) {
      return ToolExecutionResult(
        title: 'git $command',
        output: 'Direct file access is blocked for `$workDir`. '
            'This usually happens when the workspace is under Android protected '
            'storage. Move the project outside `Android/` and try again.',
      );
    }
    return ToolExecutionResult(
      title: 'git $command',
      output: e.toString(),
    );
  }
}

String? _bestEffortTreeUriPath(String treeUri) {
  if (treeUri.startsWith('/')) {
    return treeUri;
  }
  final uri = Uri.tryParse(treeUri);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  if (uri == null || uri.authority != 'com.android.externalstorage.documents') {
    return null;
  }
  final segments = uri.pathSegments;
  final treeIndex = segments.indexOf('tree');
  if (treeIndex == -1 || treeIndex + 1 >= segments.length) {
    return null;
  }
  final rawId = Uri.decodeComponent(segments[treeIndex + 1]);
  if (rawId.startsWith('raw:')) {
    return rawId.substring(4);
  }
  final separator = rawId.indexOf(':');
  if (separator <= 0) {
    return null;
  }
  final volume = rawId.substring(0, separator);
  final relative = rawId.substring(separator + 1);
  final base = volume.toLowerCase() == 'primary'
      ? '/storage/emulated/0'
      : '/storage/$volume';
  if (relative.isEmpty) {
    return base;
  }
  return '$base/$relative';
}

bool _isProtectedAndroidPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final androidRoot = RegExp(r'^/storage/[^/]+/Android(?:/.*)?$');
  return normalized == '/storage/emulated/0/Android' ||
      normalized.startsWith('/storage/emulated/0/Android/') ||
      androidRoot.hasMatch(normalized);
}

Future<GitIdentity?> _loadSavedGitIdentity(AppDatabase database) async {
  final settings = await GitSettingsStore(database: database).load();
  return settings.identity.isComplete ? settings.identity : null;
}

Future<ResolvedGitAuth?> _loadSavedGitAuth(
  AppDatabase database,
  String remoteUrl,
) {
  return GitSettingsStore(database: database)
      .resolveAuthForRemoteUrl(remoteUrl);
}

bool _looksLikeSshRemoteUrl(String url) {
  final trimmed = url.trim();
  return trimmed.startsWith('ssh://') ||
      RegExp(r'^[^@/\s]+@[^:/\s]+:.+$').hasMatch(trimmed);
}
