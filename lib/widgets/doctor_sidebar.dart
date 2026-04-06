import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

// ─── Nav Item Model ───────────────────────────────────────────────────────────

class _NavItem {
  final String name;
  final IconData icon;
  final String path;
  final bool hasBadge;

  const _NavItem({
    required this.name,
    required this.icon,
    required this.path,
    this.hasBadge = false,
  });
}

const _navItems = [
  _NavItem(
    name: 'Dashboard',
    icon: Icons.home_outlined,
    path: '/doctor-dashboard',
  ),
  _NavItem(
    name: 'My Patients',
    icon: Icons.people_outline,
    path: '/my-patients',
  ),
  _NavItem(
    name: 'Messages',
    icon: Icons.message_outlined,
    path: '/doctor-messages',
    hasBadge: true,
  ),
  _NavItem(
    name: 'Notifications',
    icon: Icons.notifications_outlined,
    path: '/doctor-notifications',
  ),
  _NavItem(
    name: 'Wallet',
    icon: Icons.account_balance_wallet_outlined,
    path: '/wallet',
  ),
  _NavItem(
    name: 'Analytics & Reports',
    icon: Icons.trending_up_outlined,
    path: '/analytics',
  ),
];

// ─── Doctor Sidebar Drawer ────────────────────────────────────────────────────

class DoctorSidebar extends StatefulWidget {
  /// The currently active route, e.g. '/doctor-dashboard'
  final String currentRoute;

  const DoctorSidebar({Key? key, required this.currentRoute}) : super(key: key);

  @override
  State<DoctorSidebar> createState() => _DoctorSidebarState();
}

class _DoctorSidebarState extends State<DoctorSidebar> {
  int _unreadCount = 0;
  bool _isDoctorMode = true;
  String _userRole = 'doctor';

  static const _green = Color(0xFF059669);
  static const _greenLight = Color(0xFFECFDF5);
  static const _greenDark = Color(0xFF065F46);
  static const _red = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _loadUserRole();
  }

Future<void> _loadUserRole() async {
    try {
      final token = await StorageService.getToken();

      if (token == null || token.isEmpty) {
        if (mounted) setState(() => _userRole = 'doctor');
        return;
      }

      final decodedToken = JwtDecoder.decode(token);
      final role = decodedToken['role'];

      if (mounted) {
        setState(() => _userRole = role ?? 'doctor');
      }
    } catch (e) {
      // Handle invalid/expired token
      if (mounted) {
        setState(() => _userRole = 'doctor');
      }
      debugPrint('Error decoding token: $e');
    }
  }

  Future<void> _fetchNotifications() async {
    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) return;

      final res = await http.get(
        Uri.parse('$API_BASE_URL/notifications'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        final unread = data
            .where((n) => n['isRead'] == false && n['deleted'] != true)
            .length;
        setState(() => _unreadCount = unread);
      }
    } catch (e) {
      debugPrint('Notifications fetch error: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) return;

      await http.patch(
        Uri.parse('$API_BASE_URL/notifications/read-all'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (mounted) setState(() => _unreadCount = 0);
    } catch (e) {
      debugPrint('Mark all read error: $e');
    }
  }

  void _navigate(String path) {
    Navigator.pop(context); // close drawer
    if (ModalRoute.of(context)?.settings.name != path) {
      Navigator.pushNamedAndRemoveUntil(context, path, (r) => false);
    }
  }

  void _handleDashboardSwitch() {
    if (_isDoctorMode) {
      _navigate('/home');
    } else {
      _navigate('/doctor-dashboard');
    }
    setState(() => _isDoctorMode = !_isDoctorMode);
  }

  void _handleLogout() async {
    // Preserve remember-me keys like the React version does
    // final rememberToken = await StorageService.getRememberToken();
    // final fingerprintEnabled = await StorageService.getFingerprintEnabled();

    // await StorageService.clearAll();

    // if (rememberToken != null)
    //   await StorageService.setRememberToken(rememberToken);
    // if (fingerprintEnabled != null)
    //   await StorageService.setFingerprintEnabled(fingerprintEnabled);

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      width: 272,
      child: Column(
        children: [
          // ── Logo header ────────────────────────────────────────────
          _buildHeader(),

          // ── Dashboard mode toggle (hidden for pure patients) ───────
          if (_userRole != 'patient') _buildModeToggle(),

          // ── Nav items ──────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                ..._navItems.map(_buildNavTile),
                const Divider(
                  height: 24,
                  thickness: 1,
                  color: Color(0xFFF3F4F6),
                ),
                _buildNavTile(
                  const _NavItem(
                    name: 'Settings',
                    icon: Icons.settings_outlined,
                    path: '/doctor-settings',
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom section ─────────────────────────────────────────
          _buildBottomSection(),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.favorite, color: _green, size: 22),
          ),
          const SizedBox(width: 10),
          const Text(
            'Malak',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Mode Toggle ───────────────────────────────────────────────────────────

  Widget _buildModeToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Row(
        children: [
          Icon(
            _isDoctorMode
                ? Icons.medical_services_outlined
                : Icons.person_outline,
            size: 18,
            color: _green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isDoctorMode ? 'Doctor Mode' : 'Patient Mode',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
          ),
          GestureDetector(
            onTap: _handleDashboardSwitch,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 24,
              decoration: BoxDecoration(
                color: _isDoctorMode ? _green : const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _isDoctorMode
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Nav Tile ──────────────────────────────────────────────────────────────

  Widget _buildNavTile(_NavItem item) {
    final isActive = widget.currentRoute == item.path;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isActive ? _green : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _navigate(item.path),
          borderRadius: BorderRadius.circular(10),
          splashColor: _green.withOpacity(0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 20,
                  color: isActive ? Colors.white : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isActive ? Colors.white : const Color(0xFF374151),
                    ),
                  ),
                ),
                // Badge for Messages
                if (item.hasBadge && _unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : _red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_unreadCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isActive ? _red : Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Bottom Section ────────────────────────────────────────────────────────

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Column(
        children: [
          // Logout
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _handleLogout,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20, color: _red),
                    SizedBox(width: 12),
                    Text(
                      'Logout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _red,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Support card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _greenLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1FAE5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Medical Support',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _greenDark,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '24/7 clinical assistance',
                  style: TextStyle(fontSize: 11, color: _green),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Contact Support',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
