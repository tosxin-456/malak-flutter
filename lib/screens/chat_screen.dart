import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';
import 'package:malak/widgets/attachment_menu_widget.dart';
import 'package:malak/widgets/audio_message_bubble.dart';
import 'package:malak/widgets/call_buttons_widget.dart';
import 'package:malak/widgets/call_message_bubble.dart';
import 'package:malak/widgets/file_message_bubble.dart';
import 'package:malak/widgets/voice_message_bubble.dart';
import 'package:malak/widgets/voice_recorder_widget.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class ChatScreen extends StatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  bool _loading = true;
  bool _sending = false;
  bool _isTyping = false;

  Map<String, dynamic>? _chat;
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _currentUser;

  // Audio playback state
  String? _playingAudioId;
  Map<String, double> _audioProgress = {};
  Map<String, double> _audioDurations = {};
  double _playbackSpeed = 1.0;

  io.Socket? _socket;
  Timer? _typingTimer;

  // FIX: Track whether socket listeners are registered to avoid duplicates
  bool _socketListenersRegistered = false;

  @override
  void initState() {
    super.initState();
    // FIX: Load current user FIRST, then init socket + chat data
    _bootstrap();
  }

  /// Load user first, then socket and chat in parallel
  Future<void> _bootstrap() async {
    await _fetchCurrentUser(); // must finish first
    await Future.wait([_initSocket(), _fetchChatData()]);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  // ── Socket ────────────────────────────────────────────────────────────────

  Future<void> _initSocket() async {
    final token = await StorageService.getToken();

    _socket = io.io(
      SOCKET_IO,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          // FIX: disable auto-reconnect duplicate listeners
          .disableAutoConnect()
          .build(),
    );

    // FIX: Register all listeners BEFORE connecting
    _registerSocketListeners();

    _socket!.connect();
  }

  void _registerSocketListeners() {
    if (_socketListenersRegistered) return;
    _socketListenersRegistered = true;

    _socket!.onConnect((_) {
      debugPrint('Socket connected');
      _socket!.emit('join_chat', widget.chatId);
    });

    _socket!.onDisconnect((_) {
      debugPrint('Socket disconnected');
    });

    _socket!.onConnectError((err) {
      debugPrint('Socket connect error: $err');
    });

    // FIX: Deduplicate incoming messages — only add if not already present
    _socket!.on('new_message', (data) {
      if (!mounted) return;
      final msg = Map<String, dynamic>.from(data as Map);
      final msgId = msg['_id']?.toString();

      // Avoid duplicates (own sent messages come back from server too)
      final alreadyExists = _messages.any((m) => m['_id']?.toString() == msgId);
      if (!alreadyExists) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    });

    // FIX: Check _currentUser safely — it's guaranteed loaded before socket init now
    _socket!.on('user_typing', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data as Map);
      final isSameChat = d['chatId']?.toString() == widget.chatId;
      final isOtherUser =
          d['userId']?.toString() != _currentUser?['_id']?.toString() &&
          d['userId']?.toString() != _currentUser?['id']?.toString();

      if (isSameChat && isOtherUser) {
        setState(() => _isTyping = true);
      }
    });

    _socket!.on('user_stopped_typing', (data) {
      if (!mounted) return;
      final d = Map<String, dynamic>.from(data as Map);
      final isSameChat = d['chatId']?.toString() == widget.chatId;
      final isOtherUser =
          d['userId']?.toString() != _currentUser?['_id']?.toString() &&
          d['userId']?.toString() != _currentUser?['id']?.toString();

      if (isSameChat && isOtherUser) {
        setState(() => _isTyping = false);
      }
    });
  }

  // ── API ───────────────────────────────────────────────────────────────────

  Future<void> _fetchCurrentUser() async {
    try {
      final token = await StorageService.getToken();
      final res = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200 && mounted) {
        // FIX: use setState so widget rebuilds with user data
        setState(() => _currentUser = json.decode(res.body));
      }
    } catch (e) {
      debugPrint('Error fetching user: $e');
    }
  }

  Future<void> _fetchChatData() async {
    // FIX: setState for loading inside try so it's definitely set
    if (mounted) setState(() => _loading = true);

    try {
      final token = await StorageService.getToken();

      final chatRes = await http.get(
        Uri.parse('$API_BASE_URL/chats/${widget.chatId}'),
        headers: {'Authorization': 'Bearer $token'},
      );

      Map<String, dynamic>? fetchedChat;
      List<Map<String, dynamic>> fetchedMessages = [];

      if (chatRes.statusCode == 200) {
        fetchedChat = json.decode(chatRes.body) as Map<String, dynamic>;
      }

      final msgRes = await http.get(
        Uri.parse('$API_BASE_URL/chats/${widget.chatId}/messages'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (msgRes.statusCode == 200) {
        final List raw = json.decode(msgRes.body) as List;
        fetchedMessages = raw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }

      // FIX: Single setState call with all fetched data so UI rebuilds once
      if (mounted) {
        setState(() {
          _chat = fetchedChat;
          _messages = fetchedMessages;
          _loading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Error fetching chat: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Messaging ─────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    // Stop typing indicator
    _typingTimer?.cancel();
    _typingTimer = null;
    _socket?.emit('typing_stop', {'chatId': widget.chatId});

    // FIX: Clear field immediately for responsive UX
    _msgCtrl.clear();
    setState(() {});

    _socket?.emit('send_message', {'chatId': widget.chatId, 'text': text});
    // NOTE: Do NOT optimistically add the message locally here.
    // The server will broadcast it back via 'new_message' and
    // _registerSocketListeners deduplicates, so it appears exactly once.
  }

  Future<void> _uploadFile(dynamic file, {bool isVoiceNote = false}) async {
    try {
      if (mounted) setState(() => _sending = true);
      final token = await StorageService.getToken();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$API_BASE_URL/chats/${widget.chatId}/messages/file'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
      if (isVoiceNote) req.fields['isVoiceNote'] = 'true';

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);
      if ((res.statusCode == 200 || res.statusCode == 201) && mounted) {
        final newMsg = Map<String, dynamic>.from(json.decode(res.body) as Map);
        setState(() => _messages.add(newMsg));
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('File upload error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    // FIX: double post-frame callback ensures ListView has rendered new items
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  Map<String, dynamic>? get _otherParticipant {
    if (_chat == null || _currentUser == null) return null;
    final parts =
        (_chat!['participants'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    try {
      return parts.firstWhere(
        (p) =>
            p['_id']?.toString() != _currentUser!['_id']?.toString() &&
            p['_id']?.toString() != _currentUser!['id']?.toString(),
      );
    } catch (_) {
      return parts.isNotEmpty ? parts.first : null;
    }
  }

  bool _isMyMessage(Map<String, dynamic> msg) {
    final senderId = msg['sender']?['_id']?.toString();
    return senderId == _currentUser?['_id']?.toString() ||
        senderId == _currentUser?['id']?.toString();
  }

  String _formatMessageTime(String? ts) {
    if (ts == null) return '';
    final dt = DateTime.tryParse(ts)?.toLocal();
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatLastSeen(String? ts) {
    if (ts == null) return 'Offline';
    final date = DateTime.tryParse(ts);
    if (date == null) return 'Offline';
    final diff = DateTime.now().difference(date).inSeconds;
    if (diff < 60) return 'Last seen just now';
    if (diff < 3600) return 'Last seen ${diff ~/ 60} min ago';
    if (diff < 86400) return 'Last seen ${diff ~/ 3600} hours ago';
    return 'Last seen ${date.day}/${date.month}/${date.year}';
  }

  Widget _buildAvatar(Map<String, dynamic>? user, {double radius = 20}) {
    if (user == null) return CircleAvatar(radius: radius);
    final img = user['profile_image']?.toString();
    if (img != null && img.isNotEmpty) {
      final src = img.startsWith('http') ? img : '$IMAGE_URL$img';
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(src));
    }
    final name = user['fullName']?.toString() ?? 'U';
    final initials = name
        .split(' ')
        .map((n) => n.isNotEmpty ? n[0] : '')
        .take(2)
        .join()
        .toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF3B82F6),
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  void _onMessageChanged(String value) {
    setState(() {});
    if (_socket == null) return;

    if (value.trim().isNotEmpty) {
      // Only emit typing_start once per burst, not on every keystroke
      if (_typingTimer == null) {
        _socket!.emit('typing_start', {'chatId': widget.chatId});
      }
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _socket!.emit('typing_stop', {'chatId': widget.chatId});
        _typingTimer = null;
      });
    } else {
      _typingTimer?.cancel();
      _typingTimer = null;
      _socket!.emit('typing_stop', {'chatId': widget.chatId});
    }
  }

  // ── Voice note playback ───────────────────────────────────────────────────

  void _togglePlayVoiceNote(String msgId, String url) {
    // TODO: integrate `audioplayers` package for full playback
    setState(() {
      _playingAudioId = _playingAudioId == msgId ? null : msgId;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    if (_chat == null) return _buildNotFound();

    final other = _otherParticipant;
    final isOnline = other?['isOnline'] == true;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(other, isOnline),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (_, i) {
                  if (_isTyping && i == _messages.length) {
                    return _buildTypingIndicator(other);
                  }
                  return _buildMessageItem(_messages[i]);
                },
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic>? other, bool isOnline) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF374151)),
            onPressed: () => Navigator.pop(context),
          ),
          _buildAvatar(other),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  other?['fullName']?.toString() ?? 'Unknown User',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Color(0xFF111827),
                  ),
                ),
                Text(
                  isOnline
                      ? 'Online'
                      : _formatLastSeen(other?['lastSeen']?.toString()),
                  style: TextStyle(
                    fontSize: 11,
                    color: isOnline
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          CallButtonsWidget(
            otherParticipant: other ?? {},
            chatId: widget.chatId,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg) {
    final mine = _isMyMessage(msg);
    final type = msg['messageType']?.toString() ?? 'text';

    Widget bubble;
    switch (type) {
      case 'image':
        bubble = _buildImageBubble(msg, mine);
        break;
      case 'voice':
        bubble = VoiceMessageBubble(
          msg: msg,
          isMyMessage: mine,
          playingAudioId: _playingAudioId,
          audioProgress: _audioProgress,
          audioDurations: _audioDurations,
          playbackSpeed: _playbackSpeed,
          onTogglePlay: _togglePlayVoiceNote,
          onSpeedChange: (s) => setState(() => _playbackSpeed = s),
        );
        break;
      case 'audio':
        bubble = AudioMessageBubble(msg: msg, isMyMessage: mine);
        break;
      case 'file':
        bubble = FileMessageBubble(msg: msg, isMyMessage: mine);
        break;
      case 'call':
        bubble = CallMessageBubble(msg: msg, isMyMessage: mine);
        break;
      default:
        bubble = _buildTextBubble(msg, mine);
    }

    // FIX: Only wrap text/image in the styled container; others self-style
    final needsContainer = type == 'text' || type == 'image';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: needsContainer
                  ? BoxDecoration(
                      color: mine ? const Color(0xFF3B82F6) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: mine
                          ? null
                          : Border.all(color: const Color(0xFFE5E7EB)),
                    )
                  : null,
              padding: needsContainer
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                  : EdgeInsets.zero,
              child: bubble,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(
                _formatMessageTime(msg['createdAt']?.toString()),
                style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
              ),
              if (mine) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.check_circle,
                  size: 12,
                  color: Color(0xFF3B82F6),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextBubble(Map<String, dynamic> msg, bool mine) {
    return Text(
      msg['content']?['text']?.toString() ?? '',
      style: TextStyle(
        color: mine ? Colors.white : const Color(0xFF1F2937),
        fontSize: 14,
      ),
    );
  }

  Widget _buildImageBubble(Map<String, dynamic> msg, bool mine) {
    final url = msg['content']?['fileUrl']?.toString() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: 220,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
      ),
    );
  }

  Widget _buildTypingIndicator(Map<String, dynamic>? other) {
    final name = other?['fullName']?.toString().split(' ').first ?? 'User';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _BouncingDot(delay: Duration(milliseconds: i * 150)),
                );
              }),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$name is typing...',
            style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          AttachmentMenuWidget(
            disabled: _sending,
            onImageSelected: (f) => _uploadFile(f),
            onFileSelected: (f) => _uploadFile(f),
            onAudioSelected: (f) => _uploadFile(f),
          ),
          VoiceRecorderWidget(
            chatId: widget.chatId,
            onSend: (msg) {
              if (mounted) {
                setState(() => _messages.add(Map<String, dynamic>.from(msg)));
                _scrollToBottom();
              }
            },
            disabled: _sending,
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _msgCtrl,
                onChanged: _onMessageChanged,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  hintStyle: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          if (_msgCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Color(0xFF3B82F6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoading() => const Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF3B82F6)),
          SizedBox(height: 12),
          Text('Loading chat...', style: TextStyle(color: Color(0xFF6B7280))),
        ],
      ),
    ),
  );

  Widget _buildNotFound() => Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Chat not found',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Go back',
              style: TextStyle(color: Color(0xFF3B82F6)),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Bouncing dot for typing indicator ────────────────────────────────────────
class _BouncingDot extends StatefulWidget {
  final Duration delay;
  const _BouncingDot({required this.delay});

  @override
  State<_BouncingDot> createState() => _BouncingDotState();
}

class _BouncingDotState extends State<_BouncingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween(
      begin: 0.0,
      end: -6.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    // FIX: Start repeating after delay, not forward() which only runs once
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, _anim.value),
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF9CA3AF),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
