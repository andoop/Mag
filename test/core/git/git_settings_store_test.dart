import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/git/git_settings_store.dart';
import 'package:mobile_agent/core/models.dart';

class _MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('git settings store', () {
    test('generate import and delete ssh keys updates settings', () async {
      final settings = <String, JsonMap>{};
      final secretStore = _MemorySecretStore();
      final store = GitSettingsStore(
        secretStore: secretStore,
        readSetting: (key) async => settings[key],
        writeSetting: (key, value) async => settings[key] = value,
      );

      var current = await store.updateIdentity(
        name: 'Andoop',
        email: 'andoop@example.com',
      );
      expect(current.identity.isComplete, isTrue);

      current = await store.generateSshKey(
        name: 'Primary key',
        comment: 'andoop@example.com',
      );
      expect(current.sshKeys, hasLength(1));
      expect(current.defaultSshKey?.name, 'Primary key');
      expect(current.sshKeys.first.publicKeyOpenSsh, startsWith('ssh-rsa '));
      expect(
        await store.readPrivateKeyPem(current.sshKeys.first.id),
        contains('BEGIN RSA PRIVATE KEY'),
      );

      final generatedPrivate = await store.readPrivateKeyPem(current.sshKeys.first.id);
      current = await store.importSshKey(
        name: 'Imported key',
        privateKeyPem: generatedPrivate!,
      );
      expect(current.sshKeys, hasLength(2));

      await store.setDefaultSshKey(current.sshKeys.last.id);
      current = await store.load();
      expect(current.defaultSshKey?.id, current.sshKeys.last.id);

      current = await store.deleteSshKey(current.sshKeys.last.id);
      expect(current.sshKeys, hasLength(1));
      expect(current.defaultSshKey?.id, current.sshKeys.first.id);
    });

    test('resolve remote credentials by host path and protocol', () async {
      final settings = <String, JsonMap>{};
      final secretStore = _MemorySecretStore();
      final store = GitSettingsStore(
        secretStore: secretStore,
        readSetting: (key) async => settings[key],
        writeSetting: (key, value) async => settings[key] = value,
      );

      var current = await store.generateSshKey(
        name: 'Primary key',
        comment: 'andoop@example.com',
      );
      final sshKeyId = current.sshKeys.first.id;

      current = await store.saveRemoteCredential(
        type: 'httpsToken',
        name: 'GitHub token',
        host: 'github.com',
        pathPrefix: '/andoop/private-repo.git',
        username: 'andoop',
        secret: 'ghp_test_token',
      );
      expect(current.remoteCredentials, hasLength(1));

      current = await store.saveRemoteCredential(
        type: 'sshKey',
        name: 'GitLab SSH',
        host: 'gitlab.com',
        pathPrefix: '/team',
        username: 'git',
        sshKeyId: sshKeyId,
      );
      expect(current.remoteCredentials, hasLength(2));

      final httpsAuth = await store.resolveAuthForRemoteUrl(
        'https://github.com/andoop/private-repo.git',
      );
      expect(httpsAuth, isNotNull);
      expect(httpsAuth!.isHttps, isTrue);
      expect(httpsAuth.username, 'andoop');
      expect(httpsAuth.secret, 'ghp_test_token');

      final sshAuth = await store.resolveAuthForRemoteUrl(
        'git@gitlab.com:team/project.git',
      );
      expect(sshAuth, isNotNull);
      expect(sshAuth!.isSsh, isTrue);
      expect(sshAuth.username, 'git');
      expect(sshAuth.privateKeyPem, contains('BEGIN RSA PRIVATE KEY'));

      final fallbackSshAuth = await store.resolveAuthForRemoteUrl(
        'ssh://git@example.com/demo/repo.git',
      );
      expect(fallbackSshAuth, isNotNull);
      expect(fallbackSshAuth!.isSsh, isTrue);
      expect(fallbackSshAuth.username, 'git');

      current = await store.deleteRemoteCredential(
        current.remoteCredentials.first.id,
      );
      expect(current.remoteCredentials, hasLength(1));
    });
  });
}
