import 'package:flutter/material.dart';

class AudioMessageBubble extends StatefulWidget {
  final Map<String, dynamic> msg;
  final bool isMyMessage;

  const AudioMessageBubble({
    super.key,
    required this.msg,
    required this.isMyMessage,
  });

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  bool _playing = false;

  // TODO: integrate `audioplayers` package
  void _togglePlay() => setState(() => _playing = !_playing);

  @override
  Widget build(BuildContext context) {
    final content = (widget.msg['content'] as Map<String, dynamic>?) ?? {};
    final name = content['fileName']?.toString() ?? 'Audio';
    final size = ((content['fileSize'] ?? 0) as num).toInt();
    final mine = widget.isMyMessage;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? const Color(0xFF16A34A) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: mine ? const Color(0xFF16A34A) : const Color(0xFFD1D5DB),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              color: mine ? Colors.white : const Color(0xFF374151),
              size: 22,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: mine ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                Text(
                  '${(size / 1024).round()} KB',
                  style: TextStyle(
                    fontSize: 11,
                    color: mine
                        ? Colors.white.withOpacity(0.7)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
