// lib/screens/doctor/my_patients_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:malak/config/api_config.dart';

// ─── Theme ────────────────────────────────────────────────────────────────────

const _bg = Color(0xFFF9FAFB);
const _surface = Colors.white;
const _textPrimary = Color(0xFF111827);
const _textSecondary = Color(0xFF6B7280);
const _divider = Color(0xFFF3F4F6);
const _green = Color(0xFF059669);
const _greenLight = Color(0xFFECFDF5);
const _blue = Color(0xFF2563EB);
const _blueLight = Color(0xFFEFF6FF);
const _red = Color(0xFFEF4444);
const _redLight = Color(0xFFFEF2F2);
const _yellow = Color(0xFFD97706);
const _yellowLight = Color(0xFFFFFBEB);
const _purple = Color(0xFF7C3AED);
const _purpleLight = Color(0xFFF5F3FF);

// ─── Screen ───────────────────────────────────────────────────────────────────

class MyPatientsPage extends StatefulWidget {
  const MyPatientsPage({Key? key}) : super(key: key);

  @override
  State<MyPatientsPage> createState() => _MyPatientsPageState();
}

class _MyPatientsPageState extends State<MyPatientsPage> {
  List<Map<String, dynamic>> _patients = [];
  bool _loading = true;

  final _searchCtrl = TextEditingController();
  String _searchTerm = '';
  String _selectedStatus = 'all';
  String _selectedCondition = 'all';
  bool _showFilters = false;

  Map<String, dynamic>? _selectedPatient;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fetchPatients();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── API ────────────────────────────────────────────────────────────────────

  Future<void> _fetchPatients() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      if (token == null) return;

      final res = await http.get(
        Uri.parse('$API_BASE_URL/appointments/doctor/patients'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode == 200 && mounted) {
        final List data = json.decode(res.body);
        setState(() {
          _patients = data.map((p) {
            final map = Map<String, dynamic>.from(p);
            // Normalise dates
            if (map['lastVisit'] != null) {
              try {
                map['lastVisit'] = _formatDate(map['lastVisit'] as String);
              } catch (_) {}
            } else {
              map['lastVisit'] = 'N/A';
            }
            map['vitals'] =
                map['vitals'] ??
                {'bp': '-', 'heartRate': '-', 'temperature': '-'};
            map['allergies'] = map['allergies'] ?? [];
            map['medications'] = map['medications'] ?? [];
            map['address'] = map['address'] ?? 'N/A';
            map['phone'] = map['phone'] ?? 'N/A';
            map['status'] = map['status'] ?? 'Active';
            final visits = (map['visits'] as List<dynamic>?) ?? [];
            map['visits'] = visits.map((v) {
              final vm = Map<String, dynamic>.from(v);
              if (vm['date'] != null) {
                try {
                  vm['date'] = _formatDate(vm['date'] as String);
                } catch (_) {}
              }
              return vm;
            }).toList();
            return map;
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Fetch patients error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _filtered {
    final term = _searchTerm.toLowerCase();
    return _patients.where((p) {
      final name = (p['name'] as String? ?? '').toLowerCase();
      final id = (p['id'] as String? ?? '').toLowerCase();
      final malakId = (p['malak_id'] as String? ?? '').toLowerCase();
      final email = (p['email'] as String? ?? '').toLowerCase();
      final matchSearch =
          term.isEmpty ||
          name.contains(term) ||
          id.contains(term) ||
          malakId.contains(term) ||
          email.contains(term);

      final status = (p['status'] as String? ?? '').toLowerCase();
      final matchStatus = _selectedStatus == 'all' || status == _selectedStatus;

      final condition = (p['condition'] as String? ?? '').toLowerCase();
      final matchCondition =
          _selectedCondition == 'all' ||
          condition.contains(_selectedCondition.toLowerCase());

      return matchSearch && matchStatus && matchCondition;
    }).toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatDate(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      const months = [
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
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) {
      return dateStr;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return _green;
      case 'new':
        return _blue;
      case 'archived':
        return _textSecondary;
      default:
        return _textSecondary;
    }
  }

  Color _statusBg(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return _greenLight;
      case 'new':
        return _blueLight;
      case 'archived':
        return _divider;
      default:
        return _divider;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Icons.verified_user_rounded;
      case 'new':
        return Icons.person_add_rounded;
      case 'archived':
        return Icons.archive_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _loading ? _buildSkeleton() : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: const Color(0x14000000),
      backgroundColor: _surface,
      toolbarHeight: 60,
      automaticallyImplyLeading: false,
      title: const Text(
        'My Patients',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.refresh_rounded,
            color: _textSecondary,
            size: 22,
          ),
          onPressed: _fetchPatients,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    final filtered = _filtered;

    return Column(
      children: [
        _buildSearchAndFilters(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Showing ${filtered.length} of ${_patients.length} patients',
                style: const TextStyle(fontSize: 12, color: _textSecondary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _blueLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_patients.length} Total',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _blue,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: _green,
                  onRefresh: _fetchPatients,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _buildPatientCard(filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  // ── Search & Filters ───────────────────────────────────────────────────────

  Widget _buildSearchAndFilters() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          // Search bar
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchTerm = v),
            style: const TextStyle(fontSize: 14, color: _textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by name, ID or email…',
              hintStyle: const TextStyle(fontSize: 14, color: _textSecondary),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: _textSecondary,
                size: 20,
              ),
              suffixIcon: _searchTerm.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: _textSecondary,
                        size: 18,
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchTerm = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: _bg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _blue, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Filter toggle row
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showFilters = !_showFilters),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.circular(8),
                    color: _showFilters ? _blueLight : _surface,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 16,
                        color: _showFilters ? _blue : _textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _showFilters ? _blue : _textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Quick status chips
              _statusChip('all', 'All'),
              const SizedBox(width: 6),
              _statusChip('active', 'Active'),
              const SizedBox(width: 6),
              _statusChip('new', 'New'),
            ],
          ),

          // Expanded filters
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: _showFilters
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      children: [
                        _filterDropdown(
                          label: 'Status',
                          value: _selectedStatus,
                          items: const [
                            ('all', 'All Status'),
                            ('active', 'Active'),
                            ('new', 'New'),
                            ('archived', 'Archived'),
                          ],
                          onChanged: (v) => setState(() => _selectedStatus = v),
                        ),
                        const SizedBox(height: 8),
                        _filterDropdown(
                          label: 'Condition',
                          value: _selectedCondition,
                          items: const [
                            ('all', 'All Conditions'),
                            ('hypertension', 'Hypertension'),
                            ('diabetes', 'Diabetes'),
                            ('anxiety', 'Anxiety'),
                            ('arthritis', 'Arthritis'),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedCondition = v),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String value, String label) {
    final isSelected = _selectedStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedStatus = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _blue : _bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _blue : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : _textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _filterDropdown({
    required String label,
    required String value,
    required List<(String, String)> items,
    required void Function(String) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: _textSecondary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        filled: true,
        fillColor: _bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _blue, width: 2),
        ),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item.$1,
              child: Text(item.$2, style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: (v) => v != null ? onChanged(v) : null,
    );
  }

  // ── Patient Card ───────────────────────────────────────────────────────────

  Widget _buildPatientCard(Map<String, dynamic> patient) {
    final name = patient['name'] as String? ?? 'Unknown';
    final email = patient['email'] as String? ?? '';
    final malakId = patient['malak_id'] as String? ?? '';
    final lastVisit = patient['lastVisit'] as String? ?? 'N/A';
    final condition = patient['condition'] as String? ?? 'N/A';
    final status = patient['status'] as String? ?? 'Active';

    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Top row: avatar + name + status badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _blueLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: _blue,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      if (email.isNotEmpty)
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (malakId.isNotEmpty)
                        Text(
                          malakId.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _blue,
                            letterSpacing: 0.6,
                          ),
                        ),
                    ],
                  ),
                ),
                _statusBadge(status),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: _divider),
            const SizedBox(height: 10),

            // Info row
            Row(
              children: [
                _infoChip(Icons.calendar_today_rounded, lastVisit, _blue),
                const SizedBox(width: 10),
                Expanded(
                  child: _infoChip(
                    Icons.medical_information_rounded,
                    condition,
                    _purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                _iconAction(
                  icon: Icons.visibility_rounded,
                  color: _blue,
                  bg: _blueLight,
                  label: 'View',
                  onTap: () => _openPatientModal(patient),
                ),
                const SizedBox(width: 8),
                _iconAction(
                  icon: Icons.history_rounded,
                  color: _green,
                  bg: _greenLight,
                  label: 'History',
                  onTap: () =>
                      Navigator.pushNamed(context, '/consultation-history'),
                ),
                const SizedBox(width: 8),
                _iconAction(
                  icon: Icons.chat_bubble_rounded,
                  color: _purple,
                  bg: _purpleLight,
                  label: 'Message',
                  onTap: () => Navigator.pushNamed(context, '/messages'),
                ),
                const SizedBox(width: 8),
                _iconAction(
                  icon: Icons.open_in_new_rounded,
                  color: _yellow,
                  bg: _yellowLight,
                  label: 'Record',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusBg(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 11, color: _statusColor(status)),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _statusColor(status),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: _textSecondary),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _iconAction({
    required IconData icon,
    required Color color,
    required Color bg,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Patient Modal ──────────────────────────────────────────────────────────

  void _openPatientModal(Map<String, dynamic> patient) {
    setState(() => _selectedPatient = patient);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PatientModal(
        patient: patient,
        onClose: () {
          Navigator.pop(context);
          setState(() => _selectedPatient = null);
        },
      ),
    );
  }

  // ── Empty State ────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _blueLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline_rounded,
              color: _blue,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No patients found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try adjusting your search or filters.',
            style: TextStyle(fontSize: 13, color: _textSecondary),
          ),
        ],
      ),
    );
  }

  // ── Skeleton ───────────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

// ─── Patient Modal Bottom Sheet ───────────────────────────────────────────────

class _PatientModal extends StatelessWidget {
  final Map<String, dynamic> patient;
  final VoidCallback onClose;

  const _PatientModal({required this.patient, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final name = patient['name'] as String? ?? 'Unknown';
    final id = patient['id'] as String? ?? '';
    final age = patient['age']?.toString() ?? 'N/A';
    final gender = patient['gender'] as String? ?? 'N/A';
    final phone = patient['phone'] as String? ?? 'N/A';
    final email = patient['email'] as String? ?? 'N/A';
    final address = patient['address'] as String? ?? 'N/A';
    final condition = patient['condition'] as String? ?? 'N/A';
    final notes = patient['notes'] as String? ?? 'No notes.';
    final allergies = (patient['allergies'] as List<dynamic>?) ?? [];
    final medications = (patient['medications'] as List<dynamic>?) ?? [];
    final visits = (patient['visits'] as List<dynamic>?) ?? [];
    final vitals =
        (patient['vitals'] as Map<String, dynamic>?) ??
        {'bp': '-', 'heartRate': '-', 'temperature': '-'};

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle + header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text(
                        'Patient Profile',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: _textSecondary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1, color: _divider),
                ],
              ),
            ),

            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                children: [
                  // Basic Info
                  _section(
                    color: _blueLight,
                    icon: Icons.person_rounded,
                    iconColor: _blue,
                    title: 'Basic Information',
                    child: Column(
                      children: [
                        _infoRow('Name', name),
                        _infoRow('ID', id),
                        _infoRow('Age', age),
                        _infoRow('Gender', gender),
                        _infoRow('Phone', phone),
                        _infoRow('Email', email),
                        _infoRow('Address', address, last: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Medical Summary
                  _section(
                    color: _redLight,
                    icon: Icons.warning_amber_rounded,
                    iconColor: _red,
                    title: 'Medical Summary',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow('Primary Condition', condition),
                        _infoRow(
                          'Allergies',
                          allergies.isEmpty ? 'None' : allergies.join(', '),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Current Medications',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (medications.isEmpty)
                          const Text(
                            'None',
                            style: TextStyle(
                              fontSize: 13,
                              color: _textSecondary,
                            ),
                          )
                        else
                          ...medications.map(
                            (m) => Padding(
                              padding: const EdgeInsets.only(left: 10, top: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: const BoxDecoration(
                                      color: _red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    m.toString(),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: _textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Vitals
                  _section(
                    color: _greenLight,
                    icon: Icons.monitor_heart_rounded,
                    iconColor: _green,
                    title: 'Latest Vitals',
                    child: Row(
                      children: [
                        _vitalCard(
                          vitals['bp']?.toString() ?? '-',
                          'Blood Pressure',
                        ),
                        const SizedBox(width: 8),
                        _vitalCard(
                          vitals['heartRate']?.toString() ?? '-',
                          'Heart Rate (bpm)',
                        ),
                        const SizedBox(width: 8),
                        _vitalCard(
                          vitals['temperature']?.toString() ?? '-',
                          'Temperature',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Visit History
                  _section(
                    color: _bg,
                    icon: Icons.calendar_month_rounded,
                    iconColor: _textSecondary,
                    title: 'Visit History',
                    child: Column(
                      children: visits.isEmpty
                          ? [
                              const Text(
                                'No visits recorded.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _textSecondary,
                                ),
                              ),
                            ]
                          : visits.map<Widget>((v) {
                              final vm = v as Map<String, dynamic>;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _divider),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          vm['date']?.toString() ?? 'N/A',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12.5,
                                            color: _textPrimary,
                                          ),
                                        ),
                                        Text(
                                          vm['reason']?.toString() ?? '',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: _textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (vm['notes'] != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        vm['notes'].toString(),
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: _textSecondary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Doctor Notes
                  _section(
                    color: _yellowLight,
                    icon: Icons.notes_rounded,
                    iconColor: _yellow,
                    title: 'Doctor Notes',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notes,
                          style: const TextStyle(
                            fontSize: 13,
                            color: _textPrimary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _noteAction(
                              icon: Icons.edit_rounded,
                              label: 'Edit Notes',
                              color: _blue,
                              bg: _blueLight,
                            ),
                            const SizedBox(width: 8),
                            _noteAction(
                              icon: Icons.upload_rounded,
                              label: 'Upload Reports',
                              color: _green,
                              bg: _greenLight,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Bottom action
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text(
                        'Open Full Record',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.shield_rounded,
                        size: 13,
                        color: _textSecondary,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Last accessed: Today at 2:30 PM',
                        style: TextStyle(fontSize: 11.5, color: _textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _section({
    required Color color,
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  static Widget _infoRow(String label, String value, {bool last = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12.5, color: _textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _vitalCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _green,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: _textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _noteAction({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
