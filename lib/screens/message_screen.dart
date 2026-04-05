import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

// ── Models ──────────────────────────────────────────────────────────────────

class ConversationModel {
  final String id;
  final String name;
  final String? avatar;
  final String lastMessage;
  final String time;
  final int unread;
  final bool isOnline;
  final String type; // 'doctor' | 'patient' | 'support'

  const ConversationModel({
    required this.id,
    required this.name,
    this.avatar,
    required this.lastMessage,
    required this.time,
    required this.unread,
    required this.isOnline,
    required this.type,
  });
}

class UserResult {
  final String id;
  final String fullName;
  final String? email;
  final String? role;
  final String? profileImage;

  const UserResult({
    required this.id,
    required this.fullName,
    this.email,
    this.role,
    this.profileImage,
  });

  factory UserResult.fromJson(Map<String, dynamic> j) => UserResult(
    id: j['_id']?.toString() ?? '',
    fullName: j['fullName'] ?? j['name'] ?? '',
    email: j['email'],
    role: j['role'] ?? j['userType'],
    profileImage: j['profile_image'],
  );
}

// ── Page ────────────────────────────────────────────────────────────────────

class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> with WidgetsBindingObserver {
  // Tab / search state
  String _activeTab = 'all';
  final _searchCtrl = TextEditingController();
  bool _searchVisible = false;

  // New-chat search modal
  bool _showUserSearch = false;
  final _userSearchCtrl = TextEditingController();
  List<UserResult> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  // Conversation list state
  List<ConversationModel> _conversations = [];
  bool _loading = true;
  String? _error;

  // Polling
  Timer? _pollTimer;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchConversations();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _userSearchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchConversations(silent: true);
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _pollTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchConversations(silent: true),
    );
  }

  // ── API calls ──────────────────────────────────────────────────────────────

  Future<void> _fetchConversations({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final token = await StorageService.getToken();
      if (token == null) throw Exception('Authentication required');

      final res = await http.get(
        Uri.parse('$API_BASE_URL/chats'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (res.statusCode != 200) {
        throw Exception('HTTP error: ${res.statusCode}');
      }

      final List data = json.decode(res.body);
      final currentId = await _getCurrentUserId();

      final convos = data.map((chat) {
        final participants =
            (chat['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final other = participants.firstWhere(
          (p) => p['_id'] != currentId,
          orElse: () => {},
        );

        return ConversationModel(
          id: chat['_id']?.toString() ?? '',
          name: other['fullName']?.toString() ?? 'Unknown User',
          avatar: other['profile_image']?.toString(),
          lastMessage: _getLastMessageText(chat['lastMessage']),
          time: _formatTime(chat['lastActivity'] ?? chat['updatedAt']),
          unread: (chat['unreadCount'] ?? 0) as int,
          isOnline: false,
          type: _determineType(other),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _conversations = convos;
          _error = null;
          if (!silent) _loading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final token = await StorageService.getToken();
      final res = await http.get(
        Uri.parse('$API_BASE_URL/users/search?q=${Uri.encodeComponent(query)}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final currentId = await _getCurrentUserId();
        final List raw = json.decode(res.body);
        final results = raw
            .map((u) => UserResult.fromJson(u as Map<String, dynamic>))
            .where((u) => u.id != currentId)
            .toList();
        if (mounted) setState(() => _searchResults = results);
      }
    } catch (e) {
      debugPrint('User search error: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _createConversation(String participantId) async {
    try {
      final token = await StorageService.getToken();
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

      final newChat = json.decode(res.body);
      _closeUserSearch();
      await _fetchConversations(silent: true);

      if (mounted) {
        Navigator.pushNamed(context, '/messages/${newChat['_id']}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create conversation. Please try again.'),
          ),
        );
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<String?> _getCurrentUserId() async {
    final token = await StorageService.getToken();
    if (token == null) return null;
    try {
      final decoded = JwtDecoder.decode(token);
      return decoded['id']?.toString() ??
          decoded['_id']?.toString() ??
          decoded['sub']?.toString();
    } catch (_) {
      return null;
    }
  }

  String _getLastMessageText(dynamic msg) {
    if (msg == null) return 'No messages yet';
    final type = msg['messageType']?.toString() ?? '';
    switch (type) {
      case 'text':
        return msg['content']?['text']?.toString() ?? 'Message';
      case 'image':
        return '📷 Photo';
      case 'voice':
        return '🎵 Voice message';
      case 'audio':
        return '🎵 Audio: ${msg['content']?['fileName'] ?? 'Audio file'}';
      case 'file':
        return '📎 ${msg['content']?['fileName'] ?? 'File'}';
      case 'call':
        final call = msg['content']?['call'];
        if (call == null) return '📞 Call';
        final icon = call['callType'] == 'video' ? '🎥' : '📞';
        switch (call['status']) {
          case 'missed':
            return '$icon Missed Call';
          case 'declined':
            return '$icon Call Declined';
          case 'ended':
            final dur = call['duration'] ?? 0;
            return dur > 0
                ? '$icon Call Ended (${_formatDuration(dur)})'
                : '$icon Call Ended';
          default:
            return '$icon Call';
        }
      default:
        return 'Message';
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatTime(dynamic dateString) {
    if (dateString == null) return '';
    final date = DateTime.tryParse(dateString.toString());
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff < 1) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff == 1) {
      return 'Yesterday';
    } else if (diff <= 7) {
      const days = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return days[date.weekday - 1];
    } else {
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
      return '${months[date.month]} ${date.day}';
    }
  }

  String _determineType(Map<String, dynamic> other) {
    final role =
        other['role']?.toString() ?? other['userType']?.toString() ?? '';
    if (role == 'doctor') return 'doctor';
    if (role == 'patient') return 'patient';
    return 'support';
  }

  List<ConversationModel> get _filtered => _conversations.where((c) {
    final tabMatch =
        _activeTab == 'all' ||
        (_activeTab == 'doctors' && c.type == 'doctor') ||
        (_activeTab == 'patient' && c.type == 'patient') ||
        (_activeTab == 'support' && c.type == 'support');
    final q = _searchCtrl.text.toLowerCase();
    final textMatch =
        q.isEmpty ||
        c.name.toLowerCase().contains(q) ||
        c.lastMessage.toLowerCase().contains(q);
    return tabMatch && textMatch;
  }).toList();

  void _closeUserSearch() {
    setState(() {
      _showUserSearch = false;
      _userSearchCtrl.clear();
      _searchResults = [];
    });
  }

  // ── Avatar Widget ──────────────────────────────────────────────────────────

  Widget _avatar(String? url, {double radius = 22}) {
    if (url != null && url.isNotEmpty) {
      final src = url.startsWith('http') ? url : '$IMAGE_URL$url';
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(src));
    }
    return CircleAvatar(
      radius: radius,
      backgroundImage: const NetworkImage(
        'https://www.gravatar.com/avatar/0662d90eb3d5d9764f07d6e25da3f5ca?s=200&r=pg&d=mm',
      ),
    );
  }

  // ── Type badge ─────────────────────────────────────────────────────────────

  Widget _typeBadge(String type) {
    const configs = {
      'doctor': (Color(0xFFDBEAFE), Color(0xFF1E40AF), 'Doctor'),
      'patient': (Color(0xFFF3E8FF), Color(0xFF6B21A8), 'Patient'),
      'support': (Color(0xFFCCFBF1), Color(0xFF0F766E), 'Support'),
    };
    final (bg, text, label) =
        configs[type] ??
        (const Color(0xFFF3F4F6), const Color(0xFF374151), type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              _buildTabs(),
              Expanded(child: _buildConversationList()),
            ],
          ),
          if (_showUserSearch) _buildUserSearchModal(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF2563EB),
        onPressed: () => setState(() => _showUserSearch = true),
        child: const Icon(Icons.message, color: Colors.white),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 12,
        16,
        12,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.message, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Messages',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _searchVisible ? Icons.close : Icons.search,
                  color: const Color(0xFF6B7280),
                ),
                onPressed: () =>
                    setState(() => _searchVisible = !_searchVisible),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Color(0xFF6B7280)),
                onPressed: () => setState(() => _showUserSearch = true),
              ),
            ],
          ),
          if (_searchVisible) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search messages...',
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF9CA3AF),
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: Color(0xFF9CA3AF),
                  size: 20,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tabs ───────────────────────────────────────────────────────────────────

  Widget _buildTabs() {
    final tabs = [
      ('all', Icons.message_outlined, 'All'),
      ('patient', Icons.person_outline, 'Patients'),
      ('doctors', Icons.people_outline, 'Doctors'),
      ('support', Icons.help_outline, 'Support'),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: tabs.map((t) {
          final (id, icon, label) = t;
          final isActive = _activeTab == id;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = id),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive
                          ? const Color(0xFF2563EB)
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: isActive
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isActive
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Conversation List ──────────────────────────────────────────────────────

  Widget _buildConversationList() {
    final filtered = _filtered;

    return RefreshIndicator(
      onRefresh: () => _fetchConversations(),
      color: const Color(0xFF2563EB),
      child: ListView(
        children: [
          // Toppins AI entry
          _buildAiEntry(),

          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Column(
                children: [
                  const Icon(
                    Icons.message_outlined,
                    size: 48,
                    color: Color(0xFFD1D5DB),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No messages found',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _searchCtrl.text.isNotEmpty
                        ? 'Try a different search term'
                        : 'Start a new conversation',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            ...filtered.map(_buildConversationTile),
        ],
      ),
    );
  }

  Widget _buildAiEntry() {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/ai-chat'),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B82F6), Color(0xFF9333EA)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.smart_toy, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Toppins AI',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF111827),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '• Online — AI Assistant ready to help',
                    style: TextStyle(color: Color(0xFF16A34A), fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFDBEAFE), Color(0xFFF3E8FF)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'AI',
                style: TextStyle(
                  color: Color(0xFF1D4ED8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationTile(ConversationModel c) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, '/messages/${c.id}'),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar with online dot
            Stack(
              children: [
                _avatar(c.avatar),
                if (c.isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ADE80),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Name / last message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      Text(
                        c.time,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    c.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.unread > 0
                          ? const Color(0xFF111827)
                          : const Color(0xFF6B7280),
                      fontWeight: c.unread > 0
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _typeBadge(c.type),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Unread badge
            if (c.unread > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${c.unread}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── User Search Modal ──────────────────────────────────────────────────────

  Widget _buildUserSearchModal() {
    return GestureDetector(
      onTap: _closeUserSearch,
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: GestureDetector(
            onTap: () {}, // prevent dismiss when tapping inside
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modal header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                    child: Row(
                      children: [
                        const Text(
                          'Search Users',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Color(0xFF9CA3AF),
                          ),
                          onPressed: _closeUserSearch,
                        ),
                      ],
                    ),
                  ),

                  // Search input
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _userSearchCtrl,
                      autofocus: true,
                      onChanged: (q) {
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 300),
                          () {
                            _searchUsers(q);
                          },
                        );
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by name or email...',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9CA3AF),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Color(0xFF9CA3AF),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF2563EB),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Results
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF2563EB),
                              ),
                            ),
                          )
                        : _searchResults.isNotEmpty
                        ? ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (_, i) =>
                                _buildUserResultTile(_searchResults[i]),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _userSearchCtrl.text.trim().isNotEmpty
                                  ? 'No users found'
                                  : 'Start typing to search for users',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 13,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserResultTile(UserResult user) {
    final isDoctor = user.role == 'doctor';
    return InkWell(
      onTap: () => _createConversation(user.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _avatar(user.profileImage, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: Color(0xFF111827),
                    ),
                  ),
                  if (user.email != null)
                    Text(
                      user.email!,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12,
                      ),
                    ),
                  if (user.role != null)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDoctor
                            ? const Color(0xFFDBEAFE)
                            : const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user.role!,
                        style: TextStyle(
                          color: isDoctor
                              ? const Color(0xFF1E40AF)
                              : const Color(0xFF374151),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Loading / Error states ─────────────────────────────────────────────────

  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF2563EB)),
            SizedBox(height: 16),
            Text(
              'Loading conversations...',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.message_outlined,
              size: 48,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(height: 12),
            const Text(
              'Error Loading Messages',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetchConversations,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
