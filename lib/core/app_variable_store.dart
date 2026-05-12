import 'database.dart';
import 'models.dart';
import 'git/git_settings_store.dart';

class AppVariableStore {
  AppVariableStore({
    AppDatabase? database,
    SecretStore? secretStore,
  })  : _database = database ?? AppDatabase.instance,
        _secretStore = secretStore ?? FlutterSecretStore();

  static const String _settingsKey = 'app_variables';
  static const String _secretPrefix = 'app_variable_';

  final AppDatabase _database;
  final SecretStore _secretStore;

  Future<List<AppVariable>> load() async {
    final raw = await _database.getSetting(_settingsKey);
    if (raw == null) return const [];
    return AppVariablesConfig.fromJson(raw).variables;
  }

  Future<List<AppVariable>> saveVariable({
    String? id,
    required String name,
    required String value,
    required String kind,
    required bool secret,
    required bool allowAiUse,
    String? note,
  }) async {
    final normalizedName = _normalizeName(name);
    if (normalizedName.isEmpty) {
      throw ArgumentError('Variable name cannot be empty');
    }
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty && id == null) {
      throw ArgumentError('Variable value cannot be empty');
    }
    final current = await load();
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingIndex =
        id == null ? -1 : current.indexWhere((item) => item.id == id);
    if (current.any(
      (item) => item.id != id && item.name.toUpperCase() == normalizedName,
    )) {
      throw ArgumentError('Variable name already exists');
    }
    final variableId = id ?? newId('var');
    final existing = existingIndex >= 0 ? current[existingIndex] : null;
    final next = AppVariable(
      id: variableId,
      name: normalizedName,
      kind: kind.trim().isEmpty ? 'secret' : kind.trim(),
      secret: secret,
      allowAiUse: allowAiUse,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      note: note?.trim().isEmpty == true ? null : note?.trim(),
    );
    if (trimmedValue.isNotEmpty) {
      await _secretStore.write('$_secretPrefix$variableId', trimmedValue);
    }
    final variables = [...current];
    if (existingIndex >= 0) {
      variables[existingIndex] = next;
    } else {
      variables.add(next);
    }
    await _save(variables);
    return load();
  }

  Future<List<AppVariable>> updateAiAccess(String id, bool allowAiUse) async {
    final current = await load();
    final variables = current
        .map((item) => item.id == id
            ? item.copyWith(
                allowAiUse: allowAiUse,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              )
            : item)
        .toList();
    await _save(variables);
    return load();
  }

  Future<String?> readValue(String id) {
    return _secretStore.read('$_secretPrefix$id');
  }

  Future<List<AppVariable>> deleteVariable(String id) async {
    final current = await load();
    final variables = current.where((item) => item.id != id).toList();
    await _secretStore.delete('$_secretPrefix$id');
    await _save(variables);
    return load();
  }

  Future<void> _save(List<AppVariable> variables) {
    variables.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _database.putSetting(
      _settingsKey,
      AppVariablesConfig(variables: variables).toJson(),
    );
  }

  String _normalizeName(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), '_');
    return normalized.toUpperCase();
  }
}
