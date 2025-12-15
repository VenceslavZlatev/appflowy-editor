import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_drag_add_area.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_row.dart';
import 'package:flutter/material.dart';

class TableView extends StatefulWidget {
  const TableView({
    super.key,
    required this.editorState,
    required this.tableNode,
    required this.tableStyle,
    this.menuBuilder,
    this.scrollController,
  });

  final EditorState editorState;
  final TableNode tableNode;
  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;
  final ScrollController? scrollController;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  late TableRowDragNotifier _rowDragNotifier;
  late TableRowActionNotifier _rowActionNotifier;
  late TableCellFocusNotifier _cellFocusNotifier;
  // Tracks which column's resize handle is currently hovered/active
  late ValueNotifier<int?> _colResizeHoverNotifier;

  // GlobalKey to measure the actual rendered height of the table
  final GlobalKey _tableContentKey = GlobalKey();

  // Store the measured height to avoid measuring during build
  double? _measuredHeight;

  @override
  void initState() {
    super.initState();
    _rowDragNotifier = TableRowDragNotifier();
    _rowActionNotifier = TableRowActionNotifier();
    _cellFocusNotifier = TableCellFocusNotifier();
    _colResizeHoverNotifier = ValueNotifier<int?>(null);

    // Listen to selection changes to update focused cell
    widget.editorState.selectionNotifier.addListener(_onSelectionChanged);

    // Measure height after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureTableHeight();
    });
  }

  @override
  void dispose() {
    widget.editorState.selectionNotifier.removeListener(_onSelectionChanged);
    _rowDragNotifier.dispose();
    _rowActionNotifier.dispose();
    _cellFocusNotifier.dispose();
    _colResizeHoverNotifier.dispose();
    super.dispose();
  }

  /// Measure the actual rendered height of the table content
  void _measureTableHeight() {
    if (!mounted) return;

    final renderBox = _tableContentKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final newHeight = renderBox.size.height;
      if (_measuredHeight != newHeight) {
        setState(() {
          _measuredHeight = newHeight;
        });
      }
    }
  }

  void _onSelectionChanged() {
    final selection = widget.editorState.selection;
    if (selection == null) {
      _cellFocusNotifier.clear();
      return;
    }

    // Check if selection is inside a table cell
    final node = widget.editorState.getNodeAtPath(selection.start.path);
    if (node == null) {
      _cellFocusNotifier.clear();
      return;
    }

    // Find the table cell node (parent of the selected node)
    Node? cellNode = node;
    while (cellNode != null && cellNode.type != TableCellBlockKeys.type) {
      cellNode = cellNode.parent;
    }

    // Verify the cell belongs to this table
    if (cellNode != null && cellNode.type == TableCellBlockKeys.type && cellNode.parent == widget.tableNode.node) {
      final rowPosition = cellNode.attributes[TableCellBlockKeys.rowPosition] as int?;
      final colPosition = cellNode.attributes[TableCellBlockKeys.colPosition] as int?;

      if (rowPosition != null && colPosition != null) {
        _cellFocusNotifier.setFocusedCell(rowPosition, colPosition);
        return;
      }
    }

    _cellFocusNotifier.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: _tableContentKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 10),
          child: IntrinsicHeight(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._buildColumns(context),
                  SizedBox(width: 5),
                  Container(
                    padding: EdgeInsets.only(top: 10),
                    child: TableDragAddArea(
                      tableNode: widget.tableNode.node,
                      editorState: widget.editorState,
                      direction: TableDirection.col,
                      width: 20,
                      height: null,
                      borderColor: widget.tableStyle.borderColor,
                      borderHoverColor: widget.tableStyle.borderHoverColor,
                      scrollController: widget.scrollController,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 5),
        Padding(
          padding: EdgeInsets.only(left: 10),
          child: TableDragAddArea(
            tableNode: widget.tableNode.node,
            editorState: widget.editorState,
            direction: TableDirection.row,
            width: widget.tableNode.tableWidth,
            height: 20,
            borderColor: widget.tableStyle.borderColor,
            borderHoverColor: widget.tableStyle.borderHoverColor,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildColumns(BuildContext context) {
    return List.generate(
      widget.tableNode.colsLen,
      (i) => RepaintBoundary(
        key: ValueKey('table_col_${widget.tableNode.node.id}_$i'),
        child: TableCol(
          colIdx: i,
          editorState: widget.editorState,
          tableNode: widget.tableNode,
          menuBuilder: widget.menuBuilder,
          tableStyle: widget.tableStyle,
          rowDragNotifier: _rowDragNotifier,
          rowActionNotifier: _rowActionNotifier,
          cellFocusNotifier: _cellFocusNotifier,
          colResizeHoverNotifier: _colResizeHoverNotifier,
          scrollController: widget.scrollController,
        ),
      ),
    );
  }
}
