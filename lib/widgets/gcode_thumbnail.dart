import 'package:flutter/material.dart';
import '../services/gcode_repository.dart';

/// Keep the image cache key stable across progress and temperature updates.
class GcodeThumbnail extends StatefulWidget {
  final String? base64;
  final double? height;
  final BoxFit fit;
  const GcodeThumbnail(
      {super.key,
      required this.base64,
      this.height,
      this.fit = BoxFit.contain});

  @override
  State<GcodeThumbnail> createState() => _GcodeThumbnailState();
}

class _GcodeThumbnailState extends State<GcodeThumbnail> {
  MemoryImage? _image;

  void _decode() {
    final bytes = decodeThumbnail(widget.base64);
    _image = bytes == null ? null : MemoryImage(bytes);
  }

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant GcodeThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64 != widget.base64) _decode();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: _image == null
            ? const Icon(Icons.insert_drive_file, size: 72)
            : Image(
                image: _image!,
                height: widget.height,
                fit: widget.fit,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
      );
}
