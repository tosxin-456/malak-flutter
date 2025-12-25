import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

// Models
class Doctor {
  final String? fullName;

  Doctor({this.fullName});

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(fullName: json['fullName']);
  }
}

class Hospital {
  final String? name;

  Hospital({this.name});

  factory Hospital.fromJson(Map<String, dynamic> json) {
    return Hospital(name: json['name']);
  }
}

class Appointment {
  final String id;
  final DateTime appointmentDateTime;
  final String time;
  final String status;
  final String appointmentMode;
  final Doctor? doctor;
  final Hospital? hospital;
  final String? reason;

  Appointment({
    required this.id,
    required this.appointmentDateTime,
    required this.time,
    required this.status,
    required this.appointmentMode,
    this.doctor,
    this.hospital,
    this.reason,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    return Appointment(
      id: json['_id'] ?? '',
      appointmentDateTime: DateTime.parse(json['appointmentDateTime']),
      time: json['time'] ?? '',
      status: json['status'] ?? 'pending',
      appointmentMode: json['appointmentMode'] ?? 'offline',
      doctor: json['doctor'] != null ? Doctor.fromJson(json['doctor']) : null,
      hospital: json['hospital'] != null
          ? Hospital.fromJson(json['hospital'])
          : null,
      reason: json['reason'],
    );
  }
}

// Service
class AppointmentService {
  static Future<List<Appointment>> fetchPatientAppointments() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) throw Exception('User not authenticated');

      final response = await http.get(
        Uri.parse('$API_BASE_URL/appointments/user'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Appointment.fromJson(json)).toList();
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch appointments');
      }
    } catch (e) {
      throw Exception('Error fetching appointments: $e');
    }
  }
}

// Main Widget
class AppointmentCalendar extends StatefulWidget {
  const AppointmentCalendar({Key? key}) : super(key: key);

  @override
  State<AppointmentCalendar> createState() => _AppointmentCalendarState();
}

class _AppointmentCalendarState extends State<AppointmentCalendar>
    with SingleTickerProviderStateMixin {
  DateTime _currentDate = DateTime.now();
  DateTime? _selectedDate;
  List<Appointment> _appointments = [];
  bool _isLoading = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadAppointments();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadAppointments() async {
    try {
      final appointments = await AppointmentService.fetchPatientAppointments();
      setState(() {
        _appointments = appointments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  List<Appointment> _getAppointmentsForDate(DateTime date) {
    return _appointments.where((apt) {
      return apt.appointmentDateTime.year == date.year &&
          apt.appointmentDateTime.month == date.month &&
          apt.appointmentDateTime.day == date.day;
    }).toList();
  }

  bool _hasAppointments(int day) {
    final testDate = DateTime(_currentDate.year, _currentDate.month, day);
    return _getAppointmentsForDate(testDate).isNotEmpty;
  }

  bool _hasMissedAppointments(int day) {
    final dateToCheck = DateTime(_currentDate.year, _currentDate.month, day);
    return _appointments.any((apt) {
      final isSameDay =
          apt.appointmentDateTime.year == dateToCheck.year &&
          apt.appointmentDateTime.month == dateToCheck.month &&
          apt.appointmentDateTime.day == dateToCheck.day;
      return isSameDay &&
          apt.appointmentDateTime.isBefore(DateTime.now()) &&
          apt.status.toLowerCase() == 'pending';
    });
  }

  bool _isPastAppointment(Appointment appointment) {
    return appointment.appointmentDateTime.isBefore(DateTime.now());
  }

  List<int?> _generateCalendarDays() {
    final firstDay = DateTime(_currentDate.year, _currentDate.month, 1);
    final lastDay = DateTime(_currentDate.year, _currentDate.month + 1, 0);
    final startDay = firstDay.weekday % 7;
    final daysInMonth = lastDay.day;

    List<int?> days = [];
    for (int i = 0; i < startDay; i++) {
      days.add(null);
    }
    for (int i = 1; i <= daysInMonth; i++) {
      days.add(i);
    }
    return days;
  }

  bool _isToday(int day) {
    final today = DateTime.now();
    return day == today.day &&
        _currentDate.month == today.month &&
        _currentDate.year == today.year;
  }

  String _formatTime(String timeString) {
    try {
      final parts = timeString.split(':');
      final hour = int.parse(parts[0]);
      final minute = parts[1];
      final ampm = hour >= 12 ? 'PM' : 'AM';
      final hour12 = hour % 12 == 0 ? 12 : hour % 12;
      return '$hour12:$minute $ampm';
    } catch (e) {
      return timeString;
    }
  }

  Color _getStatusColor(String status, bool isPast) {
    if (isPast) {
      if (status.toLowerCase() == 'pending') return Colors.red.shade100;
      return Colors.grey.shade200;
    }
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green.shade100;
      case 'pending':
        return Colors.yellow.shade100;
      case 'cancelled':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  Color _getStatusTextColor(String status, bool isPast) {
    if (isPast) {
      if (status.toLowerCase() == 'pending') return Colors.red.shade700;
      return Colors.grey.shade700;
    }
    switch (status.toLowerCase()) {
      case 'confirmed':
        return Colors.green.shade700;
      case 'pending':
        return Colors.yellow.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _getDisplayStatus(Appointment apt) {
    if (_isPastAppointment(apt)) {
      if (apt.status.toLowerCase() == 'confirmed') return 'Completed';
      if (apt.status.toLowerCase() == 'pending') return 'Missed';
      return 'Past';
    }
    return apt.status;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final calendarDays = _generateCalendarDays();
    final List<Appointment> selectedDateAppointments = _selectedDate != null
        ? _getAppointmentsForDate(_selectedDate!)
        : <Appointment>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCalendarWidget(calendarDays),
        const SizedBox(height: 16),
        _buildAppointmentsPanel(selectedDateAppointments),
      ],
    );
  }

  Widget _buildCalendarWidget(List<int?> calendarDays) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    DateFormat('MMMM yyyy').format(_currentDate),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _currentDate = DateTime(
                            _currentDate.year,
                            _currentDate.month - 1,
                          );
                          _selectedDate = null;
                        });
                      },
                      icon: const Icon(Icons.arrow_back, size: 18),
                      color: Colors.grey.shade600,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _currentDate = DateTime(
                            _currentDate.year,
                            _currentDate.month + 1,
                          );
                          _selectedDate = null;
                        });
                      },
                      icon: const Icon(Icons.arrow_forward, size: 18),
                      color: Colors.grey.shade600,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: 7 + calendarDays.length,
              itemBuilder: (context, index) {
                if (index < 7) {
                  return Center(
                    child: Text(
                      ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][index],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  );
                }

                final dayIndex = index - 7;
                final day = calendarDays[dayIndex];

                if (day == null) {
                  return const SizedBox.shrink();
                }

                final hasApts = _hasAppointments(day);
                final isTodayDate = _isToday(day);
                final hasMissed = _hasMissedAppointments(day);
                final isSelected =
                    _selectedDate != null &&
                    day == _selectedDate!.day &&
                    _currentDate.month == _selectedDate!.month &&
                    _currentDate.year == _selectedDate!.year;

                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedDate = DateTime(
                        _currentDate.year,
                        _currentDate.month,
                        day,
                      );
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isTodayDate
                          ? Colors.blue.shade600
                          : isSelected
                          ? Colors.blue.shade100
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: isSelected && !isTodayDate
                          ? Border.all(color: Colors.blue.shade400, width: 2)
                          : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isTodayDate
                                ? Colors.white
                                : isSelected
                                ? Colors.blue.shade700
                                : Colors.grey.shade700,
                          ),
                        ),
                        if (hasMissed && !isTodayDate)
                          Positioned(
                            bottom: 6,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.red.shade500,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        else if (hasApts && !isTodayDate)
                          Positioned(
                            bottom: 6,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.blue.shade500,
                                  width: 1.5,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildLegendItem(
                    Colors.blue.shade600,
                    'Today',
                    isCircle: true,
                  ),
                  _buildLegendItem(
                    Colors.blue.shade100,
                    'Selected',
                    isCircle: true,
                    hasRing: true,
                  ),
                  _buildLegendItem(
                    Colors.blue.shade500,
                    'Scheduled',
                    isRing: true,
                  ),
                  _buildLegendItem(
                    Colors.red.shade500,
                    'Missed',
                    isCircle: true,
                    isSmall: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(
    Color color,
    String label, {
    bool isCircle = false,
    bool hasRing = false,
    bool isRing = false,
    bool isSmall = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isSmall ? 6 : 10,
          height: isSmall ? 6 : 10,
          decoration: BoxDecoration(
            color: isRing ? Colors.transparent : color,
            shape: BoxShape.circle,
            border: isRing || hasRing
                ? Border.all(color: color, width: 1.5)
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildAppointmentsPanel(List<Appointment> appointments) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade50, Colors.lightBlue.shade50],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: Colors.blue.shade600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedDate != null ? 'Appointments' : 'Upcoming',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_selectedDate != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.blue.shade200),
                  ),
                ),
                child: Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate!),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (appointments.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 32,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _selectedDate != null
                            ? 'No appointments on this date'
                            : 'No upcoming appointments',
                        style: TextStyle(
                          fontSize: 13,
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
                itemCount: appointments.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final apt = appointments[index];
                  final isPast = _isPastAppointment(apt);

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Dr. ${apt.doctor?.fullName ?? "Unknown"}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(apt.status, isPast),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: _getStatusTextColor(
                                      apt.status,
                                      isPast,
                                    ).withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  _getDisplayStatus(apt),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: _getStatusTextColor(
                                      apt.status,
                                      isPast,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 13,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatTime(apt.time),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (apt.appointmentMode == 'offline')
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 13,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    apt.hospital?.name ?? 'In-person',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Icon(
                                  Icons.videocam,
                                  size: 13,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Video Consultation',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
