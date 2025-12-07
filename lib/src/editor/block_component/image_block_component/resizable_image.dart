import 'dart:io';
import 'dart:math';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:string_validator/string_validator.dart';

import 'base64_image.dart';

class ResizableImage extends StatefulWidget {
  const ResizableImage({
    super.key,
    required this.alignment,
    required this.editable,
    required this.onResize,
    required this.width,
    required this.src,
    this.height,
  });

  final String src;
  final double width;
  final double? height;
  final Alignment alignment;
  final bool editable;

  final void Function(double width) onResize;

  @override
  State<ResizableImage> createState() => _ResizableImageState();
}

const _kImageBlockComponentMinWidth = 30.0;

class _ResizableImageState extends State<ResizableImage> {
  late double imageWidth;

  double initialOffset = 0;
  double moveDistance = 0;

  Image? _cacheImage;

  @visibleForTesting
  bool onFocus = false;

  @override
  void initState() {
    super.initState();

    imageWidth = widget.width;
  }

  @override
  void didUpdateWidget(ResizableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync internal imageWidth with widget.width when it changes externally
    // This is important when resizing from a smaller saved size back to larger
    if (oldWidget.width != widget.width) {
      imageWidth = widget.width;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: SizedBox(
        width: max(_kImageBlockComponentMinWidth, imageWidth - moveDistance),
        height: widget.height,
        child: MouseRegion(
          onEnter: (event) => setState(() {
            onFocus = true;
          }),
          onExit: (event) => setState(() {
            onFocus = false;
          }),
          child: _buildResizableImage(context),
        ),
      ),
    );
  }

  Widget _buildResizableImage(BuildContext context) {
    Widget child;
    final src = widget.src;
    if (isBase64(src)) {
      // load base64 image (url is raw base64 from web)
      // Cache base64 images since they're in-memory data
      _cacheImage ??= Image.memory(
        dataFromBase64String(src),
      );
      child = _cacheImage!;
    } else if (isURL(src)) {
      // load network image
      // Use current visual width (imageWidth - moveDistance) instead of widget.width
      // This ensures the image scales properly during drag, especially when resizing up
      final currentVisualWidth = max(_kImageBlockComponentMinWidth, imageWidth - moveDistance);

      // Don't cache the Image widget - Flutter's image cache handles the actual image data
      // Recreate the widget when width changes during drag for visual feedback
      // Flutter's NetworkImage cache will handle the actual image bytes
      child = Image.network(
        widget.src,
        width: currentVisualWidth,
        gaplessPlayback: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null || loadingProgress.cumulativeBytesLoaded == loadingProgress.expectedTotalBytes) {
            return child;
          }
          return _buildLoading(context);
        },
        errorBuilder: (context, error, stackTrace) => _buildError(context),
      );
    } else {
      // load local file
      final file = File(src);
      if (file.existsSync()) {
        // Cache file images since file I/O is involved
        _cacheImage ??= Image.file(
          file,
          errorBuilder: (context, error, stackTrace) => _buildError(context),
        );
        child = _cacheImage!;
      } else {
        // File doesn't exist, show error
        child = _buildError(context);
      }
    }
    final isMobile = _isMobile();
    final handleTouchWidth = isMobile ? 30.0 : 5.0;
    final handleVisualWidth = isMobile ? 8.0 : 5.0;
    final handleOffset = isMobile ? 0.0 : 5.0;

    return Stack(
      children: [
        child,
        if (widget.editable) ...[
          _buildEdgeGesture(
            context,
            top: 0,
            left: handleOffset,
            bottom: 0,
            width: handleTouchWidth,
            visualWidth: handleVisualWidth,
            onUpdate: (distance) {
              setState(() {
                moveDistance = distance;
              });
            },
          ),
          _buildEdgeGesture(
            context,
            top: 0,
            right: handleOffset,
            bottom: 0,
            width: handleTouchWidth,
            visualWidth: handleVisualWidth,
            onUpdate: (distance) {
              setState(() {
                moveDistance = -distance;
              });
            },
          ),
        ],
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.fromSize(
            size: const Size(18, 18),
            child: const CircularProgressIndicator(),
          ),
          SizedBox.fromSize(
            size: const Size(10, 10),
          ),
          Text(AppFlowyEditorL10n.current.loading),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Container(
      height: 100,
      width: imageWidth,
      alignment: Alignment.center,
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(4.0)),
        border: Border.all(width: 1, color: Colors.black),
      ),
      child: Text(AppFlowyEditorL10n.current.imageLoadFailed),
    );
  }

  bool _isMobile() {
    return !kIsWeb && (Platform.isIOS || Platform.isAndroid);
  }

  Widget _buildEdgeGesture(
    BuildContext context, {
    double? top,
    double? left,
    double? right,
    double? bottom,
    double? width,
    double? visualWidth,
    void Function(double distance)? onUpdate,
  }) {
    final isMobile = _isMobile();
    final handleVisualWidth = visualWidth ?? width ?? 5.0;
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) {
          initialOffset = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (details) {
          if (onUpdate != null) {
            var offset = (details.globalPosition.dx - initialOffset);
            if (widget.alignment == Alignment.center) {
              offset *= 2.0;
            }
            onUpdate(offset);
          }
        },
        onHorizontalDragEnd: (details) {
          imageWidth = max(_kImageBlockComponentMinWidth, imageWidth - moveDistance);
          initialOffset = 0;
          moveDistance = 0;

          widget.onResize(imageWidth);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: (onFocus || isMobile)
              ? Center(
                  child: Container(
                    width: handleVisualWidth,
                    height: isMobile ? 60 : 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: isMobile ? 0.7 : 0.5),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(5.0),
                      ),
                      border: Border.all(
                        width: isMobile ? 2 : 1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
