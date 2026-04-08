library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'git_settings_store.dart';

class GitNetworkBridge {
  const GitNetworkBridge();

  static const MethodChannel _channel = MethodChannel('mobile_agent/git_network');

  bool get isSupported => Platform.isAndroid;

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
