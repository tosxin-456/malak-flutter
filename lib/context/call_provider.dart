import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum CallMode { idle, calling, ringing, inCall }

class IncomingCallData {
  final String fromId;
  final String from;
  final String? profileImage;
  final String callType; // 'voice' | 'video'
  final String channel;
  final String? chatId;
  final String? consultId;
  final int uid;
  final String callId;

  const IncomingCallData({
    required this.fromId,
    required this.from,
    this.profileImage,
    required this.callType,
    required this.channel,
    this.chatId,
    this.consultId,
    required this.uid,
    required this.callId,
  });

  factory IncomingCallData.fromJson(Map<String, dynamic> j) {
    return IncomingCallData(
      fromId: j['fromId']?.toString() ?? '',
      from: j['from']?.toString() ?? '',
      profileImage: j['profile_image']?.toString(),
      callType: j['callType']?.toString() ?? 'voice',
      channel: j['channel']?.toString() ?? '',
      chatId: j['chatId']?.toString(),
      consultId: j['consultId']?.toString(),
      uid: (j['uid'] ?? 0) as int,
      callId: j['callId']?.toString() ?? '',
    );
  }
}

class CalleeInfo {
  final String id;
  final String fullName;
  final String? profileImage;

  const CalleeInfo({
    required this.id,
    required this.fullName,
    this.profileImage,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CallProvider (ChangeNotifier)
// ─────────────────────────────────────────────────────────────────────────────

class CallProvider extends ChangeNotifier {
  final String userId;
  final Map<String, dynamic> userInfo;

  CallProvider({required this.userId, required this.userInfo}) {
    _initSocket();
  }

  // ── State ──────────────────────────────────────────────────────────────────

  io.Socket? _socket;
  io.Socket? get socket => _socket;

  CallMode _callMode = CallMode.idle;
  CallMode get callMode => _callMode;

  String? _callType;
  String? get callType => _callType;

  IncomingCallData? _incomingCall;
  IncomingCallData? get incomingCall => _incomingCall;

  CalleeInfo? _currentCallee;
  CalleeInfo? get currentCallee => _currentCallee;

  String? _activeChatId;
  String? get activeChatId => _activeChatId;

  String? _currentCallId;
  String? get currentCallId => _currentCallId;

  String? _activeConsultId;
  String? get activeConsultId => _activeConsultId;

  // Agora
  RtcEngine? _engine;
  RtcEngine? get engine => _engine;

  bool _localAudioEnabled = true;
  bool get localAudioEnabled => _localAudioEnabled;

  bool _localVideoEnabled = true;
  bool get localVideoEnabled => _localVideoEnabled;

  int? _localUid;
  int? get localUid => _localUid;

  final List<int> _remoteUids = [];
  List<int> get remoteUids => List.unmodifiable(_remoteUids);

  static const String _agoraAppId = '2b62436b11684c1aa0061759c55592e0';

  // ── Socket Init ────────────────────────────────────────────────────────────

  Future<void> _initSocket() async {
    final token = await StorageService.getToken();
    _socket = io.io(SOCKET_IO, <String, dynamic>{
      'transports': ['websocket'],
      'auth': {'token': token},
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionAttempts': 5,
    });

    _socket!.onConnect((_) {
      debugPrint('✅ CallProvider socket connected: ${_socket!.id}');
      _socket!.emit('user:online', userId);
    });

    _socket!.on('call:incoming', (data) {
      debugPrint('📞 Incoming call: $data');
      final d = Map<String, dynamic>.from(data);
      _incomingCall = IncomingCallData.fromJson(d);
      _currentCallId = d['callId']?.toString();
      _callMode = CallMode.ringing;
      _callType = d['callType']?.toString();
      _activeChatId = d['chatId']?.toString();
      notifyListeners();
    });

    _socket!.on('call:outgoing', (data) {
      final d = Map<String, dynamic>.from(data);
      _currentCallId = d['callId']?.toString();
      notifyListeners();
    });

    _socket!.on('call:answered', (data) {
      debugPrint('✅ Call answered: $data');
      final d = Map<String, dynamic>.from(data);
      _currentCallId = d['callId']?.toString();
      _currentCallee = CalleeInfo(
        id: d['fromId']?.toString() ?? '',
        fullName: d['from']?.toString() ?? '',
        profileImage: d['profile_image']?.toString(),
      );
      _callType = d['callType']?.toString();
      _callMode = CallMode.inCall;
      _incomingCall = null;
      notifyListeners();
    });

    _socket!.on('call:end', (_) {
      debugPrint('❌ Received call:end');
      endCall(shouldEmit: false);
    });

    _socket!.on('call:rejected', (_) {
      debugPrint('🚫 Call rejected');
      endCall(shouldEmit: false);
    });

    _socket!.on('call:missed', (_) {
      debugPrint('⏰ Call missed');
      endCall(shouldEmit: false);
    });

    _socket!.onDisconnect(
      (_) => debugPrint('❌ CallProvider socket disconnected'),
    );
    _socket!.onConnectError((e) => debugPrint('❌ Socket connect error: $e'));
  }

  // ── Agora Init ─────────────────────────────────────────────────────────────

  Future<void> _initAgora(String channel, String callTypeParam) async {
    debugPrint('Initializing Agora — channel: $channel, type: $callTypeParam');

    // Fetch token from backend
    final token = await StorageService.getToken();
    final res = await http.post(
      Uri.parse('$API_BASE_URL/agora/token'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'channelName': channel, 'uid': userId}),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to get Agora token: ${res.statusCode}');
    }

    final agoraToken = json.decode(res.body)['token']?.toString() ?? '';
    debugPrint('Got Agora token');

    // Create & init engine
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: _agoraAppId));

    // Register event handler
    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          _localUid = connection.localUid;
          debugPrint('✅ Joined Agora channel, uid: $_localUid');
          notifyListeners();
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          debugPrint('👤 Remote user joined: $remoteUid');
          _remoteUids.add(remoteUid);
          notifyListeners();
        },
        onUserOffline: (connection, remoteUid, reason) {
          debugPrint('👤 Remote user left: $remoteUid');
          _remoteUids.remove(remoteUid);
          notifyListeners();
        },
      ),
    );

    // Enable audio always; enable video only for video calls
    await _engine!.enableAudio();
    if (callTypeParam == 'video') {
      await _engine!.enableVideo();
      await _engine!.startPreview();
    }

    await _engine!.joinChannel(
      token: agoraToken,
      channelId: channel,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    debugPrint('✅ Agora join requested');
  }

  // ── Start Call ─────────────────────────────────────────────────────────────

  Future<void> startCall(
    String type, {
    required Map<String, dynamic> otherParticipant,
    String? chatId,
    String? consultId,
  }) async {
    final otherId = otherParticipant['_id']?.toString() ?? '';
    if (otherId.isEmpty || (chatId == null && consultId == null)) {
      debugPrint('❌ Missing required parameters for startCall');
      return;
    }

    if (_socket == null || !_socket!.connected) {
      debugPrint('❌ Socket not connected');
      return;
    }

    debugPrint('🔥 Starting $type call to ${otherParticipant['fullName']}');

    final channel = consultId != null
        ? 'consult-$consultId'
        : '$userId-$otherId';

    _currentCallee = CalleeInfo(
      id: otherId,
      fullName: otherParticipant['fullName']?.toString() ?? '',
      profileImage: otherParticipant['profile_image']?.toString(),
    );
    _callType = type;
    _activeChatId = chatId;
    _activeConsultId = consultId;
    _callMode = CallMode.calling;
    notifyListeners();

    try {
      await _initAgora(channel, type);
    } catch (e) {
      debugPrint('❌ Failed to init Agora: $e');
      _callMode = CallMode.idle;
      notifyListeners();
      return;
    }

    _socket!.emit('call:incoming', {
      'to': otherId,
      'from': userId,
      'callType': type,
      'channel': channel,
      'uid': userId,
      if (chatId != null) 'chatId': chatId,
      if (consultId != null) 'consultId': consultId,
    });
  }

  // ── Answer Call ────────────────────────────────────────────────────────────

  Future<void> answerCall() async {
    if (_incomingCall == null) {
      debugPrint('❌ No incoming call to answer');
      return;
    }

    debugPrint('📞 Answering call from: ${_incomingCall!.from}');

    _currentCallee = CalleeInfo(
      id: _incomingCall!.fromId,
      fullName: _incomingCall!.from,
      profileImage: _incomingCall!.profileImage,
    );
    _activeChatId = _incomingCall!.chatId;
    _activeConsultId = _incomingCall!.consultId;
    _currentCallId = _incomingCall!.callId;

    try {
      await _initAgora(_incomingCall!.channel, _incomingCall!.callType);
      _callMode = CallMode.inCall;

      final temp = _incomingCall!;
      _incomingCall = null;
      notifyListeners();

      _socket!.emit('call:answered', {
        'to': temp.fromId,
        'from': userId,
        'callType': temp.callType,
        'channel': temp.channel,
        'chatId': temp.chatId,
        'consultId': temp.consultId,
        'callId': temp.callId,
        'uid': userId,
      });

      debugPrint('✅ Emitted call:answered');
    } catch (e) {
      debugPrint('❌ Failed to answer call: $e');
      await endCall(shouldEmit: false);
    }
  }

  // ── Reject Call ────────────────────────────────────────────────────────────

  bool _speakerEnabled = true;
  bool get speakerEnabled => _speakerEnabled;

  Future<void> toggleSpeaker() async {
    _speakerEnabled = !_speakerEnabled;
    await _engine?.setEnableSpeakerphone(_speakerEnabled);
    notifyListeners();
  }

  Future<void> rejectCall() async {
    if (_incomingCall == null || _socket == null) {
      debugPrint('❌ No incoming call to reject');
      return;
    }

    debugPrint('🚫 Rejecting call from: ${_incomingCall!.fromId}');

    _socket!.emit('call:rejected', {
      'to': _incomingCall!.fromId,
      'chatId': _incomingCall!.chatId,
      'consultId': _incomingCall!.consultId,
      'callId': _incomingCall!.callId,
      'callType': _incomingCall!.callType,
    });

    await _cleanupAgora();
    _resetState();
  }

  // ── End Call ───────────────────────────────────────────────────────────────

  Future<void> endCall({bool shouldEmit = true}) async {
    try {
      debugPrint(
        '🔚 Ending call — shouldEmit: $shouldEmit, callId: $_currentCallId',
      );

      if (shouldEmit && _socket != null && _socket!.connected) {
        String? recipientId = _currentCallee?.id ?? _incomingCall?.fromId;

        if (recipientId != null && _currentCallId != null) {
          _socket!.emit('call:end', {
            'to': recipientId,
            'chatId': _activeChatId,
            'consultId': _activeConsultId,
            'callId': _currentCallId,
            'callType': _callType,
            'from': userId,
          });
          debugPrint('📤 Emitted call:end to: $recipientId');
        }
      }

      await _cleanupAgora();
    } catch (e) {
      debugPrint('❌ Error ending call: $e');
    } finally {
      _resetState();
    }
  }

  // ── Screen Share (stub) ────────────────────────────────────────────────────

  Future<void> startScreenShare() async {
    // Agora Flutter SDK uses `startScreenCapture` — platform-specific
    // implementation required. Wire up when needed.
    debugPrint('Screen share requested — implement per platform');
  }

  // ── Toggle Audio / Video ───────────────────────────────────────────────────

  Future<void> toggleAudio() async {
    _localAudioEnabled = !_localAudioEnabled;
    await _engine?.muteLocalAudioStream(!_localAudioEnabled);
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    _localVideoEnabled = !_localVideoEnabled;
    await _engine?.muteLocalVideoStream(!_localVideoEnabled);
    notifyListeners();
  }

  // ── Cleanup ────────────────────────────────────────────────────────────────

  Future<void> _cleanupAgora() async {
    if (_engine != null) {
      try {
        await _engine!.leaveChannel();
        await _engine!.release();
        debugPrint('✅ Left Agora channel');
      } catch (e) {
        debugPrint('Error leaving Agora: $e');
      }
      _engine = null;
    }
    _remoteUids.clear();
    _localUid = null;
    _localAudioEnabled = true;
    _localVideoEnabled = true;
  }

  void _resetState() {
    _incomingCall = null;
    _currentCallee = null;
    _callMode = CallMode.idle;
    _callType = null;
    _activeChatId = null;
    _activeConsultId = null;
    _currentCallId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanupAgora();
    _socket?.disconnect();
    _socket = null;
    super.dispose();
  }
}
