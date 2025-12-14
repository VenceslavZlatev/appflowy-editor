import 'dart:math';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:appflowy_editor/src/editor/util/platform_extension.dart';
import 'package:flutter/material.dart';

/// A draggable area that adds/removes table rows or columns by dragging
class TableDragAddArea extends StatefulWidget {
  const TableDragAddArea({
    super.key,
    required this.tableNode,
    required this.editorState,
    required this.direction,
    required this.width,
    this.height,
    required this.borderColor,
    required this.borderHoverColor,
    this.scrollController,
  });

  final Node tableNode;
  final EditorState editorState;
  final TableDirection direction;
  final double width;
  final double? height;
  final Color borderColor;
  final Color borderHoverColor;
  final ScrollController? scrollController;

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

  // Minimum height that an empty row is likely to render at (ignoring the smaller default attribute)
  // This prevents the drag handle from overshooting (moving faster than mouse)
  static const double _kMinInteractiveRowHeight = 30.0;

  // Overlay to enforce resize cursor during drag even if mouse leaves the handle
  OverlayEntry? _cursorOverrideOverlay;

  // Overlay for tooltip (especially needed on mobile to avoid clipping)
  OverlayEntry? _tooltipOverlay;

  // GlobalKey to get the position of the drag area
  final GlobalKey _dragAreaKey = GlobalKey();

  @override
  void dispose() {
    _removeCursorOverride();
    _removeTooltipOverlay();
    // Clean up interceptor if it exists
    if (_selectionInterceptor != null) {
      widget.editorState.selectionService.unregisterGestureInterceptor(_selectionInterceptor!.key);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRowDirection = widget.direction == TableDirection.row;
    final shouldShowActiveState = PlatformExtension.isMobile || _isHovering || _isDragging;

    // The handle is always anchored to the table edge (no visual translation).
    // It moves only when the table structure changes (rows/cols added/removed).

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTapAdd,
      onVerticalDragStart: isRowDirection ? _onDragStart : null,
      onVerticalDragUpdate: isRowDirection ? _onDragUpdate : null,
      onVerticalDragEnd: isRowDirection ? _onDragEnd : null,
      onVerticalDragCancel: isRowDirection ? () => _onDragEnd(DragEndDetails()) : null,
      onHorizontalDragStart: isRowDirection ? null : _onDragStart,
      onHorizontalDragUpdate: isRowDirection ? null : _onDragUpdate,
      onHorizontalDragEnd: isRowDirection ? null : _onDragEnd,
      onHorizontalDragCancel: isRowDirection ? null : () => _onDragEnd(DragEndDetails()),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        cursor: widget.direction == TableDirection.col ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
        child: Stack(
          key: _dragAreaKey,
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            shouldShowActiveState
                ? Container(
                    alignment: widget.direction == TableDirection.col ? Alignment.centerLeft : Alignment.center,
                    width: widget.width,
                    height: widget.height,
                    margin: EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color:
                          shouldShowActiveState ? widget.borderHoverColor.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                      border: Border.all(
                        color:
                            shouldShowActiveState ? widget.borderHoverColor.withValues(alpha: 0.5) : Colors.transparent,
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
            // Only show tooltip in Stack for desktop (not mobile) to avoid clipping issues
            if (_isDragging && !PlatformExtension.isMobile)
              Positioned(
                // For row direction (bottom handle): position below the handle
                // For col direction (vertical handle): position at a fixed offset from center
                top: widget.direction == TableDirection.row ? (widget.height ?? 20) + 4 : null,
                bottom: widget.direction == TableDirection.col ? -24 : null,
                left: widget.direction == TableDirection.col ? -5 : null,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${widget.tableNode.attributes[TableBlockKeys.colsLen]}x${widget.tableNode.attributes[TableBlockKeys.rowsLen]}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _handleTapAdd() {
    if (_isDragging) return;
    _addSingleEntry();
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

    // Enforce resize cursor globally during drag
    _addCursorOverride();

    // Show tooltip in overlay on mobile
    if (PlatformExtension.isMobile) {
      _addTooltipOverlay();
    }

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

    // Calculate how many rows/columns to add based on drag distance.
    final tableNodeWrapper = TableNode(node: widget.tableNode);
    final config = tableNodeWrapper.config;

    // We use the default height/width + border width as the threshold.
    // Use a realistic minimum height for rows to match rendered content and prevent overshoot.
    final threshold = widget.direction == TableDirection.col
        ? config.colDefaultWidth + config.borderWidth
        : max(config.rowDefaultHeight, _kMinInteractiveRowHeight) + config.borderWidth;

    // Use ceil() instead of floor() to trigger addition as soon as the drag "starts to leave"
    // the current handle position (> 0), providing immediate feedback.
    // For deletion (negative delta), ceil() effectively waits for a full row traversal, preventing accidental deletion.
    final newCount = (delta / threshold).ceil().clamp(-_initialCount + 1, 10);

    if (newCount != _tempAddedCount) {
      _updateTableSize(newCount);
    }

    // Update visual drag offset and trigger rebuild
    setState(() {
      _tempAddedCount = newCount;
    });

    // Update tooltip position on mobile
    if (PlatformExtension.isMobile && _tooltipOverlay != null) {
      _updateTooltipOverlay();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _removeCursorOverride();
    _removeTooltipOverlay();

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

  void _addCursorOverride() {
    if (_cursorOverrideOverlay != null) return;

    final cursor =
        widget.direction == TableDirection.col ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow;

    _cursorOverrideOverlay = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: MouseRegion(
          cursor: cursor,
          child: Container(
            color: Colors.transparent,
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_cursorOverrideOverlay!);
  }

  void _removeCursorOverride() {
    if (_cursorOverrideOverlay != null) {
      _cursorOverrideOverlay!.remove();
      _cursorOverrideOverlay = null;
    }
  }

  void _addTooltipOverlay() {
    if (_tooltipOverlay != null) return;

    _tooltipOverlay = OverlayEntry(
      builder: (context) => _buildTooltipOverlay(),
    );

    Overlay.of(context).insert(_tooltipOverlay!);
  }

  void _updateTooltipOverlay() {
    if (_tooltipOverlay != null) {
      _tooltipOverlay!.markNeedsBuild();
    }
  }

  void _removeTooltipOverlay() {
    if (_tooltipOverlay != null) {
      _tooltipOverlay!.remove();
      _tooltipOverlay = null;
    }
  }

  Widget _buildTooltipOverlay() {
    final renderBox = _dragAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return const SizedBox.shrink();
    }

    final globalPosition = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final tooltipText =
        '${widget.tableNode.attributes[TableBlockKeys.colsLen]}x${widget.tableNode.attributes[TableBlockKeys.rowsLen]}';
    final tooltipWidget = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          tooltipText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );

    // Calculate tooltip position
    if (widget.direction == TableDirection.row) {
      // For row direction (bottom handle): position below the handle, centered horizontally
      return Positioned(
        left: globalPosition.dx + size.width / 2,
        top: globalPosition.dy + (widget.height ?? 20) + 4,
        child: Transform.translate(
          offset: const Offset(-30, 0), // Approximate half-width offset to center (adjust if needed)
          child: tooltipWidget,
        ),
      );
    } else {
      // For col direction (vertical handle): position at a fixed offset from center
      return Positioned(
        left: globalPosition.dx - 5,
        top: globalPosition.dy + size.height / 2 - 24,
        child: tooltipWidget,
      );
    }
  }

  void _addSingleEntry() {
    final currentCount = widget.direction == TableDirection.col
        ? widget.tableNode.attributes[TableBlockKeys.colsLen] as int
        : widget.tableNode.attributes[TableBlockKeys.rowsLen] as int;

    TableActions.add(
      widget.tableNode,
      currentCount,
      widget.editorState,
      widget.direction,
    );

    if (widget.direction == TableDirection.col && widget.scrollController != null) {
      _scrollToNewColumn();
    }
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

      // Auto-scroll to the right when adding columns
      if (widget.direction == TableDirection.col && widget.scrollController != null) {
        _scrollToNewColumn();
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

  /// Scroll to keep the newly added column in view
  void _scrollToNewColumn() {
    if (widget.scrollController == null) return;

    // Use addPostFrameCallback to ensure the table has been rebuilt
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController!.hasClients) return;

      final scrollPosition = widget.scrollController!.position;
      final viewportWidth = scrollPosition.viewportDimension;
      final maxScrollExtent = scrollPosition.maxScrollExtent;

      // Only scroll if there's scroll space available
      if (maxScrollExtent > 0) {
        // Calculate how much of the table is currently visible from the right
        final currentRightPosition = scrollPosition.pixels + viewportWidth;
        final tableWidth = _calculateTableWidth();

        // If the right edge of the table is not visible, scroll to show it
        if (currentRightPosition < tableWidth) {
          widget.scrollController!.animateTo(
            maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  /// Calculate the current table width
  double _calculateTableWidth() {
    // Use the table node's built-in width calculation
    final tableNode = TableNode(node: widget.tableNode);
    return tableNode.tableWidth;
  }
}
