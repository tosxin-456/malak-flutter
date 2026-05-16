import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';
import 'package:malak/widgets/logout_button.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool editing = false;
  bool saving = false;
  bool loading = true;
  bool imageUploading = false;

  Map<String, dynamic>? user;
  String newAllergy = "";
  Map<String, String> newMedication = {
    "name": "",
    "dosage": "",
    "frequency": "",
  };




  @override
  void initState() {
    super.initState();
    fetchProfile();
  }

  Future<void> fetchProfile() async {
    // Get token from shared preferences or secure storage
    final token = await StorageService.getToken();

    try {
      final response = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        setState(() {
          user = json.decode(response.body);
          loading = false;
        });
      } else {
        throw Exception('Failed to load profile');
      }
    } catch (e) {
      print('Error fetching profile: $e');
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> handleImageUpload() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    setState(() {
      imageUploading = true;
    });

    final token = await StorageService.getToken();

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$API_BASE_URL/users/profile-image'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        await http.MultipartFile.fromPath('profileImage', image.path),
      );

      var response = await request.send();

      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var data = json.decode(responseData);
        setState(() {
          user!['profile_image'] =
              data['profileImageUrl'] ?? data['profile_image'];
          imageUploading = false;
        });
      }
    } catch (e) {
      print('Error uploading image: $e');
      setState(() {
        imageUploading = false;
      });
    }
  }

  Future<void> handleSave() async {
    setState(() {
      saving = true;
    });

    final token = await StorageService.getToken();

    try {
      final response = await http.put(
        Uri.parse('$API_BASE_URL/users/update'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(user),
      );

      if (response.statusCode == 200) {
        setState(() {
          user = json.decode(response.body);
          editing = false;
          saving = false;
        });
      }
    } catch (e) {
      print('Error updating profile: $e');
      setState(() {
        saving = false;
      });
    }
  }

  void addAllergy() {
    if (newAllergy.trim().isNotEmpty) {
      List<dynamic> allergies = user!['allergies'] ?? [];
      if (!allergies.contains(newAllergy.trim())) {
        setState(() {
          allergies.add(newAllergy.trim());
          user!['allergies'] = allergies;
          newAllergy = "";
        });
      }
    }
  }

  void removeAllergy(int index) {
    setState(() {
      List<dynamic> allergies = user!['allergies'] ?? [];
      allergies.removeAt(index);
      user!['allergies'] = allergies;
    });
  }

  void addMedication() {
    if (newMedication['name']!.trim().isNotEmpty &&
        newMedication['dosage']!.trim().isNotEmpty &&
        newMedication['frequency']!.trim().isNotEmpty) {
      setState(() {
        List<dynamic> medications = user!['medications'] ?? [];
        medications.add(Map<String, String>.from(newMedication));
        user!['medications'] = medications;
        newMedication = {"name": "", "dosage": "", "frequency": ""};
      });
    }
  }

  void removeMedication(int index) {
    setState(() {
      List<dynamic> medications = user!['medications'] ?? [];
      medications.removeAt(index);
      user!['medications'] = medications;
    });
  }

  String formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return "Not specified";
    try {
      DateTime date = DateTime.parse(dateString);
      return "${date.day} ${_getMonthName(date.month)} ${date.year}";
    } catch (e) {
      return "Not specified";
    }
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF1D4ED8)),
              SizedBox(height: 16),
              Text('Loading profile...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red),
              SizedBox(height: 16),
              Text(
                'Failed to load profile data',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D4ED8),
        elevation: 4,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.favorite, color: Color(0xFFFCA5A5), size: 24),
            const SizedBox(width: 8),
            const Text(
              'Malak',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Settings clicked')));
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ElevatedButton.icon(
              onPressed: saving
                  ? null
                  : () {
                      if (editing) {
                        handleSave();
                      } else {
                        setState(() {
                          editing = true;
                        });
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(editing ? Icons.save : Icons.edit, size: 20),
              label: Text(
                saving ? 'Saving...' : (editing ? 'Save' : 'Edit'),
                style: const TextStyle(fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
          // <-- Add Logout here
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: LogoutButton(),
          ),
        ],

      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isDesktop = constraints.maxWidth > 1024;

          if (isDesktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1, child: _buildProfileCard()),
                Expanded(flex: 2, child: _buildMainContent()),
              ],
            );
          } else {
            return SingleChildScrollView(
              child: Column(
                children: [_buildProfileCard(), _buildMainContent()],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF60A5FA),
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            spreadRadius: 2,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: user!['profile_image'] != null
                            ? Image.network(
                                user!['profile_image'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(
                                      Icons.person,
                                      size: 64,
                                      color: Colors.white,
                                    ),
                              )
                            : const Icon(
                                Icons.person,
                                size: 64,
                                color: Colors.white,
                              ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: imageUploading ? null : handleImageUpload,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1D4ED8),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: imageUploading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  user!['fullName'] ?? 'No name provided',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.email, color: Color(0xFFBFDBFE), size: 16),
                    const SizedBox(width: 4),
                    Text(
                      user!['email'] ?? 'No email provided',
                      style: const TextStyle(
                        color: Color(0xFFBFDBFE),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Quick Info
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _buildInfoCard(
                  Icons.phone,
                  'Phone',
                  user!['phone'] != null && user!['phone'] != 'N/A'
                      ? user!['phone']
                      : 'Not provided',
                ),
                const SizedBox(height: 16),
                _buildInfoCard(
                  Icons.calendar_today,
                  'Date of Birth',
                  formatDate(user!['dateOfBirth']),
                ),
                const SizedBox(height: 16),
                _buildInfoCard(
                  Icons.person_outline,
                  'Gender',
                  user!['gender'] ?? 'Not specified',
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                _buildEmergencyContact(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContact() {
    final emergencyContact = user!['emergencyContact'] ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.notifications, color: Colors.red, size: 16),
            SizedBox(width: 8),
            Text(
              'Emergency Contact',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                emergencyContact['name'] != null &&
                        emergencyContact['name'] != 'N/A'
                    ? emergencyContact['name']
                    : 'Not provided',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                emergencyContact['relationship'] != null &&
                        emergencyContact['relationship'] != 'N/A'
                    ? emergencyContact['relationship']
                    : 'Not specified',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.phone, color: Colors.red, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    emergencyContact['phone'] != null &&
                            emergencyContact['phone'] != 'N/A'
                        ? emergencyContact['phone']
                        : 'Not provided',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildMedicalInformation(),
          if (editing) ...[
            const SizedBox(height: 16),
            _buildPersonalInformationEdit(),
            const SizedBox(height: 16),
            _buildEmergencyContactEdit(),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicalInformation() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite, color: Color(0xFF2563EB), size: 20),
              SizedBox(width: 8),
              Text(
                'Medical Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1D4ED8),
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  Icons.straighten,
                  'Height',
                  user!['height']?.toString() ?? '0',
                  'cm',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  Icons.monitor_weight,
                  'Weight',
                  user!['weight']?.toString() ?? '0',
                  'kg',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  Icons.water_drop,
                  'Blood Type',
                  user!['bloodType'] ?? 'Not set',
                  '',
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          _buildAllergiesSection(),
          const SizedBox(height: 24),
          _buildMedicationsSection(),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    IconData icon,
    String label,
    String value,
    String unit,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color == Colors.blue
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color == Colors.blue
              ? const Color(0xFFBFDBFE)
              : const Color(0xFFFECACA),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: color == Colors.blue ? const Color(0xFF3B82F6) : Colors.red,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          if (editing && label != 'Blood Type')
            TextField(
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              controller: TextEditingController(text: value),
              onChanged: (val) {
                setState(() {
                  user![label.toLowerCase()] = int.tryParse(val) ?? 0;
                });
              },
            )
          else if (editing && label == 'Blood Type')
            DropdownButtonFormField<String>(
              value: value == 'Not set' ? null : value,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
              onChanged: (val) {
                setState(() {
                  user!['bloodType'] = val;
                });
              },
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color == Colors.blue
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFFDC2626),
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    ' $unit',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAllergiesSection() {
    List<dynamic> allergies = user!['allergies'] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.amber, size: 16),
            SizedBox(width: 8),
            Text('Allergies', style: TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allergies.isEmpty
                    ? [
                        Text(
                          'No allergies recorded',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ]
                    : allergies.asMap().entries.map((entry) {
                        return Chip(
                          label: Text(entry.value.toString()),
                          backgroundColor: const Color(0xFFFEF3C7),
                          labelStyle: const TextStyle(color: Color(0xFF92400E)),
                          deleteIcon: editing
                              ? const Icon(Icons.close, size: 16)
                              : null,
                          onDeleted: editing
                              ? () => removeAllergy(entry.key)
                              : null,
                        );
                      }).toList(),
              ),
              if (editing) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Add new allergy',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (val) => newAllergy = val,
                        onSubmitted: (_) => addAllergy(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: addAllergy,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFEF3C7),
                        foregroundColor: const Color(0xFF92400E),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMedicationsSection() {
    List<dynamic> medications = user!['medications'] ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.access_time, color: Color(0xFF3B82F6), size: 16),
            SizedBox(width: 8),
            Text(
              'Current Medications',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(
            children: [
              if (medications.isEmpty)
                Text(
                  'No medications recorded',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                ...medications.asMap().entries.map((entry) {
                  final med = entry.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                med['name'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1D4ED8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${med['dosage']}, ${med['frequency']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (editing)
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => removeMedication(entry.key),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              if (editing) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add New Medication',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Medication name',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => newMedication['name'] = val,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Dosage (e.g., 10mg)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => newMedication['dosage'] = val,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Frequency (e.g., twice daily)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => newMedication['frequency'] = val,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: addMedication,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Medication'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPersonalInformationEdit() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Edit Personal Information',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D4ED8),
            ),
          ),
          const Divider(height: 32),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              _buildEditField('Full Name', 'fullName', user!['fullName'] ?? ''),
              _buildEditField('Email', 'email', user!['email'] ?? ''),
              _buildEditField('Phone', 'phone', user!['phone'] ?? ''),
              _buildDateField(),
              _buildGenderDropdown(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditField(String label, String field, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
          ),
          controller: TextEditingController(text: value),
          onChanged: (val) {
            setState(() {
              user![field] = val;
            });
          },
        ),
      ],
    );
  }

  Widget _buildDateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date of Birth',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            DateTime? picked = await showDatePicker(
              context: context,
              initialDate: user!['dateOfBirth'] != null
                  ? DateTime.parse(user!['dateOfBirth'])
                  : DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              setState(() {
                user!['dateOfBirth'] = picked.toIso8601String();
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDate(user!['dateOfBirth'])),
                const Icon(Icons.calendar_today, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gender',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: user!['gender'],
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: ['Male', 'Female', 'Non-binary', 'Other', 'Prefer not to say']
              .map(
                (gender) =>
                    DropdownMenuItem(value: gender, child: Text(gender)),
              )
              .toList(),
          onChanged: (val) {
            setState(() {
              user!['gender'] = val;
            });
          },
        ),
      ],
    );
  }

  Widget _buildEmergencyContactEdit() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text(
                'Edit Emergency Contact',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 3,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              _buildEmergencyField('Name', 'name'),
              _buildEmergencyField('Relationship', 'relationship'),
              _buildEmergencyField('Phone', 'phone'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyField(String label, String field) {
    final emergencyContact = user!['emergencyContact'] ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
            ),
          ),
          controller: TextEditingController(
            text: emergencyContact[field] ?? '',
          ),
          onChanged: (val) {
            setState(() {
              if (user!['emergencyContact'] == null) {
                user!['emergencyContact'] = {};
              }
              user!['emergencyContact'][field] = val;
            });
          },
        ),
      ],
    );
  }
}
