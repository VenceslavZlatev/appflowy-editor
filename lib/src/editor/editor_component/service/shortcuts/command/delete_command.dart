import 'package:flutter/material.dart';

import 'package:appflowy_editor/appflowy_editor.dart';

/// Delete key event.
///
/// - support
///   - desktop
///   - web
///
final CommandShortcutEvent deleteCommand = CommandShortcutEvent(
  key: 'Delete Key',
  getDescription: () => AppFlowyEditorL10n.current.cmdDeleteRight,
  command: 'delete, shift+delete',
  handler: _deleteCommandHandler,
);

CommandShortcutEventHandler _deleteCommandHandler = (editorState) {
  final selection = editorState.selection;
  final selectionType = editorState.selectionType;
  if (selection == null) {
    return KeyEventResult.ignored;
  }
  if (selectionType == SelectionType.block) {
    return _deleteInBlockSelection(editorState);
  } else if (selection.isCollapsed) {
    return _deleteInCollapsedSelection(editorState);
  } else {
    return _deleteInNotCollapsedSelection(editorState);
  }
};

/// Handle delete key event when selection is collapsed.
CommandShortcutEventHandler _deleteInCollapsedSelection = (editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return KeyEventResult.ignored;
  }

  final position = selection.start;
  final node = editorState.getNodeAtPath(position.path);
  final delta = node?.delta;
  if (node == null || delta == null) {
    return KeyEventResult.ignored;
  }

  final transaction = editorState.transaction;

  if (position.offset == delta.length) {
    Node? tableParent = node.findParent((element) => element.type == TableBlockKeys.type);
    Node? nextTableParent;
    final next = node.findDownward((element) {
      nextTableParent = element.findParent((element) => element.type == TableBlockKeys.type);
      // break if only one is in a table or they're in different tables
      return tableParent != nextTableParent ||
          // merge the next node with delta
          element.delta != null;
    });
    // table nodes should be deleted using the table menu
    // in-table paragraphs should only be deleted inside the table
    if (next != null && tableParent == nextTableParent) {
      if (next.children.isNotEmpty) {
        final path = node.path + [node.children.length];
        transaction.insertNodes(path, next.children);
      }
      transaction
        ..deleteNode(next)
        ..mergeText(
          node,
          next,
        );
      editorState.apply(transaction);
      return KeyEventResult.handled;
    }
  } else {
    final nextIndex = delta.nextRunePosition(position.offset);
    if (nextIndex <= delta.length) {
      transaction.deleteText(
        node,
        position.offset,
        nextIndex - position.offset,
      );
      editorState.apply(transaction);
      return KeyEventResult.handled;
    }
  }

  return KeyEventResult.ignored;
};

/// Handle delete key event when selection is not collapsed.
CommandShortcutEventHandler _deleteInNotCollapsedSelection = (editorState) {
  final selection = editorState.selection;
  if (selection == null || selection.isCollapsed) {
    return KeyEventResult.ignored;
  }
  editorState.deleteSelection(selection);
  return KeyEventResult.handled;
};

CommandShortcutEventHandler _deleteInBlockSelection = (editorState) {
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

    if (next != null && next.delta != null) {
      // Place cursor at start of next node
      transaction.afterSelection = Selection.collapsed(
        Position(path: next.path, offset: 0),
      );
    } else if (prev != null && prev.delta != null) {
      // Place cursor at end of previous node
      transaction.afterSelection = Selection.collapsed(
        Position(path: prev.path, offset: prev.delta!.length),
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
