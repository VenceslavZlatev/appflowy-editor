import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_drag_add_area.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_row.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:appflowy_editor/src/editor/util/platform_extension.dart';
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

  @override
  void initState() {
    super.initState();
    _rowDragNotifier = TableRowDragNotifier();
    _rowActionNotifier = TableRowActionNotifier();
    _cellFocusNotifier = TableCellFocusNotifier();

    // Listen to selection changes to update focused cell
    widget.editorState.selectionNotifier.addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    widget.editorState.selectionNotifier.removeListener(_onSelectionChanged);
    _rowDragNotifier.dispose();
    _rowActionNotifier.dispose();
    _cellFocusNotifier.dispose();
    super.dispose();
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main table content
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 10),
              child: Row(
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
                      height: widget.tableNode.colsHeight,
                      borderColor: widget.tableStyle.borderColor,
                      borderHoverColor: widget.tableStyle.borderHoverColor,
                      scrollController: widget.scrollController,
                    ),
                  ),
                ],
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
        ),
        // Row action handlers overlaid on the left
        _buildRowActionHandlers(context),
      ],
    );
  }

  List<Widget> _buildColumns(BuildContext context) {
    return List.generate(
      widget.tableNode.colsLen,
      (i) => TableCol(
        colIdx: i,
        editorState: widget.editorState,
        tableNode: widget.tableNode,
        menuBuilder: widget.menuBuilder,
        tableStyle: widget.tableStyle,
        rowDragNotifier: _rowDragNotifier,
        rowActionNotifier: _rowActionNotifier,
        cellFocusNotifier: _cellFocusNotifier,
      ),
    );
  }

  Widget _buildRowActionHandlers(BuildContext context) {
    return Positioned(
      top: 10, // Match the top padding of the table
      child: ListenableBuilder(
        listenable: Listenable.merge([_rowActionNotifier, _cellFocusNotifier]),
        builder: (context, child) {
          final isMobile = PlatformExtension.isMobile;
          return Column(
            children: List.generate(
              widget.tableNode.rowsLen,
              (rowIdx) {
                final cellNode = widget.tableNode.getCell(0, rowIdx);
                final isHovered = _rowActionNotifier.hoveredRowIndex == rowIdx;
                final isFocused = _cellFocusNotifier.isRowFocused(rowIdx);
                // On mobile, show when cell is focused (selected)
                // On desktop, show only on hover
                final shouldShow = isMobile ? isFocused : isHovered;

                return SizedBox(
                  height: cellNode.cellHeight + (widget.tableNode.config.borderWidth),
                  child: TableActionHandler(
                    visible: shouldShow,
                    node: widget.tableNode.node,
                    editorState: widget.editorState,
                    position: rowIdx,
                    alignment: Alignment.centerLeft,
                    height: cellNode.cellHeight,
                    menuBuilder: widget.menuBuilder,
                    dir: TableDirection.row,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
