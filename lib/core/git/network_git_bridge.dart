library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'git_settings_store.dart';

class GitNetworkBridge {
  const GitNetworkBridge();

  static const MethodChannel _channel = MethodChannel('mobile_agent/git_network');
  static bool? debugOverrideIsSupported;

  bool get isSupported =>
      debugOverrideIsSupported ?? (Platform.isAndroid || Platform.isIOS);

  Future<Map<String, dynamic>> discoverRepository({
    required String path,
  }) {
    return _invoke('discoverRepository', {
      'path': path,
    });
  }

  Future<Map<String, dynamic>> initRepository({
    required String path,
  }) {
    return _invoke('initRepository', {
      'path': path,
    });
  }

  Future<Map<String, dynamic>> clone({
    required String url,
    required String path,
    required String remoteName,
    String? branch,
    ResolvedGitAuth? auth,
  }) {
    return _invoke('cloneRepository', {
      'url': url,
      'path': path,
      'remoteName': remoteName,
      'branch': branch,
      'auth': _authToMap(auth),
    });
  }

  Future<Map<String, dynamic>> commit({
    required String workDir,
    required String message,
    String? authorName,
    String? authorEmail,
  }) {
    return _invoke('commitRepository', {
      'workDir': workDir,
      'message': message,
      'authorName': authorName,
      'authorEmail': authorEmail,
    });
  }

  Future<Map<String, dynamic>> amendCommit({
    required String workDir,
    required String message,
    String? authorName,
    String? authorEmail,
  }) {
    return _invoke('amendCommitRepository', {
      'workDir': workDir,
      'message': message,
      'authorName': authorName,
      'authorEmail': authorEmail,
    });
  }

  Future<Map<String, dynamic>> fetch({
    required String workDir,
    required String remoteName,
    String? branch,
    ResolvedGitAuth? auth,
  }) {
    return _invoke('fetchRepository', {
      'workDir': workDir,
      'remoteName': remoteName,
      'branch': branch,
      'auth': _authToMap(auth),
    });
  }

  Future<Map<String, dynamic>> pull({
    required String workDir,
    required String remoteName,
    String? branch,
    required bool rebase,
    ResolvedGitAuth? auth,
  }) {
    return _invoke('pullRepository', {
      'workDir': workDir,
      'remoteName': remoteName,
      'branch': branch,
      'rebase': rebase,
      'auth': _authToMap(auth),
    });
  }

  Future<Map<String, dynamic>> push({
    required String workDir,
    required String remoteName,
    String? refspec,
    required bool force,
    ResolvedGitAuth? auth,
  }) {
    return _invoke('pushRepository', {
      'workDir': workDir,
      'remoteName': remoteName,
      'refspec': refspec,
      'force': force,
      'auth': _authToMap(auth),
    });
  }

  Future<Map<String, dynamic>> status({
    required String workDir,
  }) {
    return _invoke('statusRepository', {
      'workDir': workDir,
    });
  }

  Future<Map<String, dynamic>> add({
    required String workDir,
    required List<String> paths,
  }) {
    return _invoke('addRepositoryPaths', {
      'workDir': workDir,
      'paths': paths,
    });
  }

  Future<Map<String, dynamic>> addAll({
    required String workDir,
  }) {
    return _invoke('addAllRepositoryPaths', {
      'workDir': workDir,
    });
  }

  Future<Map<String, dynamic>> unstage({
    required String workDir,
    required String path,
  }) {
    return _invoke('unstageRepositoryPath', {
      'workDir': workDir,
      'path': path,
    });
  }

  Future<Map<String, dynamic>> log({
    required String workDir,
    int? maxCount,
    required bool firstParentOnly,
    String? since,
    String? until,
  }) {
    return _invoke('logRepository', {
      'workDir': workDir,
      'maxCount': maxCount,
      'firstParentOnly': firstParentOnly,
      'since': since,
      'until': until,
    });
  }

  Future<Map<String, dynamic>> showCommit({
    required String workDir,
    required String ref,
  }) {
    return _invoke('showRepositoryCommit', {
      'workDir': workDir,
      'ref': ref,
    });
  }

  Future<Map<String, dynamic>> diff({
    required String workDir,
    List<String>? paths,
  }) {
    return _invoke('diffRepository', {
      'workDir': workDir,
      'paths': paths,
    });
  }

  Future<Map<String, dynamic>> currentBranch({
    required String workDir,
  }) {
    return _invoke('currentRepositoryBranch', {
      'workDir': workDir,
    });
  }

  Future<Map<String, dynamic>> listBranches({
    required String workDir,
  }) {
    return _invoke('listRepositoryBranches', {
      'workDir': workDir,
    });
  }

  Future<Map<String, dynamic>> createBranch({
    required String workDir,
    required String name,
    String? startPoint,
  }) {
    return _invoke('createRepositoryBranch', {
      'workDir': workDir,
      'name': name,
      'startPoint': startPoint,
    });
  }

  Future<Map<String, dynamic>> deleteBranch({
    required String workDir,
    required String name,
    required bool force,
  }) {
    return _invoke('deleteRepositoryBranch', {
      'workDir': workDir,
      'name': name,
      'force': force,
    });
  }

  Future<Map<String, dynamic>> checkout({
    required String workDir,
    required String target,
  }) {
    return _invoke('checkoutRepositoryTarget', {
      'workDir': workDir,
      'target': target,
    });
  }

  Future<Map<String, dynamic>> checkoutNewBranch({
    required String workDir,
    required String name,
  }) {
    return _invoke('checkoutRepositoryNewBranch', {
      'workDir': workDir,
      'name': name,
    });
  }

  Future<Map<String, dynamic>> restoreFile({
    required String workDir,
    required String path,
  }) {
    return _invoke('restoreRepositoryFile', {
      'workDir': workDir,
      'path': path,
    });
  }

  Future<Map<String, dynamic>> merge({
    required String workDir,
    required String branch,
  }) {
    return _invoke('mergeRepositoryBranch', {
      'workDir': workDir,
      'branch': branch,
    });
  }

  Future<Map<String, dynamic>> rebase({
    required String workDir,
    required String targetRef,
  }) {
    return _invoke('rebaseRepositoryTarget', {
      'workDir': workDir,
      'targetRef': targetRef,
    });
  }

  Future<Map<String, dynamic>> getConfigValue({
    required String workDir,
    required String section,
    required String key,
  }) {
    return _invoke('getRepositoryConfigValue', {
      'workDir': workDir,
      'section': section,
      'key': key,
    });
  }

  Future<Map<String, dynamic>> setConfigValue({
    required String workDir,
    required String section,
    required String key,
    required String value,
  }) {
    return _invoke('setRepositoryConfigValue', {
      'workDir': workDir,
      'section': section,
      'key': key,
      'value': value,
    });
  }

  Future<Map<String, dynamic>> getRemoteUrl({
    required String workDir,
    required String remoteName,
  }) {
    return _invoke('getRepositoryRemoteUrl', {
      'workDir': workDir,
      'remoteName': remoteName,
    });
  }

  Future<Map<String, dynamic>> _invoke(
    String method,
    Map<String, dynamic> arguments,
  ) async {
    final raw = await _channel.invokeMethod<dynamic>(method, arguments);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic>? _authToMap(ResolvedGitAuth? auth) {
    if (auth == null) {
      return null;
    }
    return {
      'type': auth.type,
      'username': auth.username,
      'secret': auth.secret,
      'privateKeyPem': auth.privateKeyPem,
      'sourceCredentialId': auth.sourceCredentialId,
    };
  }
}
