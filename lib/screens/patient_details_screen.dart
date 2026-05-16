// lib/screens/patient_details_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

class PatientDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> appointmentFull;

  const PatientDetailsScreen({Key? key, required this.appointmentFull})
      : super(key: key);

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  bool _isProcessing = false;

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic> get _patient =>
      (widget.appointmentFull['patient'] as Map<String, dynamic>?) ?? {};

  Map<String, dynamic> get _hospital =>
      (widget.appointmentFull['hospital'] as Map<String, dynamic>?) ?? {};

  String get _status =>
      (widget.appointmentFull['status'] as String? ?? 'pending').toLowerCase();

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _formatDateTime(String? raw) {
    if (raw == null) return 'N/A';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${months[local.month - 1]} ${local.day}, ${local.year}  $h:$m $ampm';
  }

  String _formatDate(String? raw) {
    if (raw == null) return 'N/A';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Color _statusBgColor() {
    switch (_status) {
      case 'pending':   return const Color(0xFFFEF9C3);
      case 'confirmed': return const Color(0xFFDCFCE7);
      default:          return const Color(0xFFFEE2E2);
    }
  }

  Color _statusFgColor() {
    switch (_status) {
      case 'pending':   return const Color(0xFF92400E);
      case 'confirmed': return const Color(0xFF166534);
      default:          return const Color(0xFF991B1B);
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _handleAccept() async {
    final id = widget.appointmentFull['_id'] as String?;
    if (id == null) return;
    setState(() => _isProcessing = true);
    try {
      final token = await StorageService.getToken();
      final res = await http.patch(
        Uri.parse('$API_BASE_URL/appointments/$id/accept'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (!res.ok) throw Exception(body['message'] ?? 'Failed to accept');
      if (!mounted) return;
      _showSnack('Appointment accepted successfully!', isError: false);
      Navigator.of(context).pop();
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleReject() async {
    final id = widget.appointmentFull['_id'] as String?;
    if (id == null) return;
    setState(() => _isProcessing = true);
    try {
      final token = await StorageService.getToken();
      final res = await http.patch(
        Uri.parse('$API_BASE_URL/appointments/$id/reject'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (!res.ok) throw Exception(body['message'] ?? 'Failed to reject');
      if (!mounted) return;
      _showSnack('Appointment rejected successfully!', isError: false);
      Navigator.of(context).pop();
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildPatientCard(),
            const SizedBox(height: 16),
            _buildAppointmentCard(),
            if (_status == 'pending') ...[
              const SizedBox(height: 16),
              _buildActionButtons(),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF374151)),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Patient Details',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111827),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _statusBgColor(),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.access_time, size: 13, color: _statusFgColor()),
              const SizedBox(width: 4),
              Text(
                _capitalize(_status),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _statusFgColor(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Patient Card ──────────────────────────────────────────────────────────

  Widget _buildPatientCard() {
    final allergies = (_patient['allergies'] as List?)?.cast<String>() ?? [];
    final medications = (_patient['medications'] as List?)?.cast<String>() ?? [];
    final emergency = (_patient['emergencyContact'] as Map<String, dynamic>?) ?? {};

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gradient header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: const Text(
              'Patient Information',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + name
                Row(
                  children: [
                    _patientAvatar(_patient['profile_image'] as String?),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _patient['fullName'] as String? ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  size: 15, color: Color(0xFF9CA3AF)),
                              const SizedBox(width: 4),
                              Text(
                                _patient['gender'] as String? ?? 'N/A',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Divider(height: 1, color: Color(0xFFF3F4F6)),
                ),

                // Info grid
                _infoRow(Icons.email_outlined, 'Email',
                    _patient['email'] as String?, const Color(0xFF3B82F6)),
                _infoRow(Icons.phone_outlined, 'Phone',
                    _patient['phone'] as String?, const Color(0xFF22C55E)),
                _infoRow(Icons.water_drop_outlined, 'Blood Type',
                    _patient['bloodType'] as String?, const Color(0xFFEF4444)),
                _infoRow(
                    Icons.cake_outlined,
                    'Date of Birth',
                    _formatDate(_patient['dateOfBirth'] as String?),
                    const Color(0xFFA855F7)),
                _infoRow(
                    Icons.height_outlined,
                    'Height',
                    _patient['height'] != null
                        ? '${_patient['height']} cm'
                        : null,
                    const Color(0xFF6366F1)),
                _infoRow(
                    Icons.monitor_weight_outlined,
                    'Weight',
                    _patient['weight'] != null
                        ? '${_patient['weight']} kg'
                        : null,
                    const Color(0xFFF97316)),

                const SizedBox(height: 16),

                // Emergency contact
                _coloredSection(
                  color: const Color(0xFFFEE2E2),
                  borderColor: const Color(0xFFFECACA),
                  icon: Icons.warning_amber_rounded,
                  iconColor: const Color(0xFFDC2626),
                  titleColor: const Color(0xFF7F1D1D),
                  title: 'Emergency Contact',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF991B1B)),
                          children: [
                            TextSpan(
                              text: emergency['name'] as String? ?? 'N/A',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (emergency['relationship'] != null)
                              TextSpan(
                                  text: ' (${emergency['relationship']})'),
                          ],
                        ),
                      ),
                      if (emergency['phone'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          emergency['phone'] as String,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF991B1B)),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Medical info row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _coloredSection(
                        color: const Color(0xFFFFFBEB),
                        borderColor: const Color(0xFFFDE68A),
                        icon: Icons.warning_amber_rounded,
                        iconColor: const Color(0xFFD97706),
                        titleColor: const Color(0xFF78350F),
                        title: 'Allergies',
                        child: Text(
                          allergies.isEmpty
                              ? 'None reported'
                              : allergies.join(', '),
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF92400E)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _coloredSection(
                        color: const Color(0xFFF5F3FF),
                        borderColor: const Color(0xFFDDD6FE),
                        icon: Icons.medication_outlined,
                        iconColor: const Color(0xFF7C3AED),
                        titleColor: const Color(0xFF4C1D95),
                        title: 'Medications',
                        child: Text(
                          medications.isEmpty
                              ? 'None reported'
                              : medications.join(', '),
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF5B21B6)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Appointment Card ──────────────────────────────────────────────────────

  Widget _buildAppointmentCard() {
    final isOnline =
        (widget.appointmentFull['appointmentMode'] as String?) == 'online';
    final address = _hospital['address'] as String?;
    final city = _hospital['city'] as String?;
    final state = _hospital['state'] as String?;
    final country = _hospital['country'] as String?;
    final addressParts =
        [address, city, state, country].where((p) => p != null).join(', ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gradient header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: const Text(
              'Appointment Details',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(
                    Icons.calendar_today_outlined,
                    'Scheduled Date & Time',
                    _formatDateTime(
                        widget.appointmentFull['appointmentDateTime']
                            as String?),
                    const Color(0xFF22C55E)),
                _infoRow(
                    Icons.access_time_outlined,
                    'Time Slot',
                    widget.appointmentFull['time'] as String?,
                    const Color(0xFF3B82F6)),
                _infoRow(
                    isOnline ? Icons.videocam_outlined : Icons.location_on_outlined,
                    'Mode',
                    isOnline ? 'Online (Video Call)' : 'In-Person',
                    const Color(0xFFA855F7)),
                _infoRow(
                    Icons.local_hospital_outlined,
                    'Hospital',
                    _hospital['name'] as String?,
                    const Color(0xFF6366F1)),

                const SizedBox(height: 16),

                // Reason
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reason for Visit',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.appointmentFull['reason'] as String? ?? 'N/A',
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF1D4ED8)),
                      ),
                    ],
                  ),
                ),

                // Hospital address
                if (addressParts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          addressParts,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF6B7280)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Action Buttons ────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Accept
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _handleAccept,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: Text(
                _isProcessing ? 'Processing…' : 'Accept Appointment',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF22C55E).withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Reject
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _handleReject,
              icon: const Icon(Icons.cancel_outlined, size: 20),
              label: Text(
                _isProcessing ? 'Processing…' : 'Reject Appointment',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    const Color(0xFFEF4444).withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared Widgets ────────────────────────────────────────────────────────

  Widget _infoRow(IconData icon, String label, String? value, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
                const SizedBox(height: 2),
                Text(
                  value ?? 'N/A',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _coloredSection({
    required Color color,
    required Color borderColor,
    required IconData icon,
    required Color iconColor,
    required Color titleColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _patientAvatar(String? url) {
    final hasUrl = url != null && url.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: hasUrl
          ? Image.network(
              url,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackAvatar(),
            )
          : _fallbackAvatar(),
    );
  }

  Widget _fallbackAvatar() => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFDBEAFE),
          borderRadius: BorderRadius.circular(40),
        ),
        child: const Icon(Icons.person, color: Color(0xFF3B82F6), size: 36),
      );
}

// ── Extension for http.Response ───────────────────────────────────────────────

extension _ResponseX on http.Response {
  bool get ok => statusCode >= 200 && statusCode < 300;
}