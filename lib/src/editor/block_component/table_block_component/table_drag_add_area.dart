import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/material.dart';

/// A draggable area that adds/removes table rows or columns by dragging
class TableDragAddArea extends StatefulWidget {
  const TableDragAddArea({
    super.key,
    required this.tableNode,
    required this.editorState,
    required this.direction,
    required this.width,
    required this.height,
    required this.borderColor,
    required this.borderHoverColor,
  });

  final Node tableNode;
  final EditorState editorState;
  final TableDirection direction;
  final double width;
  final double height;
  final Color borderColor;
  final Color borderHoverColor;

  @override
  State<TableDragAddArea> createState() => _TableDragAddAreaState();
}

class _TableDragAddAreaState extends State<TableDragAddArea> {
  bool _isHovering = false;
  bool _isDragging = false;
  int _tempAddedCount = 0;
  late int _initialCount;
  Offset? _dragStartPosition;
  SelectionGestureInterceptor? _selectionInterceptor;

  @override
  void dispose() {
    // Clean up interceptor if it exists
    if (_selectionInterceptor != null) {
      widget.editorState.selectionService.unregisterGestureInterceptor(_selectionInterceptor!.key);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        // Prevent text selection by consuming the event
        _onDragStart(
          DragStartDetails(
            globalPosition: event.position,
            localPosition: event.localPosition,
          ),
        );
      },
      onPointerMove: (event) {
        if (_isDragging) {
          _onDragUpdate(
            DragUpdateDetails(
              globalPosition: event.position,
              localPosition: event.localPosition,
              delta: event.delta,
            ),
          );
        }
      },
      onPointerUp: (event) {
        if (_isDragging) {
          _onDragEnd(DragEndDetails());
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        cursor: widget.direction == TableDirection.col ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
        child: _isHovering || _isDragging
            ? Container(
                alignment: widget.direction == TableDirection.col ? Alignment.centerLeft : Alignment.center,
                width: widget.width,
                height: widget.height,
                decoration: BoxDecoration(
                  color:
                      _isHovering || _isDragging ? widget.borderHoverColor.withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                  border: Border.all(
                    color: _isHovering || _isDragging
                        ? widget.borderHoverColor.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: widget.borderHoverColor,
                  ),
                ),
              )
            : SizedBox(width: widget.width, height: widget.height),
      ),
    );
  }

  void _onDragStart(DragStartDetails details) {
    // Register selection interceptor to prevent text selection during drag
    _selectionInterceptor = SelectionGestureInterceptor(
      key: 'table_drag_area_${widget.direction.name}_${DateTime.now().millisecondsSinceEpoch}',
      canTap: (details) => false, // Prevent tap selection
      canPanStart: (details) => false, // Prevent pan selection
      canPanUpdate: (details) => false, // Prevent pan update selection
      canDoubleTap: (details) => false, // Prevent double tap selection
    );
    widget.editorState.selectionService.registerGestureInterceptor(_selectionInterceptor!);

    setState(() {
      _isDragging = true;
      _dragStartPosition = details.globalPosition;
      _initialCount = widget.direction == TableDirection.col
          ? widget.tableNode.attributes[TableBlockKeys.colsLen] as int
          : widget.tableNode.attributes[TableBlockKeys.rowsLen] as int;
      _tempAddedCount = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_dragStartPosition == null) return;

    final delta = widget.direction == TableDirection.col
        ? details.globalPosition.dx - _dragStartPosition!.dx
        : details.globalPosition.dy - _dragStartPosition!.dy;

    // Calculate how many rows/columns to add based on drag distance
    final threshold = widget.direction == TableDirection.col ? 100.0 : 50.0;
    final newCount = (delta / threshold).floor().clamp(-_initialCount + 1, 10);

    if (newCount != _tempAddedCount) {
      _updateTableSize(newCount);
      setState(() => _tempAddedCount = newCount);
    }
  }

  void _onDragEnd(DragEndDetails details) {
    // Unregister selection interceptor to allow text selection again
    if (_selectionInterceptor != null) {
      widget.editorState.selectionService.unregisterGestureInterceptor(_selectionInterceptor!.key);
      _selectionInterceptor = null;
    }

    setState(() {
      _isDragging = false;
      _dragStartPosition = null;
      _tempAddedCount = 0;
    });
  }

  void _updateTableSize(int countDelta) {
    final currentCount = widget.direction == TableDirection.col
        ? widget.tableNode.attributes[TableBlockKeys.colsLen] as int
        : widget.tableNode.attributes[TableBlockKeys.rowsLen] as int;

    final newCount = _initialCount + countDelta;

    if (newCount > currentCount) {
      // Add rows/columns
      for (int i = currentCount; i < newCount; i++) {
        TableActions.add(
          widget.tableNode,
          i,
          widget.editorState,
          widget.direction,
        );
      }
    } else if (newCount < currentCount) {
      // Check if any cells in the rows/columns to be deleted contain data
      if (_hasDataInRange(newCount, currentCount)) {
        // Don't delete if there's data
        return;
      }

      // Remove rows/columns
      for (int i = currentCount - 1; i >= newCount; i--) {
        TableActions.delete(
          widget.tableNode,
          i,
          widget.editorState,
          widget.direction,
        );
      }
    }
  }

  /// Check if any cells in the given range contain data
  bool _hasDataInRange(int start, int end) {
    if (widget.direction == TableDirection.col) {
      // Check columns
      final rowsLen = widget.tableNode.attributes[TableBlockKeys.rowsLen] as int;
      for (int col = start; col < end; col++) {
        for (int row = 0; row < rowsLen; row++) {
          if (_cellHasData(col, row)) {
            return true;
          }
        }
      }
    } else {
      // Check rows
      final colsLen = widget.tableNode.attributes[TableBlockKeys.colsLen] as int;
      for (int row = start; row < end; row++) {
        for (int col = 0; col < colsLen; col++) {
          if (_cellHasData(col, row)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Check if a cell contains data
  bool _cellHasData(int col, int row) {
    final cell = getCellNode(widget.tableNode, col, row);
    if (cell == null) return false;

    // Check if any child node has non-empty content
    for (final child in cell.children) {
      if (child.delta != null && child.delta!.isNotEmpty) {
        // Check if delta has actual text content
        final text = child.delta!.toPlainText();
        if (text.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }
}
