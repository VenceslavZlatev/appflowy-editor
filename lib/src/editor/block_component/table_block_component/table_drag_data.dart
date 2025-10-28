import 'package:appflowy_editor/appflowy_editor.dart';

/// Data class for table drag and drop operations
class TableDragData {
  const TableDragData({
    required this.node,
    required this.position,
    required this.dir,
    required this.editorState,
  });

  final Node node;
  final int position;
  final TableDirection dir;
  final EditorState editorState;
}
