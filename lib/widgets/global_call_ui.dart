import 'dart:async';
import 'package:flutter/material.dart';
import 'package:malak/context/call_provider.dart';
import 'package:provider/provider.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class GlobalCallUI extends StatefulWidget {
  const GlobalCallUI({super.key});

  @override
  State<GlobalCallUI> createState() => _GlobalCallUIState();
}

class _GlobalCallUIState extends State<GlobalCallUI> {
  bool _isMinimized = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, cp, _) {
        if (cp.callMode == CallMode.idle) return const SizedBox.shrink();

        return Stack(
          children: [
            if (!_isMinimized)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
            _buildCallPanel(context, cp),
          ],
        );
      },
    );
  }

  Widget _buildCallPanel(BuildContext context, CallProvider cp) {
    switch (cp.callMode) {
      case CallMode.ringing:
        if (cp.incomingCall != null) {
          return _RingingPanel(
            incoming: cp.incomingCall!,
            isMinimized: _isMinimized,
            onToggleMinimize: () =>
                setState(() => _isMinimized = !_isMinimized),
            onAnswer: cp.answerCall,
            onReject: cp.rejectCall,
          );
        }
        return const SizedBox.shrink();

      case CallMode.calling:
        return _CallingPanel(
          callee: cp.currentCallee,
          isMinimized: _isMinimized,
          onToggleMinimize: () => setState(() => _isMinimized = !_isMinimized),
          onEnd: cp.endCall,
        );

      case CallMode.inCall:
        if (cp.callType == 'video') {
          return _VideoCallPanel(
            cp: cp,
            isMinimized: _isMinimized,
            onToggleMinimize: () =>
                setState(() => _isMinimized = !_isMinimized),
          );
        }
        return _VoiceCallPanel(
          cp: cp,
          isMinimized: _isMinimized,
          onToggleMinimize: () => setState(() => _isMinimized = !_isMinimized),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _fmtDuration(int seconds) {
  final m = (seconds ~/ 60).toString().padLeft(2, '0');
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

Widget _avatar({String? imageUrl, String? name, double radius = 48}) {
  if (imageUrl != null && imageUrl.isNotEmpty) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: NetworkImage(imageUrl),
    );
  }
  final initial = (name?.isNotEmpty == true ? name![0] : '?').toUpperCase();
  return CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFF2A2A2A),
    child: Text(
      initial,
      style: TextStyle(
        color: Colors.white,
        fontSize: radius * 0.7,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

const _kBg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Ringing Panel
// ─────────────────────────────────────────────────────────────────────────────

class _RingingPanel extends StatelessWidget {
  final IncomingCallData incoming;
  final bool isMinimized;
  final VoidCallback onToggleMinimize;
  final VoidCallback onAnswer;
  final VoidCallback onReject;

  const _RingingPanel({
    required this.incoming,
    required this.isMinimized,
    required this.onToggleMinimize,
    required this.onAnswer,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = incoming.callType == 'video';

    return _FullscreenFrame(
      isMinimized: isMinimized,
      onToggleMinimize: onToggleMinimize,
      child: Container(
        decoration: _kBg,
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              _avatar(
                imageUrl: incoming.profileImage,
                name: incoming.from,
                radius: isMinimized ? 36 : 52,
              ),
              const SizedBox(height: 16),
              Text(
                incoming.from,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMinimized ? 18 : 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isVideo ? 'Incoming video call...' : 'Incoming voice call...',
                style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 14),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _LabeledCircleBtn(
                      onTap: onReject,
                      color: const Color(0xFFE53935),
                      icon: Icons.call_end,
                      label: 'Decline',
                      size: isMinimized ? 58 : 68,
                    ),
                    _LabeledCircleBtn(
                      onTap: onAnswer,
                      color: const Color(0xFF25D366),
                      icon: isVideo ? Icons.videocam : Icons.call,
                      label: 'Accept',
                      size: isMinimized ? 58 : 68,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Calling Panel (outgoing)
// ─────────────────────────────────────────────────────────────────────────────

class _CallingPanel extends StatelessWidget {
  final CalleeInfo? callee;
  final bool isMinimized;
  final VoidCallback onToggleMinimize;
  final VoidCallback onEnd;

  const _CallingPanel({
    required this.callee,
    required this.isMinimized,
    required this.onToggleMinimize,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return _FullscreenFrame(
      isMinimized: isMinimized,
      onToggleMinimize: onToggleMinimize,
      child: Container(
        decoration: _kBg,
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              _avatar(
                imageUrl: callee?.profileImage,
                name: callee?.fullName,
                radius: isMinimized ? 36 : 52,
              ),
              const SizedBox(height: 16),
              Text(
                callee?.fullName ?? '',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMinimized ? 18 : 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const _PulsingStatus(label: 'Calling...'),
              const Spacer(flex: 3),
              _LabeledCircleBtn(
                onTap: onEnd,
                color: const Color(0xFFE53935),
                icon: Icons.call_end,
                label: 'End call',
                size: isMinimized ? 58 : 68,
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Voice Call Panel
// ─────────────────────────────────────────────────────────────────────────────

class _VoiceCallPanel extends StatefulWidget {
  final CallProvider cp;
  final bool isMinimized;
  final VoidCallback onToggleMinimize;

  const _VoiceCallPanel({
    required this.cp,
    required this.isMinimized,
    required this.onToggleMinimize,
  });

  @override
  State<_VoiceCallPanel> createState() => _VoiceCallPanelState();
}

class _VoiceCallPanelState extends State<_VoiceCallPanel> {
  int _seconds = 0;
  late Timer _timer;
  bool _speakerOn = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _toggleSpeaker() => setState(() => _speakerOn = !_speakerOn);

  @override
  Widget build(BuildContext context) {
    final cp = widget.cp;
    final isMin = widget.isMinimized;
    final name =
        cp.currentCallee?.fullName ?? cp.incomingCall?.from ?? 'Voice Call';
    final image =
        cp.currentCallee?.profileImage ?? cp.incomingCall?.profileImage;

    return _FullscreenFrame(
      isMinimized: isMin,
      onToggleMinimize: widget.onToggleMinimize,
      child: Container(
        decoration: _kBg,
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              _avatar(imageUrl: image, name: name, radius: isMin ? 44 : 56),
              const SizedBox(height: 16),
              Text(
                name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isMin ? 20 : 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _fmtDuration(_seconds),
                style: const TextStyle(
                  color: Color(0xFF25D366),
                  fontSize: 15,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(flex: 3),

              // ── Controls ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ToggleBtn(
                      onTap: cp.toggleAudio,
                      toggled: !cp.localAudioEnabled,
                      icon: cp.localAudioEnabled ? Icons.mic : Icons.mic_off,
                      label: cp.localAudioEnabled ? 'Mute' : 'Unmute',
                      size: isMin ? 52 : 60,
                    ),
                    _LabeledCircleBtn(
                      onTap: cp.endCall,
                      color: const Color(0xFFE53935),
                      icon: Icons.call_end,
                      label: 'End',
                      size: isMin ? 64 : 72,
                    ),
                    _ToggleBtn(
                      onTap: _toggleSpeaker,
                      toggled: _speakerOn,
                      icon: _speakerOn ? Icons.volume_up : Icons.volume_down,
                      label: 'Speaker',
                      size: isMin ? 52 : 60,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Video Call Panel
// ─────────────────────────────────────────────────────────────────────────────

class _VideoCallPanel extends StatefulWidget {
  final CallProvider cp;
  final bool isMinimized;
  final VoidCallback onToggleMinimize;

  const _VideoCallPanel({
    required this.cp,
    required this.isMinimized,
    required this.onToggleMinimize,
  });

  @override
  State<_VideoCallPanel> createState() => _VideoCallPanelState();
}

class _VideoCallPanelState extends State<_VideoCallPanel> {
  bool _speakerOn = true;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  int _seconds = 0;
  late Timer _callTimer;
  late String _channelId;

  @override
  void initState() {
    super.initState();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
    _scheduleHide();

    // ── FIX: derive real channel name ─────────────────────────────────────
    final cp = widget.cp;
    if (cp.activeConsultId != null) {
      _channelId = 'consult-${cp.activeConsultId}';
    } else {
      final myId = cp.userId;
      final otherId = cp.currentCallee?.id ?? cp.incomingCall?.fromId ?? '';
      _channelId = '$myId-$otherId';
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _callTimer.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _onTap() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _toggleSpeaker() => setState(() => _speakerOn = !_speakerOn);

  @override
  Widget build(BuildContext context) {
    final cp = widget.cp;
    final isMin = widget.isMinimized;
    final name =
        cp.currentCallee?.fullName ?? cp.incomingCall?.from ?? 'Video Call';
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return _FullscreenFrame(
      isMinimized: isMin,
      onToggleMinimize: widget.onToggleMinimize,
      child: GestureDetector(
        onTap: _onTap,
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Remote video ──────────────────────────────────────────────
              if (cp.remoteUids.isNotEmpty && cp.engine != null)
                AgoraVideoView(
                  controller: VideoViewController.remote(
                    rtcEngine: cp.engine!,
                    canvas: VideoCanvas(uid: cp.remoteUids.first),
                    connection: RtcConnection(channelId: _channelId), // FIX
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _avatar(
                        imageUrl:
                            cp.currentCallee?.profileImage ??
                            cp.incomingCall?.profileImage,
                        name: name,
                        radius: 56,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Waiting for video...',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                ),

              // ── Local PiP ─────────────────────────────────────────────────
              if (cp.localUid != null &&
                  cp.engine != null &&
                  cp.localVideoEnabled)
                Positioned(
                  bottom: isMin ? 60 : 110,
                  right: 12,
                  width: isMin ? 80 : 110,
                  height: isMin ? 112 : 155,
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

              // ── Top gradient + name/timer ─────────────────────────────────
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(20, topPad + 48, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fmtDuration(_seconds),
                          style: const TextStyle(
                            color: Color(0xFF25D366),
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Bottom controls ───────────────────────────────────────────
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(24, 24, 24, botPad + 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ToggleBtn(
                          onTap: cp.toggleAudio,
                          toggled: !cp.localAudioEnabled,
                          icon: cp.localAudioEnabled
                              ? Icons.mic
                              : Icons.mic_off,
                          label: cp.localAudioEnabled ? 'Mute' : 'Unmute',
                          size: 52,
                        ),
                        _LabeledCircleBtn(
                          onTap: cp.endCall,
                          color: const Color(0xFFE53935),
                          icon: Icons.call_end,
                          label: 'End',
                          size: 64,
                        ),
                        _ToggleBtn(
                          onTap: _toggleSpeaker,
                          toggled: _speakerOn,
                          icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                          label: 'Speaker',
                          size: 52,
                        ),
                        _ToggleBtn(
                          onTap: cp.toggleVideo,
                          toggled: !cp.localVideoEnabled,
                          icon: cp.localVideoEnabled
                              ? Icons.videocam
                              : Icons.videocam_off,
                          label: 'Camera',
                          size: 52,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fullscreen frame
// ─────────────────────────────────────────────────────────────────────────────

class _FullscreenFrame extends StatelessWidget {
  final bool isMinimized;
  final VoidCallback onToggleMinimize;
  final Widget child;

  const _FullscreenFrame({
    required this.isMinimized,
    required this.onToggleMinimize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    if (isMinimized) {
      return Positioned(
        top: 60,
        right: 12,
        width: 240,
        height: 380,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              SizedBox.expand(child: child),
              Positioned(
                top: 8,
                right: 8,
                child: _MinimizeBtn(onTap: onToggleMinimize, expand: true),
              ),
            ],
          ),
        ),
      );
    }

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              top: topPad + 8,
              right: 12,
              child: _MinimizeBtn(onTap: onToggleMinimize, expand: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _MinimizeBtn extends StatelessWidget {
  final VoidCallback onTap;
  final bool expand;
  const _MinimizeBtn({required this.onTap, required this.expand});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(
          expand ? Icons.open_in_full : Icons.close_fullscreen,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Button widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Solid color circle button with label below
class _LabeledCircleBtn extends StatelessWidget {
  final VoidCallback onTap;
  final Color color;
  final IconData icon;
  final String label;
  final double size;

  const _LabeledCircleBtn({
    required this.onTap,
    required this.color,
    required this.icon,
    required this.label,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: size * 0.42),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Toggle button — lights up when active (e.g. muted, speaker on)
class _ToggleBtn extends StatelessWidget {
  final VoidCallback onTap;
  final bool toggled;
  final IconData icon;
  final String label;
  final double size;

  const _ToggleBtn({
    required this.onTap,
    required this.toggled,
    required this.icon,
    required this.label,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: toggled
                  ? Colors.white.withOpacity(0.9)
                  : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: toggled ? Colors.black : Colors.white,
              size: size * 0.42,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing status text
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingStatus extends StatefulWidget {
  final String label;
  const _PulsingStatus({required this.label});

  @override
  State<_PulsingStatus> createState() => _PulsingStatusState();
}

class _PulsingStatusState extends State<_PulsingStatus>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(_ctrl),
      child: Text(
        widget.label,
        style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 15),
      ),
    );
  }
}
