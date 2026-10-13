import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальные подписи участников и групп (только на этом устройстве).
class LocalLabels {
  static const _usersKey = 'veniamin_local_user_labels';
  static const _groupsKey = 'veniamin_local_group_labels';

  /// account_id / uuid → подпись
  static Map<String, String> users = {};

  /// group_id → подпись
  static Map<String, String> groups = {};

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    users = _decode(prefs.getString(_usersKey));
    groups = _decode(prefs.getString(_groupsKey));
  }

  static Map<String, String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveUsers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersKey, jsonEncode(users));
  }

  static Future<void> _saveGroups() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupsKey, jsonEncode(groups));
  }

  static String userName(String id, String fallback) {
    if (id.isEmpty) return fallback;
    final n = users[id];
    if (n != null && n.trim().isNotEmpty) return n.trim();
    return fallback;
  }

  /// Учитывает uuid и accountId.
  static String userNameFor({
    String? uuid,
    String? accountId,
    required String fallback,
  }) {
    for (final id in [accountId, uuid]) {
      if (id == null || id.isEmpty) continue;
      final n = users[id];
      if (n != null && n.trim().isNotEmpty) return n.trim();
    }
    return fallback;
  }

  static String groupName(String id, String fallback) {
    if (id.isEmpty) return fallback;
    final n = groups[id];
    if (n != null && n.trim().isNotEmpty) return n.trim();
    return fallback;
  }

  static Future<void> setUserLabel(String id, String? label) async {
    if (id.isEmpty) return;
    final t = label?.trim() ?? '';
    if (t.isEmpty) {
      users.remove(id);
    } else {
      users[id] = t;
    }
    await _saveUsers();
  }

  static Future<void> setGroupLabel(String id, String? label) async {
    if (id.isEmpty) return;
    final t = label?.trim() ?? '';
    if (t.isEmpty) {
      groups.remove(id);
    } else {
      groups[id] = t;
    }
    await _saveGroups();
  }
}
