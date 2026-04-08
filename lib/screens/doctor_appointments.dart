import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';
import 'package:malak/context/socket_provider.dart'; // <-- your new file

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

/// No longer needs socket/userId props — reads them from [SocketProvider].
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

  bool _showWaitingModal = false;
  String? _selectedPatient;
  String? _currentConsultId;
  String? _currentConsultMode;
  String? _currentPatientId;
  Timer? _waitingTimeout;

  // cached reference so we can unbind safely
  late SocketNotifier _socketNotifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Grab notifier once; safe to call in didChangeDependencies.
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
    super.dispose();
  }

  // ── Socket events ─────────────────────────────────────────────────────────

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

    setState(() {
      _showWaitingModal = false;
      _currentConsultId = null;
    });

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
    setState(() {
      _showWaitingModal = false;
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
      if (token == null || token.isEmpty) {
        throw Exception('User not authenticated');
      }

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

  // ── Start consultation ────────────────────────────────────────────────────

  Future<void> _handleStartConsultation(DoctorApt apt) async {
    final notifier = _socketNotifier;
    final socket = notifier.socket;
    final userId = notifier.userId;

    if (socket == null) {
      setState(() => _errorMessage = 'Real-time service unavailable.');
      return;
    }

    // Clear any previous error
    setState(() => _errorMessage = null);

    try {
      final token = await StorageService.getToken();
      if (token == null || token.isEmpty) throw Exception('Not authenticated');

      _currentConsultMode = apt.type;

      // 1️⃣ Create consultation on server
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

      if (!mounted) return;
      setState(() {
        _showWaitingModal = true;
        _selectedPatient = apt.patientName;
      });

      // 2️⃣ Ensure socket is connected (short grace period)
      if (!socket.connected) {
        socket.connect();
        await Future.delayed(const Duration(seconds: 2));
      }

      // Rebind events after potential reconnect
      _unbindSocketEvents();
      _bindSocketEvents();

      // 3️⃣ Notify patient
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

      // 4️⃣ 60-second timeout — auto-cancel if patient doesn't respond
      _waitingTimeout?.cancel();
      _waitingTimeout = Timer(const Duration(seconds: 60), () {
        if (_currentConsultId == consultId && mounted) {
          socket.emit('consult:cancelled', {
            'consultId': consultId,
            'reason': 'timeout',
          });
          setState(() {
            _showWaitingModal = false;
            _selectedPatient = null;
            _currentConsultId = null;
            _errorMessage = 'Patient did not respond. Try again later.';
          });
        }
      });
    } catch (e) {
      debugPrint('Start consultation error: $e');
      if (mounted) {
        setState(() {
          _showWaitingModal = false;
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
    if (mounted) {
      setState(() {
        _showWaitingModal = false;
        _selectedPatient = null;
        _currentConsultId = null;
        _currentPatientId = null;
      });
    }
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
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upcoming Appointments',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(color: Color(0xFF059669)),
                ),
              )
            else if (_appointments.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 40,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No appointments scheduled. Enjoy your day!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _appointments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _appointmentCard(_appointments[i]),
              ),
          ],
        ),
        if (_showWaitingModal) _buildWaitingModal(),
      ],
    );
  }

  Widget _appointmentCard(DoctorApt apt) {
    return Container(
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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    const SizedBox(height: 2),
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
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.access_time, size: 13, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 6),
              Text(
                '${_formatDate(apt.appointmentDateTime)} at ${apt.time}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                apt.type == 'online'
                    ? Icons.video_call_outlined
                    : Icons.location_on_outlined,
                size: 13,
                color: const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 6),
              Text(
                apt.type == 'online' ? 'Online' : 'In-person',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _statusBg(apt.status),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${apt.status[0].toUpperCase()}${apt.status.substring(1)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _statusFg(apt.status),
                  ),
                ),
              ),
              if (apt.status == 'confirmed')
                ElevatedButton(
                  onPressed: () => _handleStartConsultation(apt),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Start Consultation',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                )
              else if (apt.status == 'pending')
                OutlinedButton.icon(
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
                  icon: const Icon(Icons.visibility_outlined, size: 13),
                  label: const Text(
                    'View Details',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _patientAvatar(String? url) {
    final hasUrl = url != null && url.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: hasUrl
          ? Image.network(
              url,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackAvatar(),
            )
          : _fallbackAvatar(),
    );
  }

  Widget _fallbackAvatar() => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: const Color(0xFFE5E7EB),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(Icons.person, color: Color(0xFF9CA3AF), size: 24),
  );

  Widget _buildWaitingModal() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD1FAE5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.video_call,
                    color: Color(0xFF059669),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Waiting for Patient',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_selectedPatient ?? 'Patient'} has been notified. Waiting for them to join…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 24),
                const _BouncingDots(),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _cancelWaiting,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
            end: -10,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
        )
        .toList();
    for (var i = 0; i < 3; i++) {
      Future.delayed(
        Duration(milliseconds: i * 150),
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
              width: 12,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 4),
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
