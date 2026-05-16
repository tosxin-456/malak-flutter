import 'package:flutter/material.dart';

class CallMessageBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMyMessage;

  const CallMessageBubble({
    super.key,
    required this.msg,
    required this.isMyMessage,
  });

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final call = (msg['content']?['call'] as Map<String, dynamic>?) ?? {};
    final status = call['status']?.toString() ?? 'ended';
    final callType = call['callType']?.toString() ?? 'voice';
    final duration = (call['duration'] ?? 0) as int;

    late Color bg, textColor, iconColor;
    late IconData statusIcon;
    late String label;
    String? durationText;

    switch (status) {
      case 'missed':
        bg = isMyMessage
            ? Colors.red.withOpacity(0.2)
            : const Color(0xFFFEF2F2);
        textColor = isMyMessage
            ? const Color(0xFFFCA5A5)
            : const Color(0xFFEF4444);
        iconColor = textColor;
        statusIcon = Icons.phone_missed;
        label = 'Missed call';
        break;
      case 'declined':
      case 'rejected':
        bg = isMyMessage
            ? Colors.white.withOpacity(0.1)
            : const Color(0xFFF3F4F6);
        textColor = isMyMessage
            ? const Color(0xFFE5E7EB)
            : const Color(0xFF6B7280);
        iconColor = textColor;
        statusIcon = Icons.phone_disabled;
        label = 'Call declined';
        break;
      default:
        bg = isMyMessage
            ? Colors.white.withOpacity(0.1)
            : const Color(0xFFF3F4F6);
        textColor = isMyMessage ? Colors.white : const Color(0xFF374151);
        iconColor = isMyMessage
            ? const Color(0xFF86EFAC)
            : const Color(0xFF22C55E);
        statusIcon = Icons.call_received;
        label = 'Call ended';
        if (duration > 0) durationText = _formatDuration(duration);
    }

    final callIcon = callType == 'video' ? Icons.videocam : Icons.phone;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMyMessage
                  ? Colors.white.withOpacity(0.15)
                  : Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(callIcon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 13, color: textColor),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              if (durationText != null) ...[
                const SizedBox(height: 2),
                Text(
                  durationText,
                  style: TextStyle(
                    color: isMyMessage
                        ? Colors.white.withOpacity(0.7)
                        : const Color(0xFF6B7280),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
