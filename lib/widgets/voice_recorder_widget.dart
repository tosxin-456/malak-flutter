import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Drop-in replacement for the React VoiceRecorder component.
///
/// Usage (inside the chat input row):
/// ```dart
/// VoiceRecorderWidget(
///   chatId: widget.chatId,
///   onSend: (msg) => setState(() => _messages.add(msg)),
///   disabled: _sending,
/// )
/// ```
///
/// The preview floats above the keyboard via an [OverlayEntry], exactly
/// matching the React `position: fixed; bottom: 80px` behaviour.
class VoiceRecorderWidget extends StatefulWidget {
  final String chatId;
  final void Function(Map<String, dynamic> msg) onSend;
  final bool disabled;

  const VoiceRecorderWidget({
    super.key,
    required this.chatId,
    required this.onSend,
    required this.disabled,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget> {
  // ── Recording ──────────────────────────────────────────────────────────────
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _cancelled = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _previewPath; // local file path after stopping

  // ── Preview playback ───────────────────────────────────────────────────────
  final _player = AudioPlayer();
  bool _playing = false;
  double _currentTime = 0;
  double _duration = 0;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completeSub;

  // ── Upload ─────────────────────────────────────────────────────────────────
  bool _sending = false;

  // ── Waveform bars (random, generated once per recording) ──────────────────
  List<double> _bars = [];

  // ── Overlay for the floating preview panel ─────────────────────────────────
  OverlayEntry? _overlayEntry;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _currentTime = pos.inMilliseconds / 1000.0);
        _refreshOverlay();
      }
    });
    _durationSub = _player.onDurationChanged.listen((dur) {
      if (mounted) {
        setState(() => _duration = dur.inMilliseconds / 1000.0);
        _refreshOverlay();
      }
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _currentTime = 0;
        });
        _refreshOverlay();
      }
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    _removeOverlay();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _fmt(num s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toInt().toString().padLeft(2, '0');
    return '$m:$sec';
  }

  void _generateBars() {
    final rng = Random();
    _bars = List.generate(40, (_) => rng.nextDouble() * 60 + 20);
  }

  // ── Recording ──────────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_recording) {
      // Stop recording → show preview
      _cancelled = false;
      final path = await _recorder.stop();
      _recordTimer?.cancel();
      if (mounted) {
        setState(() {
          _recording = false;
          _previewPath = path;
          _recordTimer = null;
        });
        if (path != null) _showOverlay();
      }
    } else {
      // Start recording
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _showSnack('Microphone permission denied');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _generateBars();
      await _recorder.start(const RecordConfig(), path: path);
      if (mounted) {
        setState(() {
          _recording = true;
          _recordSeconds = 0;
          _previewPath = null;
        });
      }
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordSeconds++);
      });
    }
  }

  void _cancelRecording() {
    _cancelled = true;
    _recorder.stop();
    _recordTimer?.cancel();
    _reset();
  }

  // ── Preview playback ───────────────────────────────────────────────────────

  Future<void> _togglePlayPreview() async {
    if (_previewPath == null) return;
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.play(DeviceFileSource(_previewPath!));
      setState(() => _playing = true);
    }
    _refreshOverlay();
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  Future<void> _sendRecording() async {
    if (_previewPath == null) return;
    setState(() => _sending = true);
    _refreshOverlay();

    try {
      // Stop playback if running
      if (_playing) {
        await _player.stop();
        setState(() => _playing = false);
      }

      final token = await StorageService.getToken();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$API_BASE_URL/chats/${widget.chatId}/messages/file'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('file', _previewPath!));
      req.fields['isVoiceNote'] = 'true';
      req.fields['duration'] = '$_recordSeconds';

      final streamed = await req.send();
      final res = await http.Response.fromStream(streamed);

      if ((res.statusCode == 200 || res.statusCode == 201) && mounted) {
        widget.onSend(Map<String, dynamic>.from(jsonDecode(res.body)));
        _reset();
      } else {
        _showSnack('Failed to send voice note');
      }
    } catch (e) {
      debugPrint('Voice send error: $e');
      _showSnack('Failed to send voice note');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _reset() {
    _removeOverlay();
    if (mounted) {
      setState(() {
        _recording = false;
        _previewPath = null;
        _recordSeconds = 0;
        _playing = false;
        _currentTime = 0;
        _duration = 0;
        _sending = false;
        _bars = [];
      });
    }
  }

  // ── Overlay (floating preview panel) ──────────────────────────────────────

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = OverlayEntry(builder: (_) => _PreviewOverlay(state: this));
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Force the overlay to rebuild after state changes.
  void _refreshOverlay() {
    _overlayEntry?.markNeedsBuild();
  }

  // ── Snackbar ───────────────────────────────────────────────────────────────

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: (widget.disabled || _sending || _previewPath != null)
              ? null
              : _toggleRecording,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _recording ? const Color(0xFFEF4444) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.mic,
              size: 20,
              color: _recording ? Colors.white : const Color(0xFF6B7280),
            ),
          ),
        ),
        if (_recording) ...[
          const SizedBox(width: 4),
          Text(
            _fmt(_recordSeconds),
            style: const TextStyle(
              color: Color(0xFFEF4444),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _cancelRecording,
            child: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating preview panel rendered as an OverlayEntry
// (mirrors the React `position: fixed; bottom: 80px` panel)
// ─────────────────────────────────────────────────────────────────────────────

class _PreviewOverlay extends StatelessWidget {
  final _VoiceRecorderWidgetState state;
  const _PreviewOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    final bars = state._bars;
    final currentTime = state._currentTime;
    final duration = state._duration;
    final playing = state._playing;
    final sending = state._sending;
    final recordSeconds = state._recordSeconds;

    // Progress fraction for waveform colouring
    final progress = duration > 0 ? (currentTime / duration) : 0.0;

    return Positioned(
      bottom: 80,
      left: 8,
      right: 8,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Play / Pause
              GestureDetector(
                onTap: state._togglePlayPreview,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Waveform
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: bars.isEmpty
                      ? const SizedBox()
                      : Row(
                          children: List.generate(bars.length, (i) {
                            final barFrac = i / bars.length;
                            final played = barFrac <= progress;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 0.5,
                                ),
                                child: Container(
                                  height: bars[i] * 0.3,
                                  decoration: BoxDecoration(
                                    color: played
                                        ? const Color(0xFF22C55E)
                                        : const Color(
                                            0xFF22C55E,
                                          ).withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                ),
              ),
              const SizedBox(width: 8),

              // Time
              Text(
                state._fmt(
                  playing
                      ? currentTime
                      : (duration > 0 ? duration : recordSeconds),
                ),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),

              // Cancel
              GestureDetector(
                onTap: sending ? null : state._cancelRecording,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Send
              GestureDetector(
                onTap: sending ? null : state._sendRecording,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: sending
                        ? const Color(0xFF22C55E).withOpacity(0.5)
                        : const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
