part of '../models.dart';

class AppVariable {
  const AppVariable({
    required this.id,
    required this.name,
    required this.kind,
    required this.secret,
    required this.allowAiUse,
    required this.createdAt,
    required this.updatedAt,
    this.note,
  });

  final String id;
  final String name;
  final String kind;
  final bool secret;
  final bool allowAiUse;
  final int createdAt;
  final int updatedAt;
  final String? note;

  AppVariable copyWith({
    String? id,
    String? name,
    String? kind,
    bool? secret,
    bool? allowAiUse,
    int? createdAt,
    int? updatedAt,
    Object? note = _noJsonChange,
  }) {
    return AppVariable(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      secret: secret ?? this.secret,
      allowAiUse: allowAiUse ?? this.allowAiUse,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      note: identical(note, _noJsonChange) ? this.note : note as String?,
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'name': name,
      'kind': kind,
      'secret': secret,
      'allowAiUse': allowAiUse,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      if (note?.isNotEmpty == true) 'note': note,
    };
  }

  static AppVariable fromJson(JsonMap json) {
    final idRaw = jsonStringCoerce(json['id'], '').trim();
    final nameRaw = jsonStringCoerce(json['name'], '').trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    return AppVariable(
      id: idRaw.isEmpty ? newId('var') : idRaw,
      name: nameRaw,
      kind: jsonStringCoerce(json['kind'], 'secret').trim().isEmpty
          ? 'secret'
          : jsonStringCoerce(json['kind'], 'secret').trim(),
      secret: _jsonBool(json['secret'], true),
      allowAiUse: _jsonBool(json['allowAiUse'], false),
      createdAt: _jsonInt(json['createdAt'], now),
      updatedAt: _jsonInt(json['updatedAt'], now),
      note: jsonStringCoerce(json['note'], '').trim().isEmpty
          ? null
          : jsonStringCoerce(json['note'], '').trim(),
    );
  }
}

class AppVariablesConfig {
  const AppVariablesConfig({this.variables = const []});

  final List<AppVariable> variables;

  JsonMap toJson() {
    return {
      'variables': variables.map((item) => item.toJson()).toList(),
    };
  }

  static AppVariablesConfig fromJson(JsonMap json) {
    final variables = (json['variables'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => AppVariable.fromJson(Map<String, dynamic>.from(item)))
        .where((item) => item.name.trim().isNotEmpty)
        .toList();
    variables.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return AppVariablesConfig(variables: variables);
  }
}

const Object _noJsonChange = Object();

bool _jsonBool(dynamic value, bool fallback) {
  if (value is bool) return value;
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
  }
  return fallback;
}

int _jsonInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
