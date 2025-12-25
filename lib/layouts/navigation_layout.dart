// lib/widgets/navigation_layout.dart
import 'package:flutter/material.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Bottom navigation items
  final List<NavItem> _navItems = [
    NavItem(name: 'Dashboard', icon: Icons.home_rounded, route: '/dashboard'),
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
    if (index != -1) {
      setState(() => _selectedIndex = index);
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token != null) {
      try {
        Map<String, dynamic> decodedToken = Jwt.parseJwt(token);
        setState(() {
          _userRole = decodedToken['role'];
        });
      } catch (e) {
        print('Error decoding token: $e');
      }
    }
  }

  Future<void> _fetchNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse('YOUR_API_BASE_URL/notifications'),
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
      print('Error fetching notifications: $e');
    }
  }

  void _handleDashboardSwitch() {
    setState(() => _isDoctorMode = !_isDoctorMode);
    Navigator.pushReplacementNamed(
      context,
      _isDoctorMode ? '/doctor-dashboard' : '/dashboard',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        toolbarHeight: 70,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
              child: const Icon(
                Icons.person_rounded,
                color: Color(0xFF2563EB),
                size: 24,
              ),
            ),
          ),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_rounded,
                  color: Color(0xFF2563EB),
                  size: 26,
                ),
                onPressed: () => Navigator.pushNamed(context, '/notifications'),
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF5252),
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      _unreadCount > 9 ? '9+' : _unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          if (_userRole != 'patient')
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Icon(
                  _isDoctorMode
                      ? Icons.toggle_on_rounded
                      : Icons.toggle_off_rounded,
                  color: _isDoctorMode
                      ? const Color.fromARGB(255, 15, 126, 15)
                      : const Color(0xFF2563EB),
                  size: 32,
                ),
                onPressed: _handleDashboardSwitch,
              ),
            )
          else
            const SizedBox(width: 16),
        ],
      ),
      body: widget.child,
      bottomNavigationBar: Container(
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
                    onTap: () {
                      setState(() => _selectedIndex = index);
                      Navigator.pushReplacementNamed(context, item.route);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF1E88E5).withOpacity(0.1)
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
                            size: 26,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.name,
                            style: TextStyle(
                              color: isSelected
                                  ? const Color(0xFF1E88E5)
                                  : Colors.grey.shade600,
                              fontSize: 12,
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
