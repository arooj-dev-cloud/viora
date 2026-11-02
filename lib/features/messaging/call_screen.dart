import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/viora_theme.dart';

/// One-to-one WebRTC call. Supabase stores offers, answers and ICE signals;
/// media itself is peer-to-peer (with a public STUN server for development).
class CallScreen extends StatefulWidget {
  static bool isCallActive = false;
  const CallScreen({
    super.key,
    this.callId,
    this.participantName,
    required this.incoming,
    this.conversationId,
    this.calleeId,
    this.mediaType = 'audio',
    this.avatarUrl,
  });
  final String? callId;
  final String? participantName;
  final bool incoming;
  final String? conversationId;
  final String? calleeId;
  final String mediaType;
  final String? avatarUrl;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  final _client = Supabase.instance.client;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  RealtimeChannel? _callChannel;
  RealtimeChannel? _signalChannel;
  RTCPeerConnection? _peer;
  MediaStream? _local;
  MediaStream? _remoteOnlyStream;
  bool _video = false;
  bool _connecting = true;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speaker = true;
  bool _finished = false;
  String _status = 'Connecting securely…';
  String? _error;
  DateTime? _connectedAt;
  Timer? _durationTimer;
  Timer? _ringTimer;
  Timer? _answerPoll;
  Timer? _signalPoll;
  final Set<String> _seenSignals = <String>{};
  String _duration = '00:00';
  late String _callId;
  bool _sessionReady = false;
  bool _answerApplied = false;
  bool _answerApplying = false;
  bool _remoteDescriptionReady = false;
  final List<Map<String, dynamic>> _pendingCandidates = [];
  final List<Map<String, dynamic>> _pendingRemoteCandidates = [];
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();
  Timer? _connectTimeout;
  Timer? _disconnectTimer;
  Timer? _ringAlert;
  bool _failing = false;
  bool _relayFound = false;
  String _iceState = 'starting';

  @override
  void initState() {
    super.initState();
    CallScreen.isCallActive = true;
    _callId = widget.callId ?? const Uuid().v4();
    if (widget.incoming) _startRingAlert();
    _start();
  }

  /// Vibrate + soft system sound while an incoming call is waiting.
  void _startRingAlert() {
    void ring() {
      if (_finished || _peer != null || !mounted) return;
      HapticFeedback.vibrate();
      SystemSound.play(SystemSoundType.alert);
    }

    ring();
    _ringAlert = Timer.periodic(const Duration(milliseconds: 2400), (_) => ring());
  }

  void _stopRingAlert() {
    _ringAlert?.cancel();
    _ringAlert = null;
  }

  /// Show a short failure message, then close the call by itself.
  void _failCall(String message) {
    if (_failing || _finished) return;
    _failing = true;
    _connectTimeout?.cancel();
    if (mounted) {
      setState(() {
        _status = message;
        _error = _relayFound
            ? null
            : 'No relay server was reachable, so the two phones could not '
            'find each other across networks. Add TURN_* values to .env '
            '(see CALLS_SETUP.md).';
        _connecting = false;
      });
    }
    Timer(const Duration(seconds: 5), () {
      if (mounted && !_finished) unawaited(_hangUp());
    });
  }

  void _armConnectTimeout() {
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 30), () {
      if (_connectedAt == null) _failCall('Call failed');
    });
  }

  Future<void> _start() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      final row = widget.incoming
          ? await _client
          .from('call_sessions')
          .select()
          .eq('id', _callId)
          .single()
          : null;
      if (widget.incoming && row?['status'] != 'ringing') {
        throw StateError('This call is no longer available.');
      }
      _video = widget.incoming
          ? row!['media_type'] == 'video'
          : widget.mediaType == 'video';
      _speaker = _video; // voice calls start on the earpiece, video on speaker
      _status = widget.incoming
          ? 'Incoming ${_video ? 'video' : 'voice'} call'
          : 'Calling…';
      if (widget.incoming) {
        _sessionReady = true;
        _callChannel = _client
            .channel('viora-call-$_callId')
            .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _callId,
          ),
          callback: (payload) {
            final updated = payload.newRecord;
            if (updated['status'] == 'ended' ||
                updated['status'] == 'missed') {
              _closeRemote();
            }
          },
        )
            .subscribe();
        final latest = await _client
            .from('call_sessions')
            .select('status')
            .eq('id', _callId)
            .single();
        if (latest['status'] != 'ringing') {
          throw StateError('This call has already ended.');
        }
      } else {
        await _preparePeer();
        final offer = await _peer!.createOffer();
        await _peer!.setLocalDescription(offer);
        await _listenForSignals();
        await _client.rpc(
          'begin_call_session',
          params: {
            'p_call_id': _callId,
            'p_conversation_id': widget.conversationId,
            'p_callee_id': widget.calleeId,
            'p_media_type': widget.mediaType,
            'p_offer_sdp': jsonDecode(jsonEncode(offer.toMap())),
          },
        );
        if (_finished) {
          // Hung up while the call was still being created: close it now so
          // it does not keep ringing on the other phone.
          unawaited(_client.rpc('finish_call_session',
              params: {'p_call_id': _callId, 'p_status': 'ended'}));
          return;
        }
        _status = 'Ringing…';
        _ringTimer = Timer(const Duration(seconds: 45), () {
          if (_connectedAt == null && mounted) {
            unawaited(_hangUp(status: 'missed'));
          }
        });
        _sessionReady = true;
        for (final candidate in _pendingCandidates) {
          unawaited(_sendCandidateSafely(candidate));
        }
        _pendingCandidates.clear();
        _callChannel = _client
            .channel('viora-call-$_callId')
            .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _callId,
          ),
          callback: (payload) {
            final updated = payload.newRecord;
            if (updated['answer_sdp'] != null) {
              unawaited(_applyAnswerSafely(updated['answer_sdp'] as Map));
            }
            if (updated['status'] == 'ended' ||
                updated['status'] == 'rejected' ||
                updated['status'] == 'missed') {
              _closeRemote();
            }
          },
        )
            .subscribe();
        // Fallback: poll for the answer in case a realtime event is missed.
        _answerPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
          if (_answerApplied || _finished || !mounted) return;
          try {
            final latest = await _client
                .from('call_sessions')
                .select('answer_sdp,status')
                .eq('id', _callId)
                .single();
            if (latest['answer_sdp'] != null) {
              unawaited(_applyAnswerSafely(latest['answer_sdp'] as Map));
            }
            final st = latest['status'];
            if (st == 'ended' || st == 'rejected' || st == 'missed') {
              _closeRemote();
            }
          } catch (_) {}
        });
        final current = await _client
            .from('call_sessions')
            .select('answer_sdp,status')
            .eq('id', _callId)
            .single();
        if (current['answer_sdp'] != null) {
          await _applyAnswer(current['answer_sdp'] as Map);
        }
        if (current['status'] == 'ended' || current['status'] == 'rejected') {
          _closeRemote();
        }
      }
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (_isCallGone(e)) {
        _closeRemote();
        return;
      }
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
          _connecting = false;
          _status = 'Could not start call';
        });
        Timer(const Duration(seconds: 4), () {
          if (mounted && !_finished) unawaited(_hangUp());
        });
      }
    }
  }

  String _friendlyError(Object e) {
    final t = e.toString().toLowerCase();
    if (t.contains('permission') || t.contains('notallowed') || t.contains('denied')) {
      return 'Viora needs microphone${_video ? ' and camera' : ''} access. '
          'Allow it in your phone settings and try again.';
    }
    if (t.contains('socket') || t.contains('network') || t.contains('timeout')) {
      return 'No internet connection. Check your network and try again.';
    }
    if (t.contains('begin_call_session') || t.contains('pgrst202') || t.contains('42883')) {
      return 'Calls are not set up on the server yet. Run sql/viora_calls.sql in Supabase.';
    }
    return 'Something went wrong starting the call.';
  }

  /// True when the failure only means the call was already ended, cancelled
  /// or answered elsewhere. These are normal and should never be shown as
  /// an error to the person using the app.
  bool _isCallGone(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('no longer available') ||
        text.contains('already ended') ||
        text.contains('p0001') ||
        text.contains('pgrst116');
  }

  Future<void> _preparePeer() async {
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': _video ? {'facingMode': 'user'} : false,
    });
    _localRenderer.srcObject = _local;
    final iceServers = await _loadIceServers();
    _peer = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    for (final track in _local!.getTracks()) {
      await _peer!.addTrack(track, _local!);
    }
    await Helper.setSpeakerphoneOn(_speaker);
    _peer!.onTrack = (event) => unawaited(_attachRemoteTrack(event));
    _peer!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      if (candidate.candidate!.contains(' typ relay') && !_relayFound) {
        _relayFound = true;
        if (mounted) setState(() {});
      }
      final data = Map<String, dynamic>.from(candidate.toMap());
      if (!_sessionReady) {
        _pendingCandidates.add(data);
      } else {
        unawaited(_sendCandidateSafely(data));
      }
    };
    _peer!.onIceConnectionState = (state) {
      _iceState = state.name.replaceFirst('RTCIceConnectionState', '');
      if (mounted) setState(() {});
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _markConnected();
      }
    };
    _peer!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _disconnectTimer?.cancel();
        _connectTimeout?.cancel();
        _markConnected();
        if (mounted) {
          setState(() {
            _status = 'Connected';
            _error = null;
          });
        }
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _failCall('Call failed');
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected &&
          mounted &&
          _connectedAt != null) {
        setState(() => _status = 'Reconnecting…');
        _disconnectTimer?.cancel();
        _disconnectTimer = Timer(const Duration(seconds: 15), () {
          if (!_finished) _failCall('Connection lost');
        });
      }
    };
  }

  Future<void> _attachRemoteTrack(RTCTrackEvent event) async {
    try {
      // Some peers deliver audio and video in separate stream events (or no
      // stream at all). Keep one renderer stream and add each received track;
      // replacing srcObject for every event can leave the video renderer
      // showing only the last track/stream.
      final stream = _remoteOnlyStream ??
          await createLocalMediaStream('viora-remote-$_callId');
      _remoteOnlyStream = stream;
      final hasTrack = stream.getTracks().any((track) => track.id == event.track.id);
      if (!hasTrack) await stream.addTrack(event.track);
      _remoteRenderer.srcObject = stream;
      // Receiving either media kind confirms that the call is live, even if
      // the platform's aggregate peer connection callback arrives late.
      _markConnected();
      if (mounted) setState(() {});
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Remote media could not be attached: $error');
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadIceServers() async {
    try {
      final response = await _client.functions.invoke('turn-credentials');
      final data = response.data;
      if (response.status == 200 && data is Map && data['iceServers'] is List) {
        return (data['iceServers'] as List)
            .whereType<Map>()
            .map((server) => Map<String, dynamic>.from(server))
            .toList();
      }
      return AppConfig.stunIceServers;
    } on FunctionException {
      return AppConfig.stunIceServers;
    } on Exception {
      return AppConfig.stunIceServers;
    }
  }

  Future<void> _listenForSignals() async {
    _signalChannel = _client
        .channel('viora-signals-$_callId-${_client.auth.currentUser!.id}')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'call_signals',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'call_id',
        value: _callId,
      ),
      callback: (payload) {
        final record = payload.newRecord;
        if (record['sender_id'] == _client.auth.currentUser!.id) return;
        final data = Map<String, dynamic>.from(record['candidate'] as Map);
        if (!_seenSignals.add(jsonEncode(data))) return;
        if (!_remoteDescriptionReady) {
          _pendingRemoteCandidates.add(data);
        } else {
          unawaited(_addRemoteCandidate(data));
        }
      },
    )
        .subscribe();
    // Fetch candidates that were sent before this device subscribed, and keep
    // checking as a fallback for any missed realtime event.
    _signalPoll?.cancel();
    _signalPoll = Timer.periodic(
      const Duration(seconds: 2),
          (_) => unawaited(_pullSignals()),
    );
    unawaited(_pullSignals());
  }

  Future<void> _pullSignals() async {
    if (_finished || !mounted) return;
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    try {
      final rows = await _client
          .from('call_signals')
          .select('candidate,sender_id')
          .eq('call_id', _callId)
          .neq('sender_id', me);
      for (final row in rows) {
        final raw = row['candidate'];
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);
        if (!_seenSignals.add(jsonEncode(data))) continue;
        if (!_remoteDescriptionReady) {
          _pendingRemoteCandidates.add(data);
        } else {
          unawaited(_addRemoteCandidate(data));
        }
      }
    } catch (_) {
      // Realtime remains the primary path.
    }
  }

  Future<void> _sendCandidate(Map<String, dynamic> candidate) =>
      _client.from('call_signals').insert({
        'call_id': _callId,
        'sender_id': _client.auth.currentUser!.id,
        'candidate': candidate,
      });

  Future<void> _sendCandidateSafely(Map<String, dynamic> candidate) async {
    try {
      await _sendCandidate(candidate);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _status = 'Signaling connection interrupted';
          _error = 'Could not send network information: $error';
        });
      }
    }
  }

  Future<void> _addRemoteCandidate(Map<String, dynamic> data) async {
    try {
      await _peer?.addCandidate(
        RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not apply a network candidate: $error');
      }
    }
  }

  Future<void> _flushRemoteCandidates() async {
    _remoteDescriptionReady = true;
    final pending = List<Map<String, dynamic>>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      await _addRemoteCandidate(candidate);
    }
  }

  Future<void> _applyAnswer(Map<dynamic, dynamic> value) async {
    if (_answerApplied || _answerApplying || _peer == null) return;
    _answerApplying = true;
    _ringTimer?.cancel();
    _stopRingAlert();
    _armConnectTimeout();
    if (mounted) setState(() => _status = 'Connecting…');
    try {
      final answer = Map<String, dynamic>.from(value);
      await _peer!.setRemoteDescription(
        RTCSessionDescription(
          answer['sdp'] as String?,
          answer['type'] as String?,
        ),
      );
      _answerApplied = true;
      await _flushRemoteCandidates();
    } finally {
      _answerApplying = false;
    }
  }

  Future<void> _applyAnswerSafely(Map<dynamic, dynamic> value) async {
    try {
      await _applyAnswer(value);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _status = 'Could not connect the call';
          _error = 'The call answer could not be applied: $error';
        });
      }
    }
  }

  Future<void> _accept() async {
    _stopRingAlert();
    _armConnectTimeout();
    setState(() {
      _connecting = true;
      _status = 'Joining call…';
    });
    try {
      final row = await _client
          .from('call_sessions')
          .select()
          .eq('id', _callId)
          .single();
      await _preparePeer();
      await _listenForSignals();
      final offer = Map<String, dynamic>.from(row['offer_sdp'] as Map);
      await _peer!.setRemoteDescription(
        RTCSessionDescription(
          offer['sdp'] as String?,
          offer['type'] as String?,
        ),
      );
      await _flushRemoteCandidates();
      final answer = await _peer!.createAnswer();
      await _peer!.setLocalDescription(answer);
      await _client.rpc(
        'answer_call_session',
        params: {
          'p_call_id': _callId,
          'p_answer_sdp': jsonDecode(jsonEncode(answer.toMap())),
        },
      );
      _sessionReady = true;
      for (final candidate in _pendingCandidates) {
        unawaited(_sendCandidateSafely(candidate));
      }
      _pendingCandidates.clear();
      if (mounted) {
        setState(() {
          _connecting = false;
          _status = 'Connecting…';
        });
      }
    } catch (e) {
      if (_isCallGone(e)) {
        _closeRemote();
        return;
      }
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = _friendlyError(e);
        });
      }
    }
  }

  void _markConnected() {
    if (!mounted || _connectedAt != null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _connectedAt = DateTime.now();
      _status = 'Connected';
    });
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final seconds = DateTime.now().difference(_connectedAt!).inSeconds;
      setState(
            () => _duration =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
      );
    });
  }

  Future<void> _hangUp({String status = 'ended'}) async {
    if (_finished) return;
    _finished = true;
    _stopRingAlert();
    try {
      await _client.rpc(
        'finish_call_session',
        params: {'p_call_id': _callId, 'p_status': status},
      );
    } on Object catch (error) {
      // The call is usually already over (the other person hung up first).
      // That is harmless, so it is logged instead of shown.
      debugPrint('Call status update skipped: $error');
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = 'Could not switch camera: $error');
    }
  }

  void _closeRemote() {
    _finished = true;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    CallScreen.isCallActive = false;
    _durationTimer?.cancel();
    _ringTimer?.cancel();
    _connectTimeout?.cancel();
    _disconnectTimer?.cancel();
    _ringAlert?.cancel();
    _pulse.dispose();
    _answerPoll?.cancel();
    _signalPoll?.cancel();
    if (!_finished && (widget.incoming || _peer != null)) {
      unawaited(_finishDuringDispose());
    }
    final callChannel = _callChannel;
    final signalChannel = _signalChannel;
    if (callChannel != null) unawaited(_client.removeChannel(callChannel));
    if (signalChannel != null) unawaited(_client.removeChannel(signalChannel));
    _pendingCandidates.clear();
    _pendingRemoteCandidates.clear();
    unawaited(_releaseMedia());
    super.dispose();
  }

  Future<void> _finishDuringDispose() async {
    try {
      await _client.rpc(
        'finish_call_session',
        params: {'p_call_id': _callId, 'p_status': 'ended'},
      );
    } on Exception {
      debugPrint('Could not update call state during call-screen cleanup.');
    }
  }

  Future<void> _releaseMedia() async {
    final local = _local;
    _local = null;
    if (local != null) {
      for (final track in local.getTracks()) {
        await track.stop();
      }
      await local.dispose();
    }
    final peer = _peer;
    _peer = null;
    await peer?.close();
    final remoteOnlyStream = _remoteOnlyStream;
    _remoteOnlyStream = null;
    await remoteOnlyStream?.dispose();
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
  }

  String get _displayName {
    final n = widget.participantName?.trim() ?? '';
    return n.isEmpty ? 'Viora user' : n;
  }

  bool get _showRemoteVideo => _video && _remoteRenderer.srcObject != null;
  bool get _ringing => widget.incoming && _peer == null && !_finished;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_hangUp(status: _ringing ? 'rejected' : 'ended'));
    },
    child: Scaffold(
      backgroundColor: const Color(0xFF0E0616),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_showRemoteVideo)
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            _background(),
          if (_showRemoteVideo)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xAA000000), Color(0x00000000), Color(0xCC000000)],
                  stops: [0, .45, 1],
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: _showRemoteVideo ? const SizedBox() : _centerAvatar(),
                ),
                _bottomBar(),
              ],
            ),
          ),
          if (_video && _localRenderer.srcObject != null && !_ringing)
            Positioned(
              right: 16,
              top: MediaQuery.of(context).padding.top + 78,
              width: 108,
              height: 150,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24, width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 14),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: _cameraOff
                      ? const ColoredBox(
                    color: Color(0xFF22102E),
                    child: Center(
                      child: Icon(Icons.videocam_off, color: Colors.white54),
                    ),
                  )
                      : RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _background() => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF3A1650), Color(0xFF1C0A2B), Color(0xFF0E0616)],
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _video ? Icons.videocam_rounded : Icons.call_rounded,
              size: 14,
              color: VioraColors.blush.withValues(alpha: .8),
            ),
            const SizedBox(width: 6),
            Text(
              'VIORA ${_video ? 'VIDEO' : 'VOICE'} CALL',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: VioraColors.blush.withValues(alpha: .8),
              ),
            ),
          ],
        ),
        if (_showRemoteVideo) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _displayName,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _connectedAt != null ? _duration : _status,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _centerAvatar() {
    final initial = _displayName.characters.first.toUpperCase();
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 260,
              height: 260,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_connectedAt == null)
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Stack(
                        alignment: Alignment.center,
                        children: [
                          for (final offset in const [0.0, .5])
                            _ring((_pulse.value + offset) % 1),
                        ],
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFE586F2), Color(0xFF6667AB)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 70,
                      backgroundColor: VioraColors.mauve,
                      backgroundImage: widget.avatarUrl == null
                          ? null
                          : NetworkImage(widget.avatarUrl!),
                      child: widget.avatarUrl == null
                          ? Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                _connectedAt != null ? _duration : _status,
                key: ValueKey(_connectedAt != null ? 'time' : _status),
                style: TextStyle(
                  fontSize: _connectedAt != null ? 20 : 16,
                  color: VioraColors.silver,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (_connectedAt == null && _peer != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Network: $_iceState · ${_relayFound ? 'relay ready' : 'no relay'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            if (_connecting && _connectedAt == null && _error == null)
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 18, 32, 0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: VioraColors.blush),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ring(double t) => Opacity(
    opacity: (1 - t) * .5,
    child: Container(
      width: 150 + 110 * t,
      height: 150 + 110 * t,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE586F2), width: 2),
      ),
    ),
  );

  Widget _bottomBar() {
    if (_ringing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _bigButton(
              Icons.call_end_rounded,
              const Color(0xFFE5484D),
              'Decline',
                  () => _hangUp(status: 'rejected'),
            ),
            _bigButton(
              _video ? Icons.videocam_rounded : Icons.call_rounded,
              const Color(0xFF30C26B),
              'Accept',
              _accept,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _smallControl(
              _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              _muted ? 'Unmute' : 'Mute',
              _muted,
                  () {
                setState(() => _muted = !_muted);
                for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
                  t.enabled = !_muted;
                }
              },
            ),
            if (_video) ...[
              _smallControl(
                _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                _cameraOff ? 'Camera on' : 'Camera',
                _cameraOff,
                    () {
                  setState(() => _cameraOff = !_cameraOff);
                  for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
                    t.enabled = !_cameraOff;
                  }
                },
              ),
              _smallControl(
                Icons.cameraswitch_rounded,
                'Flip',
                false,
                _switchCamera,
              ),
            ],
            _smallControl(
              _speaker ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded,
              _speaker ? 'Speaker' : 'Earpiece',
              _speaker,
                  () {
                setState(() => _speaker = !_speaker);
                Helper.setSpeakerphoneOn(_speaker);
              },
            ),
            _bigButton(
              Icons.call_end_rounded,
              const Color(0xFFE5484D),
              null,
                  () => _hangUp(),
              size: 60,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bigButton(
      IconData icon,
      Color color,
      String? label,
      VoidCallback action, {
        double size = 72,
      }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 6,
        shadowColor: color.withValues(alpha: .6),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: action,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: size * .45),
          ),
        ),
      ),
      if (label != null) ...[
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    ],
  );

  Widget _smallControl(
      IconData icon,
      String label,
      bool active,
      VoidCallback action,
      ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Material(
        color: active ? Colors.white : Colors.white.withValues(alpha: .14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: action,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              icon,
              size: 24,
              color: active ? const Color(0xFF1C0A2B) : Colors.white,
            ),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
    ],
  );
}
