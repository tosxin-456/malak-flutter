import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

// ─── Models ──────────────────────────────────────────────────────────────────

class DoctorModel {
  final String id;
  final String fullName;
  final String specialty;
  final double rating;
  final bool available;
  final bool isOpen;
  final String? avatar;
  final String? description;
  final List<String> availableDays;
  final String timeRange;
  final List<String> appointmentModes;

  DoctorModel({
    required this.id,
    required this.fullName,
    required this.specialty,
    required this.rating,
    required this.available,
    required this.isOpen,
    this.avatar,
    this.description,
    required this.availableDays,
    required this.timeRange,
    required this.appointmentModes,
  });

  factory DoctorModel.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? json['_id']?.toString() ?? '';

    return DoctorModel(
      id: id,
      fullName: json['fullName'] ?? '',
      specialty: json['specialty'] ?? json['doctorType'] ?? '',
      rating: double.tryParse(json['rating']?.toString() ?? '0') ?? 0.0,
      available: json['available'] ?? false,
      isOpen: json['isOpen'] ?? false,
      avatar: json['avatar'] ?? json['profile_image'],
      description: json['description'] ?? json['bio'],
      availableDays: List<String>.from(json['availableDays'] ?? []),
      timeRange: json['timeRange'] ?? '',
      appointmentModes: List<String>.from(json['appointmentModes'] ?? []),
    );
  }
}

class HospitalModel {
  final String id;
  final String name;
  final String? type;

  HospitalModel({required this.id, required this.name, this.type});

  factory HospitalModel.fromJson(Map<String, dynamic> json) {
    return HospitalModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      type: json['type'],
    );
  }
}

// ─── Helper ───────────────────────────────────────────────────────────────────

/// Safely extract a List from a decoded JSON body.
/// Handles three shapes:
///   • The body itself is a List         → [ {...}, ... ]
///   • { "data": [ ... ] }
///   • { "doctors": [ ... ] }  /  { "hospitals": [ ... ] }
List _extractList(dynamic decoded, {String? hint}) {
  if (decoded is List) return decoded;
  if (decoded is Map) {
    // Try hint key first, then common wrappers
    for (final key in [hint, 'data', 'doctors', 'hospitals', 'results']) {
      if (key != null && decoded.containsKey(key) && decoded[key] is List) {
        return decoded[key] as List;
      }
    }
  }
  return [];
}

/// Human-readable label for an appointment mode value coming from the backend.
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

// ─── Component ───────────────────────────────────────────────────────────────

class DoctorSelectionComponent extends StatefulWidget {
  final void Function(DoctorModel doctor)? onDoctorSelect;
  final void Function(String hospitalId)? onHospitalSelect;

  const DoctorSelectionComponent({
    super.key,
    this.onDoctorSelect,
    this.onHospitalSelect,
  });

  @override
  State<DoctorSelectionComponent> createState() =>
      _DoctorSelectionComponentState();
}

class _DoctorSelectionComponentState extends State<DoctorSelectionComponent> {
  String? _selectedHospitalId;
  String? _selectedDoctorId;
  String _searchTerm = '';
  String _specialtyFilter = '';
  bool _showAvailableOnly = false;
  bool _showAllDoctors = false;
  String? _creatingChatFor;

  bool _loadingHospitals = true;
  bool _loadingDoctors = false;
  String? _hospitalsError;
  String? _doctorsError;

  List<HospitalModel> _hospitals = [];
  List<DoctorModel> _doctors = [];

  @override
  void initState() {
    super.initState();
    _fetchHospitals();
  }

  // ── Fetch hospitals ────────────────────────────────────────────────────────

  Future<void> _fetchHospitals() async {
    setState(() {
      _loadingHospitals = true;
      _hospitalsError = null;
    });
    try {
      final uri = Uri.parse('$API_BASE_URL/hospitals');
      debugPrint('[Hospitals] GET $uri');

      final response = await http.get(uri);
      debugPrint('[Hospitals] ${response.statusCode}');
      debugPrint(
        '[Hospitals] body preview: ${response.body.substring(0, response.body.length.clamp(0, 200))}',
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final raw = _extractList(decoded, hint: 'hospitals');
        debugPrint('[Hospitals] parsed ${raw.length} items');
        setState(() {
          _hospitals = raw
              .map((e) => HospitalModel.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } else {
        setState(
          () => _hospitalsError =
              'Failed to load hospitals (${response.statusCode})',
        );
      }
    } catch (e, st) {
      debugPrint('[Hospitals] error: $e\n$st');
      setState(() => _hospitalsError = 'Could not reach server');
    } finally {
      setState(() => _loadingHospitals = false);
    }
  }

  // ── Fetch doctors ──────────────────────────────────────────────────────────

  Future<void> _fetchDoctors(String hospitalId) async {
    setState(() {
      _loadingDoctors = true;
      _doctors = [];
      _doctorsError = null;
      _selectedDoctorId = null;
      _showAllDoctors = false;
    });
    try {
      final uri = Uri.parse('$API_BASE_URL/hospitals/$hospitalId/doctors');
      debugPrint('[Doctors] GET $uri');

      final response = await http.get(uri);
      debugPrint('[Doctors] ${response.statusCode}');
      debugPrint(
        '[Doctors] body preview: ${response.body.substring(0, response.body.length.clamp(0, 300))}',
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final raw = _extractList(decoded, hint: 'doctors');
        debugPrint('[Doctors] parsed ${raw.length} items');

        final docs = raw
            .map((e) => DoctorModel.fromJson(e as Map<String, dynamic>))
            .toList();

        setState(() => _doctors = docs);

        if (docs.isEmpty) {
          setState(() => _doctorsError = 'No doctors found at this hospital');
        }
      } else {
        setState(
          () =>
              _doctorsError = 'Failed to load doctors (${response.statusCode})',
        );
      }
    } catch (e, st) {
      debugPrint('[Doctors] error: $e\n$st');
      setState(() => _doctorsError = 'Could not reach server');
    } finally {
      setState(() => _loadingDoctors = false);
    }
  }

  // ── Create chat ────────────────────────────────────────────────────────────

  Future<void> _createConversation(String participantId) async {
    setState(() => _creatingChatFor = participantId);
    try {
      final token = await StorageService.getToken();
      final response = await http.post(
        Uri.parse('$API_BASE_URL/chats'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({'participantId': participantId}),
      );
      if (!response.statusCode.toString().startsWith('2')) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final newChat = json.decode(response.body);
      if (mounted) {
        Navigator.pushNamed(context, '/messages/${newChat['_id']}');
      }
    } catch (e) {
      debugPrint('[Chat] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create conversation. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingChatFor = null);
    }
  }

  // ── Derived state ──────────────────────────────────────────────────────────

  List<DoctorModel> get _filteredDoctors => _doctors.where((d) {
    final matchesSearch =
        d.fullName.toLowerCase().contains(_searchTerm.toLowerCase()) ||
        d.specialty.toLowerCase().contains(_searchTerm.toLowerCase());
    final matchesSpecialty =
        _specialtyFilter.isEmpty || d.specialty == _specialtyFilter;
    final matchesAvailability = !_showAvailableOnly || d.available;
    return matchesSearch && matchesSpecialty && matchesAvailability;
  }).toList();

  List<String> get _specialties => _doctors
      .map((d) => d.specialty)
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();

  IconData _specialtyIcon(String specialty) {
    const map = {
      'Cardiology': Icons.favorite_outlined,
      'Neurology': Icons.psychology,
      'Ophthalmology': Icons.visibility,
      'Orthopedics': Icons.accessibility_new,
      'Emergency Medicine': Icons.local_hospital,
      'Internal Medicine': Icons.local_hospital,
      'Family Medicine': Icons.group,
      'Pediatrics': Icons.child_care,
      'Dermatology': Icons.person,
      'Psychiatry': Icons.shield,
      'Diagnostic Medicine': Icons.bolt,
      'General Practice': Icons.local_hospital,
    };
    return map[specialty] ?? Icons.local_hospital;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredDoctors;
    final doctorsToShow = _showAllDoctors
        ? filtered
        : filtered.take(4).toList();
    final hasMore = filtered.length > 4;

    return Column(
      children: [
        _buildHospitalSection(),
        const SizedBox(height: 16),
        _buildDoctorSection(filtered, doctorsToShow, hasMore),
      ],
    );
  }

  // ── Hospital section ───────────────────────────────────────────────────────

  Widget _buildHospitalSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.location_on, 'Select Hospital'),
          const SizedBox(height: 16),
          if (_loadingHospitals)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: Color(0xFF2563EB),
                  strokeWidth: 2,
                ),
              ),
            )
          else if (_hospitalsError != null)
            _errorRetry(_hospitalsError!, _fetchHospitals)
          else if (_hospitals.isEmpty)
            _emptyState(Icons.location_off, 'No hospitals available')
          else
            DropdownButtonFormField<String>(
              value: _selectedHospitalId,
              isExpanded: true,
              decoration: _dropdownDecoration(),
              hint: const Text(
                'Choose your preferred hospital',
                style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
              ),
              items: _hospitals
                  .map(
                    (h) => DropdownMenuItem(
                      value: h.id,
                      child: Text(
                        h.type != null ? '${h.name} (${h.type})' : h.name,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _selectedHospitalId = val;
                  _doctors = [];
                  _selectedDoctorId = null;
                  _doctorsError = null;
                  _showAllDoctors = false;
                });
                _fetchDoctors(val);
                widget.onHospitalSelect?.call(val);
              },
            ),
        ],
      ),
    );
  }

  // ── Doctor section ─────────────────────────────────────────────────────────

  Widget _buildDoctorSection(
    List<DoctorModel> filtered,
    List<DoctorModel> doctorsToShow,
    bool hasMore,
  ) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.local_hospital, 'Find Your Doctor'),
          const SizedBox(height: 16),

          // Search bar
          TextField(
            onChanged: (v) => setState(() => _searchTerm = v),
            decoration: InputDecoration(
              hintText: 'Search by doctor name or specialty...',
              hintStyle: const TextStyle(
                fontSize: 14,
                color: Color(0xFF9CA3AF),
              ),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF9CA3AF)),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: _border(),
              enabledBorder: _border(),
              focusedBorder: _border(focused: true),
            ),
          ),
          const SizedBox(height: 12),

          // Filters row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _specialtyFilter.isEmpty ? null : _specialtyFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    prefixIcon: const Icon(
                      Icons.filter_list,
                      color: Color(0xFF9CA3AF),
                      size: 18,
                    ),
                    border: _border(),
                    enabledBorder: _border(),
                    focusedBorder: _border(focused: true),
                  ),
                  hint: const Text(
                    'All Specialties',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text(
                        'All Specialties',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    ..._specialties.map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _specialtyFilter = v ?? ''),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () =>
                    setState(() => _showAvailableOnly = !_showAvailableOnly),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _showAvailableOnly
                            ? const Color(0xFF2563EB)
                            : Colors.white,
                        border: Border.all(
                          color: _showAvailableOnly
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFD1D5DB),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _showAvailableOnly
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 12,
                            )
                          : null,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Available only',
                      style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Doctor list
          if (_selectedHospitalId == null)
            _emptyState(
              Icons.location_on_outlined,
              'Select a hospital above to see doctors',
            )
          else if (_loadingDoctors)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(
                  color: Color(0xFF2563EB),
                  strokeWidth: 2,
                ),
              ),
            )
          else if (_doctorsError != null)
            _errorRetry(
              _doctorsError!,
              () => _fetchDoctors(_selectedHospitalId!),
            )
          else if (_doctors.isEmpty)
            _emptyState(
              Icons.local_hospital,
              'No doctors found at this hospital',
            )
          else if (filtered.isEmpty)
            _emptyState(Icons.search_off, 'No doctors match your filters')
          else ...[
            ...doctorsToShow.map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildDoctorTile(d),
              ),
            ),
            if (hasMore)
              Center(
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _showAllDoctors = !_showAllDoctors),
                  icon: Icon(
                    _showAllDoctors
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_right,
                    size: 18,
                  ),
                  label: Text(
                    _showAllDoctors
                        ? 'Show Less'
                        : 'See All ${filtered.length} Doctors',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    backgroundColor: const Color(0xFFF3F4F6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
          ],

          // Selected doctor summary
          if (_selectedDoctorId != null) ...[
            const SizedBox(height: 16),
            Builder(
              builder: (_) {
                final doc = _doctors
                    .where((d) => d.id == _selectedDoctorId)
                    .firstOrNull;
                if (doc == null) return const SizedBox();
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Selected Doctor',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _avatarWidget(doc.avatar, radius: 20),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dr. ${doc.fullName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E3A8A),
                                ),
                              ),
                              Text(
                                doc.specialty,
                                style: const TextStyle(
                                  color: Color(0xFF1D4ED8),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // ── Doctor tile ────────────────────────────────────────────────────────────

  Widget _buildDoctorTile(DoctorModel doctor) {
    final isSelected = _selectedDoctorId == doctor.id;

    return GestureDetector(
      onTap: doctor.available
          ? () {
              setState(() => _selectedDoctorId = doctor.id);
              widget.onDoctorSelect?.call(doctor);
              widget.onHospitalSelect?.call(_selectedHospitalId ?? '');
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFEFF6FF)
              : doctor.available
              ? Colors.white
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B82F6)
                : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Opacity(
          opacity: doctor.available ? 1.0 : 0.6,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        _avatarWidget(doctor.avatar, radius: 28),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: doctor.available
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF9CA3AF),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dr. ${doctor.fullName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                _specialtyIcon(doctor.specialty),
                                color: const Color(0xFF2563EB),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  doctor.specialty,
                                  style: const TextStyle(
                                    color: Color(0xFF2563EB),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEFCE8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                color: Color(0xFFFACC15),
                                size: 13,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                doctor.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Color(0xFF92400E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (doctor.available) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => _createConversation(doctor.id),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: Color(0xFF3B82F6),
                                shape: BoxShape.circle,
                              ),
                              child: _creatingChatFor == doctor.id
                                  ? const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.message,
                                      color: Colors.white,
                                      size: 15,
                                    ),
                            ),
                          ),
                        ],
                        if (isSelected) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: Color(0xFF3B82F6),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: CircleAvatar(
                                radius: 4,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),

                if (doctor.description != null &&
                    doctor.description!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    doctor.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],

                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                const SizedBox(height: 10),

                // Bottom chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (doctor.availableDays.isNotEmpty)
                      _infoChip(
                        Icons.calendar_today,
                        doctor.availableDays.take(2).join(', '),
                      ),
                    if (doctor.timeRange.isNotEmpty)
                      _infoChip(Icons.access_time, doctor.timeRange),
                    _statusChip(
                      doctor.available ? 'Available' : 'Not Available',
                      doctor.available
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEE2E2),
                      doctor.available
                          ? const Color(0xFF166534)
                          : const Color(0xFF991B1B),
                      doctor.available
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444),
                    ),
                    _statusChip(
                      doctor.isOpen ? 'Open Schedule' : 'Fixed Schedule',
                      doctor.isOpen
                          ? const Color(0xFFDBEAFE)
                          : const Color(0xFFF3F4F6),
                      doctor.isOpen
                          ? const Color(0xFF1E40AF)
                          : const Color(0xFF6B7280),
                      doctor.isOpen
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF9CA3AF),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _avatarWidget(String? url, {double radius = 24}) {
    const fallback =
        'https://www.gravatar.com/avatar/0662d90eb3d5d9764f07d6e25da3f5ca?s=200&r=pg&d=mm';
    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(
        (url != null && url.isNotEmpty) ? url : fallback,
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String label) => Row(
    children: [
      Icon(icon, color: const Color(0xFF2563EB), size: 20),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
      ),
    ],
  );

  OutlineInputBorder _border({bool focused = false}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(
      color: focused ? const Color(0xFF2563EB) : const Color(0xFFE5E7EB),
      width: focused ? 2 : 1,
    ),
  );

  InputDecoration _dropdownDecoration() => InputDecoration(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: _border(),
    enabledBorder: _border(),
    focusedBorder: _border(focused: true),
  );

  Widget _emptyState(IconData icon, String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(icon, size: 48, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 12),
          Text(
            msg,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _errorRetry(String msg, VoidCallback onRetry) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 40, color: Color(0xFFEF4444)),
          const SizedBox(height: 8),
          Text(
            msg,
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _infoChip(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: const Color(0xFF9CA3AF)),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
      ),
    ],
  );

  Widget _statusChip(String label, Color bg, Color textColor, Color dotColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
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
      border: Border.all(color: const Color(0xFFF3F4F6)),
    ),
    padding: const EdgeInsets.all(20),
    child: child,
  );
}
