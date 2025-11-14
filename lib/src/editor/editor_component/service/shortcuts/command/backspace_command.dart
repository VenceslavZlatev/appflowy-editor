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

      // Prevent backspace from navigating out of image captions at position 0
      // Similar to how table cells work
      if (node.parent?.type == ImageBlockKeys.type && position.offset == 0) {
        return KeyEventResult.handled;
      }

      // Handle deletion in column blocks: if paragraph is empty at position 0
      final columnParent = node.findParent((element) => element.type == ColumnBlockKeys.type);
      final columnsParent = node.findParent((element) => element.type == ColumnsBlockKeys.type);
      if (columnParent != null && position.offset == 0 && node.delta != null && node.delta!.isEmpty) {
        // Check if this is the first child in the column
        final isFirstChildInColumn = columnParent.children.isNotEmpty && columnParent.children.first.id == node.id;

        if (isFirstChildInColumn) {
          // If this is the first child in the column, delete the entire column
          final columnBlock = columnParent;
          final columnsBlock = columnsParent ?? columnBlock.parent;

          // If columns block will have only one column after deletion, extract blocks from remaining column
          // Otherwise, just delete the column
          if (columnsBlock != null && columnsBlock.children.length == 2) {
            // After deletion, only one column will remain - extract all blocks from the remaining column
            // Find which column will remain (the one that's not being deleted)
            final remainingColumn = columnsBlock.children.firstWhere(
              (col) => col.id != columnBlock.id,
              orElse: () => columnsBlock.children.first,
            );
            final blocksToExtract = remainingColumn.children.map((e) => e.deepCopy()).toList();

            // Get the path where we'll insert the extracted blocks
            final columnsPath = columnsBlock.path;

            // Insert all extracted blocks BEFORE deleting to preserve position
            // Blocks should be inserted at the same level as the columns block was
            if (blocksToExtract.isNotEmpty) {
              // Insert first block at the same path as columns block (before deletion)
              transaction.insertNode(columnsPath, blocksToExtract[0]);
              // Insert subsequent blocks after the first one
              var currentPath = columnsPath;
              for (int i = 1; i < blocksToExtract.length; i++) {
                currentPath = currentPath.next;
                transaction.insertNode(currentPath, blocksToExtract[i]);
              }
              // Set selection to the first extracted block
              transaction.afterSelection = Selection.collapsed(
                Position(path: columnsPath, offset: 0),
              );
            } else {
              // If no blocks to extract, insert an empty paragraph
              transaction.insertNode(columnsPath, paragraphNode());
              transaction.afterSelection = Selection.collapsed(Position(path: columnsPath));
            }

            // Delete the column being deleted
            transaction.deleteNode(columnBlock);

            // Delete the columns block (after inserting blocks to preserve position)
            transaction.deleteNode(columnsBlock);
          } else if (columnsBlock != null && columnsBlock.children.length == 1) {
            // Only one column exists (shouldn't happen in normal flow, but handle it)
            final remainingColumn = columnsBlock.children.first;
            final blocksToExtract = remainingColumn.children.map((e) => e.deepCopy()).toList();
            final columnsPath = columnsBlock.path;

            // Insert all extracted blocks BEFORE deleting to preserve position
            if (blocksToExtract.isNotEmpty) {
              // Insert first block at the same path as columns block (before deletion)
              transaction.insertNode(columnsPath, blocksToExtract[0]);
              // Insert subsequent blocks after the first one
              var currentPath = columnsPath;
              for (int i = 1; i < blocksToExtract.length; i++) {
                currentPath = currentPath.next;
                transaction.insertNode(currentPath, blocksToExtract[i]);
              }
              transaction.afterSelection = Selection.collapsed(
                Position(path: columnsPath, offset: 0),
              );
            } else {
              transaction.insertNode(columnsPath, paragraphNode());
              transaction.afterSelection = Selection.collapsed(Position(path: columnsPath));
            }

            // Delete the columns block (after inserting blocks to preserve position)
            transaction.deleteNode(columnsBlock);
          } else {
            // Multiple columns, delete just this column
            // Find the previous column (before the deleted one) to place cursor at the end
            Node? targetTextNode;
            bool placeAtEnd = true; // Track if we should place cursor at end (previous column) or start (next column)
            if (columnsBlock != null && columnsBlock.children.length > 1) {
              // Find the index of the column being deleted
              int? deletedColumnIndex;
              for (int i = 0; i < columnsBlock.children.length; i++) {
                if (columnsBlock.children[i].id == columnBlock.id) {
                  deletedColumnIndex = i;
                  break;
                }
              }
              if (deletedColumnIndex != null && deletedColumnIndex > 0) {
                // Get the previous column (before the one being deleted)
                final previousColumn = columnsBlock.children[deletedColumnIndex - 1];
                // Find the last text node in the previous column
                if (previousColumn.children.isNotEmpty) {
                  for (var child in previousColumn.children.reversed) {
                    if (child.delta != null) {
                      targetTextNode = child;
                      placeAtEnd = true; // Place at end of previous column
                      break;
                    }
                  }
                }
              } else {
                // If deleting the first column, find the next column and place cursor at start
                if (deletedColumnIndex != null && deletedColumnIndex < columnsBlock.children.length - 1) {
                  final nextColumn = columnsBlock.children[deletedColumnIndex + 1];
                  final firstChild = nextColumn.children.firstOrNull;
                  if (firstChild?.delta != null) {
                    targetTextNode = firstChild;
                    placeAtEnd = false; // Place at start of next column
                  }
                }
              }
            }
            transaction.deleteNode(columnBlock);
            if (targetTextNode != null && targetTextNode.delta != null) {
              // Place cursor at the end of previous column or start of next column
              transaction.afterSelection = Selection.collapsed(
                Position(
                  path: targetTextNode.path,
                  offset: placeAtEnd ? targetTextNode.delta!.length : 0,
                ),
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
        } else {
          // This is not the first child, so just delete this empty paragraph
          // Check if this is the only child in the column
          final isOnlyChildInColumn = columnParent.children.length == 1 && columnParent.children.first.id == node.id;

          if (isOnlyChildInColumn) {
            // If this is the only child in a column, replace it with an empty paragraph
            // instead of deleting it (to avoid empty column placeholders)
            final nodePath = node.path;
            transaction.deleteNode(node);
            transaction.insertNode(nodePath, paragraphNode());
            transaction.afterSelection = Selection.collapsed(
              Position(path: nodePath, offset: 0),
            );
            editorState.apply(transaction);
            return KeyEventResult.handled;
          } else {
            // There are other siblings in the column, try to merge with previous sibling
            // or just delete this empty paragraph
            final prev = node.previous;
            if (prev != null && prev.delta != null) {
              // Merge with previous sibling in the same column
              final prevColumnParent = prev.findParent((element) => element.type == ColumnBlockKeys.type);
              if (prevColumnParent?.id == columnParent.id) {
                // Same column, merge with previous
                transaction
                  ..mergeText(prev, node)
                  ..insertNodes(
                    prev.path.next,
                    node.children.toList(),
                  )
                  ..deleteNode(node);
                transaction.afterSelection = Selection.collapsed(
                  Position(path: prev.path, offset: prev.delta!.length),
                );
                editorState.apply(transaction);
                return KeyEventResult.handled;
              }
            }
            // No previous sibling to merge with, just delete this empty paragraph
            final next = node.next;
            transaction.deleteNode(node);
            if (next != null && next.delta != null) {
              transaction.afterSelection = Selection.collapsed(
                Position(path: next.path, offset: 0),
              );
            } else if (prev != null && prev.delta != null) {
              transaction.afterSelection = Selection.collapsed(
                Position(path: prev.path, offset: prev.delta!.length),
              );
            } else {
              // Insert an empty paragraph at the same position
              final nodePath = node.path;
              transaction.insertNode(nodePath, paragraphNode());
              transaction.afterSelection = Selection.collapsed(
                Position(path: nodePath, offset: 0),
              );
            }
            editorState.apply(transaction);
            return KeyEventResult.handled;
          }
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

  final node = editorState.getNodeAtPath(selection.start.path);
  if (node == null) {
    return KeyEventResult.ignored;
  }

  final transaction = editorState.transaction;

  // Check if this node is inside a column
  final columnParent = node.findParent((element) => element.type == ColumnBlockKeys.type);

  // Check if this is the only child in a column
  final isOnlyChildInColumn =
      columnParent != null && columnParent.children.length == 1 && columnParent.children.first.id == node.id;

  if (isOnlyChildInColumn) {
    // If this is the only child in a column, replace it with an empty paragraph
    // instead of deleting it (to avoid empty column placeholders)
    final nodePath = node.path;
    transaction.deleteNode(node);
    transaction.insertNode(nodePath, paragraphNode());
    transaction.afterSelection = Selection.collapsed(
      Position(path: nodePath, offset: 0),
    );
  } else {
    // Normal deletion
    transaction.deleteNodesAtPath(selection.start.path);

    // Find a good place to put the cursor
    final prev = node.previous;
    final next = node.next;

    if (prev != null && prev.delta != null) {
      // Place cursor at end of previous node
      transaction.afterSelection = Selection.collapsed(
        Position(path: prev.path, offset: prev.delta!.length),
      );
    } else if (next != null && next.delta != null) {
      // Place cursor at start of next node
      transaction.afterSelection = Selection.collapsed(
        Position(path: next.path, offset: 0),
      );
    } else if (node.parent != null) {
      // Place cursor at parent's position
      transaction.afterSelection = Selection.collapsed(
        Position(path: node.parent!.path),
      );
    }
  }

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
