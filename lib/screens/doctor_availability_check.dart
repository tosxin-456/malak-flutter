import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

/// Checks whether the doctor has set their availability.
/// Navigates to /doctor-dashboard if yes, /doctor-availability if not.
/// Shows a pulsing splash screen while checking.
class DoctorAvailabilityCheck extends StatefulWidget {
  const DoctorAvailabilityCheck({Key? key}) : super(key: key);

  @override
  State<DoctorAvailabilityCheck> createState() =>
      _DoctorAvailabilityCheckState();
}

class _DoctorAvailabilityCheckState extends State<DoctorAvailabilityCheck>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.85,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _checkAvailability();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    try {
      final token = await StorageService.getToken();

      final response = await http.get(
        Uri.parse('$API_BASE_URL/doctors/doctor/availability'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch availability');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['doctorAvailability'] == true) {
        Navigator.of(context).pushReplacementNamed('/doctor-dashboard');
      } else {
        Navigator.of(context).pushReplacementNamed('/doctor-availability');
      }
    } catch (e) {
      debugPrint('Availability check error: $e');
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/doctor-availability');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF059669),
      body: Center(
        child: ScaleTransition(
          scale: _pulseAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.medical_services_outlined,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Checking your profile…',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
