
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class KnownAccount {
  final String id;
  final String label;
  KnownAccount({required this.id, required this.label});

  Map<String, dynamic> toJson() => {'id': id, 'label': label};
  factory KnownAccount.fromJson(Map<String, dynamic> j) => KnownAccount(
        id: j['id'] ?? '',
        label: j['label'] ?? '',
      );
}

class DeviceId {
  static const _key = 'veniamin_device_uuid';
  static const _accountKey = 'veniamin_account_id';
  static const _knownKey = 'veniamin_known_accounts';
  static const _lastHostKey = 'veniamin_last_host';
  static const _lastPortKey = 'veniamin_last_port';
  static const _lastNameKey = 'veniamin_last_name';
  static const _autoConnectKey = 'veniamin_auto_connect';
  static String? _uuid;
  static String? _accountId;
  static List<KnownAccount> knownAccounts = [];
  static String? lastServerHost;
  static int? lastServerPort;
  static String? lastDisplayName;
  /// true = после входа помнить сессию и автоподключаться; false после явного disconnect
  static bool wantAutoConnect = false;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _uuid = prefs.getString(_key);
    if (_uuid == null || _uuid!.isEmpty) {
      _uuid = const Uuid().v4();
      await prefs.setString(_key, _uuid!);
    }
    _accountId = prefs.getString(_accountKey);
    lastServerHost = prefs.getString(_lastHostKey);
    lastServerPort = prefs.getInt(_lastPortKey);
    lastDisplayName = prefs.getString(_lastNameKey);
    wantAutoConnect = prefs.getBool(_autoConnectKey) ?? false;
    await _loadKnown(prefs);
  }

  static Future<void> _loadKnown(SharedPreferences prefs) async {
    knownAccounts = [];
    final raw = prefs.getString(_knownKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        knownAccounts = list
            .map((e) => KnownAccount.fromJson(Map<String, dynamic>.from(e)))
            .where((a) => a.id.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    // ensure current is in list
    if (_accountId != null && _accountId!.isNotEmpty) {
      if (!knownAccounts.any((a) => a.id == _accountId)) {
        knownAccounts.add(KnownAccount(id: _accountId!, label: 'аккаунт'));
        await _saveKnown(prefs);
      }
    }
  }

  static Future<void> _saveKnown([SharedPreferences? prefs]) async {
    prefs ??= await SharedPreferences.getInstance();
    await prefs.setString(
      _knownKey,
      jsonEncode(knownAccounts.map((a) => a.toJson()).toList()),
    );
  }

  static String get uuid {
    if (_uuid == null) {
      throw StateError('DeviceId not initialized. Call DeviceId.init() first.');
    }
    return _uuid!;
  }

  static String? get accountId => _accountId;

  static Future<String?> loadAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    _accountId = prefs.getString(_accountKey);
    await _loadKnown(prefs);
    return _accountId;
  }

  static Future<void> saveAccountId(String id, {String? label}) async {
    _accountId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountKey, id);
    final idx = knownAccounts.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      if (label != null && label.isNotEmpty) {
        knownAccounts[idx] = KnownAccount(id: id, label: label);
      }
    } else {
      knownAccounts.add(KnownAccount(
        id: id,
        label: (label != null && label.isNotEmpty) ? label : 'аккаунт',
      ));
    }
    await _saveKnown(prefs);
  }

  static Future<void> removeKnown(String id) async {
    knownAccounts.removeWhere((a) => a.id == id);
    await _saveKnown();
  }

  /// Clear active account (new empty login) but keep known list.
  static Future<void> clearActiveAccount() async {
    _accountId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountKey);
  }

  static Future<void> saveLastServer({
    required String host,
    required int port,
    String? name,
  }) async {
    lastServerHost = host.trim();
    lastServerPort = port;
    if (name != null && name.trim().isNotEmpty) {
      lastDisplayName = name.trim();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastHostKey, lastServerHost!);
    await prefs.setInt(_lastPortKey, lastServerPort!);
    if (lastDisplayName != null && lastDisplayName!.isNotEmpty) {
      await prefs.setString(_lastNameKey, lastDisplayName!);
    }
  }

  static Future<void> loadLastServer() async {
    final prefs = await SharedPreferences.getInstance();
    lastServerHost = prefs.getString(_lastHostKey);
    lastServerPort = prefs.getInt(_lastPortKey);
    lastDisplayName = prefs.getString(_lastNameKey);
    wantAutoConnect = prefs.getBool(_autoConnectKey) ?? false;
  }

  static Future<void> setAutoConnect(bool value) async {
    wantAutoConnect = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoConnectKey, value);
  }
}
