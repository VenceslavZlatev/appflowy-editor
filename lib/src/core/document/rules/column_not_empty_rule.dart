import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/plugins/blocks/columns/column_block_component.dart';

/// This rule ensures that columns always have at least one child.
///
/// If a column becomes empty (e.g., after dragging text out), it will create a new empty paragraph node.
class ColumnNotEmptyRule extends DocumentRule {
  const ColumnNotEmptyRule();

  @override
  bool shouldApply({
    required EditorState editorState,
    required EditorTransactionValue value,
  }) {
    final time = value.$1;
    if (time != TransactionTime.after) {
      return false;
    }

    // Check if any column nodes are empty
    final document = editorState.document;
    return _hasEmptyColumns(document.root);
  }

  /// Recursively check if there are any empty column nodes
  bool _hasEmptyColumns(Node node) {
    if (node.type == ColumnBlockKeys.type && node.children.isEmpty) {
      return true;
    }

    // Check children recursively
    for (final child in node.children) {
      if (_hasEmptyColumns(child)) {
        return true;
      }
    }

    return false;
  }

  @override
  Future<void> apply({
    required EditorState editorState,
    required EditorTransactionValue value,
  }) async {
    final document = editorState.document;
    final emptyColumns = <Node>[];

    // Find all empty column nodes
    _findEmptyColumns(document.root, emptyColumns);

    if (emptyColumns.isEmpty) {
      return;
    }

    final transaction = editorState.transaction;

    // Insert an empty paragraph into each empty column
    for (final column in emptyColumns) {
      final columnPath = column.path;
      transaction.insertNode(columnPath.child(0), paragraphNode());
    }

    await editorState.apply(transaction);
  }

  /// Recursively find all empty column nodes
  void _findEmptyColumns(Node node, List<Node> emptyColumns) {
    if (node.type == ColumnBlockKeys.type && node.children.isEmpty) {
      emptyColumns.add(node);
      return;
    }

    // Check children recursively
    for (final child in node.children) {
      _findEmptyColumns(child, emptyColumns);
    }
  }
}
