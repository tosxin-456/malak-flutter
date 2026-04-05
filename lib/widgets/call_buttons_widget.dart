import 'package:flutter/material.dart';
import 'package:malak/context/call_provider.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CallButtonsWidget  (replaces the stub from before)
// ─────────────────────────────────────────────────────────────────────────────

class CallButtonsWidget extends StatelessWidget {
  final Map<String, dynamic> otherParticipant;
  final String? chatId;
  final String? consultId;

  const CallButtonsWidget({
    super.key,
    required this.otherParticipant,
    this.chatId,
    this.consultId,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, callProvider, _) {
        final idle = callProvider.callMode == CallMode.idle;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.phone_outlined, color: Color(0xFF374151)),
              onPressed: idle
                  ? () => callProvider.startCall(
                      'voice',
                      otherParticipant: otherParticipant,
                      chatId: chatId,
                      consultId: consultId,
                    )
                  : null,
              tooltip: 'Voice Call',
            ),
            IconButton(
              icon: const Icon(
                Icons.videocam_outlined,
                color: Color(0xFF374151),
              ),
              onPressed: idle
                  ? () => callProvider.startCall(
                      'video',
                      otherParticipant: otherParticipant,
                      chatId: chatId,
                      consultId: consultId,
                    )
                  : null,
              tooltip: 'Video Call',
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IncomingCallOverlay  — shows as a full-screen overlay when ringing
// Wrap your root widget with this to catch incoming calls app-wide.
// ─────────────────────────────────────────────────────────────────────────────

class IncomingCallOverlay extends StatelessWidget {
  final Widget child;
  const IncomingCallOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, callProvider, _) {
        final incoming = callProvider.incomingCall;
        if (callProvider.callMode == CallMode.ringing && incoming != null) {
          return Stack(
            children: [
              child,
              _IncomingCallSheet(incoming: incoming),
            ],
          );
        }
        // Show active call screen
        if (callProvider.callMode == CallMode.inCall) {
          return Stack(children: [child, const ActiveCallScreen()]);
        }
        return child;
      },
    );
  }
}

class _IncomingCallSheet extends StatelessWidget {
  final IncomingCallData incoming;
  const _IncomingCallSheet({required this.incoming});

  @override
  Widget build(BuildContext context) {
    final callProvider = Provider.of<CallProvider>(context, listen: false);
    final isVideo = incoming.callType == 'video';

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1E3A8A), Color(0xFF1D4ED8)],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top info
                Column(
                  children: [
                    const SizedBox(height: 60),
                    Text(
                      isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Avatar
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      backgroundImage: incoming.profileImage != null
                          ? NetworkImage(incoming.profileImage!)
                          : null,
                      child: incoming.profileImage == null
                          ? Text(
                              incoming.from.isNotEmpty
                                  ? incoming.from[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      incoming.from,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),

                // Buttons
                Padding(
                  padding: const EdgeInsets.only(bottom: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Reject
                      _callActionButton(
                        icon: Icons.call_end,
                        color: const Color(0xFFEF4444),
                        label: 'Decline',
                        onTap: callProvider.rejectCall,
                      ),
                      // Answer
                      _callActionButton(
                        icon: isVideo ? Icons.videocam : Icons.call,
                        color: const Color(0xFF22C55E),
                        label: 'Answer',
                        onTap: callProvider.answerCall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _callActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ActiveCallScreen  — shown when callMode == inCall
// ─────────────────────────────────────────────────────────────────────────────

class ActiveCallScreen extends StatelessWidget {
  const ActiveCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, cp, _) {
        final isVideo = cp.callType == 'video';
        final callee = cp.currentCallee;

        return Positioned.fill(
          child: Material(
            color: const Color(0xFF0F172A),
            child: SafeArea(
              child: Stack(
                children: [
                  // Remote video (full screen)
                  if (isVideo && cp.remoteUids.isNotEmpty)
                    AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: cp.engine!,
                        canvas: VideoCanvas(uid: cp.remoteUids.first),
                        connection: const RtcConnection(channelId: ''),
                      ),
                    )
                  else
                    // Voice call background
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 56,
                            backgroundColor: Colors.white.withOpacity(0.15),
                            backgroundImage: callee?.profileImage != null
                                ? NetworkImage(callee!.profileImage!)
                                : null,
                            child: callee?.profileImage == null
                                ? Text(
                                    callee?.fullName.isNotEmpty == true
                                        ? callee!.fullName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 40,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            callee?.fullName ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Call in progress',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Local video PiP (top-right)
                  if (isVideo && cp.localUid != null)
                    Positioned(
                      top: 16,
                      right: 16,
                      width: 100,
                      height: 140,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: AgoraVideoView(
                          controller: VideoViewController(
                            rtcEngine: cp.engine!,
                            canvas: const VideoCanvas(uid: 0),
                          ),
                        ),
                      ),
                    ),

                  // Control bar
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _controlBtn(
                          icon: cp.localAudioEnabled
                              ? Icons.mic
                              : Icons.mic_off,
                          color: cp.localAudioEnabled
                              ? Colors.white24
                              : const Color(0xFFEF4444),
                          onTap: cp.toggleAudio,
                          label: cp.localAudioEnabled ? 'Mute' : 'Unmute',
                        ),
                        // End call
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () => cp.endCall(),
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.call_end,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'End',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        if (isVideo)
                          _controlBtn(
                            icon: cp.localVideoEnabled
                                ? Icons.videocam
                                : Icons.videocam_off,
                            color: cp.localVideoEnabled
                                ? Colors.white24
                                : const Color(0xFFEF4444),
                            onTap: cp.toggleVideo,
                            label: cp.localVideoEnabled
                                ? 'Video off'
                                : 'Video on',
                          )
                        else
                          _controlBtn(
                            icon: Icons.volume_up,
                            color: Colors.white24,
                            onTap: () {},
                            label: 'Speaker',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
