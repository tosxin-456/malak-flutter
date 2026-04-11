import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

// ─── Data models ──────────────────────────────────────────────────────────────

class _ChatMessage {
  final String id;
  final String sender; // 'user' | 'ai'
  final String text;
  final DateTime timestamp;
  final Map<String, dynamic>? recommendation;

  _ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.recommendation,
  });
}

class _ChatSession {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<dynamic> messages;

  _ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  factory _ChatSession.fromJson(Map<String, dynamic> json) {
    return _ChatSession(
      id: json['_id'] ?? '',
      title: json['title'] ?? 'Chat Session',
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      messages: json['messages'] ?? [],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET — drop this anywhere you need the AI chat entry point
// ═══════════════════════════════════════════════════════════════════════════════

class AiSymptomChatButton extends StatefulWidget {
  /// Called when the AI recommends a doctor and the user taps "Contact Doctor".
  /// Receives the doctor's participant ID.
  final Future<void> Function(String participantId) onCreateConversation;

  const AiSymptomChatButton({super.key, required this.onCreateConversation});

  @override
  State<AiSymptomChatButton> createState() => _AiSymptomChatButtonState();
}

class _AiSymptomChatButtonState extends State<AiSymptomChatButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _openChat() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AiChatModal(onCreateConversation: widget.onCreateConversation),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ScaleTransition(
        scale: _pulseAnimation,
        child: GestureDetector(
          onTap: _openChat,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.smart_toy_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Health Assistant',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Describe your symptoms for guidance',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PRIVATE — Chat modal + all internals (not exported)
// ═══════════════════════════════════════════════════════════════════════════════

class _AiChatModal extends StatefulWidget {
  final Future<void> Function(String participantId) onCreateConversation;

  const _AiChatModal({required this.onCreateConversation});

  @override
  State<_AiChatModal> createState() => _AiChatModalState();
}

class _AiChatModalState extends State<_AiChatModal> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _currentSessionId;
  bool _isTyping = false;
  bool _isLoading = false;
  bool _showHistory = false;
  String? _error;

  List<_ChatSession> _sessions = [];
  bool _isLoadingSessions = false;
  bool _isLoadingSession = false;

  String _searchTerm = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initializeChatSession();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<String?> _getToken() async => StorageService.getToken();

  String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
        .replaceAll(RegExp(r'__(.*?)__'), r'$1')
        .replaceAll(RegExp(r'_(.*?)_'), r'$1');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _addMessage(
    String sender,
    String text, {
    Map<String, dynamic>? recommendation,
  }) {
    setState(() {
      _messages.add(
        _ChatMessage(
          id: '${DateTime.now().millisecondsSinceEpoch}_${_messages.length}',
          sender: sender,
          text: text,
          timestamp: DateTime.now(),
          recommendation: recommendation,
        ),
      );
    });
    _scrollToBottom();
  }

  Future<void> _initializeChatSession() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = await _getToken();
      if (token == null)
        throw Exception('Authentication required. Please log in.');

      final response = await http.post(
        Uri.parse('$API_BASE_URL/open-ai/session'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'title': 'Health Consultation Chat'}),
      );

      if (!response.statusCode.toString().startsWith('2')) {
        final err = json.decode(response.body);
        throw Exception(err['error'] ?? 'Failed to create chat session');
      }

      final data = json.decode(response.body);
      setState(() => _currentSessionId = data['sessionId']);
      if (data['greeting'] != null) _addMessage('ai', data['greeting']);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchSessions() async {
    setState(() => _isLoadingSessions = true);
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Authentication required.');

      final response = await http.get(
        Uri.parse('$API_BASE_URL/open-ai/sessions'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!response.statusCode.toString().startsWith('2')) {
        final err = json.decode(response.body);
        throw Exception(err['error'] ?? 'Failed to fetch sessions');
      }

      final List data = json.decode(response.body);
      setState(
        () => _sessions = data.map((s) => _ChatSession.fromJson(s)).toList(),
      );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _isLoadingSessions = false);
    }
  }

  Future<void> _loadSession(String sessionId) async {
    setState(() {
      _isLoadingSession = true;
      _error = null;
    });
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Authentication required.');

      final response = await http.get(
        Uri.parse('$API_BASE_URL/open-ai/session/$sessionId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!response.statusCode.toString().startsWith('2')) {
        final err = json.decode(response.body);
        throw Exception(err['error'] ?? 'Failed to load session');
      }

      final sessionData = json.decode(response.body);
      final List msgs = sessionData['messages'] ?? [];
      final updatedAt =
          DateTime.tryParse(sessionData['updatedAt'] ?? '') ?? DateTime.now();

      final formatted = msgs
          .where((m) => m['role'] != 'system')
          .toList()
          .asMap()
          .entries
          .map(
            (e) => _ChatMessage(
              id: '${DateTime.now().millisecondsSinceEpoch}_${e.key}',
              sender: e.value['role'] == 'user' ? 'user' : 'ai',
              text: e.value['content'] ?? '',
              timestamp: updatedAt,
              recommendation: e.value['recommendation'],
            ),
          )
          .toList();

      setState(() {
        _messages.clear();
        _messages.addAll(formatted);
        _currentSessionId = sessionId;
        _showHistory = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      setState(() => _isLoadingSession = false);
    }
  }

  Future<void> _sendMessage(String messageText) async {
    if (_currentSessionId == null) {
      setState(() => _error = 'No active chat session. Please try reopening.');
      return;
    }
    setState(() {
      _isTyping = true;
      _error = null;
    });
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Authentication required.');

      final response = await http.post(
        Uri.parse('$API_BASE_URL/open-ai/message'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'message': messageText,
          'sessionId': _currentSessionId,
        }),
      );

      if (!response.statusCode.toString().startsWith('2')) {
        final err = json.decode(response.body);
        throw Exception(err['error'] ?? 'Failed to send message');
      }

      final data = json.decode(response.body);
      _addMessage(
        'ai',
        data['reply'] ?? '',
        recommendation: data['recommendation'],
      );
    } catch (_) {
      _addMessage(
        'ai',
        "I'm sorry, I'm having trouble connecting right now. Please try again.",
      );
    } finally {
      setState(() => _isTyping = false);
    }
  }

  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isTyping || _isLoading) return;
    _addMessage('user', text);
    _inputController.clear();
    _sendMessage(text);
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _currentSessionId = null;
      _showHistory = false;
    });
    _initializeChatSession();
  }

  String _formatTimestamp(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _formatSessionDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays <= 7) return '${diff.inDays} days ago';
    if (diff.inDays <= 30) return '${(diff.inDays / 7).ceil()} weeks ago';
    if (diff.inDays <= 365) return '${(diff.inDays / 30).ceil()} months ago';
    return '${(diff.inDays / 365).ceil()} years ago';
  }

  List<_ChatSession> get _filteredSessions {
    if (_searchTerm.trim().isEmpty) return _sessions;
    final q = _searchTerm.toLowerCase();
    return _sessions.where((s) {
      return s.title.toLowerCase().contains(q) ||
          s.messages.any(
            (m) => (m['content'] ?? '').toString().toLowerCase().contains(q),
          );
    }).toList();
  }

  Map<String, List<_ChatSession>> get _groupedSessions {
    final groups = <String, List<_ChatSession>>{
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'This Month': [],
      'Older': [],
    };
    final now = DateTime.now();
    for (final s in _filteredSessions) {
      final diff = now.difference(s.updatedAt).inDays;
      if (diff == 0)
        groups['Today']!.add(s);
      else if (diff == 1)
        groups['Yesterday']!.add(s);
      else if (diff <= 7)
        groups['This Week']!.add(s);
      else if (diff <= 30)
        groups['This Month']!.add(s);
      else
        groups['Older']!.add(s);
    }
    return groups;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(
            child: _showHistory ? _buildHistoryView() : _buildChatView(),
          ),
        ],
      ),
    );
  }

  Widget _buildChatView() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.smart_toy_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Health Assistant',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      _isLoading || _isLoadingSession
                          ? 'Connecting...'
                          : _currentSessionId != null
                          ? 'Online • Ready to help'
                          : 'Offline',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.history, color: Colors.white),
                onPressed: () {
                  setState(() => _showHistory = true);
                  _fetchSessions();
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: Container(
            color: const Color(0xFFF9FAFB),
            child: _isLoading || _isLoadingSession
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isLoadingSession
                              ? 'Loading conversation...'
                              : 'Initializing chat...',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount:
                        _messages.length +
                        (_isTyping ? 1 : 0) +
                        (_error != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_error != null && index == 0) {
                        return _buildErrorBanner();
                      }
                      final i = _error != null ? index - 1 : index;
                      if (_isTyping && i == _messages.length) {
                        return _buildTypingIndicator();
                      }
                      if (i < 0 || i >= _messages.length) {
                        return const SizedBox.shrink();
                      }
                      return _buildMessageBubble(_messages[i]);
                    },
                  ),
          ),
        ),

        // Input
        Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      maxLines: 3,
                      minLines: 1,
                      enabled:
                          !_isTyping &&
                          !_isLoading &&
                          _currentSessionId != null,
                      onSubmitted: (_) => _handleSend(),
                      decoration: InputDecoration(
                        hintText: _currentSessionId == null
                            ? 'Connecting...'
                            : 'Describe your symptoms or health concerns...',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD1D5DB),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFD1D5DB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 2,
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        filled: true,
                        fillColor: _currentSessionId == null
                            ? const Color(0xFFF3F4F6)
                            : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _handleSend,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            _isTyping || _isLoading || _currentSessionId == null
                            ? const Color(0xFFD1D5DB)
                            : const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap Send or press Enter • AI-powered health guidance',
                style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(_ChatMessage message) {
    final isUser = message.sender == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              margin: const EdgeInsets.only(right: 8, top: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                size: 16,
                color: Color(0xFF2563EB),
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF2563EB) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isUser ? 14 : 4),
                      topRight: Radius.circular(isUser ? 4 : 14),
                      bottomLeft: const Radius.circular(14),
                      bottomRight: const Radius.circular(14),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isUser ? 'You' : 'AI Assistant',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isUser
                                  ? Colors.white70
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTimestamp(message.timestamp),
                            style: TextStyle(
                              fontSize: 10,
                              color: isUser
                                  ? Colors.white54
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _stripMarkdown(message.text),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: isUser
                              ? Colors.white
                              : const Color(0xFF1F2937),
                        ),
                      ),
                    ],
                  ),
                ),
                if (message.recommendation != null &&
                    message.recommendation!['doctor'] != null)
                  _DoctorRecommendationCard(
                    recommendation: message.recommendation!,
                    onContact: widget.onCreateConversation,
                  ),
              ],
            ),
          ),
          if (isUser)
            Container(
              margin: const EdgeInsets.only(left: 8, top: 4),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person, size: 16, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.smart_toy_outlined,
              size: 16,
              color: Color(0xFF2563EB),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _BouncingDot(delay: i * 150)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _error = null),
            child: const Icon(Icons.close, size: 16, color: Color(0xFF991B1B)),
          ),
        ],
      ),
    );
  }

  // ── History view ───────────────────────────────────────────────────────────

  Widget _buildHistoryView() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _showHistory = false),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.chevron_left,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chat History',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'Previous conversations',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: _startNewChat,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => setState(() => _searchTerm = v),
                  );
                },
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search previous chats...',
                  hintStyle: const TextStyle(color: Colors.white60),
                  prefixIcon: const Icon(Icons.search, color: Colors.white60),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.2),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFFF9FAFB),
            child: _isLoadingSessions
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                  )
                : _filteredSessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.history,
                          size: 56,
                          color: Color(0xFFD1D5DB),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchTerm.isNotEmpty
                              ? 'No matching conversations'
                              : 'No chat history',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Color(0xFF374151),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _searchTerm.isNotEmpty
                              ? 'Try adjusting your search terms'
                              : 'Start a new conversation to see it here',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _startNewChat,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Start New Chat'),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: _groupedSessions.entries
                        .where((e) => e.value.isNotEmpty)
                        .map((e) => _buildSessionGroup(e.key, e.value))
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionGroup(String title, List<_ChatSession> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF9CA3AF),
              letterSpacing: 1,
            ),
          ),
        ),
        ...sessions.map((s) => _buildSessionTile(s)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildSessionTile(_ChatSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _loadSession(session.id),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          color: Color(0xFF111827),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatSessionDate(session.updatedAt),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF9CA3AF),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Bouncing dot ─────────────────────────────────────────────────────────────

class _BouncingDot extends StatefulWidget {
  final int delay;
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
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(
      begin: 0,
      end: -6,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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
          margin: const EdgeInsets.symmetric(horizontal: 2),
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

// ─── Doctor recommendation card ───────────────────────────────────────────────

class _DoctorRecommendationCard extends StatelessWidget {
  final Map<String, dynamic> recommendation;
  final Future<void> Function(String participantId) onContact;

  const _DoctorRecommendationCard({
    required this.recommendation,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    final doctor = recommendation['doctor'] as Map<String, dynamic>? ?? {};
    final note = recommendation['note'] as String?;
    final doctorType = (doctor['doctorType'] as Map<String, dynamic>?)?['name'];

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFEEF2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Medical Recommendation',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E40AF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              note,
              style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 10),
          ],
          const Row(
            children: [
              Icon(Icons.person_outline, size: 14, color: Color(0xFF2563EB)),
              SizedBox(width: 6),
              Text(
                'Recommended Doctor',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E40AF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipOval(
                child: doctor['profile_image'] != null
                    ? Image.network(
                        doctor['profile_image'],
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _defaultAvatar(),
                      )
                    : _defaultAvatar(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor['fullName'] ?? 'Unknown',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star,
                            size: 13,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${doctor['averageRating']} rating',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (doctor['email'] != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.email_outlined,
                            size: 12,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              doctor['email'],
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF6B7280),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (doctor['phone'] != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone_outlined,
                            size: 12,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            doctor['phone'],
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => onContact(doctor['_id']),
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text(
                          'Contact Doctor',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _defaultAvatar() => Container(
    width: 44,
    height: 44,
    color: const Color(0xFFDBEAFE),
    child: const Icon(Icons.person, color: Color(0xFF2563EB), size: 24),
  );
}
