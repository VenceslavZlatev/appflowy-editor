import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_drag_data.dart';
import 'package:flutter/material.dart';

/// Notifier to track which row is currently being hovered during drag
class TableRowDragNotifier extends ChangeNotifier {
  int? _hoveredRow;
  int? _draggedRowPosition;

  int? get hoveredRow => _hoveredRow;
  int? get draggedRowPosition => _draggedRowPosition;

  void setHoveredRow(int? row) {
    if (_hoveredRow != row) {
      _hoveredRow = row;
      notifyListeners();
    }
  }

  void setDraggedRowPosition(int? position) {
    if (_draggedRowPosition != position) {
      _draggedRowPosition = position;
      notifyListeners();
    }
  }

  void clear() {
    if (_hoveredRow != null || _draggedRowPosition != null) {
      _hoveredRow = null;
      _draggedRowPosition = null;
      notifyListeners();
    }
  }
}

/// Notifier to track which row action handler should be visible
class TableRowActionNotifier extends ChangeNotifier {
  int? _hoveredRowIndex;

  int? get hoveredRowIndex => _hoveredRowIndex;

  void setHoveredRow(int? rowIndex) {
    if (_hoveredRowIndex != rowIndex) {
      _hoveredRowIndex = rowIndex;
      notifyListeners();
    }
  }

  void clear() {
    if (_hoveredRowIndex != null) {
      _hoveredRowIndex = null;
      notifyListeners();
    }
  }
}

/// Notifier to track which cell is currently focused (for mobile)
class TableCellFocusNotifier extends ChangeNotifier {
  int? _focusedRowIndex;
  int? _focusedColIndex;

  int? get focusedRowIndex => _focusedRowIndex;
  int? get focusedColIndex => _focusedColIndex;

  void setFocusedCell(int? rowIndex, int? colIndex) {
    if (_focusedRowIndex != rowIndex || _focusedColIndex != colIndex) {
      _focusedRowIndex = rowIndex;
      _focusedColIndex = colIndex;
      notifyListeners();
    }
  }

  void clear() {
    if (_focusedRowIndex != null || _focusedColIndex != null) {
      _focusedRowIndex = null;
      _focusedColIndex = null;
      notifyListeners();
    }
  }

  bool isRowFocused(int rowIndex) => _focusedRowIndex == rowIndex;
  bool isColFocused(int colIndex) => _focusedColIndex == colIndex;
}

/// Wrapper widget for a table row cell that handles drag and drop
class TableRowDragTarget extends StatelessWidget {
  const TableRowDragTarget({
    super.key,
    required this.tableNode,
    required this.rowIdx,
    required this.editorState,
    required this.child,
    required this.dragNotifier,
  });

  final Node tableNode;
  final int rowIdx;
  final EditorState editorState;
  final Widget child;
  final TableRowDragNotifier dragNotifier;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TableDragData>(
      onWillAcceptWithDetails: (details) {
        return details.data.dir == TableDirection.row &&
            details.data.node == tableNode &&
            details.data.position != rowIdx;
      },
      onAcceptWithDetails: (details) {
        TableActions.move(
          tableNode,
          details.data.position,
          rowIdx,
          editorState,
          TableDirection.row,
        );
        dragNotifier.clear();
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;

        // Update the notifier when hover state changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (isHovering) {
            dragNotifier.setHoveredRow(rowIdx);
            // Track the dragged row position
            final draggedPosition = candidateData.isNotEmpty ? candidateData.first?.position : null;
            dragNotifier.setDraggedRowPosition(draggedPosition);
          } else if (dragNotifier.hoveredRow == rowIdx) {
            dragNotifier.clear();
          }
        });

        return child;
      },
    );
  }
}
