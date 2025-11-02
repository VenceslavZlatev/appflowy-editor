import 'package:flutter/material.dart';

import 'package:appflowy_editor/appflowy_editor.dart';

/// Backspace key event.
///
/// - support
///   - desktop
///   - web
///   - mobile
///
final CommandShortcutEvent backspaceCommand = CommandShortcutEvent(
  key: 'backspace',
  getDescription: () => AppFlowyEditorL10n.current.cmdDeleteLeft,
  command: 'backspace, shift+backspace',
  handler: _backspaceCommandHandler,
);

CommandShortcutEventHandler _backspaceCommandHandler = (editorState) {
  final selection = editorState.selection;
  final selectionType = editorState.selectionType;

  if (selection == null) {
    return KeyEventResult.ignored;
  }

  final reason = editorState.selectionUpdateReason;

  if (selectionType == SelectionType.block) {
    return _backspaceInBlockSelection(editorState);
  } else if (selection.isCollapsed) {
    return _backspaceInCollapsedSelection(editorState);
  } else if (reason == SelectionUpdateReason.selectAll) {
    return _backspaceInSelectAll(editorState);
  } else {
    return _backspaceInNotCollapsedSelection(editorState);
  }
};

/// Handle backspace key event when selection is collapsed.
CommandShortcutEventHandler _backspaceInCollapsedSelection = (editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return KeyEventResult.ignored;
  }

  final position = selection.start;
  final node = editorState.getNodeAtPath(position.path);
  if (node == null) {
    return KeyEventResult.ignored;
  }

  final transaction = editorState.transaction;

  // delete the entire node if the delta is empty
  if (node.delta == null) {
    transaction.deleteNode(node);
    transaction.afterSelection = Selection.collapsed(
      Position(
        path: position.path,
        offset: 0,
      ),
    );
    editorState.apply(transaction);
    return KeyEventResult.handled;
  }

  // Why do we use prevRunPosition instead of the position start offset?
  // Because some character's length > 1, for example, emoji.
  final index = node.delta!.prevRunePosition(position.offset);

  if (index < 0) {
    // move this node to it's parent in below case.
    // the node's next is null
    // and the node's children is empty
    if (node.next == null && node.children.isEmpty && node.parent?.parent != null && node.parent?.delta != null) {
      final path = node.parent!.path.next;
      transaction
        ..deleteNode(node)
        ..insertNode(path, node)
        ..afterSelection = Selection.collapsed(
          Position(
            path: path,
            offset: 0,
          ),
        );
    } else {
      // If the deletion crosses columns and starts from the beginning position
      // skip the node deletion process
      // otherwise it will cause an error in table rendering.
      if (node.parent?.type == TableCellBlockKeys.type && position.offset == 0) {
        return KeyEventResult.handled;
      }

      // Handle deletion in column blocks: if paragraph is empty at position 0, delete the column
      final columnParent = node.findParent((element) => element.type == ColumnBlockKeys.type);
      final columnsParent = node.findParent((element) => element.type == ColumnsBlockKeys.type);
      if ((columnParent != null || columnsParent != null) &&
          position.offset == 0 &&
          node.delta != null &&
          node.delta!.isEmpty) {
        // Delete the column block if we're at position 0 with empty text
        if (columnParent != null) {
          final columnBlock = columnParent;
          final columnsBlock = columnsParent ?? columnBlock.parent;

          // If columns block has only one column, delete the entire columns block
          // Otherwise, just delete the column
          if (columnsBlock != null && columnsBlock.children.length == 1) {
            // Only one column left, delete the entire columns block
            final nextPath = columnsBlock.path.next;
            transaction.deleteNode(columnsBlock);
            // Insert an empty paragraph at the columns position
            transaction.insertNode(nextPath, paragraphNode());
            transaction.afterSelection = Selection.collapsed(Position(path: nextPath));
          } else {
            // Multiple columns, delete just this column
            final columnPath = columnBlock.path;
            final columnIndex = columnPath.last;
            // Find the first text node in the remaining columns to place cursor
            Node? nextTextNode;
            if (columnsBlock != null && columnsBlock.children.length > 1) {
              // Find first non-deleted column
              for (final col in columnsBlock.children) {
                if (col.path.last != columnIndex) {
                  final firstChild = col.children.firstOrNull;
                  if (firstChild?.delta != null) {
                    nextTextNode = firstChild;
                    break;
                  }
                }
              }
            }
            transaction.deleteNode(columnBlock);
            if (nextTextNode != null) {
              transaction.afterSelection = Selection.collapsed(
                Position(path: nextTextNode.path, offset: 0),
              );
            } else {
              // Fallback: place cursor after columns block or insert paragraph
              final columnsPath = columnsBlock?.path ?? columnBlock.path;
              transaction.afterSelection = Selection.collapsed(
                Position(path: columnsPath.next),
              );
            }
          }
          editorState.apply(transaction);
          return KeyEventResult.handled;
        }
      }

      Node? tableParent = node.findParent((element) => element.type == TableBlockKeys.type);
      Node? prevTableParent;
      final prev = node.previousNodeWhere((element) {
        prevTableParent = element.findParent((element) => element.type == TableBlockKeys.type);
        // break if only one is in a table or they're in different tables
        return tableParent != prevTableParent ||
            // merge with the previous node contains delta.
            element.delta != null;
      });
      // table nodes should be deleted using the table menu
      // in-table paragraphs should only be deleted inside the table
      if (prev != null && tableParent == prevTableParent) {
        assert(prev.delta != null);

        // Check if we're merging across columns
        final currentColumnParent = node.findParent((element) => element.type == ColumnBlockKeys.type);
        final prevColumnParent = prev.findParent((element) => element.type == ColumnBlockKeys.type);

        // Check if after deleting this node, the column will be empty
        // We need to check BEFORE applying the transaction
        final willColumnBeEmpty = currentColumnParent != null &&
            prevColumnParent != null &&
            currentColumnParent.id != prevColumnParent.id &&
            currentColumnParent.children.length == 1 &&
            currentColumnParent.children.first.id == node.id;

        transaction
          ..mergeText(prev, node)
          ..insertNodes(
            // insert children to previous node
            prev.path.next,
            node.children.toList(),
          )
          ..deleteNode(node);

        // If we merged across columns and the current column will be empty, delete it
        if (willColumnBeEmpty) {
          // Simply delete the column - the system will handle cleanup
          transaction.deleteNode(currentColumnParent);
        }

        transaction.afterSelection = Selection.collapsed(
          Position(
            path: prev.path,
            offset: prev.delta!.length,
          ),
        );
      } else {
        // do nothing if there is no previous node contains delta.
        return KeyEventResult.ignored;
      }
    }
  } else {
    // Although the selection may be collapsed,
    //  its length may not always be equal to 1 because some characters have a length greater than 1.
    transaction.deleteText(
      node,
      index,
      position.offset - index,
    );
  }

  editorState.apply(transaction);
  return KeyEventResult.handled;
};

/// Handle backspace key event when selection is not collapsed.
CommandShortcutEventHandler _backspaceInNotCollapsedSelection = (editorState) {
  final selection = editorState.selection;
  if (selection == null || selection.isCollapsed) {
    return KeyEventResult.ignored;
  }
  editorState.deleteSelection(selection);
  return KeyEventResult.handled;
};

CommandShortcutEventHandler _backspaceInBlockSelection = (editorState) {
  final selection = editorState.selection;
  if (selection == null || editorState.selectionType != SelectionType.block) {
    return KeyEventResult.ignored;
  }
  final transaction = editorState.transaction;
  transaction.deleteNodesAtPath(selection.start.path);
  editorState.apply(transaction).then((value) => editorState.selectionType = null);

  return KeyEventResult.handled;
};

CommandShortcutEventHandler _backspaceInSelectAll = (editorState) {
  final selection = editorState.selection;
  if (selection == null) {
    return KeyEventResult.ignored;
  }

  final transaction = editorState.transaction;
  final nodes = editorState.getNodesInSelection(selection);
  transaction.deleteNodes(nodes);

  // Insert a new paragraph node to avoid locking the editor
  transaction.insertNode(
    editorState.document.root.children.first.path,
    paragraphNode(),
  );
  transaction.afterSelection = Selection.collapsed(Position(path: [0]));

  editorState.apply(transaction);

  return KeyEventResult.handled;
};
