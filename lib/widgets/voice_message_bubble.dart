import 'package:flutter/material.dart';

class VoiceMessageBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMyMessage;
  final String? playingAudioId;
  final Map<String, double> audioProgress;
  final Map<String, double> audioDurations;
  final double playbackSpeed;
  final void Function(String msgId, String url) onTogglePlay;
  final void Function(double speed) onSpeedChange;

  const VoiceMessageBubble({
    super.key,
    required this.msg,
    required this.isMyMessage,
    required this.playingAudioId,
    required this.audioProgress,
    required this.audioDurations,
    required this.playbackSpeed,
    required this.onTogglePlay,
    required this.onSpeedChange,
  });

  static const _waveform = [
    3,
    5,
    4,
    6,
    3,
    5,
    7,
    4,
    6,
    5,
    4,
    7,
    5,
    6,
    4,
    5,
    3,
    6,
    5,
    4,
    6,
    3,
    5,
    4,
    7,
    5,
    6,
    4,
    5,
    3,
  ];

  String _fmt(double s) {
    final m = s ~/ 60;
    final sec = (s % 60).toInt().toString().padLeft(2, '0');
    return '${m.toString().padLeft(2, '0')}:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final id = msg['_id']?.toString() ?? '';
    final url = msg['content']?['fileUrl']?.toString() ?? '';
    final isPlaying = playingAudioId == id;
    final progress = audioProgress[id] ?? 0;
    final total = audioDurations[id] ?? 1;
    final mine = isMyMessage;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => onTogglePlay(id, url),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: mine ? const Color(0xFF16A34A) : const Color(0xFFE5E7EB),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: mine ? Colors.white : const Color(0xFF374151),
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Waveform
              SizedBox(
                height: 32,
                child: Row(
                  children: List.generate(_waveform.length, (i) {
                    final barProgress = (i / _waveform.length) * 100;
                    final currentProgress = (progress / total) * 100;
                    final played = barProgress <= currentProgress;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Container(
                        width: 3,
                        height: _waveform[i] * 3.0,
                        decoration: BoxDecoration(
                          color: mine
                              ? (played
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.35))
                              : (played
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFD1D5DB)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmt(isPlaying ? progress : total),
                    style: TextStyle(
                      fontSize: 10,
                      color: mine
                          ? Colors.white.withOpacity(0.8)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                  if (isPlaying)
                    GestureDetector(
                      onTap: () {
                        const speeds = [1.0, 1.5, 2.0];
                        final idx = speeds.indexOf(playbackSpeed);
                        onSpeedChange(speeds[(idx + 1) % speeds.length]);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: mine
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${playbackSpeed.toStringAsFixed(playbackSpeed == 1.0 ? 0 : 1)}x',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: mine
                                ? Colors.white
                                : const Color(0xFF374151),
                          ),
                        ),
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
}
