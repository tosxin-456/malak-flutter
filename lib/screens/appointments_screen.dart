import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:paystack_for_flutter/paystack_for_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:malak/components/doctor_selection_component.dart';
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// ─── Constants ────────────────────────────────────────────────────────────────

const _paystackSecretKey = 'sk_test_f5faaf8b06c41bc54016378dfa88964e479d33a6';

// ─── Screen ───────────────────────────────────────────────────────────────────

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  String _activeTab = 'book';
  DateTime? _selectedDateTime;
  DoctorModel? _selectedDoctor;
  String? _selectedHospitalId;
  Map<String, dynamic>? _user;
  bool _loading = true;
  String _appointmentMode = 'offline';
  String _reason = '';
  List<dynamic> _appointments = [];
  Map<String, bool> _openDetails = {};
  bool _bookingInProgress = false;
  final _reasonController = TextEditingController();

  // ── Key to force DoctorSelectionComponent to fully reset ──────────────────
  Key _doctorSelectionKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _fetchProfile();
    _fetchAppointments();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  // ── Reset all booking fields ───────────────────────────────────────────────

  void _resetBookingForm() {
    setState(() {
      _selectedDoctor = null;
      _selectedHospitalId = null;
      _selectedDateTime = null;
      _reason = '';
      _appointmentMode = 'offline';
      _doctorSelectionKey =
          UniqueKey(); // forces DoctorSelectionComponent to rebuild fresh
    });
    _reasonController.clear();
  }

  // ── Network calls ──────────────────────────────────────────────────────────

  Future<void> _fetchProfile() async {
    final token = await StorageService.getToken();
    if (token == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        setState(() => _user = json.decode(response.body));
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchAppointments() async {
    try {
      final token = await StorageService.getToken();
      final response = await http.get(
        Uri.parse('$API_BASE_URL/appointments/user'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        setState(() => _appointments = json.decode(response.body));
      }
    } catch (e) {
      debugPrint('Error fetching appointments: $e');
    }
  }

  // ── Payment ────────────────────────────────────────────────────────────────

  Future<String> _chargeWithPaystack() async {
    final completer = Completer<String>();

    final email = _user?['email'] as String? ?? 'patient@malak.app';
    final prefs = await SharedPreferences.getInstance();

    final fullName = prefs.getString('fullName') ?? '';
    final nameParts = fullName
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();

    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    final reference = 'APPT-${DateTime.now().millisecondsSinceEpoch}';

    const double amountInKobo = 2500;

    debugPrint('🚀 Starting payment...');

    PaystackFlutter().pay(
      context: context,
      secretKey: _paystackSecretKey,
      amount: amountInKobo,
      email: email,
      firstName: firstName,
      lastName: lastName,
      currency: Currency.NGN,
      reference: reference,
      callbackUrl: 'https://malak.app/payment/callback',

      onSuccess: (response) {
        final ref = response.reference ?? reference;
        debugPrint('✅ SUCCESS: $ref');
        if (!completer.isCompleted) {
          completer.complete(ref);
        }
      },

      onCancelled: (response) {
        debugPrint('❌ CANCELLED: $response');
        if (!completer.isCompleted) {
          completer.completeError(Exception('Payment cancelled'));
        }
      },
    );

    return completer.future;
  }

  // ── Booking ────────────────────────────────────────────────────────────────

  Future<void> _bookAppointment() async {
    if (_selectedDoctor == null) {
      _showSnack('Please select a doctor.');
      return;
    }
    if (_selectedDateTime == null) {
      _showSnack('Please select a date and time.');
      return;
    }
    if (_reason.isEmpty) {
      _showSnack('Please enter your reason for visit.');
      return;
    }
    if (_appointmentMode.isEmpty) {
      _showSnack('Please select an appointment mode.');
      return;
    }

    setState(() => _bookingInProgress = true);

    try {
      final paymentRef = await _chargeWithPaystack();
      await _createAppointment(paymentRef);

      _showSnack('Appointment booked successfully!', success: true);
      _resetBookingForm();
      _fetchAppointments();
    } catch (e) {
      debugPrint('[Booking] error: $e');
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _bookingInProgress = false);
    }
  }

  Future<void> _createAppointment(String paymentRef) async {
    final token = await StorageService.getToken();

    final body = {
      'doctor': _selectedDoctor!.id,
      'hospital': _selectedHospitalId,
      'patient': _user?['_id'],
      'date': _selectedDateTime!.toIso8601String().split('T')[0],
      'time':
          '${_selectedDateTime!.hour.toString().padLeft(2, '0')}:${_selectedDateTime!.minute.toString().padLeft(2, '0')}',
      'reason': _reason,
      'appointmentMode': _appointmentMode,
      'paymentRef': paymentRef,
      'isPaid': true,
    };

    final response = await http.post(
      Uri.parse('$API_BASE_URL/appointments'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(body),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final data = json.decode(response.body);
      throw Exception(data['message'] ?? 'Failed to book appointment');
    }
  }

  // ── Date/Time picker ───────────────────────────────────────────────────────

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (_selectedDoctor != null) {
      final dayName = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][picked.weekday - 1];

      if (!_selectedDoctor!.availableDays.contains(dayName)) {
        _showSnack(
          'Doctor is not available on $dayName. Please select another day.',
        );
        return;
      }

      if (_selectedDoctor!.timeRange.isNotEmpty) {
        final parts = _selectedDoctor!.timeRange.split(' - ');
        if (parts.length == 2) {
          final startParts = parts[0].split(':').map(int.parse).toList();
          final endParts = parts[1].split(':').map(int.parse).toList();
          final startMins = startParts[0] * 60 + startParts[1];
          final endMins = endParts[0] * 60 + endParts[1];
          final pickedMins = picked.hour * 60 + picked.minute;

          final bool valid = startMins < endMins
              ? pickedMins >= startMins && pickedMins <= endMins
              : pickedMins >= startMins || pickedMins <= endMins;

          if (!valid) {
            _showSnack(
              "Selected time is outside doctor's time range (${_selectedDoctor!.timeRange})",
            );
            return;
          }
        }
      }
    }

    setState(() => _selectedDateTime = picked);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626),
      ),
    );
  }

  Color _statusColor(String status) {
    const colors = {
      'confirmed': Color(0xFF166534),
      'pending': Color(0xFF92400E),
      'completed': Color(0xFF1E40AF),
      'cancelled': Color(0xFF991B1B),
    };
    return colors[status.toLowerCase()] ?? const Color(0xFF374151);
  }

  Color _statusBg(String status) {
    const colors = {
      'confirmed': Color(0xFFDCFCE7),
      'pending': Color(0xFFFEF3C7),
      'completed': Color(0xFFDBEAFE),
      'cancelled': Color(0xFFFEE2E2),
    };
    return colors[status.toLowerCase()] ?? const Color(0xFFF3F4F6);
  }

  String _appointmentModeLabel(String mode) {
    switch (mode.toLowerCase()) {
      case 'offline':
        return 'In-person';
      case 'online':
        return 'Online';
      default:
        return mode.isEmpty
            ? mode
            : '${mode[0].toUpperCase()}${mode.substring(1)}';
    }
  }

  String _monthName(int m) => [
    '',
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
  ][m];

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text(
                'Appointments',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.blue[800],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _tabButton('book', Icons.add_circle_outline, 'Book'),
                  _tabButton('history', Icons.list_alt, 'History'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _activeTab == 'book'
                  ? _buildBookTab()
                  : _buildHistoryTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String id, IconData icon, String label) {
    final isActive = _activeTab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? const Color(0xFF2563EB) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: isActive
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Book tab ───────────────────────────────────────────────────────────────

  Widget _buildBookTab() {
    final modes = (_selectedDoctor?.appointmentModes.isNotEmpty == true)
        ? _selectedDoctor!.appointmentModes.map((m) => m.toLowerCase()).toList()
        : ['offline', 'online'];

    final modeValue = modes.contains(_appointmentMode)
        ? _appointmentMode
        : modes.first;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Book an Appointment',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.blue[800],
            ),
          ),
          const SizedBox(height: 16),

          // Doctor Selection — key forces full reset after booking
          DoctorSelectionComponent(
            key: _doctorSelectionKey,
            onDoctorSelect: (d) => setState(() {
              _selectedDoctor = d;
              final newModes = d.appointmentModes.isNotEmpty
                  ? d.appointmentModes.map((m) => m.toLowerCase()).toList()
                  : ['offline', 'online'];
              _appointmentMode = newModes.first;
            }),
            onHospitalSelect: (h) => setState(() => _selectedHospitalId = h),
          ),
          const SizedBox(height: 16),

          // Date & Time
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Appointment Date & Time',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickDateTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          size: 18,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _selectedDateTime == null
                              ? 'Select date and time'
                              : '${_selectedDateTime!.day}/${_selectedDateTime!.month}/${_selectedDateTime!.year}  '
                                    '${_selectedDateTime!.hour.toString().padLeft(2, '0')}:'
                                    '${_selectedDateTime!.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: _selectedDateTime == null
                                ? const Color(0xFF9CA3AF)
                                : const Color(0xFF111827),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Appointment Mode
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Appointment Mode',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: modeValue,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFBFDBFE)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFBFDBFE)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 2,
                      ),
                    ),
                  ),
                  items: modes
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            _appointmentModeLabel(m),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _appointmentMode = v ?? 'offline'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Reason
          _sectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reason for Visit',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonController,
                  maxLines: 3,
                  onChanged: (v) => setState(() => _reason = v),
                  decoration: InputDecoration(
                    hintText: 'Briefly describe your reason for visiting...',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF9CA3AF),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFBFDBFE)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFBFDBFE)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Book Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _bookingInProgress ? null : _bookAppointment,
              icon: _bookingInProgress
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                _bookingInProgress ? 'Processing...' : 'Book Appointment',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(
                  0xFF2563EB,
                ).withOpacity(0.6),
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 20),

          _buildChatBanner(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── History tab ────────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    return _appointments.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today, size: 64, color: Color(0xFFD1D5DB)),
                SizedBox(height: 16),
                Text(
                  'No appointments found.',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 16),
                ),
              ],
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _appointments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _buildAppointmentCard(_appointments[i]),
          );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appt) {
    final id = appt['_id']?.toString() ?? '';
    final isOpen = _openDetails[id] ?? false;
    final status = appt['status'] ?? 'pending';
    final doctor = appt['doctor'] as Map<String, dynamic>? ?? {};
    final hospital = appt['hospital'] as Map<String, dynamic>? ?? {};

    DateTime? dateTime;
    if (appt['appointmentDateTime'] != null) {
      dateTime = DateTime.tryParse(appt['appointmentDateTime']);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Status badge
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusBg(status),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _statusColor(status).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: _statusColor(status),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Doctor Info
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFBFDBFE),
                      width: 2,
                    ),
                  ),
                  child: ClipOval(
                    child: doctor['profile_image'] != null
                        ? Image.network(
                            doctor['profile_image'],
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: const Color(0xFFDBEAFE),
                            child: const Icon(
                              Icons.person,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dr. ${doctor['fullName'] ?? 'Unknown'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0xFF111827),
                        ),
                      ),
                      Text(
                        hospital['name'] ?? 'N/A',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Date/Time
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateTime != null
                        ? '${dateTime.day} ${_monthName(dateTime.month)} ${dateTime.year}'
                        : 'N/A',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.access_time,
                    size: 16,
                    color: Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateTime != null
                        ? '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}'
                        : 'N/A',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF374151),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Toggle Details button
            GestureDetector(
              onTap: () => setState(
                () => _openDetails[id] = !(_openDetails[id] ?? false),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF93C5FD)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isOpen ? 'Hide Details ▲' : 'View Details ▼',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

            if (isOpen) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Reason:',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  ),
                  Flexible(
                    child: Text(
                      appt['reason'] ?? 'N/A',
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Mode:',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  ),
                  Text(
                    _appointmentModeLabel(appt['appointmentMode'] ?? ''),
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Chat banner ────────────────────────────────────────────────────────────

  Widget _buildChatBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.blue[800],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'New Feature: Live Chat with Doctors is Here!',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[800],
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Available Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You can now start quick, pre-booking conversations with available doctors based on their shifts.',
            style: TextStyle(
              color: Colors.blue[700],
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/messages'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Start Chatting', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ── Section card wrapper ───────────────────────────────────────────────────

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}
