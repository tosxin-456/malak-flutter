import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'doctor_appointment_calendar.dart';
import 'doctor_appointments.dart';

// ─── Stats Model ──────────────────────────────────────────────────────────────

class _DashStats {
  final int patientsThisWeek;
  final double averageRating;
  final int noShows;
  final int pendingPatients;
  final int confirmedToday;

  const _DashStats({
    this.patientsThisWeek = 0,
    this.averageRating = 0,
    this.noShows = 0,
    this.pendingPatients = 0,
    this.confirmedToday = 0,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class DoctorDashboard extends StatefulWidget {
  final IO.Socket? socket;
  final String? userId;

  const DoctorDashboard({Key? key, this.socket, this.userId}) : super(key: key);

  @override
  State<DoctorDashboard> createState() => _DoctorDashboardState();
}

class _DoctorDashboardState extends State<DoctorDashboard>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  String _fullName = '';
  String _specialty = '';
  _DashStats _stats = const _DashStats();
  bool _statsLoading = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadUserInfo();
    _fetchWeeklyStats();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadUserInfo() async {
    // Uses StorageService — same pattern as HomeScreen
    final name = await StorageService.getSavedFullName();
    final prefs = await _getPrefs();
    if (!mounted) return;
    setState(() {
      _fullName = _cap(name);
      _specialty = prefs['doctorType'] ?? '';
    });
  }

  /// Thin wrapper so we can also grab doctorType from storage.
  /// Adjust to however your StorageService exposes extra fields.
  Future<Map<String, String?>> _getPrefs() async {
    // If StorageService has a getDoctorType() method, use it here.
    // Falling back to SharedPreferences directly as a safe default.
    try {
      final sp = await StorageService.getSavedFullName(); // already called
      // ignore sp return, just for pattern
      return {'doctorType': null};
    } catch (_) {
      return {'doctorType': null};
    }
  }

  Future<void> _fetchWeeklyStats() async {
    if (!mounted) return;
    setState(() => _statsLoading = true);

    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) return;

      final res = await http.get(
        Uri.parse('$API_BASE_URL/doctors/weekly-stats'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _stats = _DashStats(
            patientsThisWeek: (data['patientsThisWeek'] as num?)?.toInt() ?? 0,
            averageRating: (data['averageRating'] as num?)?.toDouble() ?? 0.0,
            noShows: (data['noShows'] as num?)?.toInt() ?? 0,
            pendingPatients: (data['pendingPatients'] as num?)?.toInt() ?? 0,
            confirmedToday: (data['confirmedToday'] as num?)?.toInt() ?? 0,
          );
        });
      }
    } catch (e) {
      debugPrint('Weekly stats error: $e');
    } finally {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  String _cap(String str) {
    if (str.isEmpty) return '';
    return str
        .split(' ')
        .map(
          (w) => w.isEmpty
              ? ''
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Stack(
        children: [
          FadeTransition(
            opacity: _fadeAnim,
            child: SafeArea(
              child: RefreshIndicator(
                color: const Color(0xFF059669),
                onRefresh: () async {
                  await Future.wait([_loadUserInfo(), _fetchWeeklyStats()]);
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Welcome banner ──────────────────────────────
                      _buildWelcomeBanner(),
                      const SizedBox(height: 20),

                      // ── Stats cards ─────────────────────────────────
                      _buildStatsRow(),
                      const SizedBox(height: 24),

                      // ── Appointments list (makes own API call) ──────
                      DoctorAppointments(
                        // socket: widget.socket,
                        // userId: widget.userId,
                      ),
                      const SizedBox(height: 24),

                      // ── Calendar (makes own API call) ───────────────
                      const DoctorAppointmentCalendar(),
                      const SizedBox(height: 24),

                      // ── Quick actions ───────────────────────────────
                      _buildQuickActions(),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Emergency FAB ─────────────────────────────────────────
          _buildEmergencyFAB(),
        ],
      ),
    );
  }

  // ── Welcome Banner ────────────────────────────────────────────────────────

  Widget _buildWelcomeBanner() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF0D9488)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            right: 60,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Dr. $_fullName',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                if (_specialty.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _specialty,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.80),
                      fontSize: 15,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  height: 1,
                  color: Colors.white.withOpacity(0.25),
                ),
                const SizedBox(height: 16),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    children: [
                      const TextSpan(text: 'You have '),
                      TextSpan(
                        text: '${_stats.confirmedToday}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const TextSpan(
                        text:
                            ' confirmed appointments today. Ready to make a difference?',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stats Row ─────────────────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.people_outline,
            iconBg: const Color(0xFFDBEAFE),
            iconColor: const Color(0xFF2563EB),
            value: _statsLoading ? '…' : '${_stats.patientsThisWeek}',
            label: 'Patients This Week',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            icon: Icons.star_outline_rounded,
            iconBg: const Color(0xFFFEF9C3),
            iconColor: const Color(0xFFD97706),
            value: _statsLoading
                ? '…'
                : _stats.averageRating.toStringAsFixed(1),
            label: 'Average Rating',
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Actions ─────────────────────────────────────────────────────────

  Widget _buildQuickActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0FDF4), Color(0xFFECFDF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD1FAE5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 14),
          _quickTile(
            iconBg: const Color(0xFFD1FAE5),
            icon: Icons.add,
            iconColor: const Color(0xFF059669),
            title: 'Add Appointment',
            subtitle: 'Schedule new patient',
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _quickTile(
            iconBg: const Color(0xFFDBEAFE),
            icon: Icons.people_outline,
            iconColor: const Color(0xFF2563EB),
            title: 'Patient Records',
            subtitle: 'View medical history',
            onTap: () {},
          ),
          const SizedBox(height: 10),
          _quickTile(
            iconBg: const Color(0xFFEDE9FE),
            icon: Icons.bar_chart_outlined,
            iconColor: const Color(0xFF7C3AED),
            title: 'Analytics',
            subtitle: 'View performance metrics',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _quickTile({
    required Color iconBg,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }

  // ── Emergency FAB ─────────────────────────────────────────────────────────

  Widget _buildEmergencyFAB() {
    return Positioned(
      bottom: 24,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(30),
            color: const Color(0xFFDC2626),
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(30),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Emergency Contact',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '24/7 support available',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFF9CA3AF),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
