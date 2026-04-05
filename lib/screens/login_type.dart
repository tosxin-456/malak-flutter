import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:malak/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../routes/app_routes.dart';
import '../config/api_config.dart';

class LoginTypeScreen extends StatefulWidget {
  const LoginTypeScreen({super.key});

  @override
  State<LoginTypeScreen> createState() => _LoginTypeScreenState();
}

class _LoginTypeScreenState extends State<LoginTypeScreen>
    with SingleTickerProviderStateMixin {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String _userRole = '';
  String _userName = '';
  bool _isLoading = true;
  bool _hasDoctorType = false;
  bool _doctorAvailability = false;
  bool _loadingStatus = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _initialize();
  }

  Future<void> _initialize() async {
    await _decodeToken();
    await Future.wait([_checkDoctorType(), _checkDoctorAvailability()]);
    if (mounted) {
      setState(() => _isLoading = false);
      _animController.forward();
    }
  }

  Future<void> _decodeToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final decoded = JwtDecoder.decode(token);
       final fullName = await StorageService.getSavedFullName() ?? '';
      final firstName = fullName.split(' ').first;
      print(decoded);

      if (mounted) {
        setState(() {
          _userRole = decoded['role'] ?? 'user';
          _userName = firstName;
        });
      }
    } catch (e) {
      debugPrint('Token decode error: $e');
    }
  }

  Future<void> _checkDoctorType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final response = await http.get(
        Uri.parse('$API_BASE_URL/doctors/doctor/type'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted)
          setState(() => _hasDoctorType = data['hasDoctorType'] ?? false);
      }
    } catch (e) {
      debugPrint('Doctor type check error: $e');
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  Future<void> _checkDoctorAvailability() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final response = await http.get(
        Uri.parse('$API_BASE_URL/doctors/doctor/availability'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(
            () => _doctorAvailability = data['doctorAvailability'] ?? false,
          );
        }
      }
    } catch (e) {
      debugPrint('Doctor availability check error: $e');
    }
  }

  String _getRolePrefix(String role) {
    switch (role.toLowerCase()) {
      case 'doctor':
        return 'Dr.';
      case 'pharmacist':
        return 'Pharm.';
      case 'nurse':
        return 'Nurse';
      default:
        return '';
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'doctor':
        return Icons.local_hospital;
      case 'pharmacist':
        return Icons.medication_outlined;
      case 'nurse':
        return Icons.medical_services_outlined;
      default:
        return Icons.person_outline;
    }
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'doctor':
        return const Color(0xFF2563EB);
      case 'pharmacist':
        return const Color(0xFF16A34A);
      case 'nurse':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF6B7280);
    }
  }

  void _handleDashboardSelection(String dashboardType) {
    final role = dashboardType.toLowerCase();

    if (role == 'patient') {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else if (role == 'doctor') {
      if (!_hasDoctorType) {
        Navigator.pushReplacementNamed(context, AppRoutes.doctorType);
      } else if (!_doctorAvailability) {
        Navigator.pushReplacementNamed(context, AppRoutes.doctorAvailability);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.doctorDashboard);
      }
    } else if (role == 'nurse') {
      Navigator.pushReplacementNamed(context, AppRoutes.nurseDashboard);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.signIn);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFEEF2FF),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF2563EB),
            strokeWidth: 3,
          ),
        ),
      );
    }

    final roleColor = _getRoleColor(_userRole);
    final rolePrefix = _getRolePrefix(_userRole);
    final roleLabel = _userRole.isEmpty
        ? 'User'
        : '${_userRole[0].toUpperCase()}${_userRole.substring(1)}';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEFF6FF), Color(0xFFE0E7FF)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 448),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 40,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Role icon in circle
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: roleColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _getRoleIcon(_userRole),
                            color: roleColor,
                            size: 36,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Welcome text
                        Text(
                          'Welcome, $roleLabel!',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937),
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 6),

                        Text(
                          'Hello${rolePrefix.isNotEmpty ? ' $rolePrefix' : ''} $_userName',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF6B7280),
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 32),

                        // Section heading
                        const Text(
                          'How would you like to login?',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151),
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 20),

                        // Patient button
                        _DashboardButton(
                          label: 'As a Patient',
                          icon: Icons.people_outline,
                          backgroundColor: const Color(0xFF2563EB),
                          hoverColor: const Color(0xFF1D4ED8),
                          onTap: () => _handleDashboardSelection('Patient'),
                        ),

                        const SizedBox(height: 12),

                        // Role-specific button
                        _DashboardButton(
                          label: 'As a $roleLabel',
                          icon: _getRoleIcon(_userRole),
                          backgroundColor: const Color(0xFF4B5563),
                          hoverColor: const Color(0xFF374151),
                          onTap: () => _handleDashboardSelection(_userRole),
                        ),

                        const SizedBox(height: 28),

                        // Footer hint
                        const Text(
                          'Choose the appropriate dashboard based on your current needs',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9CA3AF),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color hoverColor;
  final VoidCallback onTap;

  const _DashboardButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.hoverColor,
    required this.onTap,
  });

  @override
  State<_DashboardButton> createState() => _DashboardButtonState();
}

class _DashboardButtonState extends State<_DashboardButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: _pressed ? widget.hoverColor : widget.backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
