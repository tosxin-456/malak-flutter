// lib/screens/notifications/notifications_page.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:malak/config/api_config.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  // ─── Theme ──────────────────────────────────────────────────────────────────
  static const _green = Color(0xFF059669);
  static const _greenLight = Color(0xFFECFDF5);
  static const _red = Color(0xFFEF4444);
  static const _bg = Color(0xFFF9FAFB);
  static const _surface = Colors.white;
  static const _textPrimary = Color(0xFF111827);
  static const _textSecondary = Color(0xFF6B7280);
  static const _divider = Color(0xFFF3F4F6);

  // ─── State ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _notifications = [];
  Map<String, bool> _preferences = {
    'appointment': true,
    'medication': true,
    'lab': true,
    'message': true,
    'system': true,
  };

  bool _loading = true;
  bool _prefsLoading = false;
  late TabController _tabController;

  // ─── Icon / colour maps ──────────────────────────────────────────────────────
  IconData _iconForType(String type) {
    switch (type) {
      case 'message':
        return Icons.chat_bubble_rounded;
      case 'appointment':
        return Icons.calendar_today_rounded;
      case 'lab':
        return Icons.science_outlined;
      case 'medication':
        return Icons.medication_rounded;
      case 'alert':
        return Icons.warning_amber_rounded;
      case 'profile':
        return Icons.person_rounded;
      case 'gift':
        return Icons.card_giftcard_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'message':
        return const Color(0xFF7C3AED);
      case 'appointment':
        return const Color(0xFF059669);
      case 'lab':
        return const Color(0xFF0D9488);
      case 'medication':
        return const Color(0xFFDB2777);
      case 'alert':
        return _red;
      case 'profile':
        return const Color(0xFFEA580C);
      case 'gift':
        return const Color(0xFFCA8A04);
      default:
        return const Color(0xFF2563EB);
    }
  }

  Color _bgForType(String type) {
    switch (type) {
      case 'message':
        return const Color(0xFFF5F3FF);
      case 'appointment':
        return _greenLight;
      case 'lab':
        return const Color(0xFFF0FDFA);
      case 'medication':
        return const Color(0xFFFDF2F8);
      case 'alert':
        return const Color(0xFFFEF2F2);
      case 'profile':
        return const Color(0xFFFFF7ED);
      case 'gift':
        return const Color(0xFFFEFCE8);
      default:
        return const Color(0xFFEFF6FF);
    }
  }

  // ─── Lifecycle ───────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchNotifications();
    _fetchPreferences();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ─── API Calls ───────────────────────────────────────────────────────────────
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<void> _fetchNotifications() async {
    final token = await _getToken();
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/notifications'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        setState(() {
          _notifications = data
              .map((n) => Map<String, dynamic>.from(n))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Fetch notifications error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchPreferences() async {
    final token = await _getToken();
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/notifications-preferences'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['preferences'] != null) {
          setState(() {
            _preferences =
                Map<String, bool>.from(data['preferences']);
          });
        }
      }
    } catch (e) {
      debugPrint('Fetch preferences error: $e');
    }
  }

  Future<void> _markAsRead(String id) async {
    final token = await _getToken();
    if (token == null) return;
    try {
      final res = await http.patch(
        Uri.parse('$API_BASE_URL/notifications/read/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200 && mounted) {
        setState(() {
          for (final n in _notifications) {
            if (n['_id'] == id) n['isRead'] = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Mark as read error: $e');
    }
  }

  Future<void> _deleteNotification(String id) async {
    final token = await _getToken();
    if (token == null) return;
    try {
      final res = await http.delete(
        Uri.parse('$API_BASE_URL/notifications/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _notifications.removeWhere((n) => n['_id'] == id);
        });
      }
    } catch (e) {
      debugPrint('Delete notification error: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    final token = await _getToken();
    if (token == null) return;
    try {
      final res = await http.patch(
        Uri.parse('$API_BASE_URL/notifications/read-all'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode == 200 && mounted) {
        setState(() {
          for (final n in _notifications) {
            n['isRead'] = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Mark all read error: $e');
    }
  }

  Future<void> _clearAll() async {
    final ids = _notifications.map((n) => n['_id'] as String).toList();
    for (final id in ids) {
      await _deleteNotification(id);
    }
  }

  Future<void> _savePreferences() async {
    final token = await _getToken();
    if (token == null) return;
    setState(() => _prefsLoading = true);
    try {
      await http.put(
        Uri.parse('$API_BASE_URL/notifications-preferences'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'preferences': _preferences}),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Preferences saved'),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Save preferences error: $e');
    } finally {
      if (mounted) setState(() => _prefsLoading = false);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────
  String _formatTime(String? timeString) {
    if (timeString == null) return '';
    try {
      final date = DateTime.parse(timeString);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inHours < 1) return 'Just now';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays == 1) return '1 day ago';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      final weeks = (diff.inDays / 7).floor();
      return '${weeks}w ago';
    } catch (_) {
      return '';
    }
  }

  int get _unreadCount =>
      _notifications.where((n) => n['isRead'] != true).length;

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _loading ? _buildSkeleton() : _buildBody(),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: const Color(0x14000000),
      backgroundColor: _surface,
      toolbarHeight: 60,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 20, color: _textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          if (_unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$_unreadCount New',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded,
              color: _textSecondary, size: 22),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (value) {
            if (value == 'read_all') _markAllAsRead();
            if (value == 'clear_all') _clearAll();
          },
          itemBuilder: (_) => [
            _popupItem(
                'read_all', Icons.done_all_rounded, 'Mark all as read'),
            _popupItem('clear_all', Icons.delete_sweep_rounded, 'Clear all'),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: TabBar(
        controller: _tabController,
        labelColor: _green,
        unselectedLabelColor: _textSecondary,
        indicatorColor: _green,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Notifications'),
          Tab(text: 'Preferences'),
        ],
      ),
    );
  }

  PopupMenuItem<String> _popupItem(
      String value, IconData icon, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: _textSecondary),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(fontSize: 13, color: _textPrimary)),
        ],
      ),
    );
  }

  // ─── Body ─────────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildNotificationsList(),
        _buildPreferencesTab(),
      ],
    );
  }

  // ─── Notifications List ───────────────────────────────────────────────────────
  Widget _buildNotificationsList() {
    if (_notifications.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      color: _green,
      onRefresh: _fetchNotifications,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _notifications.length,
        separatorBuilder: (_, __) => const Divider(
            height: 1, color: _divider, indent: 72, endIndent: 0),
        itemBuilder: (_, index) =>
            _buildNotificationTile(_notifications[index]),
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> notification) {
    final id = notification['_id'] as String? ?? '';
    final type = notification['iconType'] as String? ?? 'system';
    final isRead = notification['isRead'] == true;
    final title = notification['title'] as String? ?? '';
    final message = notification['message'] as String? ?? '';
    final time = notification['time'] as String?;

    final iconColor = _colorForType(type);
    final iconBg = _bgForType(type);

    return Dismissible(
      key: Key(id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: _red.withOpacity(0.1),
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded,
            color: _red, size: 22),
      ),
      onDismissed: (_) => _deleteNotification(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: isRead ? _surface : const Color(0xFFF0FDF4),
        child: InkWell(
          onTap: isRead ? null : () => _markAsRead(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon bubble
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      Icon(_iconForType(type), color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: isRead
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                                color: iconColor,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTime(time),
                            style: const TextStyle(
                              fontSize: 11,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (!isRead)
                            _actionChip(
                              icon: Icons.check_rounded,
                              label: 'Mark read',
                              color: _green,
                              onTap: () => _markAsRead(id),
                            ),
                          if (!isRead) const SizedBox(width: 8),
                          _actionChip(
                            icon: Icons.delete_outline_rounded,
                            label: 'Delete',
                            color: _textSecondary,
                            onTap: () => _deleteNotification(id),
                          ),
                          if (!isRead) ...[
                            const Spacer(),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty State ──────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _greenLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_none_rounded,
                color: _green, size: 34),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "You're all caught up! Appointments, medications, and updates will appear here.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: _textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Preferences Tab ──────────────────────────────────────────────────────────
  Widget _buildPreferencesTab() {
    final prefItems = [
      _PrefItem(
          key: 'appointment',
          icon: Icons.calendar_today_rounded,
          color: _green,
          bg: _greenLight,
          label: 'Appointment Reminders',
          subtitle: 'Get reminded about upcoming appointments'),
      _PrefItem(
          key: 'medication',
          icon: Icons.medication_rounded,
          color: const Color(0xFFDB2777),
          bg: const Color(0xFFFDF2F8),
          label: 'Medication Reminders',
          subtitle: 'Reminders to take your medications'),
      _PrefItem(
          key: 'lab',
          icon: Icons.science_outlined,
          color: const Color(0xFF0D9488),
          bg: const Color(0xFFF0FDFA),
          label: 'Lab Results',
          subtitle: 'Notifications when results are ready'),
      _PrefItem(
          key: 'message',
          icon: Icons.chat_bubble_rounded,
          color: const Color(0xFF7C3AED),
          bg: const Color(0xFFF5F3FF),
          label: 'Messages from Doctors',
          subtitle: 'New messages from your care team'),
      _PrefItem(
          key: 'system',
          icon: Icons.notifications_rounded,
          color: const Color(0xFF2563EB),
          bg: const Color(0xFFEFF6FF),
          label: 'System Updates',
          subtitle: 'App updates and announcements'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          const Text(
            'Notification Preferences',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Choose which notifications you want to receive.',
            style: TextStyle(fontSize: 12.5, color: _textSecondary),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: prefItems
                  .asMap()
                  .entries
                  .map((entry) => _buildPrefTile(
                      entry.value, entry.key < prefItems.length - 1))
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _prefsLoading ? null : _savePreferences,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _green.withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _prefsLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Preferences',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPrefTile(_PrefItem pref, bool showDivider) {
    final isEnabled = _preferences[pref.key] ?? true;

    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: pref.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(pref.icon, color: pref.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pref.label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pref.subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(
                value: isEnabled,
                onChanged: (val) =>
                    setState(() => _preferences[pref.key] = val),
                activeColor: _green,
                activeTrackColor: _greenLight,
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: _divider, indent: 68),
      ],
    );
  }

  // ─── Skeleton Loader ──────────────────────────────────────────────────────────
  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 6,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: _divider),
      itemBuilder: (_, __) => Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _shimmerBox(42, 42, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _shimmerBox(14, double.infinity)),
                      const SizedBox(width: 40),
                      _shimmerBox(12, 50),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _shimmerBox(12, double.infinity),
                  const SizedBox(height: 4),
                  _shimmerBox(12, 200),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox(double height, double width, {double radius = 6}) {
    return Container(
      height: height,
      width: width == double.infinity ? null : width,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─── Helper model ─────────────────────────────────────────────────────────────

class _PrefItem {
  final String key;
  final IconData icon;
  final Color color;
  final Color bg;
  final String label;
  final String subtitle;

  const _PrefItem({
    required this.key,
    required this.icon,
    required this.color,
    required this.bg,
    required this.label,
    required this.subtitle,
  });
}