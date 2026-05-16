import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class _AiMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String text;
  final DateTime timestamp;
  final Map<String, dynamic>? recommendation;

  _AiMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.recommendation,
  });

  bool get isUser => role == 'user';
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class ToppinsAiChatScreen extends StatefulWidget {
  /// Optional: pass an existing sessionId to resume a prior conversation.
  final String? sessionId;

  const ToppinsAiChatScreen({super.key, this.sessionId});

  @override
  State<ToppinsAiChatScreen> createState() => _ToppinsAiChatScreenState();
}

class _ToppinsAiChatScreenState extends State<ToppinsAiChatScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  final List<_AiMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();

  String? _sessionId;
  bool _initializing = true;
  bool _sending = false;
  String? _error;

  // suggestion chips shown before first message
  bool _showSuggestions = true;

  late AnimationController _typingDotCtrl;

  static const _suggestions = [
    'I have a persistent headache and fever',
    'What should I do for a sore throat?',
    'I feel dizzy when I stand up quickly',
    'My chest feels tight after exercise',
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _typingDotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _init();
  }

  @override
  void dispose() {
    _typingDotCtrl.dispose();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── API ────────────────────────────────────────────────────────────────────

  Future<String?> _token() => StorageService.getToken();

  Future<void> _init() async {
    if (widget.sessionId != null) {
      await _loadSession(widget.sessionId!);
    } else {
      await _createSession();
    }
  }

  Future<void> _createSession() async {
    setState(() => _initializing = true);
    try {
      final token = await _token();
      if (token == null) throw Exception('Not authenticated');

      // ── Load all past sessions first ────────────────────────────────────
      final sessionsRes = await http.get(
        Uri.parse('$API_BASE_URL/open-ai/sessions'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (sessionsRes.statusCode.toString().startsWith('2')) {
        final List allSessions = json.decode(sessionsRes.body);
        allSessions.sort((a, b) {
          final aDate = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime(0);
          final bDate = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime(0);
          return aDate.compareTo(bDate);
        });

        for (final session in allSessions) {
          final sid =
              session['_id'] as String? ?? session['sessionId'] as String?;
          if (sid == null) continue;

          final sessionRes = await http.get(
            Uri.parse('$API_BASE_URL/open-ai/session/$sid'),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (!sessionRes.statusCode.toString().startsWith('2')) continue;

          final data = json.decode(sessionRes.body);
          final List msgs = data['messages'] ?? [];
          final fallbackTs =
              DateTime.tryParse(data['updatedAt'] ?? '') ?? DateTime.now();

          for (var i = 0; i < msgs.length; i++) {
            final m = msgs[i] as Map<String, dynamic>;
            if (m['role'] == 'system') continue;

            final rawTs =
                m['createdAt'] as String? ?? m['timestamp'] as String?;
            final msgTs = rawTs != null
                ? (DateTime.tryParse(rawTs) ?? fallbackTs)
                : fallbackTs;

            _messages.add(
              _AiMessage(
                id: '${sid}_${msgTs.millisecondsSinceEpoch}_$i',
                role: m['role'] == 'user' ? 'user' : 'assistant',
                text: m['content'] ?? '',
                timestamp: msgTs,
                recommendation: m['recommendation'],
              ),
            );
          }
        }
      }

      // ── Now create the new session ──────────────────────────────────────
      final res = await http.post(
        Uri.parse('$API_BASE_URL/open-ai/session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'title': 'Toppins AI Chat'}),
      );

      if (!res.statusCode.toString().startsWith('2')) {
        final err = json.decode(res.body);
        throw Exception(err['error'] ?? 'Failed to start session');
      }

      final data = json.decode(res.body);
      _sessionId = data['sessionId'];

      if (data['greeting'] != null) {
        _addMessage('assistant', data['greeting'] as String);
        setState(() => _showSuggestions = true);
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _initializing = false);
    }
  }

 Future<void> _loadSession(String sessionId) async {
    setState(() => _initializing = true);
    try {
      final token = await _token();
      if (token == null) throw Exception('Not authenticated');

      // ── 1. Fetch ALL sessions list ──────────────────────────────────────
      final sessionsRes = await http.get(
        Uri.parse('$API_BASE_URL/open-ai/sessions'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!sessionsRes.statusCode.toString().startsWith('2')) {
        final err = json.decode(sessionsRes.body);
        throw Exception(err['error'] ?? 'Failed to fetch sessions');
      }
      final List allSessions = json.decode(sessionsRes.body);

      // Sort sessions oldest → newest so messages appear in order
      allSessions.sort((a, b) {
        final aDate = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime(0);
        final bDate = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime(0);
        return aDate.compareTo(bDate);
      });

      // ── 2. For each session, fetch its messages ─────────────────────────
      for (final session in allSessions) {
        final sid =
            session['_id'] as String? ?? session['sessionId'] as String?;
        if (sid == null) continue;

        final sessionRes = await http.get(
          Uri.parse('$API_BASE_URL/open-ai/session/$sid'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (!sessionRes.statusCode.toString().startsWith('2')) continue;

        final data = json.decode(sessionRes.body);
        final List msgs = data['messages'] ?? [];
        final fallbackTs =
            DateTime.tryParse(data['updatedAt'] ?? '') ?? DateTime.now();

        for (var i = 0; i < msgs.length; i++) {
          final m = msgs[i] as Map<String, dynamic>;
          if (m['role'] == 'system') continue;

          final rawTs = m['createdAt'] as String? ?? m['timestamp'] as String?;
          final msgTs = rawTs != null
              ? (DateTime.tryParse(rawTs) ?? fallbackTs)
              : fallbackTs;

          _messages.add(
            _AiMessage(
              id: '${sid}_${msgTs.millisecondsSinceEpoch}_$i',
              role: m['role'] == 'user' ? 'user' : 'assistant',
              text: m['content'] ?? '',
              timestamp: msgTs,
              recommendation: m['recommendation'],
            ),
          );
        }
      }

      _sessionId = sessionId;
      setState(() => _showSuggestions = _messages.isEmpty);
      _scrollToBottom(immediate: true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _initializing = false);
    }
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending || _sessionId == null) return;

    _addMessage('user', trimmed);
    _inputCtrl.clear();
    setState(() {
      _sending = true;
      _showSuggestions = false;
    });

    try {
      final token = await _token();
      if (token == null) throw Exception('Not authenticated');

      final res = await http.post(
        Uri.parse('$API_BASE_URL/open-ai/message'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'message': trimmed, 'sessionId': _sessionId}),
      );

      if (!res.statusCode.toString().startsWith('2')) {
        final err = json.decode(res.body);
        throw Exception(err['error'] ?? 'Failed to send');
      }

      final data = json.decode(res.body);
      _addMessage(
        'assistant',
        data['reply'] ?? '',
        recommendation: data['recommendation'],
      );
    } catch (_) {
      _addMessage(
        'assistant',
        "I'm having trouble connecting right now. Please try again in a moment.",
      );
    } finally {
      setState(() => _sending = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _addMessage(
    String role,
    String text, {
    Map<String, dynamic>? recommendation,
  }) {
    setState(() {
      _messages.add(
        _AiMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}_${_messages.length}',
          role: role,
          text: text,
          timestamp: DateTime.now(),
          recommendation: recommendation,
        ),
      );
    });
    _scrollToBottom();
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (immediate) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      } else {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
        .replaceAll(RegExp(r'__(.*?)__'), r'$1')
        .replaceAll(RegExp(r'_(.*?)_'), r'$1')
        .replaceAll(RegExp(r'`(.*?)`'), r'$1');
  }

  /// Groups messages by calendar day (Today, Yesterday, or formatted date).
  List<_DayGroup> get _grouped {
    if (_messages.isEmpty) return [];
    final groups = <_DayGroup>[];
    DateTime? currentDay;

    for (final msg in _messages) {
      final day = DateTime(
        msg.timestamp.year,
        msg.timestamp.month,
        msg.timestamp.day,
      );
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        groups.add(_DayGroup(date: day, messages: []));
      }
      groups.last.messages.add(msg);
    }
    return groups;
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final suffix = day.year != now.year ? ', ${day.year}' : '';
    return '${months[day.month]} ${day.day}$suffix';
  }

  String _timeLabel(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _initializing
                ? _buildInitializing()
                : _error != null
                ? _buildErrorState()
                : _buildBody(),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        4,
        MediaQuery.of(context).padding.top + 8,
        16,
        12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              size: 18,
              color: Color(0xFF374151),
            ),
            onPressed: () => Navigator.pop(context),
          ),

          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),

          // Name + status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Toppins AI',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                    letterSpacing: -0.2,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _sending ? 'Typing...' : 'Online · AI Health Assistant',
                      style: TextStyle(
                        fontSize: 12,
                        color: _sending
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // New chat
          IconButton(
            icon: const Icon(
              Icons.add_comment_outlined,
              size: 20,
              color: Color(0xFF6B7280),
            ),
            tooltip: 'New conversation',
            onPressed: () {
              setState(() {
                _messages.clear();
                _sessionId = null;
                _showSuggestions = true;
                _error = null;
              });
              _createSession();
            },
          ),
        ],
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    final groups = _grouped;

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      itemCount:
          groups.length +
          (_showSuggestions && _messages.length <= 1 ? 1 : 0) +
          (_sending ? 1 : 0),
      itemBuilder: (context, index) {
        // Suggestions strip (after greeting, before user sends anything)
        if (_showSuggestions &&
            _messages.length <= 1 &&
            index == groups.length) {
          return _buildSuggestions();
        }

        // Typing indicator at the very end
        if (_sending &&
            index ==
                groups.length +
                    (_showSuggestions && _messages.length <= 1 ? 1 : 0)) {
          return _buildTypingBubble();
        }

        if (index >= groups.length) return const SizedBox.shrink();

        final group = groups[index];
        return Column(
          children: [
            _buildDayDivider(group.date),
            ...group.messages.map(_buildMessageBubble),
          ],
        );
      },
    );
  }

  // ── Day divider ────────────────────────────────────────────────────────────

  Widget _buildDayDivider(DateTime day) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: Color(0xFFD1D5DB), thickness: 1),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              _dayLabel(day),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Divider(color: Color(0xFFD1D5DB), thickness: 1),
          ),
        ],
      ),
    );
  }

  // ── Message bubble ─────────────────────────────────────────────────────────

  Widget _buildMessageBubble(_AiMessage msg) {
    final isUser = msg.isUser;

    return Padding(
      padding: EdgeInsets.only(
        bottom: 8,
        left: isUser ? 48 : 0,
        right: isUser ? 0 : 48,
      ),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // AI avatar
              if (!isUser) ...[
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.only(right: 8, bottom: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B82F6), Color(0xFF7C3AED)],
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.smart_toy_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],

              // Bubble
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: msg.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Message copied'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF2563EB) : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isUser
                              ? const Color(0xFF2563EB).withOpacity(0.2)
                              : Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _stripMarkdown(msg.text),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.55,
                        color: isUser ? Colors.white : const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Timestamp
          Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: isUser ? 0 : 38,
              right: isUser ? 2 : 0,
            ),
            child: Text(
              _timeLabel(msg.timestamp),
              style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
            ),
          ),

          // Doctor recommendation card
          if (msg.recommendation != null &&
              msg.recommendation!['doctor'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 38),
              child: _RecommendationCard(
                recommendation: msg.recommendation!,
                onContact: (id) => _handleContactDoctor(id),
              ),
            ),
        ],
      ),
    );
  }

  // ── Typing bubble ──────────────────────────────────────────────────────────

  Widget _buildTypingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF7C3AED)],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => _TypingDot(ctrl: _typingDotCtrl, index: i),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Suggestion chips ───────────────────────────────────────────────────────

  Widget _buildSuggestions() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 38, bottom: 10),
            child: Text(
              'Try asking about:',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF9CA3AF),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions.map((s) {
              return GestureDetector(
                onTap: () => _send(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    s,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── Input bar ──────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 12,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: TextField(
                controller: _inputCtrl,
                focusNode: _focusNode,
                maxLines: null,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
                enabled: !_sending && _sessionId != null,
                decoration: const InputDecoration(
                  hintText: 'Describe your symptoms…',
                  hintStyle: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (v) => _send(v),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send button
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient:
                  (_sending ||
                      _sessionId == null ||
                      _inputCtrl.text.trim().isEmpty)
                  ? const LinearGradient(
                      colors: [Color(0xFFD1D5DB), Color(0xFFD1D5DB)],
                    )
                  : const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: (_sending || _sessionId == null)
                  ? []
                  : [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _send(_inputCtrl.text),
                child: const Center(
                  child: Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading / Error ────────────────────────────────────────────────────────

  Widget _buildInitializing() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF2563EB), strokeWidth: 2.5),
          SizedBox(height: 16),
          Text(
            'Starting conversation…',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Color(0xFFEF4444),
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Connection failed',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _error = null);
                _createSession();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Doctor contact ─────────────────────────────────────────────────────────

  Future<void> _handleContactDoctor(String participantId) async {
    try {
      final token = await _token();
      final res = await http.post(
        Uri.parse('$API_BASE_URL/chats'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'participantId': participantId}),
      );
      if (!res.statusCode.toString().startsWith('2')) {
        throw Exception('HTTP error: ${res.statusCode}');
      }
      final chat = json.decode(res.body);
      if (mounted) {
        Navigator.pushNamed(context, '/messages/${chat['_id']}');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open conversation. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════════

class _DayGroup {
  final DateTime date;
  final List<_AiMessage> messages;
  _DayGroup({required this.date, required this.messages});
}

// ── Animated typing dot ────────────────────────────────────────────────────────

class _TypingDot extends StatelessWidget {
  final AnimationController ctrl;
  final int index;

  const _TypingDot({required this.ctrl, required this.index});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        // Each dot offsets its phase by 1/3 of the cycle
        final phase = (ctrl.value + index / 3) % 1.0;
        // bounce: 0→1→0 using a sine-like curve
        final t = (phase < 0.5 ? phase * 2 : 2 - phase * 2);
        final offset = -6.0 * t;
        return Transform.translate(
          offset: Offset(0, offset),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Color.lerp(
                const Color(0xFFD1D5DB),
                const Color(0xFF2563EB),
                t,
              ),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

// ── Doctor recommendation card ─────────────────────────────────────────────────

class _RecommendationCard extends StatelessWidget {
  final Map<String, dynamic> recommendation;
  final void Function(String doctorId) onContact;

  const _RecommendationCard({
    required this.recommendation,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    final doctor = recommendation['doctor'] as Map<String, dynamic>? ?? {};
    final note = recommendation['note'] as String?;
    final doctorType = (doctor['doctorType'] as Map<String, dynamic>?)?['name'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFF5F3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Note
          if (note != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 13,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 5),
                const Text(
                  'Recommendation',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E40AF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              note,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF374151),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFDDD6FE)),
            const SizedBox(height: 12),
          ],

          // Doctor info
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: doctor['profile_image'] != null
                    ? Image.network(
                        doctor['profile_image'],
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatar(),
                      )
                    : _avatar(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor['fullName'] ?? 'Unknown Doctor',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (doctorType != null)
                      Text(
                        doctorType,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    if (doctor['averageRating'] != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${doctor['averageRating']}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => onContact(doctor['_id']),
              icon: const Icon(Icons.chat_bubble_outline, size: 15),
              label: const Text(
                'Start Conversation',
                style: TextStyle(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() => Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: const Color(0xFFDBEAFE),
      borderRadius: BorderRadius.circular(22),
    ),
    child: const Icon(Icons.person_rounded, color: Color(0xFF2563EB), size: 24),
  );
}
