// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'app_controller.dart';

extension AppControllerVariables on AppController {
  Future<void> refreshAppVariables() async {
    final variables = await _appVariableStore.load();
    state = state.copyWith(appVariables: variables);
    notifyListeners();
  }

  Future<void> saveAppVariable({
    String? id,
    required String name,
    required String value,
    required String kind,
    required bool secret,
    required bool allowAiUse,
    String? note,
  }) async {
    final variables = await _appVariableStore.saveVariable(
      id: id,
      name: name,
      value: value,
      kind: kind,
      secret: secret,
      allowAiUse: allowAiUse,
      note: note,
    );
    state = state.copyWith(appVariables: variables);
    notifyListeners();
  }

  Future<void> setAppVariableAiAccess(String id, bool allowAiUse) async {
    final variables = await _appVariableStore.updateAiAccess(id, allowAiUse);
    state = state.copyWith(appVariables: variables);
    notifyListeners();
  }

  Future<String?> readAppVariableValue(String id) {
    return _appVariableStore.readValue(id);
  }

  Future<void> deleteAppVariable(String id) async {
    final variables = await _appVariableStore.deleteVariable(id);
    state = state.copyWith(appVariables: variables);
    notifyListeners();
  }
}
