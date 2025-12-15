import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';

class TableActions {
  const TableActions._();

  static void add(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _addCol(node, position, editorState);
    } else if (dir == TableDirection.row) {
      _addRow(node, position, editorState);
    }
  }

  static void delete(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _deleteCol(node, position, editorState);
    } else if (dir == TableDirection.row) {
      _deleteRow(node, position, editorState);
    }
  }

  static void duplicate(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _duplicateCol(node, position, editorState);
    } else if (dir == TableDirection.row) {
      _duplicateRow(node, position, editorState);
    }
  }

  static void clear(
    Node node,
    int position,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _clearCol(node, position, editorState);
    } else if (dir == TableDirection.row) {
      _clearRow(node, position, editorState);
    }
  }

  static void setBgColor(
    Node node,
    int position,
    EditorState editorState,
    String? color,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _setColBgColor(node, position, editorState, color);
    } else if (dir == TableDirection.row) {
      _setRowBgColor(node, position, editorState, color);
    }
  }

  static void move(
    Node node,
    int fromPosition,
    int toPosition,
    EditorState editorState,
    TableDirection dir,
  ) {
    if (dir == TableDirection.col) {
      _moveCol(node, fromPosition, toPosition, editorState);
    } else if (dir == TableDirection.row) {
      _moveRow(node, fromPosition, toPosition, editorState);
    }
  }
}

void _addCol(Node tableNode, int position, EditorState editorState) {
  assert(position >= 0);

  final transaction = editorState.transaction;

  List<Node> cellNodes = [];
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (position != colsLen) {
    for (var i = colsLen - 1; i >= position; i--) {
      for (var j = 0; j < rowsLen; j++) {
        final node = getCellNode(tableNode, i, j)!;
        transaction.updateNode(node, {TableCellBlockKeys.colPosition: i + 1});
      }
    }
  }

  for (var i = 0; i < rowsLen; i++) {
    final node = Node(
      type: TableCellBlockKeys.type,
      attributes: {
        TableCellBlockKeys.colPosition: position,
        TableCellBlockKeys.rowPosition: i,
      },
    );
    node.insert(paragraphNode());
    final firstCellInRow = getCellNode(tableNode, 0, i);
    if (firstCellInRow?.attributes.containsKey(TableCellBlockKeys.rowBackgroundColor) ?? false) {
      node.updateAttributes({
        TableCellBlockKeys.rowBackgroundColor: firstCellInRow!.attributes[TableCellBlockKeys.rowBackgroundColor],
      });
    }

    cellNodes.add(newCellNode(tableNode, node));
  }

  late Path insertPath;
  if (position == 0) {
    insertPath = getCellNode(tableNode, 0, 0)!.path;
  } else {
    insertPath = getCellNode(tableNode, position - 1, rowsLen - 1)!.path.next;
  }
  // TODO(zoli): this calls notifyListener rowsLen+1 times. isn't there a better
  // way?
  transaction.insertNodes(insertPath, cellNodes);
  transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen + 1});

  editorState.apply(transaction, withUpdateSelection: false);
}

/// Helper function to get the current cell position from selection
_SelectionInfo? _getCurrentCellSelection(Node tableNode, EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return null;
  }

  // Get the node at the selection path
  final node = editorState.getNodeAtPath(selection.start.path);
  if (node == null) {
    return null;
  }

  // Find the table cell node (parent of the selected node)
  Node? cellNode = node;
  while (cellNode != null && cellNode.type != TableCellBlockKeys.type) {
    cellNode = cellNode.parent;
  }

  // Verify the cell belongs to this table
  if (cellNode == null || cellNode.type != TableCellBlockKeys.type || cellNode.parent != tableNode) {
    return null;
  }

  final rowPosition = cellNode.attributes[TableCellBlockKeys.rowPosition] as int?;
  final colPosition = cellNode.attributes[TableCellBlockKeys.colPosition] as int?;

  if (rowPosition == null || colPosition == null) {
    return null;
  }

  return _SelectionInfo(
    row: rowPosition,
    col: colPosition,
    offset: selection.start.offset,
  );
}

class _SelectionInfo {
  final int row;
  final int col;
  final int offset;

  _SelectionInfo({
    required this.row,
    required this.col,
    required this.offset,
  });
}

void _addRow(Node tableNode, int position, EditorState editorState) async {
  assert(position >= 0);

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  final int colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  // Capture current selection before the operation
  final originalSelection = _getCurrentCellSelection(tableNode, editorState);

  // Create a single transaction for all operations
  final transaction = editorState.transaction;
  var error = false;

  // Update existing row positions if needed
  if (position != rowsLen) {
    for (var i = 0; i < colsLen; i++) {
      for (var j = rowsLen - 1; j >= position; j--) {
        final cellNode = getCellNode(tableNode, i, j);
        if (cellNode == null) {
          error = true;
          break;
        }
        transaction.updateNode(
          cellNode,
          {
            TableCellBlockKeys.rowPosition: j + 1,
          },
        );
      }
      if (error) break;
    }
  }

  if (error) {
    AppFlowyEditorLog.editor.debug('unable to insert row - cell not found');
    return;
  }

  // Generate and insert new table cell nodes
  for (var i = 0; i < colsLen; i++) {
    final firstCellInCol = getCellNode(tableNode, i, 0);
    final colBgColor = firstCellInCol?.attributes[TableCellBlockKeys.colBackgroundColor];
    final containsColBgColor = colBgColor != null;

    final node = Node(
      type: TableCellBlockKeys.type,
      attributes: {
        TableCellBlockKeys.colPosition: i,
        TableCellBlockKeys.rowPosition: position,
        if (containsColBgColor) TableCellBlockKeys.colBackgroundColor: colBgColor,
      },
      children: [paragraphNode()],
    );

    late Path insertPath;
    if (position == 0) {
      final firstCellInCol = getCellNode(tableNode, i, 0);
      if (firstCellInCol == null) {
        error = true;
        break;
      }
      insertPath = firstCellInCol.path;
    } else {
      final cellInPrevRow = getCellNode(tableNode, i, position - 1);
      if (cellInPrevRow == null) {
        error = true;
        break;
      }
      insertPath = cellInPrevRow.path.next;
    }

    // Adjust path for previous insertions in this loop
    // Each previous column insertion added 1 node to the children list
    // so we must shift the target index by i.
    // The path is [..., index]
    final adjustedIndex = insertPath.last + i;
    final adjustedPath = List<int>.from(insertPath)..last = adjustedIndex;

    transaction.insertNode(adjustedPath, node);
  }

  if (error) {
    AppFlowyEditorLog.editor.debug('unable to insert row');
    return;
  }

  // Update the row length
  transaction.updateNode(tableNode, {
    TableBlockKeys.rowsLen: rowsLen + 1,
  });

  // Apply all operations in a single transaction
  await editorState.apply(transaction, withUpdateSelection: false);

  // Restore selection after transaction is applied
  // This is more reliable than trying to calculate paths beforehand
  if (originalSelection != null) {
    final rowDelta = position <= originalSelection.row ? 1 : 0;
    final newRow = originalSelection.row + rowDelta;
    final colsLen = tableNode.attributes[TableBlockKeys.colsLen] as int;
    final rowsLen = tableNode.attributes[TableBlockKeys.rowsLen] as int;

    // Find the cell at the new position after transaction
    if (newRow >= 0 && newRow < rowsLen && originalSelection.col >= 0 && originalSelection.col < colsLen) {
      final newCell = getCellNode(tableNode, originalSelection.col, newRow);
      if (newCell != null && newCell.children.isNotEmpty) {
        final paragraph = newCell.children.first;
        final maxOffset = paragraph.delta?.length ?? 0;
        final newOffset = originalSelection.offset.clamp(0, maxOffset);
        final newSelection = Selection.collapsed(
          Position(path: paragraph.path, offset: newOffset),
        );
        editorState.updateSelectionWithReason(
          newSelection,
          reason: SelectionUpdateReason.uiEvent,
        );
      }
    }
  }
}

void _deleteCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (colsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    transaction.deleteNode(tableNode);
    tableNode.dispose();
  } else {
    List<Node> nodes = [];
    for (var i = 0; i < rowsLen; i++) {
      nodes.add(getCellNode(tableNode, col, i)!);
    }
    transaction.deleteNodes(nodes);

    _updateCellPositions(tableNode, transaction, col + 1, 0, -1, 0);

    transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen - 1});
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _deleteRow(Node tableNode, int row, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  // Capture current selection before the operation
  final originalSelection = _getCurrentCellSelection(tableNode, editorState);

  if (rowsLen == 1) {
    if (editorState.document.root.children.length == 1) {
      final emptyParagraph = paragraphNode();
      transaction.insertNode(tableNode.path, emptyParagraph);
    }
    transaction.deleteNode(tableNode);
    tableNode.dispose();
  } else {
    List<Node> nodes = [];
    for (var i = 0; i < colsLen; i++) {
      nodes.add(getCellNode(tableNode, i, row)!);
    }
    transaction.deleteNodes(nodes);

    _updateCellPositions(tableNode, transaction, 0, row + 1, 0, -1);

    transaction.updateNode(tableNode, {TableBlockKeys.rowsLen: rowsLen - 1});
  }

  editorState.apply(transaction, withUpdateSelection: false);

  // Restore selection after transaction is applied
  if (originalSelection != null) {
    int rowDelta;
    if (row < originalSelection.row) {
      // Row deleted above current row, shift up by 1
      rowDelta = -1;
    } else if (row == originalSelection.row) {
      // Current row was deleted, move to the row above (or stay at 0 if it was the first row)
      rowDelta = originalSelection.row > 0 ? -1 : 0;
    } else {
      // Row deleted below current row, no change needed
      rowDelta = 0;
    }

    final newRow = originalSelection.row + rowDelta;
    final colsLen = tableNode.attributes[TableBlockKeys.colsLen] as int;
    final rowsLen = tableNode.attributes[TableBlockKeys.rowsLen] as int;

    // Find the cell at the new position after transaction
    if (newRow >= 0 && newRow < rowsLen && originalSelection.col >= 0 && originalSelection.col < colsLen) {
      final newCell = getCellNode(tableNode, originalSelection.col, newRow);
      if (newCell != null && newCell.children.isNotEmpty) {
        final paragraph = newCell.children.first;
        final maxOffset = paragraph.delta?.length ?? 0;
        final newOffset = originalSelection.offset.clamp(0, maxOffset);
        final newSelection = Selection.collapsed(
          Position(path: paragraph.path, offset: newOffset),
        );
        editorState.updateSelectionWithReason(
          newSelection,
          reason: SelectionUpdateReason.uiEvent,
        );
      }
    }
  }
}

void _duplicateCol(Node tableNode, int col, EditorState editorState) {
  final transaction = editorState.transaction;

  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  List<Node> nodes = [];
  for (var i = 0; i < rowsLen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    nodes.add(
      node.copyWith(
        attributes: {
          ...node.attributes,
          TableCellBlockKeys.colPosition: col + 1,
          TableCellBlockKeys.rowPosition: i,
        },
      ),
    );
  }
  transaction.insertNodes(
    getCellNode(tableNode, col, rowsLen - 1)!.path.next,
    nodes,
  );

  _updateCellPositions(tableNode, transaction, col + 1, 0, 1, 0);

  transaction.updateNode(tableNode, {TableBlockKeys.colsLen: colsLen + 1});

  editorState.apply(transaction, withUpdateSelection: false);
}

void _duplicateRow(Node tableNode, int row, EditorState editorState) async {
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  // Create a single transaction for all operations
  final transaction = editorState.transaction;

  // Update cell positions for rows after the insertion point
  final int rowsLenCurrent = tableNode.attributes[TableBlockKeys.rowsLen];
  for (var i = 0; i < colsLen; i++) {
    for (var j = rowsLenCurrent - 1; j >= row + 1; j--) {
      final cellNode = getCellNode(tableNode, i, j);
      if (cellNode != null) {
        transaction.updateNode(cellNode, {
          TableCellBlockKeys.colPosition: i,
          TableCellBlockKeys.rowPosition: j + 1,
        });
      }
    }
  }

  // Insert duplicated cells
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    final insertPath = node.path.next;

    // Adjust path for previous insertions in this loop
    final adjustedIndex = insertPath.last + i;
    final adjustedPath = List<int>.from(insertPath)..last = adjustedIndex;

    transaction.insertNode(
      adjustedPath,
      node.copyWith(
        attributes: {
          ...node.attributes,
          TableCellBlockKeys.rowPosition: row + 1,
          TableCellBlockKeys.colPosition: i,
        },
      ),
    );
  }

  // Update row length
  transaction.updateNode(tableNode, {TableBlockKeys.rowsLen: rowsLen + 1});

  // Apply all operations in a single transaction
  await editorState.apply(transaction, withUpdateSelection: false);
}

void _setColBgColor(
  Node tableNode,
  int col,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final rowslen = tableNode.attributes[TableBlockKeys.rowsLen];
  for (var i = 0; i < rowslen; i++) {
    final node = getCellNode(tableNode, col, i)!;
    transaction.updateNode(
      node,
      {TableCellBlockKeys.colBackgroundColor: color},
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _setRowBgColor(
  Node tableNode,
  int row,
  EditorState editorState,
  String? color,
) {
  final transaction = editorState.transaction;

  final colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;
    transaction.updateNode(
      node,
      {TableCellBlockKeys.rowBackgroundColor: color},
    );
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearCol(
  Node tableNode,
  int col,
  EditorState editorState,
) {
  final transaction = editorState.transaction;

  final rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  for (var i = 0; i < rowsLen; i++) {
    final node = getCellNode(tableNode, col, i)!;

    // Only insert if the cell has children
    if (node.children.isNotEmpty) {
      transaction.insertNode(
        node.children.first.path,
        paragraphNode(text: ''),
      );
    }
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _clearRow(
  Node tableNode,
  int row,
  EditorState editorState,
) {
  final transaction = editorState.transaction;

  final colsLen = tableNode.attributes[TableBlockKeys.colsLen];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, row)!;

    // Only insert if the cell has children
    if (node.children.isNotEmpty) {
      transaction.insertNode(
        node.children.first.path,
        paragraphNode(text: ''),
      );
    }
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

dynamic newCellNode(Node tableNode, n) {
  final row = n.attributes[TableCellBlockKeys.rowPosition] as int;
  final col = n.attributes[TableCellBlockKeys.colPosition] as int;
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];
  final int colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (!n.attributes.containsKey(TableCellBlockKeys.height)) {
    double nodeHeight = double.tryParse(
      tableNode.attributes[TableBlockKeys.rowDefaultHeight].toString(),
    )!;
    if (row < rowsLen) {
      final cellNode = getCellNode(tableNode, 0, row);
      if (cellNode != null) {
        nodeHeight = double.tryParse(
              cellNode.attributes[TableCellBlockKeys.height].toString(),
            ) ??
            nodeHeight;
      }
    }
    n.updateAttributes({TableCellBlockKeys.height: nodeHeight});
  }

  if (!n.attributes.containsKey(TableCellBlockKeys.width)) {
    double nodeWidth = double.tryParse(
      tableNode.attributes[TableBlockKeys.colDefaultWidth].toString(),
    )!;
    if (col < colsLen) {
      final cellNode = getCellNode(tableNode, col, 0);
      if (cellNode != null) {
        nodeWidth = double.tryParse(
              cellNode.attributes[TableCellBlockKeys.width].toString(),
            ) ??
            nodeWidth;
      }
    }
    n.updateAttributes({TableCellBlockKeys.width: nodeWidth});
  }

  return n;
}

void _updateCellPositions(
  Node tableNode,
  Transaction transaction,
  int fromCol,
  int fromRow,
  int addToCol,
  int addToRow,
) {
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen],
      colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  if (addToCol > 0) {
    // Shifting right: iterate backwards
    for (var i = colsLen - 1; i >= fromCol; i--) {
      for (var j = fromRow; j < rowsLen; j++) {
        final cellNode = getCellNode(tableNode, i, j);
        if (cellNode != null) {
          transaction.updateNode(cellNode, {
            TableCellBlockKeys.colPosition: i + addToCol,
            TableCellBlockKeys.rowPosition: j + addToRow,
          });
        }
      }
    }
  } else if (addToRow > 0) {
    // Shifting down: iterate backwards
    for (var i = fromCol; i < colsLen; i++) {
      for (var j = rowsLen - 1; j >= fromRow; j--) {
        final cellNode = getCellNode(tableNode, i, j);
        if (cellNode != null) {
          transaction.updateNode(cellNode, {
            TableCellBlockKeys.colPosition: i + addToCol,
            TableCellBlockKeys.rowPosition: j + addToRow,
          });
        }
      }
    }
  } else {
    // Shifting left or up (or no shift): iterate forwards
    for (var i = fromCol; i < colsLen; i++) {
      for (var j = fromRow; j < rowsLen; j++) {
        final cellNode = getCellNode(tableNode, i, j);
        if (cellNode != null) {
          transaction.updateNode(cellNode, {
            TableCellBlockKeys.colPosition: i + addToCol,
            TableCellBlockKeys.rowPosition: j + addToRow,
          });
        }
      }
    }
  }
}

void _moveCol(Node tableNode, int fromCol, int toCol, EditorState editorState) {
  if (fromCol == toCol) return;

  final transaction = editorState.transaction;
  final int rowsLen = tableNode.attributes[TableBlockKeys.rowsLen];

  // Store the cells we want to move
  List<Map<String, dynamic>> movingCells = [];
  for (var i = 0; i < rowsLen; i++) {
    final node = getCellNode(tableNode, fromCol, i)!;
    movingCells.add({
      'attributes': Map<String, dynamic>.from(node.attributes),
      'children': node.children.map((child) => child.copyWith()).toList(),
    });
  }

  if (fromCol < toCol) {
    // Moving right: shift cells left
    for (var col = fromCol; col < toCol; col++) {
      for (var row = 0; row < rowsLen; row++) {
        final nextCell = getCellNode(tableNode, col + 1, row)!;
        final currentCell = getCellNode(tableNode, col, row)!;

        // Copy attributes from next cell to current cell
        transaction.updateNode(currentCell, {
          ...Map<String, dynamic>.from(nextCell.attributes),
          TableCellBlockKeys.colPosition: col,
          TableCellBlockKeys.rowPosition: row,
        });

        // Replace children
        for (var child in currentCell.children) {
          transaction.deleteNode(child);
        }
        for (var i = 0; i < nextCell.children.length; i++) {
          transaction.insertNode(
            currentCell.path.child(i),
            nextCell.children[i].copyWith(),
          );
        }
      }
    }
  } else {
    // Moving left: shift cells right
    for (var col = fromCol; col > toCol; col--) {
      for (var row = 0; row < rowsLen; row++) {
        final prevCell = getCellNode(tableNode, col - 1, row)!;
        final currentCell = getCellNode(tableNode, col, row)!;

        // Copy attributes from previous cell to current cell
        transaction.updateNode(currentCell, {
          ...Map<String, dynamic>.from(prevCell.attributes),
          TableCellBlockKeys.colPosition: col,
          TableCellBlockKeys.rowPosition: row,
        });

        // Replace children
        for (var child in currentCell.children) {
          transaction.deleteNode(child);
        }
        for (var i = 0; i < prevCell.children.length; i++) {
          transaction.insertNode(
            currentCell.path.child(i),
            prevCell.children[i].copyWith(),
          );
        }
      }
    }
  }

  // Place the moved cells at the target position
  for (var row = 0; row < rowsLen; row++) {
    final targetCell = getCellNode(tableNode, toCol, row)!;
    final cellData = movingCells[row];

    transaction.updateNode(targetCell, {
      ...cellData['attributes'],
      TableCellBlockKeys.colPosition: toCol,
      TableCellBlockKeys.rowPosition: row,
    });

    // Replace children with the original ones
    for (var child in targetCell.children) {
      transaction.deleteNode(child);
    }
    final children = cellData['children'] as List<Node>;
    for (var i = 0; i < children.length; i++) {
      transaction.insertNode(targetCell.path.child(i), children[i]);
    }
  }

  editorState.apply(transaction, withUpdateSelection: false);
}

void _moveRow(Node tableNode, int fromRow, int toRow, EditorState editorState) {
  if (fromRow == toRow) return;

  final transaction = editorState.transaction;
  final int colsLen = tableNode.attributes[TableBlockKeys.colsLen];

  // Store the cells we want to move
  List<Map<String, dynamic>> movingCells = [];
  for (var i = 0; i < colsLen; i++) {
    final node = getCellNode(tableNode, i, fromRow)!;
    movingCells.add({
      'attributes': Map<String, dynamic>.from(node.attributes),
      'children': node.children.map((child) => child.copyWith()).toList(),
    });
  }

  if (fromRow < toRow) {
    // Moving down: shift cells up
    for (var row = fromRow; row < toRow; row++) {
      for (var col = 0; col < colsLen; col++) {
        final nextCell = getCellNode(tableNode, col, row + 1)!;
        final currentCell = getCellNode(tableNode, col, row)!;

        // Copy attributes from next cell to current cell
        transaction.updateNode(currentCell, {
          ...Map<String, dynamic>.from(nextCell.attributes),
          TableCellBlockKeys.colPosition: col,
          TableCellBlockKeys.rowPosition: row,
        });

        // Replace children
        for (var child in currentCell.children) {
          transaction.deleteNode(child);
        }
        for (var i = 0; i < nextCell.children.length; i++) {
          transaction.insertNode(
            currentCell.path.child(i),
            nextCell.children[i].copyWith(),
          );
        }
      }
    }
  } else {
    // Moving up: shift cells down
    for (var row = fromRow; row > toRow; row--) {
      for (var col = 0; col < colsLen; col++) {
        final prevCell = getCellNode(tableNode, col, row - 1)!;
        final currentCell = getCellNode(tableNode, col, row)!;

        // Copy attributes from previous cell to current cell
        transaction.updateNode(currentCell, {
          ...Map<String, dynamic>.from(prevCell.attributes),
          TableCellBlockKeys.colPosition: col,
          TableCellBlockKeys.rowPosition: row,
        });

        // Replace children
        for (var child in currentCell.children) {
          transaction.deleteNode(child);
        }
        for (var i = 0; i < prevCell.children.length; i++) {
          transaction.insertNode(
            currentCell.path.child(i),
            prevCell.children[i].copyWith(),
          );
        }
      }
    }
  }

  // Place the moved cells at the target position
  for (var col = 0; col < colsLen; col++) {
    final targetCell = getCellNode(tableNode, col, toRow)!;
    final cellData = movingCells[col];

    transaction.updateNode(targetCell, {
      ...cellData['attributes'],
      TableCellBlockKeys.colPosition: col,
      TableCellBlockKeys.rowPosition: toRow,
    });

    // Replace children with the original ones
    for (var child in targetCell.children) {
      transaction.deleteNode(child);
    }
    final children = cellData['children'] as List<Node>;
    for (var i = 0; i < children.length; i++) {
      transaction.insertNode(targetCell.path.child(i), children[i]);
    }
  }

  editorState.apply(transaction, withUpdateSelection: false);
}
