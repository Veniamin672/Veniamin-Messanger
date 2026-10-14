import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'device_id.dart';
import 'notifications.dart';

enum ConnState {
  disconnected,
  connecting,
  connected,
  pending,
  authenticated,
  rejected,
  error,
}

class MessageReply {
  final String id;
  final String fromName;
  final String text;
  final String msgType;

  MessageReply({
    required this.id,
    required this.fromName,
    required this.text,
    this.msgType = 'text',
  });

  factory MessageReply.fromJson(Map<String, dynamic> j) => MessageReply(
        id: j['id']?.toString() ?? '',
        fromName: j['from_name']?.toString() ?? '',
        text: j['text']?.toString() ?? '',
        msgType: j['msg_type']?.toString() ?? 'text',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'from_name': fromName,
        'text': text,
        'msg_type': msgType,
      };
}

class ChatMessage {
  final String id;
  final String fromUuid;
  final String fromName;
  final String groupId;
  final String msgType;
  final String? text;
  final String? mediaId;
  final String? filename;
  final String? mime;
  final int? size;
  final int ts;
  final MessageReply? replyTo;
  final bool edited;
  final int? editedTs;
  final bool pinned;
  final int? pinnedAt;

  ChatMessage({
    required this.id,
    required this.fromUuid,
    required this.fromName,
    this.groupId = 'global',
    required this.msgType,
    this.text,
    this.mediaId,
    this.filename,
    this.mime,
    this.size,
    required this.ts,
    this.replyTo,
    this.edited = false,
    this.editedTs,
    this.pinned = false,
    this.pinnedAt,
  });

  ChatMessage copyWith({
    String? text,
    bool? edited,
    int? editedTs,
    bool? pinned,
    int? pinnedAt,
  }) =>
      ChatMessage(
        id: id,
        fromUuid: fromUuid,
        fromName: fromName,
        groupId: groupId,
        msgType: msgType,
        text: text ?? this.text,
        mediaId: mediaId,
        filename: filename,
        mime: mime,
        size: size,
        ts: ts,
        replyTo: replyTo,
        edited: edited ?? this.edited,
        editedTs: editedTs ?? this.editedTs,
        pinned: pinned ?? this.pinned,
        pinnedAt: pinnedAt ?? this.pinnedAt,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    MessageReply? reply;
    final raw = j['reply_to'];
    if (raw is Map) {
      reply = MessageReply.fromJson(Map<String, dynamic>.from(raw));
    }
    return ChatMessage(
      id: j['id'] ?? '',
      fromUuid: j['from_uuid'] ?? '',
      fromName: j['from_name'] ?? '',
      groupId: j['group_id'] ?? 'global',
      msgType: j['msg_type'] ?? 'text',
      text: j['text'],
      mediaId: j['media_id'],
      filename: j['filename'],
      mime: j['mime'],
      size: j['size'],
      ts: j['ts'] ?? 0,
      replyTo: reply,
      edited: j['edited'] == true,
      editedTs: j['edited_ts'],
      pinned: j['pinned'] == true,
      pinnedAt: j['pinned_at'],
    );
  }
}


class UserInfo {
  final String uuid; // account id (or device uuid for legacy)
  final String displayName;
  final String role;
  final bool online;
  final String? accountId;
  final List<String> platforms; // online platforms: windows, android, ios...
  final String? callDeviceUuid; // device to ring
  final List<String> deviceUuids;

  UserInfo({
    required this.uuid,
    required this.displayName,
    required this.role,
    this.online = false,
    this.accountId,
    this.platforms = const [],
    this.callDeviceUuid,
    this.deviceUuids = const [],
  });

  factory UserInfo.fromJson(Map<String, dynamic> j) => UserInfo(
        uuid: j['uuid'] ?? j['account_id'] ?? '',
        displayName: j['display_name'] ?? '',
        role: j['role'] ?? 'member',
        online: j['online'] ?? false,
        accountId: j['account_id'],
        platforms: List<String>.from(j['platforms'] ?? []),
        callDeviceUuid: j['call_device_uuid'] ?? j['uuid'],
        deviceUuids: List<String>.from(j['device_uuids'] ?? []),
      );
}

class PendingUser {
  final String uuid;
  final String displayName;
  final int requestedAt;

  PendingUser({
    required this.uuid,
    required this.displayName,
    required this.requestedAt,
  });

  factory PendingUser.fromJson(Map<String, dynamic> j) => PendingUser(
        uuid: j['uuid'] ?? '',
        displayName: j['display_name'] ?? '',
        requestedAt: j['requested_at'] ?? 0,
      );
}

class GroupInfo {
  final String id;
  final String name;
  final String? ownerUuid;
  final List<String> members;
  final int createdAt;

  GroupInfo({
    required this.id,
    required this.name,
    this.ownerUuid,
    required this.members,
    this.createdAt = 0,
  });

  int get memberCount => members.length;

  factory GroupInfo.fromJson(Map<String, dynamic> j) {
    final members = List<String>.from(j['members'] ?? []);
    final count = j['member_count'];
    return GroupInfo(
      id: j['id'] ?? '',
      name: j['name'] ?? '',
      ownerUuid: j['owner_uuid'],
      members: members,
      createdAt: j['created_at'] ?? 0,
    );
  }
}

class PinnedEntry {
  final String messageId;
  final int? pinnedAt;
  final String? pinnedBy;
  final ChatMessage? message;

  PinnedEntry({
    required this.messageId,
    this.pinnedAt,
    this.pinnedBy,
    this.message,
  });

  factory PinnedEntry.fromJson(Map<String, dynamic> j) {
    ChatMessage? msg;
    final raw = j['message'];
    if (raw is Map) {
      msg = ChatMessage.fromJson(Map<String, dynamic>.from(raw));
    }
    return PinnedEntry(
      messageId: j['message_id']?.toString() ?? '',
      pinnedAt: j['pinned_at'] as int?,
      pinnedBy: j['pinned_by']?.toString(),
      message: msg,
    );
  }

  String get preview {
    final m = message;
    if (m == null) return 'Сообщение';
    if (m.msgType == 'text') {
      final t = m.text ?? '';
      return t.length > 80 ? '${t.substring(0, 80)}…' : t;
    }
    return m.filename ?? m.msgType;
  }

  String get fromName => message?.fromName ?? '';
}

class ConnectionService extends ChangeNotifier {
  WebSocketChannel? _channel;
  int _sessionEpoch = 0;
  int _activeEpoch = 0;
  StreamSubscription? _sub;
  Timer? _pingTimer;

  ConnState state = ConnState.disconnected;
  String? errorMessage;
  String? serverHost;
  int serverPort = 8765;
  bool useTls = true;
  String displayName = '';
  bool isAdmin = false;
  UserInfo? me;
  List<UserInfo> users = [];
  List<PendingUser> pending = [];
  List<GroupInfo> groups = [];
  String currentGroupId = 'global';
  List<ChatMessage> messages = [];
  List<PinnedEntry> pins = [];
  int maxPins = 20;
  String? typingUser;

  // Media download callbacks
  final Map<String, Completer<Uint8List?>> _mediaWaiters = {};
  final Map<String, Uint8List> mediaCache = {};
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _userDisconnected = false;

  // Call state
  String? activeCallId;
  String? callPeerUuid;
  String? callPeerName;
  bool isIncomingCall = false;
  Map<String, dynamic>? lastOfferSdp;
  Map<String, dynamic>? lastAnswerSdp;
  final List<Map<String, dynamic>> iceCandidates = [];
  void Function(Map<String, dynamic>)? onCallSignal;

  List<ChatMessage> get currentMessages =>
      messages.where((m) => m.groupId == currentGroupId).toList();

  GroupInfo? get currentGroup {
    try {
      return groups.firstWhere((g) => g.id == currentGroupId);
    } catch (_) {
      return groups.isNotEmpty ? groups.first : null;
    }
  }

  Future<void> connect(String host,
      {int port = 8765,
      required String name,
      String? accountId,
      bool useTls = true}) async {
    if (state == ConnState.connecting) {
      return;
    }
    // смена сервера / повторный вход — закрыть старое соединение и сбросить данные
    if (state == ConnState.authenticated ||
        state == ConnState.connected ||
        state == ConnState.pending ||
        _channel != null) {
      _cleanup();
    }
    _resetSession();
    _sessionEpoch += 1;
    final epoch = _sessionEpoch;
    _activeEpoch = epoch;

    serverHost = host.trim();
    serverPort = port;
    this.useTls = useTls;
    displayName = name.trim().isEmpty ? 'Anonymous' : name.trim();
    if (accountId != null && accountId.isNotEmpty) {
      await DeviceId.saveAccountId(accountId);
    }
    state = ConnState.connecting;
    errorMessage = null;
    notifyListeners();

    try {
      final scheme = this.useTls ? 'wss' : 'ws';
      final uri = Uri.parse('$scheme://$serverHost:$serverPort');
      if (this.useTls) {
        // Self-signed certs in LAN: accept for private messenger.
        // For production put a real CA cert on the server and tighten this.
        final httpClient = HttpClient()
          ..badCertificateCallback =
              (X509Certificate cert, String host, int port) => true;
        _channel = IOWebSocketChannel.connect(uri, customClient: httpClient);
      } else {
        _channel = IOWebSocketChannel.connect(uri);
      }
      await _channel!.ready;

      _sub = _channel!.stream.listen(
        (raw) {
          if (epoch != _sessionEpoch) return; // пакеты старого сервера игнор
          _onData(raw);
        },
        onError: (e) {
          if (epoch != _sessionEpoch) return;
          errorMessage = e.toString();
          state = ConnState.error;
          notifyListeners();
          if (!_userDisconnected && DeviceId.wantAutoConnect) {
            _scheduleReconnect();
          }
        },
        onDone: () {
          if (epoch != _sessionEpoch) return;
          final wasAuth = state == ConnState.authenticated ||
              state == ConnState.connected ||
              state == ConnState.pending;
          _cleanup();
          if (state != ConnState.rejected && state != ConnState.connecting) {
            if (wasAuth) {
              _resetSession();
            }
            state = ConnState.disconnected;
            notifyListeners();
            if (!_userDisconnected && DeviceId.wantAutoConnect) {
              _scheduleReconnect();
            }
          }
        },
      );

      _send({
        'type': 'hello',
        'device_uuid': DeviceId.uuid,
        'display_name': displayName,
        'account_id': accountId ?? DeviceId.accountId,
        'device_info': {'platform': defaultTargetPlatform.name},
        'protocol': '1.2',
      });

      state = ConnState.connected;
      notifyListeners();

      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        _send({'type': 'ping'});
      });
    } catch (e) {
      errorMessage = e.toString();
      state = ConnState.error;
      notifyListeners();
      _cleanup();
      if (!_userDisconnected && DeviceId.wantAutoConnect) {
        _scheduleReconnect();
      }
    }
  }

  void requestAuth() {
    _send({
      'type': 'auth',
      'display_name': displayName,
      'account_id': DeviceId.accountId,
      'device_info': {'platform': defaultTargetPlatform.name},
    });
  }

  void selectGroup(String groupId) {
    currentGroupId = groupId;
    VeniaminNotifications.activeGroupId = groupId;
    pins = [];
    getHistory(groupId: groupId);
    notifyListeners();
  }

  void sendMessage(String text, {MessageReply? replyTo}) {
    if (text.trim().isEmpty) return;
    final packet = <String, dynamic>{
      'type': 'message',
      'text': text.trim(),
      'group_id': currentGroupId,
    };
    if (replyTo != null && replyTo.id.isNotEmpty) {
      packet['reply_to'] = replyTo.toJson();
    }
    _send(packet);
  }

  void deleteMessage(String messageId) {
    if (messageId.isEmpty) return;
    _send({
      'type': 'delete_message',
      'message_id': messageId,
      'group_id': currentGroupId,
    });
    // оптимистично убираем у себя
    messages.removeWhere((m) => m.id == messageId);
    notifyListeners();
  }

  void pinMessage(String messageId) {
    if (messageId.isEmpty) return;
    _send({
      'type': 'pin_message',
      'message_id': messageId,
      'group_id': currentGroupId,
    });
  }

  void unpinMessage(String messageId) {
    if (messageId.isEmpty) return;
    _send({
      'type': 'unpin_message',
      'message_id': messageId,
      'group_id': currentGroupId,
    });
  }

  void requestPins() {
    _send({'type': 'get_pins', 'group_id': currentGroupId});
  }

  void editMessage(String messageId, String newText) {
    final text = newText.trim();
    if (messageId.isEmpty || text.isEmpty) return;
    _send({
      'type': 'edit_message',
      'message_id': messageId,
      'text': text,
      'group_id': currentGroupId,
    });
    // оптимистично
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      messages[idx] = messages[idx].copyWith(
        text: text,
        edited: true,
        editedTs: DateTime.now().millisecondsSinceEpoch,
      );
      notifyListeners();
    }
  }

  /// Максимальный размер вложения (байты).
  static const int maxFileBytes = 25 * 1024 * 1024;

  Future<bool> sendFile(String path, String filename, String mime) async {
    final file = File(path);
    try {
      final len = await file.length();
      if (len > maxFileBytes) {
        errorMessage =
            'Файл слишком большой (макс. 25 МБ). Выберите файл меньшего размера.';
        notifyListeners();
        return false;
      }
    } catch (_) {}
    final bytes = await file.readAsBytes();
    if (bytes.length > maxFileBytes) {
      errorMessage =
          'Файл слишком большой (макс. 25 МБ). Выберите файл меньшего размера.';
      notifyListeners();
      return false;
    }
    final b64 = base64Encode(bytes);
    _send({
      'type': 'file',
      'filename': filename,
      'mime': mime,
      'size': bytes.length,
      'data': b64,
      'group_id': currentGroupId,
    });
    return true;
  }

  Future<Uint8List?> downloadMedia(String mediaId) async {
    final cached = mediaCache[mediaId];
    if (cached != null) return cached;
    if (_mediaWaiters.containsKey(mediaId)) {
      return _mediaWaiters[mediaId]!.future;
    }
    final c = Completer<Uint8List?>();
    _mediaWaiters[mediaId] = c;
    _send({'type': 'get_media', 'media_id': mediaId});
    Future.delayed(const Duration(seconds: 60), () {
      if (!c.isCompleted) {
        c.complete(null);
        _mediaWaiters.remove(mediaId);
      }
    });
    final data = await c.future;
    if (data != null) {
      mediaCache[mediaId] = data;
    }
    return data;
  }

  void sendTyping(bool isTyping) {
    _send({
      'type': 'typing',
      'is_typing': isTyping,
      'group_id': currentGroupId,
    });
  }

  void getHistory({String? groupId, int limit = 100}) {
    _send({
      'type': 'get_history',
      'limit': limit,
      'group_id': groupId ?? currentGroupId,
    });
  }

  void getUsers() => _send({'type': 'get_users'});
  void getGroups() => _send({'type': 'get_groups'});

  void createGroup(String name) {
    _send({'type': 'create_group', 'name': name});
  }

  void addToGroup(String groupId, String memberUuid) {
    _send({
      'type': 'add_to_group',
      'group_id': groupId,
      'member_uuid': memberUuid,
    });
  }

  void removeFromGroup(String groupId, String memberUuid) {
    _send({
      'type': 'remove_from_group',
      'group_id': groupId,
      'member_uuid': memberUuid,
    });
  }

  void leaveGroup(String groupId) {
    if (groupId == 'global') return;
    _send({'type': 'leave_group', 'group_id': groupId});
    // оптимистично убираем с клиента сразу
    groups = groups.where((g) => g.id != groupId).toList();
    if (currentGroupId == groupId) {
      currentGroupId = groups.isNotEmpty ? groups.first.id : 'global';
      getHistory(groupId: currentGroupId);
    }
    notifyListeners();
  }

  void adminListPending() => _send({'type': 'admin_list_pending'});
  void adminAccept(String uuid) =>
      _send({'type': 'admin_accept', 'uuid': uuid});
  void adminReject(String uuid) =>
      _send({'type': 'admin_reject', 'uuid': uuid});
  void adminKick(String uuid) => _send({'type': 'admin_kick', 'uuid': uuid});

  void adminBroadcast(String text) {
    _send({'type': 'admin_broadcast', 'text': text});
  }

  void adminResetMessages(String password) {
    _send({'type': 'admin_reset_messages', 'password': password});
  }

  void sendCallOffer(String toUuid, String callId, Map<String, dynamic> sdp) {
    activeCallId = callId;
    callPeerUuid = toUuid;
    _send({
      'type': 'call_offer',
      'to_uuid': toUuid,
      'call_id': callId,
      'sdp': sdp,
    });
  }

  void sendCallAnswer(String toUuid, String callId, Map<String, dynamic> sdp) {
    _send({
      'type': 'call_answer',
      'to_uuid': toUuid,
      'call_id': callId,
      'sdp': sdp,
    });
  }

  void sendIce(String toUuid, String callId, Map<String, dynamic> candidate) {
    _send({
      'type': 'call_ice',
      'to_uuid': toUuid,
      'call_id': callId,
      'candidate': candidate,
    });
  }

  void hangup() {
    if (activeCallId != null) {
      final pkt = <String, dynamic>{
        'type': 'call_hangup',
        'call_id': activeCallId,
      };
      if (callPeerUuid != null) pkt['to_uuid'] = callPeerUuid;
      _send(pkt);
    }
    _clearCall();
  }

  void rejectCall() {
    if (callPeerUuid != null && activeCallId != null) {
      _send({
        'type': 'call_reject',
        'to_uuid': callPeerUuid,
        'call_id': activeCallId,
      });
    }
    _clearCall();
  }

  void _clearCall() {
    activeCallId = null;
    callPeerUuid = null;
    callPeerName = null;
    isIncomingCall = false;
    lastOfferSdp = null;
    lastAnswerSdp = null;
    iceCandidates.clear();
    notifyListeners();
  }

  void _send(Map<String, dynamic> packet) {
    packet['ts'] ??= DateTime.now().millisecondsSinceEpoch;
    _channel?.sink.add(jsonEncode(packet));
  }

  void _notifyNewMessage(ChatMessage msg) {
    // свои не уведомляем
    if (msg.fromUuid == DeviceId.uuid || msg.fromUuid == (me?.uuid ?? '')) {
      return;
    }
    if (msg.msgType == 'date') return;

    String body;
    if (msg.msgType == 'file' || msg.mediaId != null) {
      body = '📎 ${msg.filename ?? "файл"}';
    } else if (msg.msgType == 'system') {
      body = msg.text ?? 'системное сообщение';
    } else {
      body = msg.text ?? '';
    }
    if (body.length > 120) body = '${body.substring(0, 120)}…';

    String? groupName;
    for (final g in groups) {
      if (g.id == msg.groupId) {
        groupName = g.name;
        break;
      }
    }
    final title = (groupName != null && groupName.isNotEmpty)
        ? '${msg.fromName} · $groupName'
        : msg.fromName;

    VeniaminNotifications.showMessage(
      title: title,
      body: body.isEmpty ? 'новое сообщение' : body,
      payload: msg.groupId,
      groupId: msg.groupId,
    );
  }

  void _onData(dynamic raw) {
    try {
      final packet = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = packet['type'] as String?;
      if (type == null) return;

      switch (type) {
        case 'auth_accepted':
          state = ConnState.authenticated;
          isAdmin = packet['is_admin'] == true;
          final host = serverHost;
          if (host != null && host.isNotEmpty) {
            DeviceId.saveLastServer(
              host: host,
              port: serverPort,
              name: displayName,
              useTls: useTls,
            );
          }
          _userDisconnected = false;
          _reconnectAttempt = 0;
          DeviceId.setAutoConnect(true);
          VeniaminNotifications.activeGroupId = currentGroupId;
          if (packet['user'] != null) {
            me = UserInfo.fromJson(packet['user']);
            final aid = me?.accountId ?? packet['user']['account_id'];
            if (aid is String && aid.isNotEmpty) {
              DeviceId.saveAccountId(aid, label: me?.displayName ?? displayName);
            }
          }
          if (packet['users'] is List) {
            users = (packet['users'] as List)
                .map((u) => UserInfo.fromJson(u))
                .toList();
          }
          // всегда перезаписываем список групп с этого сервера
          if (packet['groups'] is List) {
            groups = (packet['groups'] as List)
                .map((g) => GroupInfo.fromJson(Map<String, dynamic>.from(g as Map)))
                .toList();
          } else {
            groups = [];
          }
          if (groups.isNotEmpty &&
              !groups.any((g) => g.id == currentGroupId)) {
            currentGroupId = groups.first.id;
          } else if (groups.isEmpty) {
            currentGroupId = 'global';
          }
          getHistory();
          getUsers();
          getGroups();
          if (isAdmin) adminListPending();
          notifyListeners();
          break;

        case 'auth_pending':
          state = ConnState.pending;
          notifyListeners();
          break;

        case 'auth_required':
          requestAuth();
          break;

        case 'auth_rejected':
          state = ConnState.rejected;
          errorMessage = 'Access denied by admin';
          notifyListeners();
          disconnect();
          break;

        case 'pins_updated':
          if (packet['group_id']?.toString() == currentGroupId ||
              packet['group_id'] == null) {
            final raw = packet['pins'];
            if (raw is List) {
              pins = raw
                  .whereType<Map>()
                  .map((e) => PinnedEntry.fromJson(Map<String, dynamic>.from(e)))
                  .toList();
            } else {
              pins = [];
            }
            final mx = packet['max_pins'];
            if (mx is int) maxPins = mx;
            // sync pinned flag on messages
            final ids = pins.map((p) => p.messageId).toSet();
            messages = messages
                .map((m) => m.copyWith(pinned: ids.contains(m.id)))
                .toList();
            notifyListeners();
          }
          break;

        case 'message_edited':
          final mid = packet['message_id']?.toString();
          final newText = packet['text']?.toString();
          if (mid != null && newText != null) {
            final idx = messages.indexWhere((m) => m.id == mid);
            if (idx >= 0) {
              messages[idx] = messages[idx].copyWith(
                text: newText,
                edited: true,
                editedTs: packet['edited_ts'] as int? ??
                    DateTime.now().millisecondsSinceEpoch,
              );
              notifyListeners();
            }
          }
          break;

        case 'message_deleted':
          final mid = packet['message_id']?.toString();
          if (mid != null) {
            messages.removeWhere((m) => m.id == mid);
            final mediaId = packet['media_id']?.toString();
            if (mediaId != null) {
              mediaCache.remove(mediaId);
            }
            notifyListeners();
          }
          break;

        case 'message_broadcast':
        case 'file_broadcast':
        case 'system_broadcast':
          final msg = ChatMessage.fromJson(packet);
          messages.add(msg);
          notifyListeners();
          _notifyNewMessage(msg);
          break;

        case 'history':
          final gid = packet['group_id'] ?? currentGroupId;
          final list = packet['messages'] as List? ?? [];
          messages.removeWhere((m) => m.groupId == gid);
          messages.addAll(list.map((m) => ChatMessage.fromJson(m)));
          messages.sort((a, b) => a.ts.compareTo(b.ts));
          notifyListeners();
          break;

        case 'user_list':
          users = (packet['users'] as List? ?? [])
              .map((u) => UserInfo.fromJson(u))
              .toList();
          notifyListeners();
          break;

        case 'user_joined':
        case 'user_left':
          getUsers();
          break;

        case 'group_list':
          groups = (packet['groups'] as List? ?? [])
              .map((g) => GroupInfo.fromJson(g))
              .toList();
          if (groups.isNotEmpty &&
              !groups.any((g) => g.id == currentGroupId)) {
            currentGroupId = groups.first.id;
          }
          notifyListeners();
          break;

        case 'group_updated':
          getGroups();
          break;

        case 'pending_list':
          pending = (packet['pending'] as List? ?? [])
              .map((p) => PendingUser.fromJson(p))
              .toList();
          notifyListeners();
          break;

        case 'media_data':
          final mid = packet['media_id'] as String?;
          final dataB64 = packet['data'] as String?;
          if (mid != null) {
            Uint8List? bytes;
            if (dataB64 != null) {
              try {
                bytes = base64Decode(dataB64);
              } catch (_) {}
            }
            if (bytes != null) {
              mediaCache[mid] = bytes;
            }
            if (_mediaWaiters.containsKey(mid)) {
              _mediaWaiters[mid]!.complete(bytes);
              _mediaWaiters.remove(mid);
            }
          }
          break;

        case 'typing_broadcast':
          if (packet['group_id'] == currentGroupId) {
            typingUser =
                packet['is_typing'] == true ? packet['display_name'] : null;
            notifyListeners();
          }
          break;

        case 'call_incoming':
          isIncomingCall = true;
          callPeerUuid = packet['from_uuid'];
          callPeerName = packet['from_name'];
          activeCallId = packet['call_id'];
          lastOfferSdp = packet['sdp'] != null
              ? Map<String, dynamic>.from(packet['sdp'])
              : null;
          notifyListeners();
          onCallSignal?.call(packet);
          VeniaminNotifications.showIncomingCall(
            fromName: packet['from_name']?.toString() ?? 'звонок',
          );
          break;

        case 'call_answered':
          lastAnswerSdp = packet['sdp'] != null
              ? Map<String, dynamic>.from(packet['sdp'])
              : null;
          // ICE must go to the device that actually answered
          if (packet['from_uuid'] != null) {
            callPeerUuid = packet['from_uuid'] as String;
          }
          notifyListeners();
          onCallSignal?.call(packet);
          break;

        case 'call_ice_candidate':
          if (packet['candidate'] != null) {
            iceCandidates.add(Map<String, dynamic>.from(packet['candidate']));
          }
          onCallSignal?.call(packet);
          break;

        case 'call_busy':
          final busyMsg = packet['message']?.toString() ??
              'Линия этого абонента занята, попробуйте перезвонить позже';
          errorMessage = busyMsg;
          onCallSignal?.call(packet);
          _clearCall();
          notifyListeners();
          break;

        case 'call_peer_joined':
        case 'call_peer_left':
          onCallSignal?.call(packet);
          break;

        case 'call_ended':
          _clearCall();
          onCallSignal?.call(packet);
          break;

        case 'reset_done':
          messages.clear();
          messages.add(ChatMessage(
            id: packet['id'] ?? '',
            fromUuid: 'system',
            fromName: 'SYSTEM',
            msgType: 'system',
            text: packet['message']?.toString() ?? 'Messages wiped',
            ts: packet['ts'] ?? DateTime.now().millisecondsSinceEpoch,
          ));
          notifyListeners();
          break;

        case 'error':
          errorMessage = packet['message']?.toString();
          notifyListeners();
          break;

        case 'pong':
          break;

        case 'system':
          messages.add(ChatMessage(
            id: packet['id'] ?? '',
            fromUuid: 'system',
            fromName: 'SYSTEM',
            msgType: 'system',
            text: packet['message']?.toString() ?? '',
            ts: packet['ts'] ?? DateTime.now().millisecondsSinceEpoch,
          ));
          notifyListeners();
          break;
      }
    } catch (e) {
      debugPrint('parse error: $e');
    }
  }

  void disconnect() {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    DeviceId.setAutoConnect(false);
    _sessionEpoch += 1; // любые пакеты старого сокета отбрасываются
    _cleanup();
    _resetSession();
    state = ConnState.disconnected;
    errorMessage = null;
    notifyListeners();
  }

  /// Подключение к последнему серверу (старт приложения / resume / автореконнект).
  Future<void> tryAutoConnect() async {
    await DeviceId.loadLastServer();
    if (!DeviceId.wantAutoConnect) return;
    final host = DeviceId.lastServerHost;
    if (host == null || host.isEmpty) return;
    if (state == ConnState.authenticated ||
        state == ConnState.connecting ||
        state == ConnState.pending) {
      return;
    }
    _userDisconnected = false;
    final name = (DeviceId.lastDisplayName != null &&
            DeviceId.lastDisplayName!.isNotEmpty)
        ? DeviceId.lastDisplayName!
        : 'Anonymous';
    await connect(
      host,
      port: DeviceId.lastServerPort ?? 8765,
      name: name,
      accountId: DeviceId.accountId,
      useTls: DeviceId.lastUseTls,
    );
  }

  void _scheduleReconnect() {
    if (_userDisconnected || !DeviceId.wantAutoConnect) return;
    if (state == ConnState.connecting || state == ConnState.authenticated) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 8);
    // 2, 4, 8, ... до ~30 сек
    final sec = (2 * (1 << (_reconnectAttempt - 1))).clamp(2, 30);
    debugPrint('[veniamin] reconnect in ${sec}s (attempt $_reconnectAttempt)');
    _reconnectTimer = Timer(Duration(seconds: sec), () {
      if (_userDisconnected || !DeviceId.wantAutoConnect) return;
      if (state == ConnState.authenticated || state == ConnState.connecting) {
        return;
      }
      tryAutoConnect();
    });
  }

  /// Сброс данных сессии (группы/чат/юзеры другого сервера не должны «залипать»).
  void _resetSession() {
    me = null;
    isAdmin = false;
    users = [];
    pending = [];
    groups = [];
    messages = [];
    pins = [];
    mediaCache.clear();
    currentGroupId = 'global';
    typingUser = null;
    _clearCall();
    for (final c in _mediaWaiters.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _mediaWaiters.clear();
  }

  void _cleanup() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
