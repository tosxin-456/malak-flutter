import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class AttachmentMenuWidget extends StatefulWidget {
  final bool disabled;
  final void Function(dynamic file) onImageSelected;
  final void Function(dynamic file) onFileSelected;
  final void Function(dynamic file) onAudioSelected;

  const AttachmentMenuWidget({
    super.key,
    required this.disabled,
    required this.onImageSelected,
    required this.onFileSelected,
    required this.onAudioSelected,
  });

  @override
  State<AttachmentMenuWidget> createState() => _AttachmentMenuWidgetState();
}

class _AttachmentMenuWidgetState extends State<AttachmentMenuWidget> {
  bool _open = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) widget.onImageSelected(file);
    setState(() => _open = false);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
    );
    if (result?.files.single.path != null) {
      widget.onFileSelected(result!.files.single);
    }
    setState(() => _open = false);
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result?.files.single.path != null) {
      widget.onAudioSelected(result!.files.single);
    }
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.attach_file, color: Color(0xFF6B7280)),
          onPressed: widget.disabled
              ? null
              : () => setState(() => _open = !_open),
        ),
        if (_open)
          Positioned(
            bottom: 48,
            left: 0,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 190,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFF3F4F6)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            'Attach',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            size: 16,
                            color: Color(0xFF9CA3AF),
                          ),
                          onPressed: () => setState(() => _open = false),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    _menuItem(
                      Icons.image,
                      const Color(0xFF3B82F6),
                      'Photos & Videos',
                      _pickImage,
                    ),
                    _menuItem(
                      Icons.insert_drive_file,
                      const Color(0xFF16A34A),
                      'Documents',
                      _pickFile,
                    ),
                    _menuItem(
                      Icons.mic,
                      const Color(0xFF9333EA),
                      'Audio',
                      _pickAudio,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _menuItem(
    IconData icon,
    Color color,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
            ),
          ],
        ),
      ),
    );
  }
}
