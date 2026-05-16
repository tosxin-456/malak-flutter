import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';
import 'package:malak/context/socket_provider.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class DoctorApt {
  final String id;
  final String? patientId;
  final String patientName;
  final String? avatar;
  final DateTime appointmentDateTime;
  final String time;
  final String type;
  final String reason;
  final String status;
  final Map<String, dynamic>? raw;

  const DoctorApt({
    required this.id,
    this.patientId,
    required this.patientName,
    this.avatar,
    required this.appointmentDateTime,
    required this.time,
    required this.type,
    required this.reason,
    required this.status,
    this.raw,
  });

  factory DoctorApt.fromJson(Map<String, dynamic> json) {
    final dt =
        DateTime.tryParse(json['appointmentDateTime'] as String? ?? '') ??
        DateTime.now();
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final fallbackTime = '$h12:$minute $ampm';

    return DoctorApt(
      id: json['_id'] as String? ?? '',
      patientId: json['patient']?['_id'] as String?,
      patientName: json['patient']?['fullName'] as String? ?? 'Unknown',
      avatar: json['patient']?['profile_image'] as String?,
      appointmentDateTime: dt,
      time: json['time'] as String? ?? fallbackTime,
      type: (json['appointmentMode'] as String?) == 'online'
          ? 'online'
          : 'offline',
      reason: json['reason'] as String? ?? 'No reason provided',
      status: json['status'] as String? ?? 'pending',
      raw: json,
    );
  }
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class DoctorAppointments extends StatefulWidget {
  const DoctorAppointments({Key? key}) : super(key: key);

  @override
  State<DoctorAppointments> createState() => _DoctorAppointmentsState();
}

class _DoctorAppointmentsState extends State<DoctorAppointments> {
  List<DoctorApt> _appointments = [];
  List<Map<String, dynamic>> _fullDetails = [];
  bool _loading = true;
  String? _errorMessage;

  String? _selectedPatient;
  String? _currentConsultId;
  String? _currentConsultMode;
  String? _currentPatientId;
  Timer? _waitingTimeout;
  OverlayEntry? _overlayEntry;

  late SocketNotifier _socketNotifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _socketNotifier = SocketProvider.of(context);
    _bindSocketEvents();
  }

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  @override
  void dispose() {
    _waitingTimeout?.cancel();
    _unbindSocketEvents();
    _removeWaitingOverlay();
    super.dispose();
  }

  // ── Socket ────────────────────────────────────────────────────────────────

  void _bindSocketEvents() {
    _socketNotifier.socket?.on('consult:accepted', _onConsultAccepted);
    _socketNotifier.socket?.on('consult:cancelled', _onConsultCancelled);
  }

  void _unbindSocketEvents() {
    _socketNotifier.socket?.off('consult:accepted');
    _socketNotifier.socket?.off('consult:cancelled');
  }

  void _onConsultAccepted(dynamic data) {
    if (data is! Map) return;
    final consultId = data['consultId'] as String?;
    if (consultId == null || consultId != _currentConsultId) return;
    _waitingTimeout?.cancel();
    _waitingTimeout = null;
    if (!mounted) return;
    final mode = _currentConsultMode;
    final cid = _currentConsultId;
    _removeWaitingOverlay();
    setState(() => _currentConsultId = null);
    if (mode == 'offline') {
      Navigator.of(context).pushNamed('/consultation-room/$cid/visit');
    } else {
      Navigator.of(context).pushNamed('/consultation-room/$cid/live');
    }
  }

  void _onConsultCancelled(dynamic data) {
    if (data is! Map) return;
    final consultId = data['consultId'] as String?;
    if (consultId == null || consultId != _currentConsultId) return;
    _waitingTimeout?.cancel();
    _waitingTimeout = null;
    if (!mounted) return;
    final reason = data['reason'] as String?;
    _removeWaitingOverlay();
    setState(() {
      _selectedPatient = null;
      _currentConsultId = null;
      _errorMessage = reason == 'doctor_cancel'
          ? 'You cancelled the consultation.'
          : 'Patient declined the consultation.';
    });
  }

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadAppointments() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) throw Exception('Not authenticated');
      final res = await http.get(
        Uri.parse('$API_BASE_URL/appointments/doctor'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Failed to fetch appointments');
      }
      final raw = jsonDecode(res.body) as List<dynamic>;
      _fullDetails = raw.cast<Map<String, dynamic>>();
      final now = DateTime.now();
      final mapped =
          raw
              .map((e) => DoctorApt.fromJson(e as Map<String, dynamic>))
              .where((a) => a.appointmentDateTime.isAfter(now))
              .toList()
            ..sort(
              (a, b) => a.appointmentDateTime.compareTo(b.appointmentDateTime),
            );
      setState(() => _appointments = mapped);
    } catch (e) {
      debugPrint('DoctorAppointments error: $e');
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Consultation ──────────────────────────────────────────────────────────

  Future<void> _handleStartConsultation(DoctorApt apt) async {
    final socket = _socketNotifier.socket;
    final userId = _socketNotifier.userId;
    if (socket == null) {
      setState(() => _errorMessage = 'Real-time service unavailable.');
      return;
    }
    setState(() => _errorMessage = null);
    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) throw Exception('Not authenticated');
      _currentConsultMode = apt.type;
      final res = await http.post(
        Uri.parse('$API_BASE_URL/consultations/create'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'appointmentId': apt.id, 'patientId': apt.patientId}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception(body['message'] ?? 'Failed to create consultation');
      }
      final consultId = body['consultId'] as String?;
      if (consultId == null) throw Exception('No consultId returned');
      _currentConsultId = consultId;
      _currentPatientId = apt.patientId;
      setState(() => _selectedPatient = apt.patientName);
      _showWaitingOverlay();
      if (!socket.connected) {
        socket.connect();
        await Future.delayed(const Duration(seconds: 2));
      }
      _unbindSocketEvents();
      _bindSocketEvents();
      socket.emit('consult:incoming', {
        'to': apt.patientId,
        'from': userId,
        'consultId': consultId,
        'appointmentMode': apt.type,
      });
      socket.emit('consult:doctor_ready', {
        'to': apt.patientId,
        'consultId': consultId,
      });
      _waitingTimeout?.cancel();
      _waitingTimeout = Timer(const Duration(seconds: 60), () {
        if (_currentConsultId == consultId && mounted) {
          socket.emit('consult:cancelled', {
            'consultId': consultId,
            'reason': 'timeout',
          });
          _removeWaitingOverlay();
          setState(() {
            _selectedPatient = null;
            _currentConsultId = null;
            _errorMessage = 'Patient did not respond. Try again later.';
          });
        }
      });
    } catch (e) {
      debugPrint('Start consultation error: $e');
      if (mounted) {
        _removeWaitingOverlay();
        setState(() {
          _currentConsultId = null;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _cancelWaiting() {
    final socket = _socketNotifier.socket;
    if (_currentConsultId != null && socket != null) {
      socket.emit('consult:cancelled', {
        'to': _currentPatientId,
        'consultId': _currentConsultId,
        'reason': 'doctor_cancel',
      });
    }
    _waitingTimeout?.cancel();
    _waitingTimeout = null;
    _removeWaitingOverlay();
    if (mounted) {
      setState(() {
        _selectedPatient = null;
        _currentConsultId = null;
        _currentPatientId = null;
      });
    }
  }

  // ── Overlay ───────────────────────────────────────────────────────────────

  void _showWaitingOverlay() {
    _overlayEntry = OverlayEntry(
      builder: (_) => Material(
        color: Colors.black54,
        child: SafeArea(
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF059669).withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.video_call_rounded,
                      color: Color(0xFF059669),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  const Text(
                    'Waiting for Patient',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Subtitle
                  Text(
                    '${_selectedPatient ?? 'Patient'} has been notified.\nWaiting for them to join…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Dots
                  const _BouncingDots(),
                  const SizedBox(height: 32),

                  // Divider
                  Container(height: 1, color: const Color(0xFFF3F4F6)),
                  const SizedBox(height: 20),

                  // Cancel
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _cancelWaiting,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                      ),
                      child: const Text(
                        'Cancel Consultation',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeWaitingOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _statusBg(String s) {
    switch (s.toLowerCase()) {
      case 'confirmed':
        return const Color(0xFFDCFCE7);
      case 'pending':
        return const Color(0xFFFEF9C3);
      case 'completed':
        return const Color(0xFFDBEAFE);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Color _statusFg(String s) {
    switch (s.toLowerCase()) {
      case 'confirmed':
        return const Color(0xFF166534);
      case 'pending':
        return const Color(0xFF92400E);
      case 'completed':
        return const Color(0xFF1D4ED8);
      default:
        return const Color(0xFF374151);
    }
  }

  IconData _statusIcon(String s) {
    switch (s.toLowerCase()) {
      case 'confirmed':
        return Icons.check_circle_outline_rounded;
      case 'pending':
        return Icons.hourglass_empty_rounded;
      case 'completed':
        return Icons.task_alt_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  String _formatDate(DateTime dt) {
    const wd = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${wd[dt.weekday % 7]}, ${mo[dt.month - 1]} ${dt.day}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Upcoming Appointments',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            GestureDetector(
              onTap: _loadAppointments,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFF059669),
                  size: 18,
                ),
              ),
            ),
          ],
        ),

        // Error banner
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFDC2626),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _errorMessage = null),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFFDC2626),
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Content
        if (_loading)
          _buildSkeleton()
        else if (_appointments.isEmpty)
          _buildEmpty()
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _appointments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _appointmentCard(_appointments[i]),
          ),
      ],
    );
  }

  // ── Skeleton loader ───────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return Column(
      children: List.generate(
        3,
        (_) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF3F4F6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _shimmer(width: 48, height: 48, radius: 10),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _shimmer(width: 140, height: 14, radius: 6),
                      const SizedBox(height: 6),
                      _shimmer(width: 100, height: 11, radius: 6),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _shimmer(width: 180, height: 11, radius: 6),
              const SizedBox(height: 8),
              _shimmer(width: 120, height: 11, radius: 6),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _shimmer(width: 80, height: 26, radius: 20),
                  _shimmer(width: 120, height: 36, radius: 10),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shimmer({
    required double width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              size: 30,
              color: Color(0xFF059669),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No appointments today',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Enjoy your free time — no upcoming\nappointments scheduled.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF9CA3AF),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Appointment card ──────────────────────────────────────────────────────

  Widget _appointmentCard(DoctorApt apt) {
    final isConfirmed = apt.status.toLowerCase() == 'confirmed';
    final isPending = apt.status.toLowerCase() == 'pending';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConfirmed
              ? const Color(0xFFD1FAE5)
              : const Color(0xFFF3F4F6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top accent bar for confirmed
          if (isConfirmed)
            Container(
              height: 4,
              decoration: const BoxDecoration(
                color: Color(0xFF059669),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Patient row
                Row(
                  children: [
                    _patientAvatar(apt.avatar),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            apt.patientName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            apt.reason,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _statusBg(apt.status),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _statusIcon(apt.status),
                            size: 11,
                            color: _statusFg(apt.status),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${apt.status[0].toUpperCase()}${apt.status.substring(1)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _statusFg(apt.status),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Container(height: 1, color: const Color(0xFFF9FAFB)),
                const SizedBox(height: 14),

                // Info chips row
                Row(
                  children: [
                    _infoChip(icon: Icons.access_time_rounded, label: apt.time),
                    const SizedBox(width: 8),
                    _infoChip(
                      icon: Icons.calendar_month_outlined,
                      label: _formatDate(apt.appointmentDateTime),
                    ),
                    const SizedBox(width: 8),
                    _infoChip(
                      icon: apt.type == 'online'
                          ? Icons.video_call_outlined
                          : Icons.location_on_outlined,
                      label: apt.type == 'online' ? 'Online' : 'In-person',
                      color: apt.type == 'online'
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF059669),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Action buttons
                if (isConfirmed)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _handleStartConsultation(apt),
                      icon: const Icon(
                        Icons.play_circle_outline_rounded,
                        size: 18,
                      ),
                      label: const Text(
                        'Start Consultation',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                    ),
                  )
                else if (isPending)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final full = _fullDetails.firstWhere(
                          (a) => a['_id'] == apt.id,
                          orElse: () => {},
                        );
                        Navigator.of(context).pushNamed(
                          '/patient/${apt.patientId}',
                          arguments: {'appointmentFull': full},
                        );
                      },
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text(
                        'View Details',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF374151),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
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

  Widget _infoChip({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final c = color ?? const Color(0xFF6B7280);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: c,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _patientAvatar(String? url) {
    final hasUrl = url != null && url.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: hasUrl
          ? Image.network(
              url,
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackAvatar(),
            )
          : _fallbackAvatar(),
    );
  }

  Widget _fallbackAvatar() => Container(
    width: 50,
    height: 50,
    decoration: BoxDecoration(
      color: const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(Icons.person, color: Color(0xFF059669), size: 26),
  );
}

// ─── Bouncing dots ────────────────────────────────────────────────────────────

class _BouncingDots extends StatefulWidget {
  const _BouncingDots();

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      ),
    );
    _anims = _controllers
        .map(
          (c) => Tween<double>(
            begin: 0,
            end: -12,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        )
        .toList();
    for (var i = 0; i < 3; i++) {
      Future.delayed(
        Duration(milliseconds: i * 160),
        () => mounted ? _controllers[i].repeat(reverse: true) : null,
      );
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => AnimatedBuilder(
          animation: _anims[i],
          builder: (_, __) => Transform.translate(
            offset: Offset(0, _anims[i].value),
            child: Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: const BoxDecoration(
                color: Color(0xFF059669),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
