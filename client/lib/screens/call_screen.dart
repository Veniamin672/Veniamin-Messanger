import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';
import '../theme.dart';
import '../services/connection.dart';

/// Voice-only WebRTC call. Signaling via Veniamin server.
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

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final _remoteRenderer = RTCVideoRenderer();
  bool _connected = false;
  bool _muted = false;
  bool _remoteSet = false;
  String _status = 'connecting…';
  late final String _callId;
  late String _peerTarget;
  final List<RTCIceCandidate> _pendingIce = [];

  ConnectionService get conn => widget.connection;

  @override
  void initState() {
    super.initState();
    _callId = conn.activeCallId ?? const Uuid().v4();
    conn.activeCallId = _callId;
    _peerTarget = widget.peerUuid;
    conn.callPeerUuid = widget.peerUuid;
    conn.callPeerName = widget.peerName;
    conn.onCallSignal = _onSignal;
    _init();
  }

  Future<void> _init() async {
    try {
      await _remoteRenderer.initialize();

      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      };

      _pc = await createPeerConnection(config);

      _pc!.onIceCandidate = (RTCIceCandidate c) {
        if (c.candidate != null && c.candidate!.isNotEmpty) {
          conn.sendIce(_peerTarget, _callId, {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          });
        }
      };

      _pc!.onIceConnectionState = (RTCIceConnectionState state) {
        if (!mounted) return;
        setState(() {
          switch (state) {
            case RTCIceConnectionState.RTCIceConnectionStateConnected:
            case RTCIceConnectionState.RTCIceConnectionStateCompleted:
              _connected = true;
              _status = 'connected';
              break;
            case RTCIceConnectionState.RTCIceConnectionStateChecking:
              _status = 'connecting…';
              break;
            case RTCIceConnectionState.RTCIceConnectionStateFailed:
              _status = 'failed';
              break;
            case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
              _status = 'disconnected';
              break;
            default:
              break;
          }
        });
      };

      _pc!.onConnectionState = (RTCPeerConnectionState state) {
        if (!mounted) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() {
            _connected = true;
            _status = 'connected';
          });
        }
      };

      _pc!.onTrack = (RTCTrackEvent event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer.srcObject = event.streams[0];
        }
        for (final track in event.streams.expand((s) => s.getAudioTracks())) {
          track.enabled = true;
        }
        try {
          Helper.setSpeakerphoneOn(true);
        } catch (_) {}
      };

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
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = true;
        await _pc!.addTrack(track, _localStream!);
      }
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}

      if (widget.isIncoming) {
        setState(() => _status = 'incoming call…');
      } else {
        setState(() => _status = 'calling ${widget.peerName}…');
        final offer = await _pc!.createOffer({
          'offerToReceiveAudio': 1,
          'offerToReceiveVideo': 0,
        });
        await _pc!.setLocalDescription(offer);
        conn.sendCallOffer(_peerTarget, _callId, {
          'type': offer.type,
          'sdp': offer.sdp,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'error: $e');
      }
    }
  }

  Future<void> _drainIce() async {
    for (final c in _pendingIce) {
      try {
        await _pc?.addCandidate(c);
      } catch (_) {}
    }
    _pendingIce.clear();
    // also drain from connection service buffer
    for (final raw in List<Map<String, dynamic>>.from(conn.iceCandidates)) {
      try {
        await _pc?.addCandidate(RTCIceCandidate(
          raw['candidate'],
          raw['sdpMid'],
          raw['sdpMLineIndex'],
        ));
      } catch (_) {}
    }
    conn.iceCandidates.clear();
  }

  Future<void> _acceptIncoming() async {
    if (conn.lastOfferSdp == null) {
      setState(() => _status = 'no offer received');
      return;
    }
    try {
      setState(() => _status = 'answering…');
      final offer = RTCSessionDescription(
        conn.lastOfferSdp!['sdp'] as String?,
        conn.lastOfferSdp!['type'] as String?,
      );
      await _pc!.setRemoteDescription(offer);
      _remoteSet = true;
      await _drainIce();

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _pc!.setLocalDescription(answer);
      conn.sendCallAnswer(_peerTarget, _callId, {
        'type': answer.type,
        'sdp': answer.sdp,
      });
      setState(() => _status = 'connecting…');
    } catch (e) {
      if (mounted) setState(() => _status = 'answer error: $e');
    }
  }

  void _onSignal(Map<String, dynamic> packet) async {
    final type = packet['type'];
    try {
      if (type == 'call_busy') {
        final msg = packet['message']?.toString() ??
            'Линия этого абонента занята, попробуйте перезвонить позже';
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF2D2D30),
              title: const Text(
                'Линия занята',
                style: TextStyle(color: Color(0xFFFF6B6B)),
              ),
              content: Text(
                msg,
                style: const TextStyle(color: Color(0xFFD4D4D4)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK', style: TextStyle(color: Color(0xFF007c42))),
                ),
              ],
            ),
          );
          if (mounted) Navigator.of(context).pop();
        }
        return;
      }
      if (type == 'call_answered' && packet['sdp'] != null) {
        if (packet['from_uuid'] != null) {
          _peerTarget = packet['from_uuid'] as String;
          conn.callPeerUuid = _peerTarget;
        }
        final sdp = Map<String, dynamic>.from(packet['sdp'] as Map);
        await _pc?.setRemoteDescription(
          RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?),
        );
        _remoteSet = true;
        await _drainIce();
        if (mounted) setState(() => _status = 'connecting…');
      } else if (type == 'call_ice_candidate' && packet['candidate'] != null) {
        final c = Map<String, dynamic>.from(packet['candidate'] as Map);
        final ice = RTCIceCandidate(
          c['candidate'] as String?,
          c['sdpMid'] as String?,
          c['sdpMLineIndex'] as int?,
        );
        if (_remoteSet) {
          await _pc?.addCandidate(ice);
        } else {
          _pendingIce.add(ice);
        }
      } else if (type == 'call_ended') {
        _end(local: false);
      }
    } catch (e) {
      debugPrint('call signal error: $e');
    }
  }

  void _toggleMute() {
    if (_localStream == null) return;
    for (final t in _localStream!.getAudioTracks()) {
      t.enabled = !t.enabled;
    }
    setState(() => _muted = !_muted);
  }

  void _end({bool local = true}) {
    if (local) conn.hangup();
    _pc?.close();
    _localStream?.dispose();
    _remoteRenderer.dispose();
    conn.onCallSignal = null;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    conn.onCallSignal = null;
    _pc?.close();
    _localStream?.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VColors.bg,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _connected ? Icons.call : Icons.call_outlined,
                size: 48,
                color: _connected ? VColors.green : VColors.dim,
              ),
              const SizedBox(height: 16),
              Text(
                widget.peerName,
                style: const TextStyle(
                  fontSize: 22,
                  color: VColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style: const TextStyle(color: VColors.dim, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              // keep remote audio alive
              SizedBox(
                width: 1,
                height: 1,
                child: RTCVideoView(_remoteRenderer),
              ),
              const SizedBox(height: 48),
              if (widget.isIncoming && !_connected && _status.contains('incoming'))
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundBtn(
                      icon: Icons.call_end,
                      color: VColors.red,
                      onTap: () {
                        conn.rejectCall();
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: 32),
                    _RoundBtn(
                      icon: Icons.call,
                      color: VColors.green,
                      onTap: _acceptIncoming,
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _RoundBtn(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      color: _muted ? VColors.yellow : VColors.blue,
                      onTap: _toggleMute,
                    ),
                    const SizedBox(width: 32),
                    _RoundBtn(
                      icon: Icons.call_end,
                      color: VColors.red,
                      onTap: () => _end(local: true),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Icon(icon, color: color, size: 28),
        ),
      ),
    );
  }
}
