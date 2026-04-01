import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 最近打开的项目（按 [treeUri] 去重），用于对齐 OpenCode 首页「最近项目」。
/// 与平台沙盒 URI 绑定，便于日后 iOS 文件访问演进后仍用同一 key。
class ProjectRecentsStore {
  ProjectRecentsStore._();

  static const _key = 'project_recents_v1';

  static Future<void> touch(String treeUri, String displayName) async {
    final trimmedUri = treeUri.trim();
    if (trimmedUri.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = _decode(prefs.getString(_key));
    list.removeWhere((e) => e['treeUri'] == trimmedUri);
    list.insert(0, {
      'treeUri': trimmedUri,
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
      final uri = e['treeUri'] as String?;
      final at = e['lastOpenedAt'];
      if (uri == null || uri.isEmpty) continue;
      if (at is int) {
        out[uri] = at;
      } else if (at is num) {
        out[uri] = at.toInt();
      }
    }
    return out;
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
