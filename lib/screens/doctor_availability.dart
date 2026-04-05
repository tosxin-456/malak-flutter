import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../routes/app_routes.dart';
import '../config/api_config.dart';

class DoctorAvailabilityScreen extends StatefulWidget {
  const DoctorAvailabilityScreen({super.key});

  @override
  State<DoctorAvailabilityScreen> createState() =>
      _DoctorAvailabilityScreenState();
}

class _DoctorAvailabilityScreenState extends State<DoctorAvailabilityScreen>
    with TickerProviderStateMixin {
  final _secureStorage = const FlutterSecureStorage();

  int _currentStep = 1;
  final int _totalSteps = 3;
  bool _saving = false;
  String _messageType = '';
  String _messageText = '';

  // Form data
  List<String> _daysAvailable = [];
  String _startTime = '';
  String _endTime = '';
  int _numPatients = 5;
  bool _isOpen = false;
  List<String> _appointmentModes = [];
  int _totalSlots = 0;

  final List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  late AnimationController _pageAnim;
  late Animation<double> _pageFade;
  late Animation<Offset> _pageSlide;

  @override
  void initState() {
    super.initState();
    _pageAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pageFade = CurvedAnimation(parent: _pageAnim, curve: Curves.easeOut);
    _pageSlide = Tween<Offset>(
      begin: const Offset(0.05, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _pageAnim, curve: Curves.easeOut));

    _pageAnim.forward();
    _checkAvailability();
  }

  @override
  void dispose() {
    _pageAnim.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final response = await http.get(
        Uri.parse('$API_BASE_URL/doctors/doctor/availability'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['doctorAvailability'] == true && mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.doctorDashboard);
        }
      }
    } catch (e) {
      debugPrint('Availability check error: $e');
    }
  }

  void _recalcSlots() {
    if (_startTime.isNotEmpty && _endTime.isNotEmpty && _numPatients > 0) {
      final start = _parseTime(_startTime);
      var end = _parseTime(_endTime);
      if (end <= start) end += 24 * 60;
      setState(() => _totalSlots = _numPatients);
    } else {
      setState(() => _totalSlots = 0);
    }
  }

  int _parseTime(String t) {
    final parts = t.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  void _toggleDay(String day) {
    setState(() {
      if (_daysAvailable.contains(day)) {
        _daysAvailable.remove(day);
      } else {
        _daysAvailable.add(day);
      }
    });
  }

  void _toggleMode(String mode) {
    setState(() {
      if (_appointmentModes.contains(mode)) {
        _appointmentModes.remove(mode);
      } else {
        _appointmentModes.add(mode);
      }
    });
  }

  void _handleNext() {
    if (_currentStep == 1 && !_isOpen && _daysAvailable.isEmpty) {
      _setMessage('error', 'Please select at least one day to continue');
      return;
    }
    if (_currentStep == 2 && (_startTime.isEmpty || _endTime.isEmpty)) {
      _setMessage('error', 'Please set both start and end times');
      return;
    }
    _setMessage('', '');
    _animateTo(_currentStep + 1);
  }

  void _handlePrevious() {
    _setMessage('', '');
    _animateTo(_currentStep - 1);
  }

  void _animateTo(int step) async {
    await _pageAnim.reverse();
    setState(() => _currentStep = step.clamp(1, _totalSteps));
    _pageAnim.forward();
  }

  void _setMessage(String type, String text) {
    setState(() {
      _messageType = type;
      _messageText = text;
    });
  }

  Future<void> _handleComplete() async {
    setState(() => _saving = true);
    _setMessage('', '');

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final body = {
        'daysAvailable': _daysAvailable,
        'startTime': _startTime,
        'endTime': _endTime,
        'numPatients': _numPatients,
        'isOpen': _isOpen,
        'appointmentModes': _appointmentModes,
      };

      final response = await http.post(
        Uri.parse('$API_BASE_URL/doctors/doctor/availability'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _setMessage('success', 'Availability set successfully!');
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.doctorDashboard);
        }
      } else {
        throw Exception('Failed to save availability');
      }
    } catch (e) {
      _setMessage('error', 'Failed to save availability. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF2563EB)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (isStart) {
          _startTime = formatted;
        } else {
          _endTime = formatted;
        }
      });
      _recalcSlots();
    }
  }

  String appointmentModeLabel(String mode) {
    switch (mode.toLowerCase()) {
      case 'offline':
        return 'In-person';
      case 'online':
        return 'Online';
      default:
        // Capitalise first letter for anything unexpected
        return mode.isEmpty
            ? mode
            : '${mode[0].toUpperCase()}${mode.substring(1)}';
    }
  }

  // ─── Step Indicator ──────────────────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_totalSteps * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final stepBefore = (i ~/ 2) + 1;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 64,
            height: 2,
            color: stepBefore < _currentStep
                ? const Color(0xFF2563EB)
                : const Color(0xFFD1D5DB),
          );
        }
        final step = (i ~/ 2) + 1;
        final isCompleted = step < _currentStep;
        final isActive = step == _currentStep;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (isCompleted || isActive)
                ? const Color(0xFF2563EB)
                : Colors.white,
            border: Border.all(
              color: (isCompleted || isActive)
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFD1D5DB),
              width: 2,
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 20)
                : Text(
                    '$step',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isActive ? Colors.white : const Color(0xFF9CA3AF),
                    ),
                  ),
          ),
        );
      }),
    );
  }

  // ─── Step 1: Days ────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    return Column(
      children: [
        _stepIcon(
          Icons.calendar_today,
          const Color(0xFFDBEAFE),
          const Color(0xFF2563EB),
        ),
        const SizedBox(height: 20),
        const Text(
          'Select Your Available Days',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose the days of the week when you\'ll be available for patient appointments.',
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Open schedule checkbox
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _isOpen = !_isOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _isOpen ? const Color(0xFF2563EB) : Colors.white,
                    border: Border.all(
                      color: _isOpen
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFD1D5DB),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: _isOpen
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Available Anytime (Open Schedule)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Day grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 3.2,
          ),
          itemCount: _daysOfWeek.length,
          itemBuilder: (context, index) {
            final day = _daysOfWeek[index];
            final selected = _daysAvailable.contains(day);
            return GestureDetector(
              onTap: () => _toggleDay(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF2563EB) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFE5E7EB),
                    width: 2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF2563EB).withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF374151),
                    ),
                  ),
                ),
              ),
            );
          },
        ),

        if (_daysAvailable.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Selected: ${_daysAvailable.join(', ')}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E40AF),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }

  // ─── Step 2: Hours ────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    return Column(
      children: [
        _stepIcon(
          Icons.access_time,
          const Color(0xFFDBEAFE),
          const Color(0xFF2563EB),
        ),
        const SizedBox(height: 20),
        const Text(
          'Set Your Working Hours',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Define your daily working hours. This will apply to all your selected days.',
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        // Start time
        _timePickerField(
          label: 'Start Time',
          value: _startTime,
          hint: 'Tap to select',
          onTap: () => _pickTime(true),
        ),

        const SizedBox(height: 16),

        // End time
        _timePickerField(
          label: 'End Time',
          value: _endTime,
          hint: 'Tap to select',
          onTap: () => _pickTime(false),
        ),

        const SizedBox(height: 24),

        // Appointment modes
        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Appointment Modes',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: ['offline', 'online'].map((mode) {
            final selected = _appointmentModes.contains(mode);
            return Padding(
              padding: const EdgeInsets.only(right: 24),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _toggleMode(mode),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF2563EB)
                              : Colors.white,
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF2563EB)
                                : const Color(0xFFD1D5DB),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 14,
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        appointmentModeLabel(mode),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // Number of patients
        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Number of Patients per Day',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          initialValue: _numPatients.toString(),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'e.g. 10',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
          ),
          onChanged: (v) {
            final parsed = int.tryParse(v);
            if (parsed != null && parsed > 0) {
              setState(() => _numPatients = parsed);
              _recalcSlots();
            }
          },
        ),

        if (_totalSlots > 0) ...[
          const SizedBox(height: 10),
          Text(
            'Total appointment slots per day: $_totalSlots',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  // ─── Step 3: Review ───────────────────────────────────────────────────────────

  Widget _buildStep3() {
    return Column(
      children: [
        _stepIcon(
          Icons.check_circle_outline,
          const Color(0xFFD1FAE5),
          const Color(0xFF16A34A),
        ),
        const SizedBox(height: 20),
        const Text(
          'Review Your Availability',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Please review your availability settings before completing this step.',
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),

        _reviewCard(
          icon: Icons.calendar_today,
          title: 'Available Days',
          child: _isOpen && _startTime.isNotEmpty && _endTime.isNotEmpty
              ? Text(
                  'Open Schedule: $_startTime – $_endTime',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1E40AF),
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _daysAvailable
                      .map(
                        (day) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDBEAFE),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            day,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),

        const SizedBox(height: 12),

        _reviewCard(
          icon: Icons.access_time,
          title: 'Working Hours',
          child: Text(
            _startTime.isNotEmpty && _endTime.isNotEmpty
                ? '$_startTime – $_endTime'
                : 'Not set',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF374151),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 12),

        _reviewCard(
          icon: Icons.people_outline,
          title: 'Patients per Day',
          child: Text(
            '$_numPatients patients',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF374151),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        if (_appointmentModes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _reviewCard(
            icon: Icons.video_call_outlined,
            title: 'Appointment Modes',
            child: Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: _appointmentModes
                  .map(
                    (m) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${m[0].toUpperCase()}${m.substring(1)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF065F46),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  Widget _stepIcon(IconData icon, Color bg, Color fg) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: fg, size: 30),
    );
  }

  Widget _timePickerField({
    required String label,
    required String value,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFD1D5DB)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 20,
                  color: Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 10),
                Text(
                  value.isNotEmpty ? value : hint,
                  style: TextStyle(
                    fontSize: 16,
                    color: value.isNotEmpty
                        ? const Color(0xFF111827)
                        : const Color(0xFF9CA3AF),
                    fontWeight: value.isNotEmpty
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _reviewCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: const Color(0xFF6B7280)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildMessage() {
    if (_messageText.isEmpty) return const SizedBox.shrink();
    final isSuccess = _messageType == 'success';
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isSuccess ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        border: Border.all(
          color: isSuccess ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_outline : Icons.error_outline,
            color: isSuccess
                ? const Color(0xFF16A34A)
                : const Color(0xFFB91C1C),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _messageText,
              style: TextStyle(
                fontSize: 14,
                color: isSuccess
                    ? const Color(0xFF166534)
                    : const Color(0xFFB91C1C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEFF6FF), Color(0xFFFAFAFF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  children: [
                    const Text(
                      'Set Your Availability',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Let patients know when you\'re available for appointments',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    _buildStepIndicator(),
                    const SizedBox(height: 8),
                    Text(
                      'Step $_currentStep of $_totalSteps',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Content ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.07),
                              blurRadius: 24,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _buildMessage(),
                            FadeTransition(
                              opacity: _pageFade,
                              child: SlideTransition(
                                position: _pageSlide,
                                child: _currentStep == 1
                                    ? _buildStep1()
                                    : _currentStep == 2
                                    ? _buildStep2()
                                    : _buildStep3(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Bottom Nav Buttons ──
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Previous
              TextButton.icon(
                onPressed: _currentStep == 1 ? null : _handlePrevious,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Previous'),
                style: TextButton.styleFrom(
                  foregroundColor: _currentStep == 1
                      ? const Color(0xFFD1D5DB)
                      : const Color(0xFF374151),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),

              // Continue / Complete
              if (_currentStep < _totalSteps)
                ElevatedButton.icon(
                  onPressed: _handleNext,
                  icon: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  label: const Icon(Icons.arrow_forward, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _saving ? null : _handleComplete,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Complete Setup',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                  label: _saving
                      ? const Text('Saving...', style: TextStyle(fontSize: 15))
                      : const Icon(Icons.check_circle_outline, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                    disabledBackgroundColor: const Color(0xFF86EFAC),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
