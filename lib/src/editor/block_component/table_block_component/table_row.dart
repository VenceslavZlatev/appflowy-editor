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
  int? _endRowIndex;
  int? _endColIndex;

  int? get focusedRowIndex => _focusedRowIndex;
  int? get focusedColIndex => _focusedColIndex;
  int? get endRowIndex => _endRowIndex;
  int? get endColIndex => _endColIndex;

  void setFocusedCell(int? rowIndex, int? colIndex) {
    if (_focusedRowIndex != rowIndex || _focusedColIndex != colIndex || _endRowIndex != null || _endColIndex != null) {
      _focusedRowIndex = rowIndex;
      _focusedColIndex = colIndex;
      _endRowIndex = null;
      _endColIndex = null;
      notifyListeners();
    }
  }

  void updateFocusEnd(int rowIndex, int colIndex) {
    if (_endRowIndex != rowIndex || _endColIndex != colIndex) {
      _endRowIndex = rowIndex;
      _endColIndex = colIndex;
      notifyListeners();
    }
  }

  bool suppressClear = false;

  void clear() {
    if (suppressClear) return;
    if (_focusedRowIndex != null || _focusedColIndex != null || _endRowIndex != null || _endColIndex != null) {
      _focusedRowIndex = null;
      _focusedColIndex = null;
      _endRowIndex = null;
      _endColIndex = null;
      notifyListeners();
    }
  }

  bool isRowFocused(int rowIndex) => _focusedRowIndex == rowIndex;
  bool isColFocused(int colIndex) => _focusedColIndex == colIndex;

  bool isCellFocused(int rowIndex, int colIndex) {
    if (_focusedRowIndex == null || _focusedColIndex == null) return false;
    final startRow = _focusedRowIndex!;
    final startCol = _focusedColIndex!;
    final endRow = _endRowIndex ?? startRow;
    final endCol = _endColIndex ?? startCol;

    final minRow = startRow < endRow ? startRow : endRow;
    final maxRow = startRow > endRow ? startRow : endRow;
    final minCol = startCol < endCol ? startCol : endCol;
    final maxCol = startCol > endCol ? startCol : endCol;

    return rowIndex >= minRow && rowIndex <= maxRow && colIndex >= minCol && colIndex <= maxCol;
  }

  int? get minRow {
    if (_focusedRowIndex == null) return null;
    final endRow = _endRowIndex ?? _focusedRowIndex!;
    return _focusedRowIndex! < endRow ? _focusedRowIndex : endRow;
  }

  int? get maxRow {
    if (_focusedRowIndex == null) return null;
    final endRow = _endRowIndex ?? _focusedRowIndex!;
    return _focusedRowIndex! > endRow ? _focusedRowIndex : endRow;
  }

  int? get minCol {
    if (_focusedColIndex == null) return null;
    final endCol = _endColIndex ?? _focusedColIndex!;
    return _focusedColIndex! < endCol ? _focusedColIndex : endCol;
  }

  int? get maxCol {
    if (_focusedColIndex == null) return null;
    final endCol = _endColIndex ?? _focusedColIndex!;
    return _focusedColIndex! > endCol ? _focusedColIndex : endCol;
  }
}

/// Wrapper widget for a table row cell that handles drag and drop
class TableRowDragTarget extends StatelessWidget {
  const TableRowDragTarget({
    super.key,
    required this.tableNode,
    required this.rowIdx,
    required this.colIdx,
    required this.editorState,
    required this.child,
    required this.dragNotifier,
    required this.cellFocusNotifier,
  });

  final Node tableNode;
  final int rowIdx;
  final int colIdx;
  final EditorState editorState;
  final Widget child;
  final TableRowDragNotifier dragNotifier;
  final TableCellFocusNotifier cellFocusNotifier;

  @override
  Widget build(BuildContext context) {
    return DragTarget<TableDragData>(
      onWillAcceptWithDetails: (details) {
        if (details.data.dir == TableDirection.cell) {
          return true;
        }
        return details.data.dir == TableDirection.row &&
            details.data.node == tableNode &&
            details.data.position != rowIdx;
      },
      onAcceptWithDetails: (details) {
        if (details.data.dir == TableDirection.cell) {
          // Commit selection? The notifier update during drag is enough for visual.
          // Maybe trigger something else? For now, visual is key.
          return;
        }
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
            final data = candidateData.first;
            if (data?.dir == TableDirection.cell) {
              cellFocusNotifier.updateFocusEnd(rowIdx, colIdx);
            } else {
              dragNotifier.setHoveredRow(rowIdx);
              // Track the dragged row position
              final draggedPosition = data?.position;
              dragNotifier.setDraggedRowPosition(draggedPosition);
            }
          } else if (dragNotifier.hoveredRow == rowIdx) {
            dragNotifier.clear();
          }
        });

        return child;
      },
    );
  }
}
