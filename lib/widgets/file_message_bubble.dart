import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class FileMessageBubble extends StatelessWidget {
  final Map<String, dynamic> msg;
  final bool isMyMessage;

  const FileMessageBubble({
    super.key,
    required this.msg,
    required this.isMyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final content = (msg['content'] as Map<String, dynamic>?) ?? {};
    final name = content['fileName']?.toString() ?? 'File';
    final url = content['fileUrl']?.toString() ?? '';
    final size = ((content['fileSize'] ?? 0) as num).toInt();
    final sizeKb = (size / 1024).round();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMyMessage ? const Color(0xFF16A34A) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMyMessage
              ? const Color(0xFF16A34A)
              : const Color(0xFFD1D5DB),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.attach_file,
            size: 16,
            color: isMyMessage ? Colors.white : const Color(0xFF374151),
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
                    fontWeight: FontWeight.w500,
                    color: isMyMessage ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                Text(
                  '$sizeKb KB',
                  style: TextStyle(
                    fontSize: 11,
                    color: isMyMessage
                        ? Colors.white.withOpacity(0.7)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => launchUrl(Uri.parse(url)),
            child: Icon(
              Icons.download,
              size: 18,
              color: isMyMessage ? Colors.white : const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
}
