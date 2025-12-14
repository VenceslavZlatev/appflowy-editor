import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/util/platform_extension.dart';
import 'package:flutter/material.dart';

class TableColBorder extends StatefulWidget {
  const TableColBorder({
    super.key,
    required this.tableNode,
    required this.editorState,
    required this.colIdx,
    required this.resizable,
    required this.borderColor,
    required this.borderHoverColor,
    this.hitboxWidth,
    this.hitboxAlignment = Alignment.centerRight,
    this.activeColNotifier,
  });

  final bool resizable;
  final int colIdx;
  final TableNode tableNode;
  final EditorState editorState;

  final Color borderColor;
  final Color borderHoverColor;
  final double? hitboxWidth;
  final AlignmentGeometry hitboxAlignment;
  final ValueNotifier<int?>? activeColNotifier;

  @override
  State<TableColBorder> createState() => _TableColBorderState();
}

class _TableColBorderState extends State<TableColBorder> {
  final GlobalKey _borderKey = GlobalKey();
  bool _borderHovering = false;
  bool _borderDragging = false;
  VoidCallback? _tableListener;

  Offset? _lastLongPressPosition;

  Offset initialOffset = const Offset(0, 0);

  @override
  void didUpdateWidget(TableColBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset cache and update listener when table node changes
    if (oldWidget.tableNode != widget.tableNode) {
      // Remove old listener and add new one
      if (_tableListener != null) {
        oldWidget.tableNode.node.removeListener(_tableListener!);
      }
      _setupTableListener();
    }
    // Listen to notifier changes to rebuild when highlighting needs update
    if (oldWidget.activeColNotifier != widget.activeColNotifier) {
      if (oldWidget.activeColNotifier != null) {
        oldWidget.activeColNotifier!.removeListener(_onNotifierChanged);
      }
      if (widget.activeColNotifier != null) {
        widget.activeColNotifier!.addListener(_onNotifierChanged);
      }
    }
  }

  void _onNotifierChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _setupTableListener();
    if (widget.activeColNotifier != null) {
      widget.activeColNotifier!.addListener(_onNotifierChanged);
    }
  }

  @override
  void dispose() {
    if (_tableListener != null) {
      widget.tableNode.node.removeListener(_tableListener!);
    }
    if (widget.activeColNotifier != null) {
      widget.activeColNotifier!.removeListener(_onNotifierChanged);
    }
    super.dispose();
  }

  void _setupTableListener() {
    _tableListener = () {
      if (mounted) {
        // Use addPostFrameCallback to debounce updates during rapid changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              // Rebuild to update border
            });
          }
        });
      }
    };
    widget.tableNode.node.addListener(_tableListener!);
  }

  bool get _isActive {
    if (_borderHovering || _borderDragging) return true;
    if (widget.activeColNotifier != null) {
      return widget.activeColNotifier!.value == widget.colIdx;
    }
    return false;
  }

  void _updateActiveState(bool active) {
    if (widget.activeColNotifier != null) {
      if (active) {
        // Only update if we are not already active to avoid loops
        if (widget.activeColNotifier!.value != widget.colIdx) {
          widget.activeColNotifier!.value = widget.colIdx;
        }
      } else {
        // Only clear if we are the current active one
        if (widget.activeColNotifier!.value == widget.colIdx) {
          widget.activeColNotifier!.value = null;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.resizable ? buildResizableBorder(context) : buildFixedBorder(context);
  }

  MouseRegion buildResizableBorder(BuildContext context) {
    // If hitboxWidth is provided, we use it to determine the width of the GestureDetector container.
    // Otherwise we default to the visual border width.
    final touchWidth = widget.hitboxWidth ?? widget.tableNode.config.borderWidth;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) {
        setState(() => _borderHovering = true);
        _updateActiveState(true);
      },
      onExit: (_) {
        setState(() => _borderHovering = false);
        _updateActiveState(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent, // Allow hits on transparent areas
        onLongPressStart: (LongPressStartDetails details) {
          if (!PlatformExtension.isMobile) return;
          setState(() => _borderDragging = true);
          _updateActiveState(true);
          _lastLongPressPosition = details.globalPosition;
        },
        onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) {
          if (!PlatformExtension.isMobile || _lastLongPressPosition == null) {
            return;
          }
          final delta = details.globalPosition.dx - _lastLongPressPosition!.dx;
          final colWidth = widget.tableNode.getColWidth(widget.colIdx);
          widget.tableNode.setColWidth(
            widget.colIdx,
            colWidth + delta,
          );
          _lastLongPressPosition = details.globalPosition;
        },
        onLongPressEnd: (LongPressEndDetails details) {
          if (!PlatformExtension.isMobile) return;
          final transaction = widget.editorState.transaction;
          widget.tableNode.setColWidth(
            widget.colIdx,
            widget.tableNode.getColWidth(widget.colIdx),
            transaction: transaction,
            force: true,
          );
          transaction.afterSelection = transaction.beforeSelection;
          widget.editorState.apply(transaction);
          setState(() => _borderDragging = false);
          _updateActiveState(false);
          _lastLongPressPosition = null;
        },
        onHorizontalDragStart: (DragStartDetails details) {
          setState(() => _borderDragging = true);
          _updateActiveState(true);
          initialOffset = details.globalPosition;
        },
        onHorizontalDragEnd: (_) {
          final transaction = widget.editorState.transaction;
          widget.tableNode.setColWidth(
            widget.colIdx,
            widget.tableNode.getColWidth(widget.colIdx),
            transaction: transaction,
            force: true,
          );
          transaction.afterSelection = transaction.beforeSelection;
          widget.editorState.apply(transaction);
          setState(() => _borderDragging = false);
          _updateActiveState(false);
        },
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          final colWidth = widget.tableNode.getColWidth(widget.colIdx);
          widget.tableNode.setColWidth(
            widget.colIdx,
            colWidth + details.delta.dx,
          );
        },
        child: Container(
          key: _borderKey,
          width: touchWidth,
          // The container itself is transparent to allow the visual line to be positioned inside
          color: Colors.transparent,
          child: Align(
            // Use the configured alignment for the visual line within the hitbox
            alignment: widget.hitboxAlignment,
            child: Container(
              width: widget.tableNode.config.borderWidth,
              color: _isActive ? widget.borderHoverColor : widget.borderColor,
            ),
          ),
        ),
      ),
    );
  }

  Container buildFixedBorder(BuildContext context) {
    return Container(
      width: widget.tableNode.config.borderWidth,
      color: widget.borderColor,
    );
  }
}
