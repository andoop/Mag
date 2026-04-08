part of '../models.dart';

class GitIdentity {
  GitIdentity({
    required this.name,
    required this.email,
  });

  final String name;
  final String email;

  bool get isComplete => name.trim().isNotEmpty && email.trim().isNotEmpty;

  GitIdentity copyWith({
    String? name,
    String? email,
  }) {
    return GitIdentity(
      name: name ?? this.name,
      email: email ?? this.email,
    );
  }

  JsonMap toJson() => {
        'name': name,
        'email': email,
      };

  factory GitIdentity.fromJson(JsonMap json) => GitIdentity(
        name: (json['name'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
      );
}

class GitSshKey {
  GitSshKey({
    required this.id,
    required this.name,
    required this.algorithm,
    required this.publicKeyOpenSsh,
    required this.comment,
    required this.fingerprint,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String algorithm;
  final String publicKeyOpenSsh;
  final String comment;
  final String fingerprint;
  final int createdAt;

  GitSshKey copyWith({
    String? id,
    String? name,
    String? algorithm,
    String? publicKeyOpenSsh,
    String? comment,
    String? fingerprint,
    int? createdAt,
  }) {
    return GitSshKey(
      id: id ?? this.id,
      name: name ?? this.name,
      algorithm: algorithm ?? this.algorithm,
      publicKeyOpenSsh: publicKeyOpenSsh ?? this.publicKeyOpenSsh,
      comment: comment ?? this.comment,
      fingerprint: fingerprint ?? this.fingerprint,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'name': name,
        'algorithm': algorithm,
        'publicKeyOpenSsh': publicKeyOpenSsh,
        'comment': comment,
        'fingerprint': fingerprint,
        'createdAt': createdAt,
      };

  factory GitSshKey.fromJson(JsonMap json) => GitSshKey(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        algorithm: (json['algorithm'] as String?) ?? 'rsa',
        publicKeyOpenSsh: (json['publicKeyOpenSsh'] as String?) ?? '',
        comment: (json['comment'] as String?) ?? '',
        fingerprint: (json['fingerprint'] as String?) ?? '',
        createdAt: (json['createdAt'] as int?) ?? 0,
      );
}

class GitRemoteCredential {
  GitRemoteCredential({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.pathPrefix,
    required this.username,
    this.sshKeyId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String type;
  final String host;
  final String pathPrefix;
  final String username;
  final String? sshKeyId;
  final int createdAt;

  bool get isSsh => type == 'sshKey';
  bool get isHttps => type == 'httpsToken' || type == 'httpsBasic';

  GitRemoteCredential copyWith({
    String? id,
    String? name,
    String? type,
    String? host,
    String? pathPrefix,
    String? username,
    Object? sshKeyId = _unset,
    int? createdAt,
  }) {
    return GitRemoteCredential(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      host: host ?? this.host,
      pathPrefix: pathPrefix ?? this.pathPrefix,
      username: username ?? this.username,
      sshKeyId:
          identical(sshKeyId, _unset) ? this.sshKeyId : sshKeyId as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'host': host,
        'pathPrefix': pathPrefix,
        'username': username,
        'sshKeyId': sshKeyId,
        'createdAt': createdAt,
      };

  factory GitRemoteCredential.fromJson(JsonMap json) => GitRemoteCredential(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'httpsToken',
        host: (json['host'] as String?) ?? '',
        pathPrefix: (json['pathPrefix'] as String?) ?? '',
        username: (json['username'] as String?) ?? '',
        sshKeyId: json['sshKeyId'] as String?,
        createdAt: (json['createdAt'] as int?) ?? 0,
      );
}

class GitSettings {
  GitSettings({
    required this.identity,
    required this.sshKeys,
    required this.remoteCredentials,
    this.defaultSshKeyId,
  });

  final GitIdentity identity;
  final List<GitSshKey> sshKeys;
  final List<GitRemoteCredential> remoteCredentials;
  final String? defaultSshKeyId;

  factory GitSettings.defaults() => GitSettings(
        identity: GitIdentity(name: '', email: ''),
        sshKeys: const [],
        remoteCredentials: const [],
      );

  GitSshKey? get defaultSshKey {
    final id = defaultSshKeyId;
    if (id == null || id.isEmpty) {
      return sshKeys.isEmpty ? null : sshKeys.first;
    }
    for (final key in sshKeys) {
      if (key.id == id) {
        return key;
      }
    }
    return sshKeys.isEmpty ? null : sshKeys.first;
  }

  GitSettings copyWith({
    GitIdentity? identity,
    List<GitSshKey>? sshKeys,
    List<GitRemoteCredential>? remoteCredentials,
    Object? defaultSshKeyId = _unset,
  }) {
    return GitSettings(
      identity: identity ?? this.identity,
      sshKeys: sshKeys ?? this.sshKeys,
      remoteCredentials: remoteCredentials ?? this.remoteCredentials,
      defaultSshKeyId: identical(defaultSshKeyId, _unset)
          ? this.defaultSshKeyId
          : defaultSshKeyId as String?,
    );
  }

  JsonMap toJson() => {
        'identity': identity.toJson(),
        'sshKeys': sshKeys.map((item) => item.toJson()).toList(),
        'remoteCredentials':
            remoteCredentials.map((item) => item.toJson()).toList(),
        'defaultSshKeyId': defaultSshKeyId,
      };

  factory GitSettings.fromJson(JsonMap json) => GitSettings(
        identity: GitIdentity.fromJson(
          Map<String, dynamic>.from(
            json['identity'] as Map? ?? const <String, dynamic>{},
          ),
        ),
        sshKeys: (json['sshKeys'] as List? ?? const [])
            .map((item) => GitSshKey.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        remoteCredentials: (json['remoteCredentials'] as List? ?? const [])
            .map(
              (item) => GitRemoteCredential.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
        defaultSshKeyId: json['defaultSshKeyId'] as String?,
      );
}
