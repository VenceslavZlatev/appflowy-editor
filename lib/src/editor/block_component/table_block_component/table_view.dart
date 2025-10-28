import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_action_handler.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_col.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_drag_add_area.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/table_row.dart';
import 'package:appflowy_editor/src/editor/block_component/table_block_component/util.dart';
import 'package:flutter/material.dart';

class TableView extends StatefulWidget {
  const TableView({
    super.key,
    required this.editorState,
    required this.tableNode,
    required this.tableStyle,
    this.menuBuilder,
  });

  final EditorState editorState;
  final TableNode tableNode;
  final TableBlockComponentMenuBuilder? menuBuilder;
  final TableStyle tableStyle;

  @override
  State<TableView> createState() => _TableViewState();
}

class _TableViewState extends State<TableView> {
  late TableRowDragNotifier _rowDragNotifier;
  late TableRowActionNotifier _rowActionNotifier;

  @override
  void initState() {
    super.initState();
    _rowDragNotifier = TableRowDragNotifier();
    _rowActionNotifier = TableRowActionNotifier();
  }

  @override
  void dispose() {
    _rowDragNotifier.dispose();
    _rowActionNotifier.dispose();
    super.dispose();
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
            Row(
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
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
      ),
    );
  }

  Widget _buildRowActionHandlers(BuildContext context) {
    return Positioned(
      top: 10, // Match the top padding of the table
      child: ListenableBuilder(
        listenable: _rowActionNotifier,
        builder: (context, child) {
          return Column(
            children: List.generate(
              widget.tableNode.rowsLen,
              (rowIdx) {
                final cellNode = widget.tableNode.getCell(0, rowIdx);
                final isHovered = _rowActionNotifier.hoveredRowIndex == rowIdx;

                return SizedBox(
                  height: cellNode.cellHeight + (widget.tableNode.config.borderWidth),
                  child: TableActionHandler(
                    visible: isHovered,
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
