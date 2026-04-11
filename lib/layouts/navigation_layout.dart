// lib/layouts/navigation_layout.dart
import 'package:flutter/material.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malak/config/api_config.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';

class NavigationLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;

  const NavigationLayout({
    Key? key,
    required this.child,
    required this.currentRoute,
  }) : super(key: key);

  @override
  State<NavigationLayout> createState() => _NavigationLayoutState();
}

class _NavigationLayoutState extends State<NavigationLayout> {
  int _selectedIndex = 0;
  int _unreadCount = 0;
  bool _isDoctorMode = false;
  String? _userRole;
  String? _profileImageUrl;

  static const _blue = Color(0xFF2563EB);

  // ── 4 bottom nav items (Wallet moved to AppBar) ───────────────────────────
  final List<NavItem> _navItems = [
    NavItem(name: 'Dashboard', icon: Icons.home_rounded, route: '/home'),
    NavItem(
      name: 'Appointments',
      icon: Icons.calendar_today_rounded,
      route: '/appointments',
    ),
    NavItem(
      name: 'Messages',
      icon: Icons.chat_bubble_rounded,
      route: '/messages',
    ),
    NavItem(name: 'Profile', icon: Icons.person_rounded, route: '/profile'),
  ];

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadUserData();
    await _fetchNotifications();
    _updateSelectedIndex();
  }

  void _updateSelectedIndex() {
    final index = _navItems.indexWhere(
      (item) => item.route == widget.currentRoute,
    );
    if (index != -1) setState(() => _selectedIndex = index);
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      try {
        final decoded = Jwt.parseJwt(token);
        setState(() => _userRole = decoded['role']);
      } catch (e) {
        debugPrint('Error decoding token: $e');
      }
    }
    // Fetch profile image
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() => _profileImageUrl = data['profile_image']);
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    }
  }

  Future<void> _fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/notifications'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final List notifications = json.decode(response.body);
        final unread = notifications
            .where((n) => !n['isRead'] && !n['deleted'])
            .length;
        setState(() => _unreadCount = unread);
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
    }
  }

  void _handleDashboardSwitch() {
    setState(() => _isDoctorMode = !_isDoctorMode);
    Navigator.pushNamedAndRemoveUntil(
      context,
      _isDoctorMode ? '/doctor-dashboard' : '/home',
      (r) => false,
    );
  }

  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    Navigator.pushNamed(context, _navItems[index].route);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: widget.child,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          // Profile avatar
         GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: CircleAvatar(
              radius: 19,
              backgroundColor: _blue.withOpacity(0.10),
              backgroundImage: _profileImageUrl != null
                  ? NetworkImage(_profileImageUrl!)
                  : null,
              child: _profileImageUrl == null
                  ? const Icon(Icons.person_rounded, color: _blue, size: 22)
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        // ── Doctor/Patient toggle (non-patient roles only) ────────────────
        if (_userRole != 'patient')
          IconButton(
            padding: EdgeInsets.zero,
            onPressed: _handleDashboardSwitch,
            icon: Icon(
              _isDoctorMode
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
              color: _isDoctorMode
                  ? const Color.fromARGB(255, 15, 126, 15)
                  : _blue,
              size: 36,
            ),
          ),

        // ── Wallet ────────────────────────────────────────────────────────
        IconButton(
          icon: const Icon(
            Icons.account_balance_wallet_outlined,
            color: Color(0xFF374151),
            size: 23,
          ),
          onPressed: () => Navigator.pushNamed(context, '/wallet'),
        ),

        // ── Notification bell with badge ──────────────────────────────────
        Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_rounded,
                color: _blue,
                size: 26,
              ),
              onPressed: () => Navigator.pushNamed(context, '/notifications'),
            ),
            if (_unreadCount > 0)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF5252),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 17,
                    minHeight: 17,
                  ),
                  child: Text(
                    _unreadCount > 9 ? '9+' : '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),

        const SizedBox(width: 4),
      ],
    );
  }

  // ── Bottom Nav ────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _navItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isSelected = _selectedIndex == index;

              return Expanded(
                child: GestureDetector(
                  onTap: () => _onNavTap(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1E88E5).withOpacity(0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          color: isSelected
                              ? const Color(0xFF1E88E5)
                              : Colors.grey.shade600,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF1E88E5)
                                : Colors.grey.shade600,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class NavItem {
  final String name;
  final IconData icon;
  final String route;

  NavItem({required this.name, required this.icon, required this.route});
}
