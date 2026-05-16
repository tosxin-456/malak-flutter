import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../routes/app_routes.dart';
import '../config/api_config.dart';
import '../services/storage_service.dart';

/// Role metadata
class _RoleData {
  final String prefix;
  final Color accent;
  final Color accentLight;
  final IconData icon;
  final String dashLabel;

  const _RoleData({
    required this.prefix,
    required this.accent,
    required this.accentLight,
    required this.icon,
    required this.dashLabel,
  });
}

const _roles = <String, _RoleData>{
  'doctor': _RoleData(
    prefix: 'Dr.',
    accent: Color(0xFF2563EB),
    accentLight: Color(0xFFEFF6FF),
    icon: Icons.medical_services,
    dashLabel: 'Doctor Dashboard',
  ),
  'pharmacist': _RoleData(
    prefix: 'Pharm.',
    accent: Color(0xFF059669),
    accentLight: Color(0xFFECFDF5),
    icon: Icons.medication_rounded,
    dashLabel: 'Pharmacy Dashboard',
  ),
  'nurse': _RoleData(
    prefix: 'Nurse',
    accent: Color(0xFF7C3AED),
    accentLight: Color(0xFFF5F3FF),
    icon: Icons.favorite_rounded,
    dashLabel: 'Nurse Dashboard',
  ),
  'patient': _RoleData(
    prefix: '',
    accent: Color(0xFF0EA5E9),
    accentLight: Color(0xFFF0F9FF),
    icon: Icons.person_rounded,
    dashLabel: 'Patient Dashboard',
  ),
};

_RoleData _roleDataFor(String role) =>
    _roles[role.toLowerCase()] ?? _roles['patient']!;

// ─── Screen ──────────────────────────────────────────────────────────────────
class RoleBasedLoginScreen extends StatefulWidget {
  const RoleBasedLoginScreen({super.key});

  @override
  State<RoleBasedLoginScreen> createState() => _RoleBasedLoginScreenState();
}

class _RoleBasedLoginScreenState extends State<RoleBasedLoginScreen>
    with TickerProviderStateMixin {
  // ── state ──────────────────────────────────────────────────────────────────
  String _role = '';
  String _firstName = '';
  bool _loading = true;
  bool _hasDoctorType = false;
  bool _hasDoctorAvailability = false;

  // ── animations ─────────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ── card stagger ──────────────────────────────────────────────────────────
  late AnimationController _card1Ctrl;
  late AnimationController _card2Ctrl;
  late Animation<double> _card1Fade;
  late Animation<double> _card2Fade;
  late Animation<Offset> _card1Slide;
  late Animation<Offset> _card2Slide;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _card1Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _card2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _card1Fade = CurvedAnimation(parent: _card1Ctrl, curve: Curves.easeOut);
    _card2Fade = CurvedAnimation(parent: _card2Ctrl, curve: Curves.easeOut);
    _card1Slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _card1Ctrl, curve: Curves.easeOutCubic));
    _card2Slide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _card2Ctrl, curve: Curves.easeOutCubic));

    _initUser();
  }

  Future<void> _initUser() async {
    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppRoutes.signIn);
        return;
      }

      final decoded = JwtDecoder.decode(token);
      final role = (decoded['role'] as String? ?? 'patient').toLowerCase();
      final fullName = await StorageService.getSavedFullName() ?? '';

      // Fetch doctor-specific status in parallel (only if needed)
      if (role == 'doctor') {
        await Future.wait([
          _fetchDoctorType(token),
          _fetchDoctorAvailability(token),
        ]);
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _firstName = fullName.split(' ').first;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ _initUser error: $e');
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.signIn);
      return;
    }

    // staggered entry animations
    _fadeCtrl.forward();
    _slideCtrl.forward();
    Future.delayed(
      const Duration(milliseconds: 200),
      () => _card1Ctrl.forward(),
    );
    Future.delayed(
      const Duration(milliseconds: 360),
      () => _card2Ctrl.forward(),
    );
  }

  Future<void> _fetchDoctorType(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/doctors/doctor/type'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _hasDoctorType = data['hasDoctorType'] ?? false;
      }
    } catch (e) {
      debugPrint('❌ _fetchDoctorType: $e');
    }
  }

  Future<void> _fetchDoctorAvailability(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/doctors/doctor/availability'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _hasDoctorAvailability = data['doctorAvailability'] ?? false;
      }
    } catch (e) {
      debugPrint('❌ _fetchDoctorAvailability: $e');
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _card1Ctrl.dispose();
    _card2Ctrl.dispose();
    super.dispose();
  }

  // ── navigation ─────────────────────────────────────────────────────────────
  void _go(String dashboardType) {
    HapticFeedback.lightImpact();
    final role = dashboardType.toLowerCase();

    if (role == 'patient') {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else if (role == 'doctor') {
      if (!_hasDoctorType) {
        // Navigator.pushReplacementNamed(context, AppRoutes.doctorType);
      } else if (!_hasDoctorAvailability) {
        // Navigator.pushReplacementNamed(context, AppRoutes.doctorAvailability);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } else if (role == 'nurse') {
      // Navigator.pushReplacementNamed(context, AppRoutes.nurseDashboard);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.signIn);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const _LoadingScreen();

    final rd = _roleDataFor(_role);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: Stack(
        children: [
          // ── decorative background blobs ──────────────────────────────────
          Positioned(
            top: -80,
            right: -60,
            child: _Blob(color: rd.accent.withOpacity(0.10), size: 280),
          ),
          Positioned(
            bottom: -100,
            left: -80,
            child: _Blob(color: rd.accent.withOpacity(0.07), size: 340),
          ),
          Positioned(
            top: size.height * 0.35,
            left: -40,
            child: _Blob(
              color: const Color(0xFF7C3AED).withOpacity(0.05),
              size: 160,
            ),
          ),

          // ── main content ─────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        children: [
                          _Header(role: _role, firstName: _firstName, rd: rd),
                          const SizedBox(height: 36),
                          _SectionLabel(text: 'Choose your dashboard'),
                          const SizedBox(height: 16),

                          // patient card
                          FadeTransition(
                            opacity: _card1Fade,
                            child: SlideTransition(
                              position: _card1Slide,
                              child: _DashboardCard(
                                label: 'Continue as Patient',
                                sublabel:
                                    'Access appointments & health records',
                                icon: Icons.person_rounded,
                                accent: const Color(0xFF0EA5E9),
                                accentLight: const Color(0xFFF0F9FF),
                                isPrimary: true,
                                onTap: () => _go('patient'),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // role card
                          FadeTransition(
                            opacity: _card2Fade,
                            child: SlideTransition(
                              position: _card2Slide,
                              child: _DashboardCard(
                                label: 'Continue as ${_capitalise(_role)}',
                                sublabel: rd.dashLabel,
                                icon: rd.icon,
                                accent: rd.accent,
                                accentLight: rd.accentLight,
                                isPrimary: false,
                                onTap: () => _go(_role),
                              ),
                            ),
                          ),

                          const SizedBox(height: 40),
                          _Footer(accent: rd.accent),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── sub-widgets ─────────────────────────────────────────────────────────────

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF8FAFF),
      body: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Color(0xFF2563EB),
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _Header extends StatelessWidget {
  final String role;
  final String firstName;
  final _RoleData rd;

  const _Header({
    required this.role,
    required this.firstName,
    required this.rd,
  });

  @override
  Widget build(BuildContext context) {
    final prefix = rd.prefix.isNotEmpty ? '${rd.prefix} ' : '';

    return Column(
      children: [
        // avatar ring
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: rd.accentLight,
            border: Border.all(color: rd.accent.withOpacity(0.25), width: 2),
          ),
          child: Icon(rd.icon, color: rd.accent, size: 36),
        ),
        const SizedBox(height: 20),

        // greeting
        Text(
          'Welcome back,',
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$prefix$firstName',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),

        // role pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: rd.accentLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: rd.accent.withOpacity(0.2)),
          ),
          child: Text(
            _capitalise(role),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: rd.accent,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF94A3B8),
          letterSpacing: 0.6,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Container(height: 1, color: const Color(0xFFE2E8F0))),
    ],
  );
}

class _DashboardCard extends StatefulWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color accent;
  final Color accentLight;
  final bool isPrimary;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.accent,
    required this.accentLight,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  State<_DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<_DashboardCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.975,
    ).animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: widget.isPrimary ? _buildPrimary() : _buildSecondary(),
      ),
    );
  }

  Widget _buildPrimary() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [widget.accent, widget.accent.withOpacity(0.82)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: widget.accent.withOpacity(0.35),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: _CardContent(
      label: widget.label,
      sublabel: widget.sublabel,
      icon: widget.icon,
      iconBg: Colors.white.withOpacity(0.18),
      iconColor: Colors.white,
      labelColor: Colors.white,
      sublabelColor: Colors.white.withOpacity(0.82),
      chevronColor: Colors.white.withOpacity(0.7),
    ),
  );

  Widget _buildSecondary() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: _CardContent(
      label: widget.label,
      sublabel: widget.sublabel,
      icon: widget.icon,
      iconBg: widget.accentLight,
      iconColor: widget.accent,
      labelColor: const Color(0xFF0F172A),
      sublabelColor: const Color(0xFF64748B),
      chevronColor: const Color(0xFFCBD5E1),
    ),
  );
}

class _CardContent extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final Color labelColor;
  final Color sublabelColor;
  final Color chevronColor;

  const _CardContent({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.labelColor,
    required this.sublabelColor,
    required this.chevronColor,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: labelColor,
                letterSpacing: -0.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 12,
                color: sublabelColor,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      Icon(Icons.arrow_forward_ios_rounded, size: 15, color: chevronColor),
    ],
  );
}

class _Footer extends StatelessWidget {
  final Color accent;
  const _Footer({required this.accent});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'Choose the dashboard that fits your current task.\nYou can switch at any time.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.6),
      ),
    ],
  );
}

// ─── helpers ─────────────────────────────────────────────────────────────────
String _capitalise(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
