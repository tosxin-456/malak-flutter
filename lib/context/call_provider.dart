import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:malak/config/api_config.dart';
import 'package:malak/context/socket_provider.dart';
import 'package:malak/services/storage_service.dart';
import 'package:malak/utils/agora_uid.dart';
import 'package:permission_handler/permission_handler.dart';

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
      callType: normalizeCallType(j['callType']),
      channel: j['channel']?.toString() ?? '',
      chatId: j['chatId']?.toString(),
      consultId: j['consultId']?.toString(),
      uid: _parseUid(j['uid']),
      callId: j['callId']?.toString() ?? '',
    );
  }

  static int _parseUid(dynamic uid) {
    if (uid is int) return uid;
    if (uid is num) return uid.toInt();
    return toAgoraUid(uid);
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
  final SocketNotifier _socketNotifier;

  CallProvider({
    required this.userId,
    required this.userInfo,
    required SocketNotifier socketNotifier,
  }) : _socketNotifier = socketNotifier {
    _socketNotifier.addListener(_onSocketNotifierChanged);
    _attachSocket(_socketNotifier.socket);
  }

  // ── State ──────────────────────────────────────────────────────────────────

  io.Socket? _socket;
  io.Socket? get socket => _socket;

  String? _activeChannel;
  String? get activeChannel => _activeChannel;

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

  int? _agoraUid;
  int? get agoraUid => _agoraUid;

  bool _localAudioEnabled = true;
  bool get localAudioEnabled => _localAudioEnabled;

  bool _localVideoEnabled = true;
  bool get localVideoEnabled => _localVideoEnabled;

  int? _localUid;
  int? get localUid => _localUid;

  final List<int> _remoteUids = [];
  List<int> get remoteUids => List.unmodifiable(_remoteUids);

  String _agoraAppId = agoraAppIdFallback;
  bool _agoraConfigLoaded = false;
  String _activeMediaType = 'voice';

  // ── Shared socket wiring ───────────────────────────────────────────────────

  void _onSocketNotifierChanged() {
    _attachSocket(_socketNotifier.socket);
  }

  void _attachSocket(io.Socket? next) {
    if (identical(next, _socket)) return;
    _detachCallListeners();
    _socket = next;
    if (_socket != null) {
      _registerCallListeners();
    }
  }

  void _detachCallListeners() {
    final s = _socket;
    if (s == null) return;
    s.off('call:incoming');
    s.off('call:outgoing');
    s.off('call:answered');
    s.off('call:end');
    s.off('call:rejected');
    s.off('call:missed');
  }

  void _registerCallListeners() {
    final s = _socket;
    if (s == null) return;

    s.on('call:incoming', (data) {
      handleIncomingFromPush(Map<String, dynamic>.from(data as Map));
    });

    s.on('call:outgoing', (data) {
      final d = Map<String, dynamic>.from(data as Map);
      _currentCallId = d['callId']?.toString();
      if (d['callType'] != null) {
        _callType = normalizeCallType(d['callType']);
      }
      notifyListeners();
    });

    s.on('call:answered', (data) async {
      debugPrint('✅ Call answered: $data');
      final d = Map<String, dynamic>.from(data as Map);
      _currentCallId = d['callId']?.toString();
      _currentCallee = CalleeInfo(
        id: d['fromId']?.toString() ?? '',
        fullName: d['from']?.toString() ?? '',
        profileImage: d['profile_image']?.toString(),
      );
      final mediaType = normalizeCallType(d['callType']);
      _callType = mediaType;
      _incomingCall = null;
      _callMode = CallMode.inCall;
      notifyListeners();

      if (_engine == null && d['channel'] != null) {
        try {
          await _initAgora(d['channel'].toString(), mediaType);
        } catch (e) {
          debugPrint('❌ Failed to join after answer: $e');
          await endCall(shouldEmit: true);
          return;
        }
      } else {
        _callMode = CallMode.inCall;
      }
      notifyListeners();
    });

    s.on('call:end', (_) {
      debugPrint('❌ Received call:end');
      endCall(shouldEmit: false);
    });

    s.on('call:rejected', (_) {
      debugPrint('🚫 Call rejected');
      endCall(shouldEmit: false);
    });

    s.on('call:missed', (_) {
      debugPrint('⏰ Call missed');
      endCall(shouldEmit: false);
    });
  }

  Future<void> _loadAgoraConfig() async {
    if (_agoraConfigLoaded) return;
    try {
      final token = await StorageService.getToken();
      final res = await http.get(
        Uri.parse('$API_BASE_URL/agora/config'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        final appId = body['appId']?.toString();
        if (appId != null && appId.isNotEmpty) {
          _agoraAppId = appId;
        }
      }
    } catch (e) {
      debugPrint('Could not load Agora config: $e');
    } finally {
      _agoraConfigLoaded = true;
    }
  }

  Future<void> _activateLocalMedia() async {
    final engine = _engine;
    if (engine == null) return;

    await engine.enableLocalAudio(true);
    await engine.muteLocalAudioStream(false);
    await engine.adjustRecordingSignalVolume(100);
    await engine.adjustPlaybackSignalVolume(100);
    _localAudioEnabled = true;

    if (_activeMediaType == 'video') {
      await engine.enableLocalVideo(true);
      await engine.muteLocalVideoStream(false);
      _localVideoEnabled = true;
    }

    if (_activeMediaType == 'voice') {
      await engine.setDefaultAudioRouteToSpeakerphone(true);
      await engine.setEnableSpeakerphone(true);
      _speakerEnabled = true;
    }

    await engine.updateChannelMediaOptions(
      ChannelMediaOptions(
        publishMicrophoneTrack: true,
        publishCameraTrack: _activeMediaType == 'video',
        autoSubscribeAudio: true,
        autoSubscribeVideo: _activeMediaType == 'video',
      ),
    );
    notifyListeners();
  }

  Future<bool> _ensureCallPermissions(String mediaType) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      debugPrint('❌ Microphone permission denied');
      return false;
    }
    if (mediaType == 'video') {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        debugPrint('❌ Camera permission denied');
        return false;
      }
    }
    return true;
  }

  // ── Agora Init ─────────────────────────────────────────────────────────────

  Future<void> _initAgora(String channel, String callTypeParam) async {
    final mediaType = normalizeCallType(callTypeParam);
    _activeMediaType = mediaType;

    if (!await _ensureCallPermissions(mediaType)) {
      throw Exception('Microphone or camera permission denied');
    }

    await _loadAgoraConfig();

    final joinUid = toAgoraUid(userId);
    _agoraUid = joinUid;
    _activeChannel = channel;

    debugPrint('Initializing Agora — channel: $channel, type: $mediaType, uid: $joinUid');

    if (_engine != null) {
      await _cleanupAgora();
    }

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

    final body = json.decode(res.body) as Map<String, dynamic>;
    final agoraToken = body['token']?.toString() ?? '';
    final tokenUid = body['uid'];
    final resolvedUid = tokenUid is int
        ? tokenUid
        : (tokenUid is num ? tokenUid.toInt() : joinUid);
    _agoraUid = resolvedUid;

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: _agoraAppId));

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) async {
          _localUid = connection.localUid;
          debugPrint('✅ Joined Agora channel, uid: $_localUid');
          await _activateLocalMedia();
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          debugPrint('👤 Remote user joined: $remoteUid');
          if (!_remoteUids.contains(remoteUid)) {
            _remoteUids.add(remoteUid);
          }
          notifyListeners();
        },
        onUserOffline: (connection, remoteUid, reason) {
          debugPrint('👤 Remote user left: $remoteUid');
          _remoteUids.remove(remoteUid);
          notifyListeners();
        },
      ),
    );

    await _engine!.enableAudio();
    if (mediaType == 'video') {
      await _engine!.enableVideo();
      await _engine!.startPreview();
    }

    await _engine!.joinChannel(
      token: agoraToken,
      channelId: channel,
      uid: resolvedUid,
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishMicrophoneTrack: true,
        publishCameraTrack: mediaType == 'video',
        autoSubscribeAudio: true,
        autoSubscribeVideo: mediaType == 'video',
      ),
    );

    await _activateLocalMedia();

    debugPrint('✅ Agora join requested');
  }

  /// Socket or FCM — show incoming call UI.
  void handleIncomingFromPush(Map<String, dynamic> data) {
    debugPrint('📞 Incoming call: $data');
    final fromId = data['fromId']?.toString() ?? '';
    if (fromId.isEmpty || fromId == userId) {
      debugPrint('Ignoring invalid or self incoming call');
      return;
    }

    final callId = data['callId']?.toString() ?? '';
    if (_callMode == CallMode.ringing &&
        (_incomingCall?.callId == callId || _currentCallId == callId)) {
      return;
    }

    if (_callMode == CallMode.inCall || _callMode == CallMode.calling) {
      debugPrint('Ignoring incoming call — already in a call');
      return;
    }

    _incomingCall = IncomingCallData.fromJson(data);
    _currentCallId = callId.isNotEmpty ? callId : _incomingCall?.callId;
    _callMode = CallMode.ringing;
    _callType = normalizeCallType(data['callType']);
    _activeChatId = data['chatId']?.toString();
    final consult = data['consultId']?.toString();
    _activeConsultId = consult != null && consult.isNotEmpty ? consult : null;
    notifyListeners();
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

    final mediaType = normalizeCallType(type);
    debugPrint('🔥 Starting $mediaType call to ${otherParticipant['fullName']}');

    if (otherId == userId) {
      debugPrint('❌ Cannot call yourself');
      return;
    }

    final channel = consultId != null
        ? 'consult-$consultId'
        : ([userId, otherId]..sort()).join('-');

    _currentCallee = CalleeInfo(
      id: otherId,
      fullName: otherParticipant['fullName']?.toString() ?? '',
      profileImage: otherParticipant['profile_image']?.toString(),
    );
    _callType = mediaType;
    _activeChatId = chatId;
    _activeConsultId = consultId;
    _callMode = CallMode.calling;
    _activeChannel = channel;
    notifyListeners();

    try {
      await _initAgora(channel, mediaType);
    } catch (e) {
      debugPrint('❌ Failed to init Agora for outgoing call: $e');
      await endCall(shouldEmit: false);
      return;
    }

    _socket!.emit('call:incoming', {
      'to': otherId,
      'from': userId,
      'callType': mediaType,
      'channel': channel,
      'uid': toAgoraUid(userId),
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

    if (_socket == null || !_socket!.connected) {
      debugPrint('❌ Socket not connected');
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
    _callType = _incomingCall!.callType;

    final temp = _incomingCall!;
    _incomingCall = null;
    _callMode = CallMode.inCall;
    notifyListeners();

    try {
      await _initAgora(temp.channel, temp.callType);

      _socket!.emit('call:answered', {
        'to': temp.fromId,
        'from': userId,
        'callType': temp.callType,
        'channel': temp.channel,
        'chatId': temp.chatId,
        'consultId': temp.consultId,
        'callId': temp.callId,
        'uid': toAgoraUid(userId),
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
    final engine = _engine;
    if (engine != null) {
      await engine.setEnableSpeakerphone(_speakerEnabled);
      await engine.adjustPlaybackSignalVolume(_speakerEnabled ? 100 : 0);
    }
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
        final recipientId = _currentCallee?.id ?? _incomingCall?.fromId;

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

  Future<void> startScreenShare() async {
    debugPrint('Screen share requested — implement per platform');
  }

  Future<void> toggleAudio() async {
    _localAudioEnabled = !_localAudioEnabled;
    final engine = _engine;
    if (engine == null) return;

    if (_localAudioEnabled) {
      await engine.enableLocalAudio(true);
      await engine.muteLocalAudioStream(false);
      await engine.adjustRecordingSignalVolume(100);
    } else {
      await engine.muteLocalAudioStream(true);
    }
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    _localVideoEnabled = !_localVideoEnabled;
    final engine = _engine;
    if (engine == null) return;

    if (_localVideoEnabled) {
      await engine.enableLocalVideo(true);
      await engine.muteLocalVideoStream(false);
    } else {
      await engine.muteLocalVideoStream(true);
    }
    notifyListeners();
  }

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
    _agoraUid = null;
    _activeChannel = null;
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
    _socketNotifier.removeListener(_onSocketNotifierChanged);
    _detachCallListeners();
    _cleanupAgora();
    super.dispose();
  }
}
