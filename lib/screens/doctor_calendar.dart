import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class AppointmentModel {
  final String id;
  final DateTime appointmentDateTime;
  final String? time;
  final String? status;
  final String? appointmentMode;
  final String? reason;
  final Map<String, dynamic>? patient;
  final Map<String, dynamic>? hospital;

  const AppointmentModel({
    required this.id,
    required this.appointmentDateTime,
    this.time,
    this.status,
    this.appointmentMode,
    this.reason,
    this.patient,
    this.hospital,
  });

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    return AppointmentModel(
      id: json['_id'] as String? ?? '',
      appointmentDateTime:
          DateTime.tryParse(json['appointmentDateTime'] as String? ?? '') ??
          DateTime.now(),
      time: json['time'] as String?,
      status: json['status'] as String?,
      appointmentMode: json['appointmentMode'] as String?,
      reason: json['reason'] as String?,
      patient: json['patient'] as Map<String, dynamic>?,
      hospital: json['hospital'] as Map<String, dynamic>?,
    );
  }

  bool get isPast => appointmentDateTime.isBefore(DateTime.now());
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class DoctorAppointmentCalendar extends StatefulWidget {
  const DoctorAppointmentCalendar({Key? key}) : super(key: key);

  @override
  State<DoctorAppointmentCalendar> createState() =>
      _DoctorAppointmentCalendarState();
}

class _DoctorAppointmentCalendarState extends State<DoctorAppointmentCalendar> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;
  List<AppointmentModel> _appointments = [];
  bool _loading = false;

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _fetchAppointments();
  }

  // ── API ──────────────────────────────────────────────────────────────────

  Future<void> _fetchAppointments() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token') ?? '';
      final apiBase = const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://localhost:3000/api',
      );

      final res = await http.get(
        Uri.parse('$apiBase/appointments/doctor'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        setState(() {
          _appointments = list
              .map((e) => AppointmentModel.fromJson(e))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Calendar fetch error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<AppointmentModel> _appointmentsForDate(DateTime date) =>
      _appointments.where((a) {
        final d = a.appointmentDateTime;
        return d.year == date.year &&
            d.month == date.month &&
            d.day == date.day;
      }).toList();

  bool _hasAppointments(int day) => _appointments.any((a) {
    final d = a.appointmentDateTime;
    return d.year == _currentMonth.year &&
        d.month == _currentMonth.month &&
        d.day == day;
  });

  bool _hasMissed(int day) => _appointments.any((a) {
    final d = a.appointmentDateTime;
    return d.year == _currentMonth.year &&
        d.month == _currentMonth.month &&
        d.day == day &&
        a.isPast &&
        (a.status?.toLowerCase() == 'pending');
  });

  bool _isToday(int day) {
    final now = DateTime.now();
    return _currentMonth.year == now.year &&
        _currentMonth.month == now.month &&
        day == now.day;
  }

  bool _isSelected(int day) =>
      _selectedDate != null &&
      _selectedDate!.year == _currentMonth.year &&
      _selectedDate!.month == _currentMonth.month &&
      _selectedDate!.day == day;

  List<int?> _generateCalendarDays() {
    final firstWeekday =
        DateTime(_currentMonth.year, _currentMonth.month, 1).weekday % 7;
    final daysInMonth = DateUtils.getDaysInMonth(
      _currentMonth.year,
      _currentMonth.month,
    );
    final days = <int?>[...List.filled(firstWeekday, null)];
    for (var i = 1; i <= daysInMonth; i++) {
      days.add(i);
    }
    return days;
  }

  String _formatTime(String? t) {
    if (t == null || t.isEmpty) return '';
    try {
      final parts = t.split(':');
      final hour = int.parse(parts[0]);
      final min = parts[1];
      final ampm = hour >= 12 ? 'PM' : 'AM';
      final h12 = hour % 12 == 0 ? 12 : hour % 12;
      return '$h12:$min $ampm';
    } catch (_) {
      return t;
    }
  }

  Color _statusBgColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'confirmed':
        return const Color(0xFFDCFCE7);
      case 'pending':
        return const Color(0xFFFEF9C3);
      case 'cancelled':
        return const Color(0xFFFEE2E2);
      case 'missed':
        return const Color(0xFFFEE2E2);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  Color _statusTextColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'confirmed':
        return const Color(0xFF15803D);
      case 'pending':
        return const Color(0xFFB45309);
      case 'cancelled':
        return const Color(0xFFDC2626);
      case 'missed':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF374151);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildCalendarCard(),
        const SizedBox(height: 16),
        _buildAppointmentsPanel(),
      ],
    );
  }

  Widget _buildCalendarCard() {
    final days = _generateCalendarDays();
    final monthLabel = DateFormat('MMMM yyyy').format(_currentMonth);

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
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                monthLabel,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              Row(
                children: [
                  _navButton(Icons.chevron_left, () {
                    setState(() {
                      _currentMonth = DateTime(
                        _currentMonth.year,
                        _currentMonth.month - 1,
                      );
                    });
                  }),
                  const SizedBox(width: 4),
                  _navButton(Icons.chevron_right, () {
                    setState(() {
                      _currentMonth = DateTime(
                        _currentMonth.year,
                        _currentMonth.month + 1,
                      );
                    });
                  }),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Day labels
          Row(
            children: _dayLabels
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),

          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: days.length,
            itemBuilder: (context, i) {
              final day = days[i];
              if (day == null) return const SizedBox.shrink();

              final today = _isToday(day);
              final selected = _isSelected(day);
              final hasApts = _hasAppointments(day);
              final missed = _hasMissed(day);

              Color bgColor = Colors.transparent;
              Color textColor = const Color(0xFF374151);
              BoxBorder? border;

              if (today) {
                bgColor = const Color(0xFF059669);
                textColor = Colors.white;
              } else if (selected) {
                bgColor = const Color(0xFFD1FAE5);
                textColor = const Color(0xFF065F46);
                border = Border.all(color: const Color(0xFF34D399), width: 2);
              }

              return GestureDetector(
                onTap: () => setState(() {
                  _selectedDate = DateTime(
                    _currentMonth.year,
                    _currentMonth.month,
                    day,
                  );
                }),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: bgColor,
                        shape: BoxShape.circle,
                        border: border,
                      ),
                      child: Center(
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: today
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                    if (!today && hasApts)
                      Positioned(
                        bottom: 2,
                        child: missed
                            ? Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                              )
                            : Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF10B981),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 16),
          const Divider(color: Color(0xFFF3F4F6)),
          const SizedBox(height: 12),

          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legendItem(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Color(0xFF059669),
                    shape: BoxShape.circle,
                  ),
                ),
                label: 'Today',
              ),
              _legendItem(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF34D399),
                      width: 2,
                    ),
                  ),
                ),
                label: 'Selected',
              ),
              _legendItem(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF10B981),
                      width: 2,
                    ),
                  ),
                ),
                label: 'Scheduled',
              ),
              _legendItem(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                label: 'Missed',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Icon(icon, size: 18, color: const Color(0xFF374151)),
    ),
  );

  Widget _legendItem({required Widget child, required String label}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
      ),
    ],
  );

  // ── Appointments Panel ────────────────────────────────────────────────────

  Widget _buildAppointmentsPanel() {
    final aptList = _selectedDate != null
        ? _appointmentsForDate(_selectedDate!)
        : <AppointmentModel>[];

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0FDF4), Color(0xFFECFDF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD1FAE5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today,
                color: Color(0xFF059669),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                _selectedDate != null ? 'Appointments' : 'Upcoming',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          if (_selectedDate != null) ...[
            const SizedBox(height: 12),
            Text(
              DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate!),
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFFBBF7D0)),
          ],
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (aptList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 36,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectedDate != null
                          ? 'No appointments on this date'
                          : 'No upcoming appointments',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: aptList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _appointmentCard(aptList[i]),
            ),
        ],
      ),
    );
  }

  Widget _appointmentCard(AppointmentModel apt) {
    final isPast = apt.isPast;
    String displayStatus = apt.status ?? '';
    if (isPast) {
      if (apt.status == 'confirmed') displayStatus = 'Completed';
      if (apt.status == 'pending') displayStatus = 'Missed';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  apt.patient?['fullName'] as String? ?? 'Unknown Patient',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusBgColor(displayStatus),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  displayStatus.isNotEmpty
                      ? '${displayStatus[0].toUpperCase()}${displayStatus.substring(1)}'
                      : '',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusTextColor(displayStatus),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.access_time, size: 13, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 6),
              Text(
                _formatTime(apt.time),
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                apt.appointmentMode == 'offline'
                    ? Icons.location_on_outlined
                    : Icons.video_call_outlined,
                size: 13,
                color: const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 6),
              Text(
                apt.appointmentMode == 'offline'
                    ? (apt.hospital?['name'] as String? ?? 'In-person')
                    : 'Video Consultation',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          if (apt.reason != null && apt.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              apt.reason!,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
