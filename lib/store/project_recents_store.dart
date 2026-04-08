import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 最近打开的项目（按 workspace id 去重）。
class ProjectRecentsStore {
  ProjectRecentsStore._();

  static const _key = 'project_recents_v2';

  static Future<void> touch(String workspaceId, String displayName) async {
    final trimmedId = workspaceId.trim();
    if (trimmedId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = _decode(prefs.getString(_key));
    list.removeWhere((e) => e['workspaceId'] == trimmedId);
    list.insert(0, {
      'workspaceId': trimmedId,
      'displayName': displayName.trim().isEmpty ? 'Project' : displayName.trim(),
      'lastOpenedAt': DateTime.now().millisecondsSinceEpoch,
    });
    while (list.length > 48) {
      list.removeLast();
    }
    await prefs.setString(_key, jsonEncode(list));
  }

  /// treeUri -> lastOpenedAt（毫秒）
  static Future<Map<String, int>> lastOpenedMap() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _decode(prefs.getString(_key));
    final out = <String, int>{};
    for (final e in list) {
      final workspaceId = e['workspaceId'] as String?;
      final at = e['lastOpenedAt'];
      if (workspaceId == null || workspaceId.isEmpty) continue;
      if (at is int) {
        out[workspaceId] = at;
      } else if (at is num) {
        out[workspaceId] = at.toInt();
      }
    }
    return out;
  }

  static Future<void> remove(String workspaceId) async {
    final trimmedId = workspaceId.trim();
    if (trimmedId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = _decode(prefs.getString(_key));
    list.removeWhere((e) => e['workspaceId'] == trimmedId);
    await prefs.setString(_key, jsonEncode(list));
  }

  static Future<void> replaceWorkspaceId({
    required String oldWorkspaceId,
    required String newWorkspaceId,
    required String displayName,
  }) async {
    final oldId = oldWorkspaceId.trim();
    final newId = newWorkspaceId.trim();
    if (oldId.isEmpty || newId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = _decode(prefs.getString(_key));
    int? lastOpenedAt;
    list.removeWhere((e) {
      final hit = e['workspaceId'] == oldId;
      if (hit) {
        final raw = e['lastOpenedAt'];
        if (raw is int) {
          lastOpenedAt = raw;
        } else if (raw is num) {
          lastOpenedAt = raw.toInt();
        }
      }
      return hit;
    });
    list.removeWhere((e) => e['workspaceId'] == newId);
    list.insert(0, {
      'workspaceId': newId,
      'displayName': displayName.trim().isEmpty ? 'Project' : displayName.trim(),
      'lastOpenedAt': lastOpenedAt ?? DateTime.now().millisecondsSinceEpoch,
    });
    while (list.length > 48) {
      list.removeLast();
    }
    await prefs.setString(_key, jsonEncode(list));
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
