library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../database.dart';
import '../models.dart';
import 'exceptions/git_exceptions.dart';

abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class ResolvedGitAuth {
  const ResolvedGitAuth({
    required this.type,
    required this.username,
    this.secret,
    this.privateKeyPem,
    this.sourceCredentialId,
  });

  final String type;
  final String username;
  final String? secret;
  final String? privateKeyPem;
  final String? sourceCredentialId;

  bool get isSsh => type == 'ssh';
  bool get isHttps => type == 'https-basic';
}

class FlutterSecretStore implements SecretStore {
  FlutterSecretStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(
        key: key,
        value: value,
      );

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class GitSettingsStore {
  GitSettingsStore({
    AppDatabase? database,
    SecretStore? secretStore,
    Future<JsonMap?> Function(String key)? readSetting,
    Future<void> Function(String key, JsonMap value)? writeSetting,
  })  : _database = database,
        _secretStore = secretStore ?? FlutterSecretStore(),
        _readSetting = readSetting,
        _writeSetting = writeSetting;

  static const String _settingsKey = 'git_settings';
  static const String _secretPrefix = 'git_ssh_private_';
  static const String _remoteSecretPrefix = 'git_remote_secret_';

  final AppDatabase? _database;
  final SecretStore _secretStore;
  final Future<JsonMap?> Function(String key)? _readSetting;
  final Future<void> Function(String key, JsonMap value)? _writeSetting;

  Future<GitSettings> load() async {
    final raw = await _getSetting(_settingsKey);
    if (raw == null) {
      return GitSettings.defaults();
    }
    return GitSettings.fromJson(raw);
  }

  Future<void> save(GitSettings settings) async {
    await _putSetting(_settingsKey, settings.toJson());
  }

  Future<GitSettings> updateIdentity({
    required String name,
    required String email,
  }) async {
    final current = await load();
    final next = current.copyWith(
      identity: current.identity.copyWith(
        name: name.trim(),
        email: email.trim(),
      ),
    );
    await save(next);
    return next;
  }

  Future<GitSettings> generateSshKey({
    required String name,
    String? comment,
    int keySize = 2048,
  }) async {
    final current = await load();
    final pair = CryptoUtils.generateRSAKeyPair(keySize: keySize);
    final publicKey = pair.publicKey as RSAPublicKey;
    final privateKey = pair.privateKey as RSAPrivateKey;
    final id = newId('sshkey');
    final note = (comment ?? current.identity.email).trim();
    final openssh = _encodeRsaPublicKeyToOpenSsh(publicKey, comment: note);
    final metadata = GitSshKey(
      id: id,
      name: name.trim().isEmpty ? 'RSA $keySize' : name.trim(),
      algorithm: 'rsa-$keySize',
      publicKeyOpenSsh: openssh,
      comment: note,
      fingerprint: _fingerprintFromOpenSsh(openssh),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _secretStore.write(
      '$_secretPrefix$id',
      CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey),
    );
    final next = current.copyWith(
      sshKeys: [...current.sshKeys, metadata],
      defaultSshKeyId: current.defaultSshKeyId ?? metadata.id,
    );
    await save(next);
    return next;
  }

  Future<GitSettings> importSshKey({
    required String name,
    required String privateKeyPem,
    String? publicKeyOpenSsh,
    String? comment,
  }) async {
    final trimmedPem = privateKeyPem.trim();
    if (trimmedPem.isEmpty) {
      throw const GitException('Private key cannot be empty');
    }
    final current = await load();
    late final RSAPrivateKey privateKey;
    try {
      privateKey = CryptoUtils.rsaPrivateKeyFromPem(trimmedPem);
    } catch (_) {
      privateKey = CryptoUtils.rsaPrivateKeyFromPemPkcs1(trimmedPem);
    }
    final publicKey = RSAPublicKey(
      privateKey.modulus!,
      privateKey.publicExponent!,
    );
    final note = comment?.trim().isNotEmpty == true
        ? comment!.trim()
        : _extractComment(publicKeyOpenSsh).isNotEmpty
            ? _extractComment(publicKeyOpenSsh)
            : current.identity.email;
    final openssh = publicKeyOpenSsh?.trim().isNotEmpty == true
        ? publicKeyOpenSsh!.trim()
        : _encodeRsaPublicKeyToOpenSsh(publicKey, comment: note);
    final id = newId('sshkey');
    final metadata = GitSshKey(
      id: id,
      name: name.trim().isEmpty ? 'Imported RSA key' : name.trim(),
      algorithm: 'rsa-imported',
      publicKeyOpenSsh: openssh,
      comment: note,
      fingerprint: _fingerprintFromOpenSsh(openssh),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _secretStore.write('$_secretPrefix$id', trimmedPem);
    final next = current.copyWith(
      sshKeys: [...current.sshKeys, metadata],
      defaultSshKeyId: current.defaultSshKeyId ?? metadata.id,
    );
    await save(next);
    return next;
  }

  Future<GitSettings> deleteSshKey(String id) async {
    final current = await load();
    final nextKeys = current.sshKeys.where((item) => item.id != id).toList();
    await _secretStore.delete('$_secretPrefix$id');
    final next = current.copyWith(
      sshKeys: nextKeys,
      defaultSshKeyId: current.defaultSshKeyId == id
          ? (nextKeys.isEmpty ? null : nextKeys.first.id)
          : current.defaultSshKeyId,
    );
    await save(next);
    return next;
  }

  Future<GitSettings> setDefaultSshKey(String? id) async {
    final current = await load();
    if (id != null &&
        id.isNotEmpty &&
        !current.sshKeys.any((item) => item.id == id)) {
      throw GitException('SSH key not found: $id');
    }
    final next = current.copyWith(defaultSshKeyId: id);
    await save(next);
    return next;
  }

  Future<String?> readPrivateKeyPem(String id) async {
    return _secretStore.read('$_secretPrefix$id');
  }

  Future<GitSettings> saveRemoteCredential({
    String? id,
    required String type,
    required String name,
    required String host,
    String? pathPrefix,
    String? username,
    String? secret,
    String? sshKeyId,
  }) async {
    final normalizedType = type.trim();
    final normalizedHost = host.trim().toLowerCase();
    if (!_isSupportedRemoteCredentialType(normalizedType)) {
      throw GitException('Unsupported remote credential type: $type');
    }
    if (normalizedHost.isEmpty) {
      throw const GitException('Remote host cannot be empty');
    }

    final current = await load();
    final normalizedPathPrefix = _normalizePathPrefix(pathPrefix);
    final normalizedUsername = username?.trim() ?? '';
    if (normalizedType == 'sshKey') {
      final resolvedSshKeyId = (sshKeyId ?? '').trim();
      if (resolvedSshKeyId.isEmpty) {
        throw const GitException('SSH remote credential requires an SSH key');
      }
      final sshKeyExists =
          current.sshKeys.any((item) => item.id == resolvedSshKeyId);
      if (!sshKeyExists) {
        throw GitException('SSH key not found: $resolvedSshKeyId');
      }
    } else if ((secret ?? '').trim().isEmpty && id == null) {
      throw const GitException('HTTPS remote credential requires a token or password');
    }

    final existingIndex = id == null
        ? -1
        : current.remoteCredentials.indexWhere((item) => item.id == id);
    final existing =
        existingIndex == -1 ? null : current.remoteCredentials[existingIndex];
    final nextId = existing?.id ?? newId('remote');
    final nextCredential = GitRemoteCredential(
      id: nextId,
      name: name.trim().isEmpty ? normalizedHost : name.trim(),
      type: normalizedType,
      host: normalizedHost,
      pathPrefix: normalizedPathPrefix,
      username: normalizedUsername,
      sshKeyId:
          normalizedType == 'sshKey' ? (sshKeyId?.trim().isEmpty == true ? null : sshKeyId!.trim()) : null,
      createdAt: existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
    );

    if (normalizedType != 'sshKey') {
      final nextSecret = secret?.trim();
      if (nextSecret != null && nextSecret.isNotEmpty) {
        await _secretStore.write('$_remoteSecretPrefix$nextId', nextSecret);
      } else if (existing == null) {
        throw const GitException('HTTPS remote credential requires a token or password');
      }
    } else if (existing != null && existing.type != 'sshKey') {
      await _secretStore.delete('$_remoteSecretPrefix$nextId');
    }

    final nextCredentials = [...current.remoteCredentials];
    if (existingIndex == -1) {
      nextCredentials.add(nextCredential);
    } else {
      nextCredentials[existingIndex] = nextCredential;
    }
    final next = current.copyWith(remoteCredentials: nextCredentials);
    await save(next);
    return next;
  }

  Future<GitSettings> deleteRemoteCredential(String id) async {
    final current = await load();
    final nextCredentials =
        current.remoteCredentials.where((item) => item.id != id).toList();
    await _secretStore.delete('$_remoteSecretPrefix$id');
    final next = current.copyWith(remoteCredentials: nextCredentials);
    await save(next);
    return next;
  }

  Future<ResolvedGitAuth?> resolveAuthForRemoteUrl(String remoteUrl) async {
    final target = _parseRemoteUrl(remoteUrl);
    if (target == null || target.protocol == 'local') {
      return null;
    }

    final settings = await load();
    GitRemoteCredential? bestMatch;
    var bestScore = -1;
    for (final candidate in settings.remoteCredentials) {
      if (!_credentialMatchesTarget(candidate, target)) {
        continue;
      }
      final score = _normalizePathPrefix(candidate.pathPrefix).length;
      if (score > bestScore) {
        bestMatch = candidate;
        bestScore = score;
      }
    }

    if (bestMatch != null) {
      if (bestMatch.isSsh) {
        final keyId = bestMatch.sshKeyId;
        if (keyId == null || keyId.isEmpty) {
          throw GitException('SSH key missing for credential: ${bestMatch.name}');
        }
        final privateKeyPem = await readPrivateKeyPem(keyId);
        if (privateKeyPem == null || privateKeyPem.trim().isEmpty) {
          throw GitException('SSH private key missing for credential: ${bestMatch.name}');
        }
        return ResolvedGitAuth(
          type: 'ssh',
          username: bestMatch.username.trim().isNotEmpty
              ? bestMatch.username.trim()
              : (target.username.isNotEmpty ? target.username : 'git'),
          privateKeyPem: privateKeyPem,
          sourceCredentialId: bestMatch.id,
        );
      }
      final secret =
          await _secretStore.read('$_remoteSecretPrefix${bestMatch.id}');
      if (secret == null || secret.trim().isEmpty) {
        throw GitException('Remote credential secret missing: ${bestMatch.name}');
      }
      return ResolvedGitAuth(
        type: 'https-basic',
        username: bestMatch.username.trim().isNotEmpty
            ? bestMatch.username.trim()
            : target.username,
        secret: secret.trim(),
        sourceCredentialId: bestMatch.id,
      );
    }

    if (target.protocol == 'ssh') {
      final defaultSshKey = settings.defaultSshKey;
      if (defaultSshKey == null) {
        return null;
      }
      final privateKeyPem = await readPrivateKeyPem(defaultSshKey.id);
      if (privateKeyPem == null || privateKeyPem.trim().isEmpty) {
        return null;
      }
      return ResolvedGitAuth(
        type: 'ssh',
        username: target.username.isNotEmpty ? target.username : 'git',
        privateKeyPem: privateKeyPem,
      );
    }

    return null;
  }

  String _extractComment(String? publicKeyOpenSsh) {
    if (publicKeyOpenSsh == null) {
      return '';
    }
    final parts = publicKeyOpenSsh.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) {
      return '';
    }
    return parts.sublist(2).join(' ').trim();
  }

  String _encodeRsaPublicKeyToOpenSsh(
    RSAPublicKey publicKey, {
    String? comment,
  }) {
    final type = utf8.encode('ssh-rsa');
    final exponent = _encodeMpInt(publicKey.exponent!);
    final modulus = _encodeMpInt(publicKey.modulus!);
    final bytes = BytesBuilder()
      ..add(_encodeUint32(type.length))
      ..add(type)
      ..add(_encodeUint32(exponent.length))
      ..add(exponent)
      ..add(_encodeUint32(modulus.length))
      ..add(modulus);
    final base = base64.encode(bytes.toBytes());
    final suffix = comment == null || comment.trim().isEmpty
        ? ''
        : ' ${comment.trim()}';
    return 'ssh-rsa $base$suffix';
  }

  String _fingerprintFromOpenSsh(String publicKeyOpenSsh) {
    final parts = publicKeyOpenSsh.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) {
      return '';
    }
    final bytes = base64.decode(parts[1]);
    final digest = sha256.convert(bytes);
    return 'SHA256:${base64.encode(digest.bytes).replaceAll('=', '')}';
  }

  Uint8List _encodeUint32(int value) {
    return Uint8List.fromList([
      (value >> 24) & 0xff,
      (value >> 16) & 0xff,
      (value >> 8) & 0xff,
      value & 0xff,
    ]);
  }

  Uint8List _encodeMpInt(BigInt value) {
    final bytes = _encodeBigInt(value);
    if (bytes.isEmpty) {
      return Uint8List.fromList([0]);
    }
    if (bytes.first & 0x80 != 0) {
      return Uint8List.fromList([0, ...bytes]);
    }
    return bytes;
  }

  Uint8List _encodeBigInt(BigInt value) {
    var v = value;
    if (v == BigInt.zero) {
      return Uint8List(0);
    }
    final out = <int>[];
    while (v > BigInt.zero) {
      out.insert(0, (v & BigInt.from(0xff)).toInt());
      v = v >> 8;
    }
    return Uint8List.fromList(out);
  }

  bool _isSupportedRemoteCredentialType(String value) {
    return value == 'sshKey' ||
        value == 'httpsToken' ||
        value == 'httpsBasic';
  }

  String _normalizePathPrefix(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty || trimmed == '/') {
      return '';
    }
    var normalized = trimmed.replaceAll('\\', '/');
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  bool _credentialMatchesTarget(
    GitRemoteCredential candidate,
    _RemoteUrlTarget target,
  ) {
    if (candidate.host.trim().toLowerCase() != target.host) {
      return false;
    }
    if (candidate.isSsh && target.protocol != 'ssh') {
      return false;
    }
    if (candidate.isHttps &&
        target.protocol != 'http' &&
        target.protocol != 'https') {
      return false;
    }
    final prefix = _normalizePathPrefix(candidate.pathPrefix);
    if (prefix.isEmpty) {
      return true;
    }
    if (target.path == prefix) {
      return true;
    }
    return target.path.startsWith('$prefix/');
  }

  _RemoteUrlTarget? _parseRemoteUrl(String remoteUrl) {
    final trimmed = remoteUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('/') ||
        trimmed.startsWith('./') ||
        trimmed.startsWith('../') ||
        trimmed.startsWith('file://')) {
      return const _RemoteUrlTarget(
        protocol: 'local',
        host: '',
        path: '',
        username: '',
      );
    }
    if (trimmed.startsWith('ssh://') ||
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://')) {
      final uri = Uri.parse(trimmed);
      final userInfo = uri.userInfo.trim();
      return _RemoteUrlTarget(
        protocol: uri.scheme.toLowerCase(),
        host: uri.host.trim().toLowerCase(),
        path: _normalizePathPrefix(uri.path),
        username: userInfo,
      );
    }
    final scpMatch =
        RegExp(r'^([^@]+)@([^:]+):/?(.+)$').firstMatch(trimmed);
    if (scpMatch != null) {
      return _RemoteUrlTarget(
        protocol: 'ssh',
        host: (scpMatch.group(2) ?? '').trim().toLowerCase(),
        path: _normalizePathPrefix('/${scpMatch.group(3) ?? ''}'),
        username: (scpMatch.group(1) ?? '').trim(),
      );
    }
    return null;
  }

  Future<JsonMap?> _getSetting(String key) async {
    final reader = _readSetting;
    if (reader != null) {
      return reader(key);
    }
    final database = _database;
    if (database == null) {
      return null;
    }
    return database.getSetting(key);
  }

  Future<void> _putSetting(String key, JsonMap value) async {
    final writer = _writeSetting;
    if (writer != null) {
      return writer(key, value);
    }
    final database = _database;
    if (database == null) {
      throw const GitException('No settings writer configured');
    }
    return database.putSetting(key, value);
  }
}

class _RemoteUrlTarget {
  const _RemoteUrlTarget({
    required this.protocol,
    required this.host,
    required this.path,
    required this.username,
  });

  final String protocol;
  final String host;
  final String path;
  final String username;
}
