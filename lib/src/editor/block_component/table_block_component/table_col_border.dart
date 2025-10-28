import 'package:appflowy_editor/appflowy_editor.dart';
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
  });

  final bool resizable;
  final int colIdx;
  final TableNode tableNode;
  final EditorState editorState;

  final Color borderColor;
  final Color borderHoverColor;

  @override
  State<TableColBorder> createState() => _TableColBorderState();
}

class _TableColBorderState extends State<TableColBorder> {
  final GlobalKey _borderKey = GlobalKey();
  bool _borderHovering = false;
  bool _borderDragging = false;
  double? _cachedHeight;
  VoidCallback? _tableListener;

  Offset initialOffset = const Offset(0, 0);

  @override
  void initState() {
    super.initState();
    _setupTableListener();
  }

  @override
  void dispose() {
    if (_tableListener != null) {
      widget.tableNode.node.removeListener(_tableListener!);
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
              _cachedHeight = null; // Reset cache to force recalculation
            });
          }
        });
      }
    };
    widget.tableNode.node.addListener(_tableListener!);
  }

  @override
  Widget build(BuildContext context) {
    return widget.resizable ? buildResizableBorder(context) : buildFixedBorder(context);
  }

  double _getBorderHeight() {
    // Use cached height if available and not dragging
    if (_cachedHeight != null && !_borderDragging) {
      return _cachedHeight!;
    }

    // Calculate height from table node
    final height = widget.tableNode.colsHeight;
    _cachedHeight = height;
    return height;
  }

  @override
  void didUpdateWidget(TableColBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset cache and update listener when table node changes
    if (oldWidget.tableNode != widget.tableNode) {
      _cachedHeight = null;
      // Remove old listener and add new one
      if (_tableListener != null) {
        oldWidget.tableNode.node.removeListener(_tableListener!);
      }
      _setupTableListener();
    }
  }

  MouseRegion buildResizableBorder(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _borderHovering = true),
      onExit: (_) => setState(() => _borderHovering = false),
      child: GestureDetector(
        onHorizontalDragStart: (DragStartDetails details) {
          setState(() => _borderDragging = true);
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
          width: widget.tableNode.config.borderWidth,
          height: _getBorderHeight(),
          color: _borderHovering || _borderDragging ? widget.borderHoverColor : widget.borderColor,
        ),
      ),
    );
  }

  Container buildFixedBorder(BuildContext context) {
    return Container(
      width: widget.tableNode.config.borderWidth,
      height: _getBorderHeight(),
      color: widget.borderColor,
    );
  }
}
