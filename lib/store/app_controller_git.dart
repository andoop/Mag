// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'app_controller.dart';

extension AppControllerGit on AppController {
  Future<void> refreshGitSettings() async {
    final settings = await _gitSettingsStore.load();
    state = state.copyWith(gitSettings: settings);
    notifyListeners();
  }

  Future<void> saveGitIdentity({
    required String name,
    required String email,
  }) async {
    final settings = await _gitSettingsStore.updateIdentity(
      name: name,
      email: email,
    );
    state = state.copyWith(gitSettings: settings);
    notifyListeners();
  }

  Future<void> generateGitSshKey({
    required String name,
    String? comment,
  }) async {
    final settings = await _gitSettingsStore.generateSshKey(
      name: name,
      comment: comment,
    );
    state = state.copyWith(gitSettings: settings);
    notifyListeners();
  }

  Future<void> importGitSshKey({
    required String name,
    required String privateKeyPem,
    String? publicKeyOpenSsh,
    String? comment,
  }) async {
    final settings = await _gitSettingsStore.importSshKey(
      name: name,
      privateKeyPem: privateKeyPem,
      publicKeyOpenSsh: publicKeyOpenSsh,
      comment: comment,
    );
    state = state.copyWith(gitSettings: settings);
    notifyListeners();
  }

  Future<void> deleteGitSshKey(String id) async {
    final settings = await _gitSettingsStore.deleteSshKey(id);
    state = state.copyWith(gitSettings: settings);
    notifyListeners();
  }

  Future<void> setDefaultGitSshKey(String? id) async {
    final settings = await _gitSettingsStore.setDefaultSshKey(id);
    state = state.copyWith(gitSettings: settings);
    notifyListeners();
  }

  Future<void> saveGitRemoteCredential({
    String? id,
    required String type,
    required String name,
    required String host,
    String? pathPrefix,
    String? username,
    String? secret,
    String? sshKeyId,
  }) async {
    final settings = await _gitSettingsStore.saveRemoteCredential(
      id: id,
      type: type,
      name: name,
      host: host,
      pathPrefix: pathPrefix,
      username: username,
      secret: secret,
      sshKeyId: sshKeyId,
    );
    state = state.copyWith(gitSettings: settings);
    notifyListeners();
  }

  Future<void> deleteGitRemoteCredential(String id) async {
    final settings = await _gitSettingsStore.deleteRemoteCredential(id);
    state = state.copyWith(gitSettings: settings);
    notifyListeners();
  }
}
