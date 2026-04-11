// lib/layouts/doctor_navigation_layout.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:malak/config/api_config.dart';

class DoctorNavigationLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;

  const DoctorNavigationLayout({
    Key? key,
    required this.child,
    required this.currentRoute,
  }) : super(key: key);

  @override
  State<DoctorNavigationLayout> createState() => _DoctorNavigationLayoutState();
}

class _DoctorNavigationLayoutState extends State<DoctorNavigationLayout> {
  int _selectedIndex = 0;
  int _unreadCount = 0;
  bool _isDoctorMode = true;
  String? _userRole;
  String? _profileImageUrl;

  static const _green = Color(0xFF059669);
  static const _greenLight = Color(0xFFECFDF5);

  // ── 4 bottom nav items (Wallet lives in AppBar) ───────────────────────────
  final List<_NavItem> _navItems = [
    _NavItem(
      name: 'Home',
      icon: Icons.home_rounded,
      route: '/doctor-dashboard',
    ),
    _NavItem(
      name: 'Patients',
      icon: Icons.people_outline,
      route: '/my-patients',
    ),
    _NavItem(
      name: 'Messages',
      icon: Icons.chat_bubble_rounded,
      route: '/doctor-messages',
      hasBadge: true,
    ),
    _NavItem(name: 'Profile', icon: Icons.person_rounded, route: '/profile'),
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
    if (token == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final res = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() => _profileImageUrl = data['profile_image']);
      }
    } catch (e) {
      debugPrint('Error fetching profile image: $e');
    }
  }

  Future<void> _fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/notifications'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final List data = json.decode(res.body);
        final unread = data
            .where((n) => n['isRead'] == false && n['deleted'] != true)
            .length;
        setState(() => _unreadCount = unread);
      }
    } catch (e) {
      debugPrint('Notifications error: $e');
    }
  }

  void _handleDashboardSwitch() {
    final goingToPatient = _isDoctorMode;
    setState(() => _isDoctorMode = !_isDoctorMode);
    Navigator.pushNamedAndRemoveUntil(
      context,
      goingToPatient ? '/home' : '/doctor-dashboard',
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
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: _buildAppBar(),
      body: widget.child,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: const Color(0x14000000),
      backgroundColor: Colors.white,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          // Profile avatar
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _greenLight,
                shape: BoxShape.circle, // ✅ makes it fully round
                image: _profileImageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(_profileImageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _profileImageUrl == null
                  ? const Icon(Icons.person_outline, color: _green, size: 20)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          // Logo
          // Row(
          //   mainAxisSize: MainAxisSize.min,
          //   children: [
          //     Container(
          //       width: 26,
          //       height: 26,
          //       decoration: BoxDecoration(
          //         color: _greenLight,
          //         borderRadius: BorderRadius.circular(6),
          //       ),
          //       child: const Icon(Icons.favorite, color: _green, size: 14),
          //     ),
          //     const SizedBox(width: 6),
          //     const Text(
          //       'Malak',
          //       style: TextStyle(
          //         fontSize: 18,
          //         fontWeight: FontWeight.w800,
          //         color: Color(0xFF111827),
          //         letterSpacing: -0.4,
          //       ),
          //     ),
          //   ],
          // ),
        ],
      ),
      actions: [
        // ── Doctor/Patient toggle ─────────────────────────────────────────
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
                  : const Color(0xFF9CA3AF),
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
                color: const Color.fromARGB(255, 15, 126, 15),
                size: 26,
              ),
              onPressed: () => Navigator.pushNamed(context, '/notifications'),
            ),
            if (_unreadCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
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
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _green.withOpacity(0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              item.icon,
                              color: isSelected ? _green : Colors.grey.shade500,
                              size: 24,
                            ),
                            if (item.hasBadge && _unreadCount > 0)
                              Positioned(
                                top: -4,
                                right: -6,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEF4444),
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 15,
                                    minHeight: 15,
                                  ),
                                  child: Text(
                                    _unreadCount > 9 ? '9+' : '$_unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          style: TextStyle(
                            color: isSelected ? _green : Colors.grey.shade500,
                            fontSize: 11,
                            fontWeight: isSelected
                                ? FontWeight.w700
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

// ─── Nav Item Model ───────────────────────────────────────────────────────────

class _NavItem {
  final String name;
  final IconData icon;
  final String route;
  final bool hasBadge;

  const _NavItem({
    required this.name,
    required this.icon,
    required this.route,
    this.hasBadge = false,
  });
}
