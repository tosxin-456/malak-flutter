// lib/layouts/navigation_layout.dart
import 'package:flutter/material.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malak/config/api_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:malak/screens/home_screen.dart';
import 'package:malak/screens/appointments_screen.dart';
import 'package:malak/screens/message_screen.dart';
import 'package:malak/screens/profile_screen.dart';

class NavigationLayout extends StatefulWidget {
  const NavigationLayout({Key? key}) : super(key: key);

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

  final List<Widget> _pages = [
    const HomeScreen(),
    const AppointmentsScreen(),
    const MessageScreen(),
    // const ProfilePage(),
  ];

  final List<NavItem> _navItems = [
    NavItem(name: 'Dashboard', icon: Icons.home_rounded),
    NavItem(name: 'Appointments', icon: Icons.calendar_today_rounded),
    NavItem(name: 'Messages', icon: Icons.chat_bubble_rounded),
    NavItem(name: 'Profile', icon: Icons.person_rounded),
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
    if (token != null) {
      try {
        final decoded = Jwt.parseJwt(token);
        if (mounted) setState(() => _userRole = decoded['role']);
      } catch (e) {
        debugPrint('Error decoding token: $e');
      }
    }
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
      if (!mounted) return;
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
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
          return;
        }
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
        if (shouldExit == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: _buildAppBar(),
        body: IndexedStack(index: _selectedIndex, children: _pages),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
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

  NavItem({required this.name, required this.icon});
}
