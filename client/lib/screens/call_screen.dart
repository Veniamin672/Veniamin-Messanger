import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import '../theme.dart';
import '../services/connection.dart';

/// Голосовой WebRTC-звонок (1:1 и группа, mesh).
class CallScreen extends StatefulWidget {
  final ConnectionService connection;
  final String peerUuid;
  final String peerName;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.connection,
    required this.peerUuid,
    required this.peerName,
    required this.isIncoming,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _PeerSlot {
  final String id;
  final String name;
  RTCPeerConnection? pc;
  final List<RTCIceCandidate> pendingIce = [];
  bool remoteSet = false;
  bool connected = false;

  _PeerSlot({required this.id, required this.name});
}

class _CallScreenState extends State<CallScreen> {
  MediaStream? _localStream;
  final Map<String, _PeerSlot> _peers = {};
  bool _muted = false;
  bool _speakerOn = true;
  String _status = 'connecting…';
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  DateTime? _callStartedAt;
  List<MediaDeviceInfo> _audioInputs = [];
  List<MediaDeviceInfo> _audioOutputs = [];
  String? _selectedInputId;
  String? _selectedOutputId;
  late final String _callId;
  final _pcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  ConnectionService get conn => widget.connection;

  bool get _anyConnected => _peers.values.any((p) => p.connected);

  void _startTimerIfNeeded() {
    if (_timer != null) return;
    _callStartedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _callStartedAt == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(_callStartedAt!);
      });
    });
  }

  String get _elapsedLabel {
    final s = _elapsed.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${sec.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _callId = conn.activeCallId ?? const Uuid().v4();
    conn.activeCallId = _callId;
    conn.callPeerUuid = widget.peerUuid;
    conn.callPeerName = widget.peerName;
    conn.onCallSignal = _onSignal;
    _init();
  }

  Future<void> _init() async {
    try {
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        });
      } catch (e) {
        if (mounted) {
          setState(() => _status =
              'нет доступа к микрофону\n'
              'Настройки → Приложения → Veniamin → Микрофон');
        }
        return;
      }
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}

      if (widget.isIncoming) {
        setState(() => _status = 'входящий…');
        // offer уже в lastOfferSdp от первого пира
        if (conn.lastOfferSdp != null) {
          await _answerPeer(widget.peerUuid, widget.peerName, conn.lastOfferSdp!);
        }
      } else {
        setState(() => _status = 'вызов ${widget.peerName}…');
        await _callPeer(widget.peerUuid, widget.peerName);
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'error: $e');
    }
  }

  Future<_PeerSlot> _ensurePeer(String id, String name) async {
    final existing = _peers[id];
    if (existing != null && existing.pc != null) return existing;

    final slot = existing ?? _PeerSlot(id: id, name: name);
    _peers[id] = slot;

    final pc = await createPeerConnection(_pcConfig);
    slot.pc = pc;

    pc.onIceCandidate = (RTCIceCandidate c) {
      if (c.candidate != null && c.candidate!.isNotEmpty) {
        conn.sendIce(id, _callId, {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      if (!mounted) return;
      setState(() {
        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          slot.connected = true;
          _status = 'на линии';
          _startTimerIfNeeded();
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          slot.connected = false;
        }
      });
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() {
          slot.connected = true;
          _status = 'на линии';
        });
        _startTimerIfNeeded();
      }
    };

    pc.onTrack = (RTCTrackEvent event) {
      for (final track in event.streams.expand((s) => s.getAudioTracks())) {
        track.enabled = true;
      }
      try {
        Helper.setSpeakerphoneOn(true);
      } catch (_) {}
    };

    if (_localStream != null) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !_muted;
        await pc.addTrack(track, _localStream!);
      }
    }

    if (mounted) setState(() {});
    return slot;
  }

  Future<void> _callPeer(String id, String name) async {
    final slot = await _ensurePeer(id, name);
    final offer = await slot.pc!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await slot.pc!.setLocalDescription(offer);
    conn.sendCallOffer(id, _callId, {
      'type': offer.type,
      'sdp': offer.sdp,
    });
  }

  Future<void> _answerPeer(
    String id,
    String name,
    Map<String, dynamic> offerSdp,
  ) async {
    final slot = await _ensurePeer(id, name);
    final offer = RTCSessionDescription(
      offerSdp['sdp'] as String?,
      offerSdp['type'] as String?,
    );
    await slot.pc!.setRemoteDescription(offer);
    slot.remoteSet = true;
    await _drainIce(slot);

    final answer = await slot.pc!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 0,
    });
    await slot.pc!.setLocalDescription(answer);
    conn.sendCallAnswer(id, _callId, {
      'type': answer.type,
      'sdp': answer.sdp,
    });
    if (mounted) setState(() => _status = 'connecting…');
  }

  Future<void> _drainIce(_PeerSlot slot) async {
    for (final c in slot.pendingIce) {
      try {
        await slot.pc?.addCandidate(c);
      } catch (_) {}
    }
    slot.pendingIce.clear();
  }

  Future<void> _onSignal(Map<String, dynamic> packet) async {
    final type = packet['type'];
    try {
      if (type == 'call_busy') {
        final msg = packet['message']?.toString() ??
            'Линия этого абонента занята, попробуйте перезвонить позже';
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: VColors.surface,
              title: const Text('Линия занята',
                  style: TextStyle(color: Color(0xFFFF6B6B))),
              content: Text(msg, style: const TextStyle(color: VColors.text)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK',
                      style: TextStyle(color: VColors.green)),
                ),
              ],
            ),
          );
          // если это был доп. участник — не закрываем весь звонок
          if (_peers.length <= 1 && mounted) {
            Navigator.of(context).pop();
          }
        }
        return;
      }

      final from = packet['from_uuid']?.toString();
      final fromName = packet['from_name']?.toString() ?? from ?? '?';

      if (type == 'call_incoming' && packet['sdp'] != null && from != null) {
        // доп. оффер в том же звонке (кто-то добавляет mesh-связь)
        if (packet['call_id']?.toString() == _callId ||
            conn.activeCallId == _callId) {
          final sdp = Map<String, dynamic>.from(packet['sdp'] as Map);
          await _answerPeer(from, fromName, sdp);
        }
        return;
      }

      if (type == 'call_answered' && packet['sdp'] != null && from != null) {
        final slot = await _ensurePeer(from, fromName);
        final sdp = Map<String, dynamic>.from(packet['sdp'] as Map);
        await slot.pc?.setRemoteDescription(
          RTCSessionDescription(
            sdp['sdp'] as String?,
            sdp['type'] as String?,
          ),
        );
        slot.remoteSet = true;
        await _drainIce(slot);
        if (mounted) setState(() => _status = 'connecting…');
        return;
      }

      if (type == 'call_ice_candidate' && packet['candidate'] != null) {
        final peerId = from ?? widget.peerUuid;
        final slot = _peers[peerId];
        final c = Map<String, dynamic>.from(packet['candidate'] as Map);
        final ice = RTCIceCandidate(
          c['candidate'] as String?,
          c['sdpMid'] as String?,
          c['sdpMLineIndex'] as int?,
        );
        if (slot == null) {
          // peer ещё не создан — создадим слот-заглушку
          final s = _PeerSlot(id: peerId, name: peerId);
          s.pendingIce.add(ice);
          _peers[peerId] = s;
          return;
        }
        if (slot.remoteSet) {
          await slot.pc?.addCandidate(ice);
        } else {
          slot.pendingIce.add(ice);
        }
        return;
      }

      if (type == 'call_peer_joined') {
        final uid = packet['uuid']?.toString();
        final name = packet['display_name']?.toString() ?? uid ?? '?';
        if (uid == null) return;
        final me = conn.me?.accountId ?? conn.me?.uuid;
        if (uid == me) return;
        // уже есть связь — не дублируем
        if (_peers.containsKey(uid) && _peers[uid]!.pc != null) return;
        // существующие участники сами звонят новому
        setState(() => _status = 'подключение $name…');
        await _callPeer(uid, name);
        return;
      }

      if (type == 'call_peer_left') {
        final uid = from;
        if (uid == null) return;
        final slot = _peers.remove(uid);
        slot?.pc?.close();
        if (mounted) {
          setState(() {
            if (_peers.isEmpty) {
              _status = 'участники вышли';
            }
          });
        }
        if (_peers.isEmpty && mounted) {
          _end(local: false);
        }
        return;
      }

      if (type == 'call_ended') {
        _end(local: false);
      }
    } catch (e) {
      debugPrint('call signal error: $e');
    }
  }

  void _toggleMute() {
    if (_localStream == null) return;
    for (final tr in _localStream!.getAudioTracks()) {
      tr.enabled = !tr.enabled;
    }
    setState(() => _muted = !_muted);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(next);
    } catch (_) {}
    if (mounted) setState(() => _speakerOn = next);
  }

  Future<void> _refreshDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      _audioInputs = devices
          .where((d) => d.kind == 'audioinput')
          .toList();
      _audioOutputs = devices
          .where((d) => d.kind == 'audiooutput')
          .toList();
    } catch (_) {
      _audioInputs = [];
      _audioOutputs = [];
    }
  }

  Future<void> _switchMicrophone(String deviceId) async {
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'deviceId': deviceId,
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      final newTrack = stream.getAudioTracks().first;
      newTrack.enabled = !_muted;
      for (final slot in _peers.values) {
        final senders = await slot.pc?.getSenders() ?? [];
        for (final sender in senders) {
          if (sender.track?.kind == 'audio') {
            await sender.replaceTrack(newTrack);
          }
        }
      }
      for (final tr in _localStream?.getTracks() ?? []) {
        await tr.stop();
      }
      await _localStream?.dispose();
      _localStream = stream;
      _selectedInputId = deviceId;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('switch mic: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось сменить микрофон: $e'),
            backgroundColor: VColors.surface,
          ),
        );
      }
    }
  }

  Future<void> _selectOutput(String? deviceId) async {
    // На Android/iOS выбор выхода часто только через speakerphone.
    _selectedOutputId = deviceId;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _showAudioSheet() async {
    await _refreshDevices();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: VColors.surface,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Звук',
                    style: TextStyle(
                      color: VColors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Динамик',
                        style: TextStyle(color: VColors.text)),
                    subtitle: Text(
                      _speakerOn
                          ? 'звук на громкую связь'
                          : 'телефон у уха',
                      style: const TextStyle(color: VColors.dim, fontSize: 12),
                    ),
                    value: _speakerOn,
                    activeColor: VColors.green,
                    onChanged: (v) async {
                      try {
                        await Helper.setSpeakerphoneOn(v);
                      } catch (_) {}
                      setState(() => _speakerOn = v);
                      Navigator.pop(ctx);
                      _showAudioSheet();
                    },
                  ),
                  const Divider(color: VColors.border),
                  const Text(
                    'Микрофон (вход)',
                    style: TextStyle(color: VColors.dim, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  if (_audioInputs.isEmpty)
                    const Text('устройства не найдены',
                        style: TextStyle(color: VColors.dim, fontSize: 12))
                  else
                    ..._audioInputs.map((d) {
                      final selected = d.deviceId == _selectedInputId;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: selected ? VColors.green : VColors.dim,
                        ),
                        title: Text(
                          d.label.isNotEmpty ? d.label : 'Микрофон',
                          style: const TextStyle(
                              color: VColors.text, fontSize: 13),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _switchMicrophone(d.deviceId);
                        },
                      );
                    }),
                  const SizedBox(height: 8),
                  const Divider(color: VColors.border),
                  const Text(
                    'Динамик / выход',
                    style: TextStyle(color: VColors.dim, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  if (_audioOutputs.isEmpty)
                    const Text(
                      'На телефоне выход обычно переключается кнопкой «динамик». Список устройств может быть пуст.',
                      style: TextStyle(color: VColors.dim, fontSize: 12),
                    )
                  else
                    ..._audioOutputs.map((d) {
                      final selected = d.deviceId == _selectedOutputId;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 18,
                          color: selected ? VColors.green : VColors.dim,
                        ),
                        title: Text(
                          d.label.isNotEmpty ? d.label : 'Выход',
                          style: const TextStyle(
                              color: VColors.text, fontSize: 13),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _selectOutput(d.deviceId);
                        },
                      );
                    }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddSheet() async {
    final me = conn.me?.accountId ?? conn.me?.uuid;
    final inCall = _peers.keys.toSet()..add(me ?? '');
    final candidates = conn.users.where((u) {
      final id = u.accountId ?? u.uuid;
      if (id.isEmpty || id == me) return false;
      if (inCall.contains(id) || inCall.contains(u.uuid)) return false;
      return u.online;
    }).toList();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: VColors.surface,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Добавить в звонок…',
                  style: TextStyle(
                    color: VColors.green,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (candidates.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Нет доступных участников онлайн',
                    style: TextStyle(color: VColors.dim),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  itemBuilder: (_, i) {
                    final u = candidates[i];
                    final id = u.accountId ?? u.uuid;
                    final name = u.displayName;
                    return ListTile(
                      title: Text(
                        name,
                        style: const TextStyle(color: VColors.text),
                      ),
                      trailing: IconButton(
                        tooltip: 'Добавить',
                        icon: const Icon(Icons.person_add_alt_1,
                            color: VColors.green),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          setState(() => _status = 'добавление $name…');
                          await _callPeer(id, name);
                        },
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        setState(() => _status = 'добавление $name…');
                        await _callPeer(id, name);
                      },
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _end({bool local = true}) {
    _timer?.cancel();
    if (local) conn.hangup();
    for (final p in _peers.values) {
      p.pc?.close();
    }
    _peers.clear();
    _localStream?.dispose();
    conn.onCallSignal = null;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    conn.onCallSignal = null;
    for (final p in _peers.values) {
      p.pc?.close();
    }
    _localStream?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = _peers.values.map((p) => p.name).toList();
    if (names.isEmpty) names.add(widget.peerName);

    return Scaffold(
      backgroundColor: VColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Icon(
              _anyConnected ? Icons.call : Icons.call_outlined,
              size: 48,
              color: _anyConnected ? VColors.green : VColors.dim,
            ),
            const SizedBox(height: 12),
            Text(
              names.length > 1 ? 'Групповой звонок' : names.first,
              style: const TextStyle(
                fontSize: 22,
                color: VColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: VColors.dim, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              _timer != null ? _elapsedLabel : '00:00',
              style: TextStyle(
                color: _anyConnected ? VColors.green : VColors.dim,
                fontSize: 28,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  for (final p in _peers.values)
                    ListTile(
                      leading: Icon(
                        p.connected ? Icons.phone_in_talk : Icons.phone,
                        color: p.connected ? VColors.green : VColors.dim,
                        size: 20,
                      ),
                      title: Text(
                        p.name,
                        style: const TextStyle(color: VColors.text),
                      ),
                      subtitle: Text(
                        p.connected ? 'на линии' : 'подключение…',
                        style: const TextStyle(
                            color: VColors.dim, fontSize: 11),
                      ),
                    ),
                  if (_peers.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.person, color: VColors.dim),
                      title: Text(widget.peerName,
                          style: const TextStyle(color: VColors.text)),
                      subtitle: Text(_status,
                          style: const TextStyle(
                              color: VColors.dim, fontSize: 11)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundBtn(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    color: _muted ? VColors.red : VColors.surface,
                    onTap: _toggleMute,
                    label: 'микрофон',
                  ),
                  _RoundBtn(
                    icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                    color: _speakerOn ? VColors.green.withOpacity(0.35) : VColors.surface,
                    onTap: _toggleSpeaker,
                    onLongPress: _showAudioSheet,
                    label: _speakerOn ? 'динамик' : 'у уха',
                  ),
                  _RoundBtn(
                    icon: Icons.person_add_alt_1,
                    color: VColors.surface,
                    onTap: _showAddSheet,
                    label: 'добавить',
                  ),
                  _RoundBtn(
                    icon: Icons.call_end,
                    color: VColors.red,
                    onTap: () => _end(local: true),
                    label: 'сброс',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String label;

  const _RoundBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.onLongPress,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(icon, color: VColors.text, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: VColors.dim, fontSize: 11)),
      ],
    );
  }
}
