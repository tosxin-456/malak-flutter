// lib/layouts/doctor_navigation_layout.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:malak/config/api_config.dart';
import 'package:malak/screens/doctor_dashboard.dart';
import 'package:malak/screens/my_patients.dart';
import 'package:malak/screens/message_screen.dart';
import 'package:malak/screens/profile_screen.dart';

class DoctorNavigationLayout extends StatefulWidget {
  const DoctorNavigationLayout({Key? key}) : super(key: key);

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

  // ── The 4 tab pages ───────────────────────────────────────────────────────
  final List<Widget> _pages = [
    const DoctorDashboard(),
    const MyPatientsPage(),
    const MessageScreen(),
    // const ProfilePage(),
  ];

  final List<_NavItem> _navItems = [
    _NavItem(name: 'Home', icon: Icons.home_rounded),
    _NavItem(name: 'Patients', icon: Icons.people_outline),
    _NavItem(name: 'Messages', icon: Icons.chat_bubble_rounded, hasBadge: true),
    _NavItem(name: 'Profile', icon: Icons.person_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchNotifications();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null) return;
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) setState(() => _profileImageUrl = data['profile_image']);
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
    if (index == 3) {
      // Profile tab → navigate as a full route, no layout wrapping it
      Navigator.pushNamed(context, '/profile');
      return;
    }
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        // If not on Home tab, go Home first
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return;
        }
        // On Home tab → confirm exit
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit App'),
            content: const Text('Are you sure you want to exit?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (shouldExit == true) {
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: _buildAppBar(),
        // IndexedStack keeps all pages alive — no rebuild on tab switch
        body: IndexedStack(index: _selectedIndex, children: _pages),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

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
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _greenLight,
                shape: BoxShape.circle,
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
        ],
      ),
      actions: [
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
        IconButton(
          icon: const Icon(
            Icons.account_balance_wallet_outlined,
            color: Color(0xFF374151),
            size: 23,
          ),
          onPressed: () => Navigator.pushNamed(context, '/wallet'),
        ),
        Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_rounded,
                color: Color.fromARGB(255, 15, 126, 15),
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

class _NavItem {
  final String name;
  final IconData icon;
  final bool hasBadge;

  const _NavItem({
    required this.name,
    required this.icon,
    this.hasBadge = false,
  });
}
