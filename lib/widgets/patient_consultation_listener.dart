import 'package:flutter/material.dart';
import 'package:malak/context/socket_provider.dart';
import 'package:malak/services/firebase_messaging_service.dart';
import 'package:provider/provider.dart';

/// Listens for doctor starting a consultation (socket + FCM) and shows join UI.
class PatientConsultationListener extends StatefulWidget {
  final Widget child;

  const PatientConsultationListener({super.key, required this.child});

  @override
  State<PatientConsultationListener> createState() =>
      _PatientConsultationListenerState();
}

class _PatientConsultationListenerState extends State<PatientConsultationListener> {
  bool _showModal = false;
  String? _consultId;
  String? _doctorId;
  String? _doctorName;
  String? _doctorAvatar;
  String _appointmentMode = 'online';
  String? _boundSocketId;

  @override
  void initState() {
    super.initState();
    FirebaseMessagingService.instance.onConsultationIncoming =
        _onPushConsultation;
  }

  @override
  void dispose() {
    FirebaseMessagingService.instance.onConsultationIncoming = null;
    super.dispose();
  }

  void _onPushConsultation(Map<String, dynamic> data) {
    if (!mounted) return;
    _openModal(
      consultId: data['consultId']?.toString(),
      doctorId: data['fromId']?.toString(),
      doctorName: data['fromName']?.toString() ?? 'Your doctor',
      doctorAvatar: null,
      appointmentMode: data['appointmentMode']?.toString() ?? 'online',
    );
  }

  void _openModal({
    required String? consultId,
    required String? doctorId,
    required String doctorName,
    String? doctorAvatar,
    required String appointmentMode,
  }) {
    if (consultId == null || consultId.isEmpty) return;
    setState(() {
      _showModal = true;
      _consultId = consultId;
      _doctorId = doctorId;
      _doctorName = doctorName;
      _doctorAvatar = doctorAvatar;
      _appointmentMode = appointmentMode;
    });
  }

  void _closeModal() {
    setState(() {
      _showModal = false;
      _consultId = null;
      _doctorId = null;
      _doctorName = null;
      _doctorAvatar = null;
    });
  }

  void _bindSocket(SocketNotifier socketNotifier) {
    final socket = socketNotifier.socket;
    if (socket == null) return;

    socket.off('consult:incoming');
    socket.off('consult:cancelled');

    socket.on('consult:incoming', (data) {
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      if (!mounted) return;
      _openModal(
        consultId: map['consultId']?.toString(),
        doctorId: map['fromId']?.toString(),
        doctorName: map['fromName']?.toString() ?? 'Your doctor',
        doctorAvatar: map['profile_image']?.toString(),
        appointmentMode: map['appointmentMode']?.toString() ?? 'online',
      );
    });

    socket.on('consult:cancelled', (data) {
      if (data is! Map) return;
      final cid = data['consultId']?.toString();
      if (cid != null && cid == _consultId && mounted) {
        _closeModal();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Consultation was cancelled')),
        );
      }
    });
  }

  void _joinConsultation(SocketNotifier socketNotifier) {
    final socket = socketNotifier.socket;
    final consultId = _consultId;
    final doctorId = _doctorId;
    if (socket == null || consultId == null) return;

    socket.emit('consult:accepted', {'to': doctorId, 'consultId': consultId});

    _closeModal();

    final route = _appointmentMode == 'offline'
        ? '/consultation-room/$consultId/visit'
        : '/consultation-room/$consultId/live';
    Navigator.of(context).pushNamed(route);
  }

  void _decline(SocketNotifier socketNotifier) {
    final socket = socketNotifier.socket;
    if (socket != null && _consultId != null) {
      socket.emit('consult:cancelled', {
        'to': _doctorId,
        'consultId': _consultId,
        'reason': 'patient_declined',
      });
    }
    _closeModal();
  }

  void _ensureSocketListeners(SocketNotifier socketNotifier) {
    final socket = socketNotifier.socket;
    if (socket == null || !socketNotifier.isConnected) return;
    final sid = socket.id;
    if (sid != null && sid == _boundSocketId) return;
    _boundSocketId = sid;
    _bindSocket(socketNotifier);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SocketNotifier>(
      builder: (context, socketNotifier, _) {
        _ensureSocketListeners(socketNotifier);

        return Stack(
          children: [
            widget.child,
            if (_showModal) ...[
              ModalBarrier(
                color: Colors.black54,
                dismissible: false,
              ),
              Center(
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: _doctorAvatar != null &&
                                  _doctorAvatar!.isNotEmpty
                              ? NetworkImage(_doctorAvatar!)
                              : null,
                          child: _doctorAvatar == null || _doctorAvatar!.isEmpty
                              ? const Icon(Icons.person, size: 40)
                              : null,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Consultation is ready!',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Dr. $_doctorName is ready to begin',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _joinConsultation(socketNotifier),
                            icon: const Icon(Icons.videocam),
                            label: const Text('Enter consultation'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => _decline(socketNotifier),
                          child: const Text('Not now'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
